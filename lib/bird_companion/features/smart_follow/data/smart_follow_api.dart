import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_gateway.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

/// SmartFollow HTTP 接口（联合开发任务书 §6.3–§6.8）。
///
/// 这里只做"路径 + 解析"，不做状态合并、幂等键生成与重试策略——
/// 那些属于 `smart_follow_repository.dart`（分工任务书 F3）。
///
/// 协议头：联合 §6 说沿用现有认证头与协议版本头，但没有为 SmartFollow
/// 定义新的 `X-BirdBox-Protocol` 值，因此**不发明**头部，只复用
/// `ApiClient` 已有的 `X-Api-Version`/`Authorization`。是否需要一个
/// `smart-follow-v1` 协议头，列入分工任务书问询单第 10 条。
class SmartFollowApi implements SmartFollowGateway {
  SmartFollowApi(this._client);

  final ApiClient _client;

  /// `/recognition-capabilities`：三项能力一起读，避免多次往返。
  @override
  Future<SmartFollowCapabilities> capabilities() async => SmartFollowCapabilities.fromJson(
    await _client.get(ApiEndpoints.recognitionCapabilities),
  );

  /// 识别进行中开启跟随（§6.3）。同一 RecognitionJob 只允许一个活动会话。
  @override
  Future<SmartFollowSession> startOnRecognitionJob(
    String recognitionJobId,
    SmartFollowStartRequest request, {
    String? idempotencyKey,
  }) async {
    final raw = await _client.post(
      ApiEndpoints.startSmartFollow(_requiredId(recognitionJobId, 'recognitionJobId')),
      data: request.toJson(),
      idempotencyKey: idempotencyKey,
    );
    return SmartFollowSession.fromJson(_unwrapSession(raw));
  }

  /// 会话权威快照（§6.5）。页面所有数字都以它为准。
  @override
  Future<SmartFollowSession> session(String sessionId) async {
    final raw = await _client.get(ApiEndpoints.smartFollowSession(_requiredId(sessionId, 'sessionId')));
    return SmartFollowSession.fromJson(_unwrapSession(raw));
  }

  /// child CopyJob 分页（§6.6）。服务端固定排序 + cursor 快照。
  @override
  Future<SmartFollowChildJobPage> childJobs(
    String sessionId, {
    String? cursor,
    int pageSize = 50,
  }) async {
    final raw = await _client.get(
      ApiEndpoints.smartFollowCopyJobs(_requiredId(sessionId, 'sessionId')),
      queryParameters: {
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
        'page_size': pageSize,
      },
    );
    return SmartFollowChildJobPage.fromJson(raw);
  }

  /// 会话动作（§6.7）。
  ///
  /// 契约未规定响应体：后端可能回会话、可能只回 `{ok:true}`。回不出会话时
  /// 返回 null，调用方按"重读会话"处理，不在这里编造状态。
  @override
  Future<SmartFollowSession?> act(
    String sessionId,
    SmartFollowAction action, {
    required int expectedStateVersion,
    String? idempotencyKey,
  }) async {
    final raw = await _client.post(
      ApiEndpoints.smartFollowActions(_requiredId(sessionId, 'sessionId')),
      data: {'action': action.wire, 'expected_state_version': expectedStateVersion},
      idempotencyKey: idempotencyKey,
    );
    final candidate = raw['session'] ?? raw['smart_follow_session'] ?? raw['smart_follow'] ?? raw;
    if (candidate is! Map || !candidate.containsKey('session_id')) return null;
    return SmartFollowSession.fromJson(Map<String, dynamic>.from(candidate));
  }

  /// 识别任务 → 会话 ID。
  ///
  /// 现阶段从 `recognition-events` 的首帧读 `smart_follow_session_id`；这是
  /// App 已有的能力（`recognition_repository.dart` 同样字段），但它是"顺带
  /// 读到"而不是正式契约，问询单第 5 条拿到专用查询接口后替换此实现。
  @override
  Future<String?> sessionIdForRecognitionJob(String recognitionJobId) async {
    final raw = await _client.get(
      ApiEndpoints.recognitionEvents(_requiredId(recognitionJobId, 'recognitionJobId')),
      queryParameters: {'after_event_seq': 0, 'page_size': 1},
    );
    final value = raw['smart_follow_session_id'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 信息可更新状态（§6.8）。
  @override
  Future<SmartFollowMetadataAvailability> metadataAvailability(String sessionId) async {
    final raw = await _client.get(ApiEndpoints.smartFollowMetadataAvailability(_requiredId(sessionId, 'sessionId')));
    final candidate = raw['availability'] ?? raw;
    return SmartFollowMetadataAvailability.fromJson(Map<String, dynamic>.from(candidate as Map));
  }

  /// 生成信息更新预览（§6.8）。与 RC3 预检一致，允许后端异步构建后轮询详情。
  @override
  Future<SmartFollowMetadataPreview> previewMetadata(
    String sessionId, {
    Map<String, dynamic>? data,
    String? idempotencyKey,
  }) async {
    var raw = await _client.post(
      ApiEndpoints.smartFollowMetadataPreview(_requiredId(sessionId, 'sessionId')),
      data: data ?? const <String, dynamic>{},
      idempotencyKey: idempotencyKey,
    );
    if (raw['state'] == 'building') {
      final previewId = ProtocolValidation.requiredId(raw, 'preview_id');
      for (var attempt = 0; attempt < 20; attempt++) {
        raw = await _client.get(ApiEndpoints.smartFollowMetadataPreviewDetail.replaceFirst('{previewId}', previewId));
        if (raw['state'] == 'ready') break;
        if (raw['state'] == 'failed') {
          throw StateError('信息更新预览生成失败，请检查目标盘与识别结果状态');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (raw['state'] != 'ready') {
        throw StateError('信息更新预览生成超时，请稍后重试');
      }
    }
    return SmartFollowMetadataPreview.fromJson(Map<String, dynamic>.from(raw));
  }

  /// 预览详情（§6.8）。
  @override
  Future<SmartFollowMetadataPreview> previewDetail(String previewId) async => SmartFollowMetadataPreview.fromJson(
    await _client.get(ApiEndpoints.smartFollowMetadataPreviewDetail.replaceFirst('{previewId}', _requiredId(previewId, 'previewId'))),
  );

  /// 用户确认后创建统一信息更新（§6.8）。必须带预览 token、原参数与幂等键。
  @override
  Future<SmartFollowMetadataUpdate> createMetadataUpdate(
    String sessionId, {
    required Map<String, dynamic> data,
    String? idempotencyKey,
  }) async {
    final raw = await _client.post(
      ApiEndpoints.smartFollowMetadataUpdates(_requiredId(sessionId, 'sessionId')),
      data: data,
      idempotencyKey: idempotencyKey,
    );
    final candidate = raw['update'] ?? raw['metadata_update'] ?? raw;
    return SmartFollowMetadataUpdate.fromJson(Map<String, dynamic>.from(candidate as Map));
  }

  /// 父任务状态（§6.8）。
  @override
  Future<SmartFollowMetadataUpdate> metadataUpdate(String updateId) async => SmartFollowMetadataUpdate.fromJson(
    await _client.get(ApiEndpoints.smartFollowMetadataUpdateDetail.replaceFirst('{updateId}', _requiredId(updateId, 'updateId'))),
  );

  /// 兼容三种包法：裸会话、`{session: ...}`、`{smart_follow: ...}`。
  static Map<String, dynamic> _unwrapSession(Map<String, dynamic> raw) {
    final candidate = raw['session'] ?? raw['smart_follow_session'] ?? raw['smart_follow'] ?? raw;
    if (candidate is! Map) {
      throw const ProtocolCompatibilityException('session', '必须是对象');
    }
    return Map<String, dynamic>.from(candidate);
  }

  static String _requiredId(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(value, field, 'must not be empty');
    return trimmed;
  }
}
