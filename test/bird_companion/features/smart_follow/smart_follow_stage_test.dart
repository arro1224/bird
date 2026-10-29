import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_stage.dart';
import 'package:flutter_test/flutter_test.dart';

SmartFollowSession sessionJson({
  String state = 'following',
  int eligible = 0,
  int pending = 0,
  int assigned = 0,
  int copiedAssets = 0,
  int failed = 0,
  int childJobs = 0,
  bool metadataAvailable = false,
  String? errorMessage,
}) => SmartFollowSession.fromJson({
  'session_id': 'sf_1',
  'recognition_job_id': 'rec_1',
  'state': state,
  'state_version': 1,
  'eligible_count': eligible,
  'pending_count': pending,
  'assigned_count': assigned,
  'copied_asset_count': copiedAssets,
  'failed_asset_count': failed,
  'child_job_count': childJobs,
  'metadata_update_available': metadataAvailable,
  'error_message': errorMessage,
  'allowed_actions': const <String>[],
});

void main() {
  test('等待目标盘 / 等待源卡：等待色且说明识别仍在继续', () {
    final target = resolveSmartFollowStage(session: sessionJson(state: 'waiting_for_target'));
    expect(target.label, '等待目标盘');
    expect(target.isWaiting, isTrue);
    expect(target.hint, contains('识别仍在继续'));

    final source = resolveSmartFollowStage(session: sessionJson(state: 'waiting_for_source'));
    expect(source.label, '等待源卡');
    expect(source.isWaiting, isTrue);
  });

  test('失败显示后端原因，没有原因时给可操作文案', () {
    final failing = resolveSmartFollowStage(session: sessionJson(state: 'failed', errorMessage: '盒子内部错误 500'));
    expect(failing.label, '失败／需要处理');
    expect(failing.hint, '盒子内部错误 500');
    expect(failing.tone, SmartFollowStageTone.failure);

    final withoutMessage = resolveSmartFollowStage(session: sessionJson(state: 'failed'));
    expect(withoutMessage.hint, contains('不能自动恢复'));
  });

  test('完成后按"信息可更新"给出不同副标题', () {
    final done = resolveSmartFollowStage(session: sessionJson(state: 'completed'));
    expect(done.label, '已完成');
    expect(done.hint, contains('全部处理完'));

    final updatable = resolveSmartFollowStage(session: sessionJson(state: 'completed', metadataAvailable: true));
    expect(updatable.hint, contains('可选择更新'));
  });

  test('部分完成说明失败张数或用户主动结束', () {
    final withFailures = resolveSmartFollowStage(session: sessionJson(state: 'completed_partial', failed: 2));
    expect(withFailures.label, '部分完成');
    expect(withFailures.hint, contains('2 张'));

    final byUser = resolveSmartFollowStage(session: sessionJson(state: 'completed_partial'));
    expect(byUser.hint, contains('不会再复制'));
  });

  test('暂停 / 排空 / 已创建 三段文案', () {
    expect(resolveSmartFollowStage(session: sessionJson(state: 'paused')).label, '已暂停');
    expect(resolveSmartFollowStage(session: sessionJson(state: 'draining')).label, '识别结束·正在完成剩余复制');
    expect(resolveSmartFollowStage(session: sessionJson(state: 'created')).label, '识别与复制中');
  });

  test('识别与复制中：有待复制项', () {
    final stage = resolveSmartFollowStage(session: sessionJson(pending: 2, assigned: 6, copiedAssets: 4, childJobs: 2));
    expect(stage.label, '识别与复制中');
    expect(stage.tone, SmartFollowStageTone.running);
  });

  test('复制快于识别：转"等待新的识别结果"且不提前完成', () {
    final stage = resolveSmartFollowStage(session: sessionJson(pending: 0, assigned: 5, copiedAssets: 5, childJobs: 3));
    expect(stage.label, '等待新的识别结果');
    expect(stage.hint, contains('5 张'));
    expect(stage.tone, SmartFollowStageTone.running);
  });

  test('识别已结束但会话还在 following：按排空展示', () {
    final stage = resolveSmartFollowStage(session: sessionJson(pending: 1, assigned: 3, copiedAssets: 2), recognitionRunning: false);
    expect(stage.label, '识别结束·正在完成剩余复制');
  });

  test('信息更新运行中优先于会话状态', () {
    final running = SmartFollowMetadataUpdate.fromJson({'update_id': 'u1', 'state': 'running'});
    final stage = resolveSmartFollowStage(session: sessionJson(state: 'completed'), metadataUpdate: running);
    expect(stage.label, '正在统一保存信息');
    expect(stage.hint, contains('不会重新复制'));
  });

  test('信息更新已结束时回到会话自身文案', () {
    final finished = SmartFollowMetadataUpdate.fromJson({'update_id': 'u1', 'state': 'completed_partial'});
    final stage = resolveSmartFollowStage(session: sessionJson(state: 'completed'), metadataUpdate: finished);
    expect(stage.label, '已完成');
  });

  test('未冻结状态原样显示', () {
    final stage = resolveSmartFollowStage(session: sessionJson(state: 'recognition_interrupted'));
    expect(stage.id, 'unknown');
    expect(stage.label, 'recognition_interrupted');
    expect(stage.hint, contains('还不认识'));
  });
}
