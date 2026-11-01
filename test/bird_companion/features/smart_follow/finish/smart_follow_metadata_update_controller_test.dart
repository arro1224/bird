import 'dart:async';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'metadata_update_fixtures.dart';

void main() {
  for (final variant in ['missing', 'empty', 'truncated', 'unknown-count']) {
    test('incomplete terminal children ($variant) block both M1 and M3 new previews', () async {
      final local = MetadataUpdateEnvironment();
      addTearDown(local.dispose);
      local.backend.available = true;
      switch (variant) {
        case 'missing':
          local.backend.updateData.remove('child_jobs');
        case 'empty':
          local.backend.updateData['child_jobs'] = [];
        case 'truncated':
          local.backend.updateData['child_jobs'] = [MetadataUpdateBackend.child('md-a', 'copy-1')];
        case 'unknown-count':
          local.backend.updateData.remove('child_job_count');
      }
      await local.controller.refresh();
      expect(local.controller.canPreview, isFalse);
      final hint = SmartFollowMetadataController(
        repository: local.repository,
        sessionId: 'sf_fake',
        readRecognition: (id) async => BirdJobStatus(id: id, type: BirdJobType.analysis, state: BirdJobState.completed),
      );
      addTearDown(hint.dispose);
      await hint.refresh();
      expect(hint.activeUpdateId, 'update-1');
      expect(hint.canPreview, isFalse);
      expect(local.backend.creates, 0);
    });
  }
  test('session active parent blocks a new preview when availability omits it', () async {
    final local = MetadataUpdateEnvironment();
    addTearDown(local.dispose);
    await local.controller.refresh();
    local.backend.data['active_metadata_update_id'] = 'update-2';
    local.backend.active = null;
    local.backend.available = true;
    await local.controller.refresh();
    expect(local.controller.updateId, 'update-1');
    expect(local.controller.otherActiveId, 'update-2');
    expect(local.controller.canPreview, isFalse);
  });
  late MetadataUpdateEnvironment env;
  setUp(() => env = MetadataUpdateEnvironment());
  tearDown(() => env.dispose());
  test('complete parent report preserves photo/file units without changing copy state', () async {
    await env.controller.refresh();
    expect(env.controller.report!.title, '识别信息更新完成');
    expect(env.controller.report!.complete, isTrue);
    expect(env.controller.report!.update.count('updated_asset_count'), 3);
    expect(env.controller.report!.update.count('updated_file_count'), 5);
    expect(env.controller.session!.state.wire, 'completed');
    expect(env.backend.creates, 0);
    expect(env.backend.actCalls, 0);
  });
  test('partial child failure overrides a misleading completed heading', () async {
    (env.backend.updateData['child_jobs'] as List)[1] = MetadataUpdateBackend.child('md-b', 'copy-2', files: 3, failed: 1, state: 'failed');
    await env.controller.refresh();
    expect(env.controller.report!.title, '识别信息部分更新');
  });
  for (final state in ['completed_partial', 'failed', 'cancelled', 'queued', 'running', 'future_server_state']) {
    test('parent $state is rendered without assuming success', () async {
      env.backend.updateData['state'] = state;
      await env.controller.refresh();
      expect(env.controller.report!.title, isNot('识别信息更新完成'));
      expect(env.controller.canPreview, isFalse);
      if (state == 'future_server_state') expect(env.controller.report!.title, '状态待确认');
    });
  }
  for (final key in SmartFollowMetadataUpdate.countAliases.keys) {
    test('missing parent $key never becomes authoritative zero', () async {
      env.backend.updateData.remove(key);
      await env.controller.refresh();
      expect(env.controller.report!.update.count(key), isNull);
      expect(env.controller.report!.complete, isFalse);
      expect(env.controller.report!.title, contains('报告待补齐'));
    });
  }
  test('missing child outcome keeps aggregate report incomplete', () async {
    ((env.backend.updateData['child_jobs'] as List).first as Map).remove('failed_file_count');
    await env.controller.refresh();
    expect(env.controller.report!.complete, isFalse);
    expect(env.controller.report!.children.first.count('failed_file_count'), isNull);
  });
  test('missing child mapping cannot silently open an arbitrary RC3 task', () async {
    ((env.backend.updateData['child_jobs'] as List).first as Map).remove('copy_job_id');
    await env.controller.refresh();
    expect(env.controller.report!.complete, isFalse);
    expect(env.controller.report!.children.first.copyJobId, isNull);
  });
  test('missing child list is not an empty successful report', () async {
    env.backend.updateData.remove('child_jobs');
    await env.controller.refresh();
    expect(env.controller.report!.complete, isFalse);
  });
  test('malformed child entries fail instead of disappearing silently', () async {
    env.backend.updateData['child_jobs'] = ['bad-entry'];
    await env.controller.refresh();
    expect(env.controller.report, isNull);
    expect(env.controller.error, isNotNull);
  });
  test('duplicate identical metadata IDs are counted once', () async {
    final children = env.backend.updateData['child_jobs'] as List;
    children.add(<String, dynamic>{...Map<String, dynamic>.from(children.first as Map)});
    await env.controller.refresh();
    expect(env.controller.report!.children, hasLength(2));
    expect(env.controller.report!.complete, isTrue);
  });
  test('conflicting duplicate mapping invalidates the report', () async {
    final children = env.backend.updateData['child_jobs'] as List;
    children.add(<String, dynamic>{...Map<String, dynamic>.from(children.first as Map), 'copy_job_id': 'wrong-copy'});
    await env.controller.refresh();
    expect(env.controller.report!.complete, isFalse);
    expect(env.controller.report!.issues.join(), contains('重复子任务'));
  });
  test('parent-child file count disagreement is not a complete result', () async {
    env.backend.updateData['updated_file_count'] = 99;
    await env.controller.refresh();
    expect(env.controller.report!.complete, isFalse);
    expect(env.controller.report!.issues.join(), contains('文件数不一致'));
  });
  test('terminal parent with running child stays incomplete and cannot update again', () async {
    ((env.backend.updateData['child_jobs'] as List).first as Map)['state'] = 'running';
    env.backend.available = true;
    await env.controller.refresh();
    expect(env.controller.report!.complete, isFalse);
    expect(env.controller.canPreview, isFalse);
  });
  test('read failure retains and marks last report, then retry recovers same ID', () async {
    await env.controller.refresh();
    env.backend.parentFails = true;
    await env.controller.refresh();
    expect(env.controller.report, isNotNull);
    expect(env.controller.error, isNotNull);
    expect(env.controller.canPreview, isFalse);
    env.backend.parentFails = false;
    await env.controller.refresh();
    expect(env.controller.error, isNull);
    expect(env.backend.parentReads.toSet(), {'update-1'});
    expect(env.backend.creates, 0);
  });
  test('a wrong parent response never populates the report', () async {
    env.backend.wrongParent = true;
    await env.controller.refresh();
    expect(env.controller.report, isNull);
    expect(env.controller.error, isNotNull);
  });
  test('explicit unrelated route ID cannot be claimed as this session history', () async {
    final other = env.newController(id: 'unrelated');
    addTearDown(other.dispose);
    await other.refresh();
    expect(other.report, isNull);
    expect(env.backend.parentReads, isEmpty);
  });
  test('lower parent state version cannot roll back an observed terminal result', () async {
    env.backend.updateData['state_version'] = 5;
    await env.controller.refresh();
    env.backend.updateData.addAll({'state_version': 2, 'state': 'running'});
    await env.controller.refresh();
    expect(env.controller.report!.update.state, 'completed');
  });
  test('availability is independently refreshed after completion and can become true again', () async {
    await env.controller.refresh();
    expect(env.controller.canPreview, isFalse);
    env.backend.available = true;
    await env.controller.refresh();
    expect(env.controller.canPreview, isTrue);
    env.backend.available = false;
    await env.controller.refresh();
    expect(env.controller.canPreview, isFalse);
    expect(env.backend.creates, 0);
  });
  test('availability failure does not erase a valid report or enable writing', () async {
    env.backend.availabilityFails = true;
    await env.controller.refresh();
    expect(env.controller.report!.complete, isTrue);
    expect(env.controller.availabilityError, isNotNull);
    expect(env.controller.canPreview, isFalse);
  });
  test('capability false still allows historical report but hides new update', () async {
    env.backend.capability = false;
    await env.controller.refresh();
    expect(env.controller.report!.complete, isTrue);
    expect(env.controller.canPreview, isFalse);
    expect(env.backend.availabilityReads, 0);
  });
  test('new active update never replaces the old report being viewed', () async {
    await env.controller.refresh();
    env.backend.active = 'update-2';
    env.backend.available = true;
    await env.controller.refresh();
    expect(env.controller.updateId, 'update-1');
    expect(env.controller.otherActiveId, 'update-2');
    expect(env.controller.canPreview, isFalse);
  });
  test('known parent identity survives repository restart after active reference disappears', () async {
    await env.controller.refresh();
    env.backend.active = null;
    env.backend.data['active_metadata_update_id'] = null;
    env.backend.availabilityFails = true;
    final repo = SmartFollowRepository(env.backend, metadataStorage: env.store, metadataDeviceId: () => 'box-1');
    final restored = env.newController(follows: repo, id: null);
    addTearDown(restored.dispose);
    addTearDown(repo.dispose);
    await restored.refresh();
    expect(restored.updateId, 'update-1');
    expect(restored.report!.complete, isTrue);
  });
  test('historical references remain isolated across boxes', () async {
    await env.controller.refresh();
    final other = SmartFollowRepository(env.backend, metadataStorage: env.store, metadataDeviceId: () => 'box-2');
    addTearDown(other.dispose);
    expect(other.metadataUpdateHistory('sf_fake'), isEmpty);
  });
  test('concurrent reference writes retain every distinct historical parent', () async {
    await Future.wait([env.repository.rememberMetadataUpdate('sf_fake', 'a'), env.repository.rememberMetadataUpdate('sf_fake', 'b'), env.repository.rememberMetadataUpdate('sf_fake', 'a')]);
    expect(env.repository.metadataUpdateHistory('sf_fake'), ['a', 'b']);
  });
  test('explicit zero-work terminal report differs from missing statistics', () async {
    env.backend.updateData.addAll({'child_jobs': <Map<String, dynamic>>[], 'child_job_count': 0, 'updated_asset_count': 0, 'updated_file_count': 0, 'failed_count': 0, 'blocked_count': 0, 'unchanged_count': 0});
    await env.controller.refresh();
    expect(env.controller.report!.complete, isTrue);
    expect(env.controller.report!.update.count('updated_file_count'), 0);
  });
  test('M1 permits a fresh preview after old active parent has ended', () async {
    env.backend.available = true;
    final hint = SmartFollowMetadataController(
      repository: env.repository,
      sessionId: 'sf_fake',
      readRecognition: (id) async => BirdJobStatus(id: id, type: BirdJobType.analysis, state: BirdJobState.completed),
    );
    addTearDown(hint.dispose);
    await hint.refresh();
    expect(hint.activeUpdateId, isNull);
    expect(hint.latestUpdateId, 'update-1');
    expect(hint.canPreview, isTrue);
    expect(env.backend.creates, 0);
  });
  test('concurrent reads coalesce and device reset drops a late parent response', () async {
    env.backend.parentGate = Completer<void>();
    final first = env.controller.refresh();
    final second = env.controller.refresh();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    env.current = false;
    env.repository.resetForDeviceChange();
    env.backend.parentGate!.complete();
    await first;
    expect(env.controller.report, isNull);
    expect(env.controller.error, contains('盒子连接已变化'));
  });
}
