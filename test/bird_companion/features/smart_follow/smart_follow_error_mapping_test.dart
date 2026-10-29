import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 联合开发任务书 §8 的 14 条最低集合：每一条都必须有专属文案，
/// 不能落成"连接超时"/"操作未完成"这类通用兜底。
void main() {
  const expectedTitles = {
    'SMART_FOLLOW_UNAVAILABLE': '当前盒子不支持边识别边复制',
    'SMART_FOLLOW_ALREADY_ACTIVE': '这个识别任务已经在跟随复制',
    'SMART_FOLLOW_JOB_NOT_RUNNING': '识别任务当前没有运行',
    'SMART_FOLLOW_JOB_ALREADY_TERMINAL': '识别已经结束',
    'SMART_FOLLOW_TARGET_UNAVAILABLE': '等待目标存储设备',
    'SMART_FOLLOW_SOURCE_UNAVAILABLE': '等待原相机卡',
    'SMART_FOLLOW_TARGET_IDENTITY_CHANGED': '插入了不同的目标盘',
    'SMART_FOLLOW_INSUFFICIENT_SPACE': '目标盘空间不足',
    'SMART_FOLLOW_STATE_VERSION_CONFLICT': '跟随任务状态已更新',
    'SMART_FOLLOW_ACTION_NOT_ALLOWED': '当前操作不可用',
    'SMART_FOLLOW_IDEMPOTENCY_CONFLICT': '请求与之前的记录不一致',
    'SMART_FOLLOW_RECONCILIATION_REQUIRED': '识别结果需要核对',
    'SMART_FOLLOW_METADATA_NOT_AVAILABLE': '当前没有可更新的信息',
    'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED': '部分照片的信息无法更新',
  };

  test('14 条错误码都有专属标题，且不落通用兜底', () {
    for (final entry in expectedTitles.entries) {
      final message = UserMessageMapper.fromError(ApiException(message: '', code: entry.key, statusCode: 409));
      expect(message.title, entry.value, reason: entry.key);
      expect(message.message.trim(), isNotEmpty, reason: entry.key);
      expect(message.title, isNot('操作未完成'), reason: entry.key);
      expect(message.title, isNot('连接超时'), reason: entry.key);
    }
  });

  test('后端给普通语言时优先展示后端文案，给内部细节时用 App 文案', () {
    final friendly = UserMessageMapper.fromError(const ApiException(message: '请插回原来的目标盘后继续', code: 'SMART_FOLLOW_TARGET_UNAVAILABLE'));
    expect(friendly.message, '请插回原来的目标盘后继续');

    final internal = UserMessageMapper.fromError(const ApiException(message: 'Exception at /run/media/usb1/x', code: 'SMART_FOLLOW_TARGET_UNAVAILABLE'));
    expect(internal.message, contains('不会自动换到其他盘'));
  });

  test('创建结果未知：提示用同一次请求重试，而不是新建任务', () {
    final message = UserMessageMapper.fromError(const SmartFollowOutcomeUnknown('rec_1', 'timeout'));
    expect(message.title, '还没确认跟随是否已开始');
    expect(message.message, contains('不要新建任务'));
    expect(message.actionLabel, '重试');
  });

  test('未识别的 SMART_FOLLOW 码仍走通用兜底但不崩', () {
    final message = UserMessageMapper.fromError(const ApiException(message: 'x', code: 'SMART_FOLLOW_SOMETHING_NEW'));
    expect(message.title, isNotEmpty);
    expect(message.message, isNotEmpty);
  });
}
