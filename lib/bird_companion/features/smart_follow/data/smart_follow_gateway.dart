import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

/// SmartFollow 的数据来源抽象。
///
/// 真实实现是 [SmartFollowApi]（HTTP）；测试与离线演示用内存假后端实现同一
/// 接口，因此页面/仓储不依赖 Dio，也不会出现"只有真机能跑"的分支。
///
/// 幂等键语义：`idempotencyKey == null` 表示"这次调用不需要去重"（读操作，
/// 或后端自会生成的预览），由实现决定是否带默认键。
abstract interface class SmartFollowGateway {
  Future<SmartFollowCapabilities> capabilities();

  /// 识别进行中开启跟随（联合 §6.3）。幂等键必须稳定。
  Future<SmartFollowSession> startOnRecognitionJob(
    String recognitionJobId,
    SmartFollowStartRequest request, {
    String? idempotencyKey,
  });

  Future<SmartFollowSession> session(String sessionId);

  Future<SmartFollowChildJobPage> childJobs(String sessionId, {String? cursor, int pageSize});

  /// 返回 null 表示后端没有回会话（调用方应重读会话）。
  Future<SmartFollowSession?> act(
    String sessionId,
    SmartFollowAction action, {
    required int expectedStateVersion,
    String? idempotencyKey,
  });

  /// 识别任务当前绑定的 SmartFollow 会话 ID。
  ///
  /// 用途：创建超时后"查原结果"，以及不重复创建（联合 §6.3、App §5）。
  /// 目前只能从 `recognition-events` 的 `smart_follow_session_id` 读；
  /// 专用的"按 recognition_job 查会话"接口仍在与后端对账（问询单第 5 条）。
  Future<String?> sessionIdForRecognitionJob(String recognitionJobId);

  Future<SmartFollowMetadataAvailability> metadataAvailability(String sessionId);

  Future<SmartFollowMetadataPreview> previewMetadata(String sessionId, {Map<String, dynamic>? data, String? idempotencyKey});

  Future<SmartFollowMetadataPreview> previewDetail(String previewId);

  Future<SmartFollowMetadataUpdate> createMetadataUpdate(
    String sessionId, {
    required Map<String, dynamic> data,
    String? idempotencyKey,
  });

  Future<SmartFollowMetadataUpdate> metadataUpdate(String updateId);
}
