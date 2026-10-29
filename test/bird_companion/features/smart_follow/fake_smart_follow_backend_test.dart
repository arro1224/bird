import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

const startRequest = SmartFollowStartRequest(targetMediaId: 'media_usb_fake', reviewExportEnabled: true);

void main() {
  group('FakeSmartFollowBackend 自身语义', () {
    test('未满一批不封批，识别结束立即封最后一批，子任务收敛后完成', () {
      final backend = FakeSmartFollowBackend(batchSize: 8)..start();
      for (var i = 0; i < 3; i++) {
        backend.commitPhoto();
      }
      expect(backend.state, SmartFollowState.following);
      expect(backend.eligibleCount, 3);
      expect(backend.pendingCount, 3);
      expect(backend.children, isEmpty);

      backend.finishRecognition();
      expect(backend.state, SmartFollowState.draining);
      expect(backend.children, hasLength(1));
      expect(backend.children.single.assetCount, 3);

      backend.completeChildJobs();
      expect(backend.state, SmartFollowState.completed);
      expect(backend.copiedAssetCount, 3);
    });

    test('满 8 张立即封批，余下等待下一批', () {
      final backend = FakeSmartFollowBackend(batchSize: 8)..start();
      for (var i = 0; i < 9; i++) {
        backend.commitPhoto();
      }
      expect(backend.children, hasLength(1));
      expect(backend.children.single.assetCount, 8);
      expect(backend.pendingCount, 1);
    });

    test('medium/unknown/reject 不计入已识别与待复制', () {
      final backend = FakeSmartFollowBackend()..start();
      for (var i = 0; i < 5; i++) {
        backend.commitPhoto(eligible: false);
      }
      backend.commitPhoto();
      expect(backend.recognizedCount, 6);
      expect(backend.eligibleCount, 1);
      expect(backend.pendingCount, 1);
    });

    test('等待目标盘时计数与队列不动', () {
      final backend = FakeSmartFollowBackend()..start();
      backend.commitPhoto();
      backend.commitPhoto();
      backend.waitForTarget();
      expect(backend.state, SmartFollowState.waitingForTarget);
      expect(backend.eligibleCount, 2);
      expect(backend.pendingCount, 2);
      expect(backend.children, isEmpty);
      final actions = backend.current.allowedActions;
      expect(actions, [SmartFollowAction.pause, SmartFollowAction.stopFollowing]);
    });

    test('子任务清单创建后不再变化', () {
      final backend = FakeSmartFollowBackend(batchSize: 2)..start();
      backend.commitPhoto();
      backend.commitPhoto();
      final first = backend.children.single.copyJobId;
      backend.commitPhoto();
      backend.commitPhoto();
      expect(backend.children.first.copyJobId, first);
      expect(backend.children.first.assetCount, 2);
      expect(backend.children, hasLength(2));
    });
  });

  group('Repository + Fake 联调', () {
    test('开启 → 逐张跟随 → 排空 → 完成，页面只认后端数字', () async {
      final backend = FakeSmartFollowBackend(batchSize: 2);
      final repository = SmartFollowRepository(backend);
      addTearDown(repository.dispose);

      final started = await repository.startOnRecognitionJob('rec_fake', startRequest);
      expect(started.state, SmartFollowState.following);

      backend.commitPhoto();
      backend.commitPhoto();
      await repository.refresh(started.sessionId);
      var snapshot = repository.snapshot(started.sessionId)!;
      expect(snapshot.eligibleCount, 2);
      expect(snapshot.childJobCount, 1);
      expect(snapshot.isFinished, isFalse);

      backend.finishRecognition();
      backend.completeChildJobs();
      await repository.refresh(started.sessionId);
      snapshot = repository.snapshot(started.sessionId)!;
      expect(snapshot.state, SmartFollowState.completed);
      expect(snapshot.copiedAssetCount, 2);
      expect(snapshot.metadataUpdateAvailable, isTrue);
      expect(snapshot.canShowCompletion, isTrue);
    });

    test('动作走 allowed_actions：暂停后按钮换成继续', () async {
      final backend = FakeSmartFollowBackend();
      final repository = SmartFollowRepository(backend);
      addTearDown(repository.dispose);
      final started = await repository.startOnRecognitionJob('rec_fake', startRequest);

      final paused = await repository.act(started.sessionId, SmartFollowAction.pause);
      expect(paused.state, SmartFollowState.paused);
      expect(paused.supports(SmartFollowAction.resume), isTrue);
      expect(paused.supports(SmartFollowAction.pause), isFalse);

      final resumed = await repository.act(started.sessionId, SmartFollowAction.resume);
      expect(resumed.state, SmartFollowState.following);
    });

    test('完成当前结果：冻结截止序号、排空已识别项目、进入 draining', () async {
      final backend = FakeSmartFollowBackend(batchSize: 8);
      final repository = SmartFollowRepository(backend);
      addTearDown(repository.dispose);
      final started = await repository.startOnRecognitionJob('rec_fake', startRequest);
      for (var i = 0; i < 3; i++) {
        backend.commitPhoto();
      }
      await repository.refresh(started.sessionId);
      final result = await repository.act(started.sessionId, SmartFollowAction.finishCurrentResults);
      expect(result.state, SmartFollowState.draining);
      expect(result.cutoffEventSeq, 3);
      expect(result.childJobCount, 1);
    });

    test('子任务按 cursor 分页', () async {
      final backend = FakeSmartFollowBackend(batchSize: 1);
      final repository = SmartFollowRepository(backend);
      addTearDown(repository.dispose);
      final started = await repository.startOnRecognitionJob('rec_fake', startRequest);
      for (var i = 0; i < 3; i++) {
        backend.commitPhoto();
      }
      final firstPage = await repository.childJobs(started.sessionId, pageSize: 2);
      expect(firstPage.items, hasLength(2));
      expect(firstPage.hasMore, isTrue);
      final secondPage = await repository.childJobs(started.sessionId, cursor: firstPage.nextCursor, pageSize: 2);
      expect(secondPage.items, hasLength(1));
      expect(secondPage.hasMore, isFalse);
      expect(secondPage.items.single.state, CopyJobState.running);
    });

    test('信息更新：预览 → 部分确认 → 父任务完成', () async {
      final backend = FakeSmartFollowBackend(batchSize: 1);
      final repository = SmartFollowRepository(backend);
      addTearDown(repository.dispose);
      final started = await repository.startOnRecognitionJob('rec_fake', startRequest);
      backend.commitPhoto();
      backend.commitPhoto();
      backend.finishRecognition();
      backend.completeChildJobs();
      // 目标盘上有副本被外部改过：信息更新必须要求部分确认。
      backend.blockMetadataUpdate();
      await repository.refresh(started.sessionId);
      final availability = await repository.metadataAvailability(started.sessionId);
      expect(availability.available, isTrue);

      final preview = await repository.previewMetadata(started.sessionId);
      expect(preview.hasUpdatableItems, isTrue);
      expect(preview.requiresPartialConfirmation, isTrue);

      await expectLater(
        repository.createMetadataUpdate(started.sessionId, preview),
        throwsA(isA<ApiException>().having((error) => error.code, 'code', 'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED')),
      );

      final update = await repository.createMetadataUpdate(started.sessionId, preview, confirmPartial: true);
      expect(update.isTerminal, isFalse);
      backend.completeMetadataUpdate(partial: true, blockedFiles: 1);
      final finished = await repository.metadataUpdate(update.updateId);
      expect(finished.isTerminal, isTrue);
      expect(finished.isPartial, isTrue);
    });
  });
}
