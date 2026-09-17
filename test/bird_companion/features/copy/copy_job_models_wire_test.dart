import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// RC3 响应容错解析冻结测试（阶段 D 批次 1）。
///
/// 响应协议未冻结：未知字段忽略 / 缺失给默认 / 未知枚举保留 raw /
/// 未知 allowed_action 丢弃。联调期后端字段演进时只需放宽此处。
void main() {
  group('CopyJobState tolerant parsing', () {
    test('未知 state 不抛异常并保留 raw', () {
      final detail = CopyJobDetail.fromJson({
        'copy_job_id': 'job-1',
        'state': 'brand_new_state',
        'event_seq': 3,
      });
      expect(detail.state.wire, 'brand_new_state');
      expect(detail.state.label, 'brand_new_state');
      expect(detail.state.isCustom, isTrue);
      expect(detail.state.isTerminal, isFalse);
    });

    test('空 state 抛协议异常（唯一必填语义字段）', () {
      expect(
        () => CopyJobDetail.fromJson({'copy_job_id': 'job-1'}),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
    });

    test('isTerminal/isWaitingDevice/isTransition 按协议 §12 判定', () {
      expect(CopyJobState.fromWire('completed').isTerminal, isTrue);
      expect(CopyJobState.fromWire('completed_with_errors').isTerminal, isTrue);
      expect(CopyJobState.fromWire('cancelled').isTerminal, isTrue);
      expect(CopyJobState.fromWire('failed').isTerminal, isTrue);
      expect(CopyJobState.fromWire('running').isRunning, isTrue);
      expect(CopyJobState.fromWire('pause_requested').isTransition, isTrue);
      expect(CopyJobState.fromWire('waiting_for_target').isWaitingDevice, isTrue);
      expect(CopyJobState.fromWire(null), same(CopyJobState.unknown));
    });
  });

  group('CopyJobDetail tolerant parsing', () {
    test('stateVersion 三键依次回退（state_version/expected_state_version/version）', () {
      int version(Map<String, dynamic> json) =>
          CopyJobDetail.fromJson({
            'copy_job_id': 'job-1',
            'state': 'running',
            ...json,
          }).stateVersion;
      expect(version({'state_version': 7}), 7);
      expect(version({'expected_state_version': 9}), 9);
      expect(version({'version': 11}), 11);
      // state_version 优先。
      expect(version({'state_version': 7, 'version': 11}), 7);
      expect(version({}), 0);
    });

    test('stats 缺失给默认值且不抛', () {
      final stats = CopyJobStats.fromJson({});
      expect(stats.totalFiles, 0);
      expect(stats.copiedFiles, 0);
      expect(stats.effectiveProgressPercent, isNull);
      expect(stats.currentFile, isNull);
    });

    test('未知 allowed_action 丢弃、已知保留', () {
      final detail = CopyJobDetail.fromJson({
        'copy_job_id': 'job-1',
        'state': 'running',
        'allowed_actions': ['pause', 'brand_new_action', 'cancel', null],
      });
      expect(
        detail.allowedActions.map((action) => action.wire),
        ['pause', 'cancel'],
      );
    });

    test('设备快照全 nullable 且不得复用严格模型', () {
      final snapshot = CopyJobDeviceSnapshot.fromJson({'display_name': 'U 盘 Ee'});
      expect(snapshot.mediaId, isNull);
      expect(snapshot.presentationLabel, 'U 盘 Ee');
      expect(const CopyJobDeviceSnapshot().presentationLabel, isNull);
    });
  });

  group('分页容器', () {
    test('next_cursor 接受 int 与 String，has_more 缺失按 cursor 推断', () {
      final intCursor = CopyJobItemPage.fromJson({
        'items': [],
        'next_cursor': 20,
      });
      expect(intCursor.nextCursor, '20');
      expect(intCursor.hasMore, isTrue);

      final noCursor = CopyJobItemPage.fromJson({'items': []});
      expect(noCursor.hasMore, isFalse);
      expect(noCursor.nextCursor, isNull);

      final explicit = CopyJobItemPage.fromJson({
        'items': [],
        'has_more': false,
        'next_cursor': '5',
      });
      expect(explicit.hasMore, isFalse);
    });

    test('items 非法行忽略不抛', () {
      final page = CopyJobItemPage.fromJson({'items': [null, 'junk', {'copy_item_id': 'i1'}]});
      expect(page.items, hasLength(1));
      expect(page.items.first.copyItemId, 'i1');
    });

    test('CopyJobEvent seq 容错 seq|event_seq', () {
      expect(CopyJobEvent.fromJson({'seq': 5}).seq, 5);
      expect(CopyJobEvent.fromJson({'event_seq': 6}).seq, 6);
      expect(CopyJobEvent.fromJson({}).seq, isNull);
    });
  });

  group('SafeRemoveResult / CopyDeviceList', () {
    test('safe_to_remove 缺失按 false（保守）', () {
      expect(SafeRemoveResult.fromJson({}).safeToRemove, isFalse);
      final result = SafeRemoveResult.fromJson({
        'safe_to_remove': true,
        'keep_until': '2026-09-17T12:00:00.000',
      });
      expect(result.safeToRemove, isTrue);
      expect(result.keepUntil, isNotNull);
    });

    test('CopyDeviceList 顶层推荐键两形态都接受，行仍严格', () {
      final device = {
        'media_id': 'media_1',
        'display_name': 'U 盘 Ee',
        'kind': 'usb_flash',
        'kind_confidence': 'medium',
        'detail': '',
        'capacity_bytes': 1,
        'free_bytes': 1,
        'filesystem': 'exfat',
        'label': '',
        'role_state': 'available',
        'can_be_source': false,
        'can_be_target': true,
        'target_block_reasons': <String>[],
        'identity_confidence': 'stable_uuid',
      };
      expect(
        CopyDeviceList.fromJson({
          'devices': [device],
          'last_successful_target_media_id': 'media_1',
        }).recommendedTargetMediaId,
        'media_1',
      );
      expect(
        CopyDeviceList.fromJson({
          'devices': [device],
          'recommended_target_media_id': 'media_1',
        }).recommendedTargetMediaId,
        'media_1',
      );
      expect(
        CopyDeviceList.fromJson({
          'devices': [device],
          'last_successful_target_media_id': 'media_1',
        }).devices.single.mediaId,
        'media_1',
      );
      // 设备行严格：未知 kind 抛协议异常。
      expect(
        () => CopyDeviceList.fromJson({
          'devices': [
            {...device, 'kind': 'unknown_kind'},
          ],
        }),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
    });
  });

  group('CopyReport', () {
    test('字段全 optional，isPartialSuccess 由失败项驱动', () {
      const empty = CopyReport();
      expect(empty.isPartialSuccess, isFalse);
      expect(const CopyReport(failedFiles: 2).isPartialSuccess, isTrue);
    });
  });

  group('CopyJobItem', () {
    test('copy_item_id 三键容错（copy_item_id|item_id|id）', () {
      expect(CopyJobItem.fromJson({'copy_item_id': 'a'}).copyItemId, 'a');
      expect(CopyJobItem.fromJson({'item_id': 'b'}).copyItemId, 'b');
      expect(CopyJobItem.fromJson({'id': 'c'}).copyItemId, 'c');
      expect(() => CopyJobItem.fromJson({}), throwsA(isA<ProtocolCompatibilityException>()));
    });

    test('targetPath 组合目录与文件名', () {
      expect(
        CopyJobItem.fromJson({
          'copy_item_id': 'a',
          'target_relative_directory': '20260901',
          'target_filename': 'DSC05001.ARW',
        }).targetPath,
        '20260901/DSC05001.ARW',
      );
      expect(
        CopyJobItem.fromJson({'copy_item_id': 'a', 'target_filename': 'f.ARW'}).targetPath,
        'f.ARW',
      );
      expect(CopyJobItem.fromJson({'copy_item_id': 'a'}).targetPath, isNull);
    });
  });

  group('CopyTimeline.compute', () {
    test('运行中按 stats 推导复制/校验阶段', () {
      final copying = CopyTimeline.compute(
        state: CopyJobState.fromWire('running'),
        stats: CopyJobStats.fromJson({'total_files': 2, 'copied_files': 0}),
      );
      expect(copying.stages[CopyTimelineStageId.copyingFiles.index].status, CopyStageStatus.active);
      expect(copying.stages[CopyTimelineStageId.verifyingFiles.index].status, CopyStageStatus.pending);

      final verifying = CopyTimeline.compute(
        state: CopyJobState.fromWire('running'),
        stats: CopyJobStats.fromJson({'total_files': 2, 'copied_files': 2}),
      );
      expect(verifying.stages[CopyTimelineStageId.copyingFiles.index].status, CopyStageStatus.done);
      expect(verifying.stages[CopyTimelineStageId.verifyingFiles.index].status, CopyStageStatus.active);
    });

    test('终态成功全 done；取消跳过审阅/同步/完成；失败标记当前阶段', () {
      final completed = CopyTimeline.compute(state: CopyJobState.fromWire('completed_with_errors'));
      expect(completed.stages.every((stage) => stage.status == CopyStageStatus.done), isTrue);

      final cancelled = CopyTimeline.compute(state: CopyJobState.fromWire('cancelled'));
      expect(cancelled.stages[CopyTimelineStageId.done.index].status, CopyStageStatus.skipped);
      expect(cancelled.stages[CopyTimelineStageId.writingReview.index].status, CopyStageStatus.skipped);

      final failed = CopyTimeline.compute(state: CopyJobState.fromWire('failed'));
      expect(failed.stages[CopyTimelineStageId.copyingFiles.index].status, CopyStageStatus.failed);
    });
  });
}
