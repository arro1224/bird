import 'dart:async';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_gateway.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// SmartFollow 的权威状态仓储（分工任务书 F3）。
///
/// 职责边界：
/// - **只信后端**：页面上的每个数字都来自会话快照，这里不做 "+1"；
/// - **只进不退**：`state_version` 更旧的响应不得覆盖当前快照；
/// - **幂等**：同一意图的请求键稳定不变（创建按 job、动作按 状态版本、信息更新按预览 token）；
/// - **结果未知不瞎重建**：创建超时先查原会话，查不到就抛
///   [SmartFollowOutcomeUnknown]，由界面提示"用同一次请求重试"。
///
/// 事件只当唤醒信号（联合 §7）：收到通知后重读会话，不拿 payload 里的数字
/// 覆盖状态。
class SmartFollowRepository extends ChangeNotifier {
  SmartFollowRepository(this._gateway);

  final SmartFollowGateway _gateway;
  final Map<String, SmartFollowSession> _sessions = {};
  final Map<String, String> _sessionIdByJob = {};
  final Map<String, Future<SmartFollowSession>> _refreshing = {};
  final Set<String> _repeatRefresh = {};
  SmartFollowCapabilities? _capabilities;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  bool _disposed = false;

  static const eventTypes = {
    'RecognitionResultCommitted',
    'SmartFollowStateChanged',
    'SmartFollowCountsChanged',
    'SmartFollowChildJobCreated',
    'SmartFollowMetadataAvailabilityChanged',
    'SmartFollowMetadataUpdateStateChanged',
  };

  SmartFollowSession? snapshot(String sessionId) => _sessions[sessionId.trim()];

  String? sessionIdForJob(String recognitionJobId) => _sessionIdByJob[recognitionJobId.trim()];

  SmartFollowSession? snapshotForJob(String recognitionJobId) {
    final sessionId = sessionIdForJob(recognitionJobId);
    return sessionId == null ? null : snapshot(sessionId);
  }

  SmartFollowCapabilities? get cachedCapabilities => _capabilities;

  /// 切换盒子时调用：会话 ID 与能力都属于"某台盒子"，不能跨设备复用。
  ///
  /// 由 `app_dependencies` 在设备变化时触发（重连另一台盒子、重新配对）。
  void resetForDeviceChange() {
    if (_disposed) return;
    final hadState = _sessions.isNotEmpty || _sessionIdByJob.isNotEmpty || _capabilities != null;
    _sessions.clear();
    _sessionIdByJob.clear();
    _repeatRefresh.clear();
    _capabilities = null;
    if (hadState) notifyListeners();
  }

  /// 入口门控（F5）。旧盒子 404 视为"能力全无"，不抛给界面。
  Future<SmartFollowCapabilities> capabilities({bool forceRefresh = false}) async {
    final cached = _capabilities;
    if (!forceRefresh && cached != null) return cached;
    try {
      final value = await _gateway.capabilities();
      if (_disposed) return value;
      _capabilities = value;
      return value;
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      if (_disposed) return SmartFollowCapabilities.none;
      _capabilities = SmartFollowCapabilities.none;
      return SmartFollowCapabilities.none;
    }
  }

  /// 重读会话（同一会话并发调用合并成一次请求）。
  Future<SmartFollowSession> refresh(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    final inFlight = _refreshing[id];
    if (inFlight != null) {
      _repeatRefresh.add(id);
      return inFlight;
    }
    final request = _refresh(id);
    _refreshing[id] = request;
    return request.whenComplete(() {
      _refreshing.remove(id);
      if (_repeatRefresh.remove(id) && !_disposed) {
        unawaited(refresh(id).catchError((Object _) => _sessions[id] ?? _missing(id)));
      }
    });
  }

  Future<SmartFollowSession> _refresh(String sessionId) async {
    final incoming = await _gateway.session(sessionId);
    if (_disposed) return incoming;
    return _merge(incoming);
  }

  SmartFollowSession _missing(String sessionId) => _sessions[sessionId] ?? (throw ArgumentError.value(sessionId, 'sessionId', 'unknown session'));

  /// 按 job 重读：先看已映射的会话，再尝试从识别事件里找回。
  Future<SmartFollowSession?> refreshForJob(String recognitionJobId) async {
    final known = sessionIdForJob(recognitionJobId);
    if (known != null) return refresh(known);
    final recovered = await _tryRecover(recognitionJobId);
    return recovered;
  }

  /// 开启跟随（联合 §6.3）。
  ///
  /// 调用顺序刻意如此：
  /// 1. 已有活动会话 → 直接返回（OLED 建过、或用户重复点了）；
  /// 2. 用识别事件查回会话（上次超时留下的一半结果）；
  /// 3. 才真正 POST，键固定为 `follow-start-<jobId>`；
  /// 4. 超时/断连时**不换键重建**：再查一次，仍查不到就抛
  ///    [SmartFollowOutcomeUnknown]，重试即"同键再来一次"。
  Future<SmartFollowSession> startOnRecognitionJob(
    String recognitionJobId,
    SmartFollowStartRequest request,
  ) async {
    final jobId = recognitionJobId.trim();
    if (jobId.isEmpty) throw ArgumentError.value(recognitionJobId, 'recognitionJobId', 'must not be empty');
    final active = snapshotForJob(jobId);
    if (active != null && !active.isFinished) return active;

    final recovered = await _tryRecover(jobId);
    if (recovered != null) return recovered;

    try {
      final started = await _gateway.startOnRecognitionJob(jobId, request, idempotencyKey: 'follow-start-$jobId');
      if (_disposed) return started;
      return _merge(started);
    } on ApiException catch (error) {
      if (error.code == 'SMART_FOLLOW_ALREADY_ACTIVE') {
        final existing = await _tryRecover(jobId);
        if (existing != null) return existing;
      }
      if (_outcomeUnknown(error)) {
        final existing = await _tryRecover(jobId);
        if (existing != null) return existing;
        throw SmartFollowOutcomeUnknown(jobId, error);
      }
      rethrow;
    }
  }

  /// 会话动作（联合 §6.7）。只允许后端给过的动作；版本冲突后刷新再抛，
  /// 让界面提示"重新确认"，不把旧意图套到新状态上。
  Future<SmartFollowSession> act(String sessionId, SmartFollowAction action) async {
    final id = sessionId.trim();
    final current = snapshot(id) ?? await refresh(id);
    if (!current.supports(action)) {
      throw ApiException(
        message: '当前状态不允许该操作',
        code: 'SMART_FOLLOW_ACTION_NOT_ALLOWED',
        retryable: false,
        details: {'session_id': id, 'action': action.wire, 'state': current.state.wire},
      );
    }
    final key = '$id-${action.wire}-${current.stateVersion}';
    try {
      final updated = await _gateway.act(id, action, expectedStateVersion: current.stateVersion, idempotencyKey: key);
      if (_disposed) return updated ?? current;
      if (updated == null) return refresh(id);
      return _merge(updated);
    } on ApiException catch (error) {
      if (error.code == 'SMART_FOLLOW_STATE_VERSION_CONFLICT' || error.statusCode == 409) {
        try {
          await refresh(id);
        } catch (_) {
          // 保留原始冲突：连刷新都失败时不能让用户看到"刷新失败"而丢掉冲突原因。
        }
      }
      rethrow;
    }
  }

  /// 子任务分页透传（联合 §6.6）。分页游标由调用方（页面/控制器）持有。
  Future<SmartFollowChildJobPage> childJobs(String sessionId, {String? cursor, int pageSize = 50}) =>
      _gateway.childJobs(sessionId.trim(), cursor: cursor, pageSize: pageSize);

  // ---- 信息统一更新（联合 §6.8）----

  Future<SmartFollowMetadataAvailability> metadataAvailability(String sessionId) => _gateway.metadataAvailability(sessionId.trim());

  Future<SmartFollowMetadataPreview> previewMetadata(String sessionId, {Map<String, dynamic>? data}) =>
      _gateway.previewMetadata(sessionId.trim(), data: data);

  /// 用预览生成写入任务。键由 `会话 + preview_token` 派生：用户连点两次也只有一个任务。
  ///
  /// 预览表明存在不可更新项时，调用方必须先显式传 `confirmPartial: true`，
  /// 否则这里直接拒绝——避免"部分失败被当成全部成功"。
  Future<SmartFollowMetadataUpdate> createMetadataUpdate(
    String sessionId,
    SmartFollowMetadataPreview preview, {
    Map<String, dynamic> extra = const {},
    bool confirmPartial = false,
  }) async {
    if (!preview.hasUpdatableItems) {
      throw const ApiException(message: '没有可更新的照片', code: 'SMART_FOLLOW_METADATA_NOT_AVAILABLE', retryable: false);
    }
    if (preview.isExpired) {
      throw const ApiException(message: '信息更新预览已过期，请重新获取', code: 'SMART_FOLLOW_METADATA_NOT_AVAILABLE', retryable: true);
    }
    if (preview.requiresPartialConfirmation && !confirmPartial) {
      throw const ApiException(
        message: '存在无法安全更新的副本，需要用户确认部分更新',
        code: 'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED',
        retryable: false,
      );
    }
    return _gateway.createMetadataUpdate(
      sessionId.trim(),
      data: {'preview_token': preview.previewToken, 'target_media_id': preview.targetMediaId, if (confirmPartial) 'confirm_partial': true, ...extra},
      idempotencyKey: 'md-create-${sessionId.trim()}-${preview.previewToken}',
    );
  }

  Future<SmartFollowMetadataUpdate> metadataUpdate(String updateId) => _gateway.metadataUpdate(updateId.trim());

  // ---- 事件 ----

  /// 绑定全局事件流（WebSocket 通知）。可重复调用，只订阅一次。
  ///
  /// 约束：事件不是事实来源（联合 §7）。收到后只重读会话；断线期间漏掉的
  /// 通知必须靠页面刷新/进前台补，不能指望这条流。
  void bindEvents(Stream<DeviceEvent> events) {
    _eventSubscription ??= events.listen((event) => unawaited(handleEvent(event.type, event.payload)));
  }

  /// WebSocket/本地事件只唤醒重读（联合 §7）。未知事件、payload 不全都安全忽略。
  Future<void> handleEvent(String type, Map<String, dynamic> payload) async {
    if (_disposed || !eventTypes.contains(type)) return;
    final sessionId = _stringOf(payload, const ['session_id', 'smart_follow_session_id']);
    final jobId = _stringOf(payload, const ['recognition_job_id', 'job_id']);
    final target = sessionId ?? (jobId == null ? null : sessionIdForJob(jobId));
    try {
      if (target != null) {
        await refresh(target);
      } else if (jobId != null) {
        await refreshForJob(jobId);
      }
    } catch (_) {
      // 事件是通知，不是事实来源：读失败时保留旧快照，等下一次刷新/前台恢复。
    }
  }

  SmartFollowSession _merge(SmartFollowSession incoming) {
    final current = _sessions[incoming.sessionId];
    if (current != null && incoming.stateVersion < current.stateVersion) {
      // 旧响应不能把新状态退回去（例如刷新与动作响应乱序）。
      _sessionIdByJob[current.recognitionJobId] = current.sessionId;
      return current;
    }
    _sessions[incoming.sessionId] = incoming;
    _sessionIdByJob[incoming.recognitionJobId] = incoming.sessionId;
    notifyListeners();
    return incoming;
  }

  Future<SmartFollowSession?> _tryRecover(String recognitionJobId) async {
    try {
      final sessionId = await _gateway.sessionIdForRecognitionJob(recognitionJobId);
      if (sessionId == null || sessionId.trim().isEmpty) return null;
      return await refresh(sessionId.trim());
    } catch (_) {
      // 恢复是尽力而为：识别事件接口不可用（旧盒子）时不影响正常创建路径。
      return null;
    }
  }

  /// 请求可能已经到达盒子但没拿到响应：此时"失败"不等于"没创建"。
  static bool _outcomeUnknown(ApiException error) {
    final cause = error.cause;
    if (cause is! DioException) return false;
    return switch (cause.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => true,
      _ => false,
    };
  }

  static String? _stringOf(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  @override
  void dispose() {
    if (_disposed) return; // 幂等：页面与依赖容器可能各收一次
    _disposed = true;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    super.dispose();
  }
}
