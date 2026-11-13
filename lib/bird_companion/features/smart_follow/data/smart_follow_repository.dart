import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_gateway.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/continuous_queue_models.dart';
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
  SmartFollowRepository(this._gateway, {this.metadataStorage, this.metadataDeviceId});

  final SmartFollowGateway _gateway;
  Future<SmartFollowSessionPage> sessions({String? cursor}) async {
    final generation = _deviceGeneration;
    final gateway = _gateway;
    if (gateway is! SmartFollowSessionListGateway) throw StateError('当前盒子不支持跟随会话列表。');
    final page = await (gateway as SmartFollowSessionListGateway).sessions(cursor: cursor);
    _checkDevice(generation);
    return page;
  }
  Future<GroupedCopyHistoryPage> groupedHistory({String? cursor}) async {
    final generation = _deviceGeneration;
    final gateway = _gateway;
    if (gateway is! SmartFollowHistoryGateway) throw StateError('当前盒子不支持分组复制历史。');
    final page = await (gateway as SmartFollowHistoryGateway).groupedHistory(cursor: cursor);
    _checkDevice(generation);
    return page;
  }
  Future<SmartFollowFilePage> fileItems(String sessionId, {String? cursor, String? state}) async {
    final generation = _deviceGeneration;
    final gateway = _gateway;
    if (gateway is! SmartFollowQueueGateway) throw StateError('当前盒子不支持持续队列文件明细。');
    final page = await (gateway as SmartFollowQueueGateway).fileItems(sessionId, cursor: cursor, state: state);
    _checkDevice(generation);
    return page;
  }
  final DiagnosticStorage? metadataStorage;
  final String? Function()? metadataDeviceId;
  final Map<String, Map<String, dynamic>> _metadataPending = {};
  final Map<String, Future<SmartFollowMetadataUpdate>> _metadataCreating = {};
  final Map<String, List<String>> _metadataHistory = {};
  final Map<String, Future<void>> _metadataRemembering = {};
  final Map<String, SmartFollowMetadataUpdate> _metadataSnapshots = {};
  String _metadataHistorySlot(String sessionId) => 'smart-follow-metadata-history:${metadataDeviceId?.call() ?? 'local'}:${sessionId.trim()}';
  List<String> metadataUpdateHistory(String sessionId) {
    final slot = _metadataHistorySlot(sessionId);
    final saved = metadataStorage?.read<List>(slot) ?? _metadataHistory[slot] ?? const [];
    return List.unmodifiable(saved.whereType<String>().where((id) => id.trim().isNotEmpty).toSet());
  }

  Future<void> rememberMetadataUpdate(String sessionId, String updateId) {
    final generation = _deviceGeneration;
    final slot = _metadataHistorySlot(sessionId);
    final previous = _metadataRemembering[slot] ?? Future<void>.value();
    final request = previous.catchError((Object _) {}).then((_) async {
      _checkDevice(generation);
      final ids = metadataUpdateHistory(sessionId);
      if (ids.contains(updateId)) return;
      final next = [...ids, updateId];
      await metadataStorage?.write(slot, next);
      _checkDevice(generation);
      _metadataHistory[slot] = next;
    });
    _metadataRemembering[slot] = request;
    return request.whenComplete(() {
      if (identical(_metadataRemembering[slot], request)) _metadataRemembering.remove(slot);
    });
  }

  String _metadataSlot(String sessionId) => 'smart-follow-metadata-create:${metadataDeviceId?.call() ?? 'local'}:${sessionId.trim()}';
  bool hasPendingMetadata(String sessionId) => _metadataRecord(_metadataSlot(sessionId)) != null;
  Map? _metadataRecord(String slot) => metadataStorage?.read<Map>(slot) ?? _metadataPending[slot];
  Future<void> resolvePendingMetadata(String sessionId) => _removeMetadataPending(_metadataSlot(sessionId));
  Future<void> _removeMetadataPending(String slot) async {
    await metadataStorage?.remove(slot);
    _metadataPending.remove(slot);
  }

  final Map<String, SmartFollowSession> _sessions = {};
  final Map<String, String> _sessionIdByJob = {};
  final Map<String, Future<SmartFollowSession>> _refreshing = {};
  final Set<String> _repeatRefresh = {};
  SmartFollowCapabilities? _capabilities;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  bool _disposed = false;
  int _deviceGeneration = 0;
  int get deviceGeneration => _deviceGeneration;
  final Map<String, Future<SmartFollowSession>> _starting = {};
  final Map<String, String> _startBodies = {};

  void _checkDevice(int generation) {
    if (_disposed || generation != _deviceGeneration) throw StateError('盒子连接已变化，请重新打开原任务。');
  }

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
    ++_deviceGeneration;
    _metadataSnapshots.clear();
    _metadataHistory.clear();
    _metadataRemembering.clear();
    _refreshing.clear();
    _starting.clear();
    _startBodies.clear();
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
    final generation = _deviceGeneration;
    try {
      final value = await _gateway.capabilities();
      _checkDevice(generation);
      _capabilities = value;
      return value;
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      _checkDevice(generation);
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
      if (!identical(_refreshing[id], request)) return;
      _refreshing.remove(id);
      if (_repeatRefresh.remove(id) && !_disposed) {
        unawaited(refresh(id).catchError((Object _) => _sessions[id] ?? _missing(id)));
      }
    });
  }

  Future<SmartFollowSession> _refresh(String sessionId) async {
    final generation = _deviceGeneration;
    var incoming = await _gateway.session(sessionId);
    _checkDevice(generation);
    if (incoming.sessionId != sessionId) throw StateError('返回的跟随会话不属于当前请求。');
    final events = _gateway;
    if (events is SmartFollowEventGateway && incoming.raw['event_seq'] is int) {
      final slot = 'smart-follow-event-cursor:${metadataDeviceId?.call() ?? 'local'}:$sessionId';
      var cursor = metadataStorage?.read<int>(slot) ?? 0;
      var changed = false;
      for (var page = 0; page < 8; page++) {
        Map<String, dynamic> response;
        try {
          response = await (events as SmartFollowEventGateway).sessionEvents(sessionId, afterEventSeq: cursor);
        } on ApiException catch (e) {
          if (e.statusCode == 404) break;
          rethrow;
        }
        _checkDevice(generation);
        final legacyCursor = response.containsKey('next_after_event_seq') && !response.containsKey('has_more');
        if ((!legacyCursor && response['session_id'] != sessionId) || response['items'] is! List || (!legacyCursor && response['has_more'] is! bool)) throw StateError('跟随事件归属或分页不完整');
        final items = response['items'] as List;
        for (final item in items) {
          if (item is! Map || item['session_id'] != sessionId || item['event_seq'] != cursor + 1) throw StateError('跟随事件不连续，请重新核对原任务');
          cursor++;
          changed = true;
        }
        final more = legacyCursor ? items.length == 200 : response['has_more'] == true;
        if ((legacyCursor ? response['next_after_event_seq'] : response['next_event_seq']) != cursor || (more && items.isEmpty)) throw StateError('跟随事件游标无效');
        await metadataStorage?.write(slot, cursor);
        _checkDevice(generation);
        if (!more) break;
      }
      // Persisted event cursors never replace authoritative counts. Read a fresh
      // snapshot after catch-up so an event cannot advance past an older screen.
      if (changed) {
        incoming = await _gateway.session(sessionId);
        _checkDevice(generation);
      }
    }
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
  ) {
    final jobId = recognitionJobId.trim();
    final body = jsonEncode(request.toJson());
    if (_startBodies.containsKey(jobId) && _startBodies[jobId] != body) throw StateError('原创建请求尚未确认，不能更换参数重试。');
    _startBodies[jobId] = body;
    final existing = _starting[jobId];
    if (existing != null) return existing;
    final generation = _deviceGeneration;
    final future = _startOnRecognitionJob(jobId, request).whenComplete(() {
      if (generation == _deviceGeneration) _starting.remove(jobId);
    });
    _starting[jobId] = future;
    return future;
  }

  Future<SmartFollowSession> _startOnRecognitionJob(String recognitionJobId, SmartFollowStartRequest request) async {
    final generation = _deviceGeneration;
    final jobId = recognitionJobId.trim();
    if (jobId.isEmpty) throw ArgumentError.value(recognitionJobId, 'recognitionJobId', 'must not be empty');
    final active = snapshotForJob(jobId);
    if (active != null && !active.isFinished) return active;

    final recovered = await _tryRecover(jobId);
    _checkDevice(generation);
    if (recovered != null) return recovered;

    try {
      final started = await _gateway.startOnRecognitionJob(jobId, request, idempotencyKey: 'follow-start-$jobId');
      _checkDevice(generation);
      if (started.recognitionJobId != jobId) throw StateError('返回的跟随会话不属于本轮识别。');
      return _merge(started);
    } on ApiException catch (error) {
      _checkDevice(generation);
      if (error.code == 'SMART_FOLLOW_ALREADY_ACTIVE') {
        final existing = await _tryRecover(jobId);
        if (existing != null) return existing;
      }
      if (_outcomeUnknown(error)) {
        final existing = await _tryRecover(jobId);
        if (existing != null) return existing;
        throw SmartFollowOutcomeUnknown(jobId, error);
      }
      if (error.statusCode != null && error.statusCode! >= 400 && error.statusCode! < 500 && !const {408, 409, 429}.contains(error.statusCode)) _startBodies.remove(jobId);
      rethrow;
    }
  }

  /// 会话动作（联合 §6.7）。只允许后端给过的动作；版本冲突后刷新再抛，
  /// 让界面提示"重新确认"，不把旧意图套到新状态上。
  Future<SmartFollowSession> act(String sessionId, SmartFollowAction action) async {
    final generation = _deviceGeneration;
    final id = sessionId.trim();
    final current = snapshot(id) ?? await refresh(id);
    _checkDevice(generation);
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
      _checkDevice(generation);
      if (updated == null) return refresh(id);
      return _merge(updated);
    } on ApiException catch (error) {
      _checkDevice(generation);
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
  Future<SmartFollowChildJobPage> childJobs(String sessionId, {String? cursor, int pageSize = 50}) => _gateway.childJobs(sessionId.trim(), cursor: cursor, pageSize: pageSize);

  // ---- 信息统一更新（联合 §6.8）----

  Future<SmartFollowMetadataAvailability> metadataAvailability(String sessionId) async {
    final generation = _deviceGeneration;
    final result = await _gateway.metadataAvailability(sessionId.trim());
    _checkDevice(generation);
    return result;
  }

  Future<SmartFollowMetadataPreview> previewMetadata(String sessionId, {Map<String, dynamic>? data}) async {
    if (hasPendingMetadata(sessionId)) throw StateError('上次信息更新结果待确认，请先查询原任务');
    final generation = _deviceGeneration;
    final result = await _gateway.previewMetadata(sessionId.trim(), data: data);
    _checkDevice(generation);
    return result;
  }

  Future<SmartFollowMetadataPreview> previewDetail(String previewId) async {
    final generation = _deviceGeneration;
    final result = await _gateway.previewDetail(previewId);
    _checkDevice(generation);
    if (result.previewId != previewId) throw StateError('返回的预览不属于当前请求');
    return result;
  }

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
    if (preview.needsPartialConsent && !confirmPartial) {
      throw const ApiException(
        message: '存在无法安全更新的副本，需要用户确认部分更新',
        code: 'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED',
        retryable: false,
      );
    }
    if (extra.keys.any(const {'preview_token', 'target_media_id', 'confirm_partial'}.contains)) throw ArgumentError('不得覆盖已确认预览的参数');
    final body = {'preview_token': preview.previewToken, 'target_media_id': preview.targetMediaId, if (confirmPartial) 'confirm_partial': true, ...extra};
    final slot = _metadataSlot(sessionId);
    final previous = _metadataRecord(slot);
    if (previous != null && jsonEncode(previous) != jsonEncode(body)) throw StateError('上次信息更新结果待确认，请先查询原任务');
    final existing = _metadataCreating[slot];
    if (existing != null) return existing;
    final generation = _deviceGeneration;
    final request = () async {
      _metadataPending[slot] = body;
      await metadataStorage?.write(slot, body);
      _checkDevice(generation);
      try {
        final result = await _gateway.createMetadataUpdate(sessionId.trim(), data: body, idempotencyKey: 'md-create-${sessionId.trim()}-${preview.previewToken}');
        _checkDevice(generation);
        await rememberMetadataUpdate(sessionId, result.updateId);
        _checkDevice(generation);
        await _removeMetadataPending(slot);
        return result;
      } catch (error) {
        // These known 4xx responses explicitly reject the write. An unknown
        // conflict/timeout cannot prove that the task was never accepted.
        if (error is ApiException &&
            error.statusCode != null &&
            error.statusCode! >= 400 &&
            error.statusCode! < 500 &&
            (!const {408, 409, 429}.contains(error.statusCode) || const {'SMART_FOLLOW_METADATA_NOT_AVAILABLE', 'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED', 'COPY_PREVIEW_EXPIRED'}.contains(error.code))) {
          await _removeMetadataPending(slot);
        }
        rethrow;
      }
    }();
    _metadataCreating[slot] = request;
    return request.whenComplete(() {
      if (identical(_metadataCreating[slot], request)) _metadataCreating.remove(slot);
    });
  }

  Future<SmartFollowMetadataUpdate> metadataUpdate(String updateId) async {
    final generation = _deviceGeneration;
    final result = await _gateway.metadataUpdate(updateId.trim());
    _checkDevice(generation);
    if (result.updateId != updateId.trim()) throw StateError('返回的信息更新任务不属于当前请求');
    final previous = _metadataSnapshots[result.updateId];
    if (previous != null && previous.stateVersionKnown && result.stateVersionKnown && result.stateVersion < previous.stateVersion) return previous;
    _metadataSnapshots[result.updateId] = result;
    return result;
  }

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
    final generation = _deviceGeneration;
    try {
      final sessionId = await _gateway.sessionIdForRecognitionJob(recognitionJobId);
      _checkDevice(generation);
      if (sessionId == null || sessionId.trim().isEmpty) return null;
      final recovered = await refresh(sessionId.trim());
      _checkDevice(generation);
      if (recovered.recognitionJobId != recognitionJobId) throw StateError('识别任务与跟随会话归属不一致。');
      return recovered;
    } catch (_) {
      _checkDevice(generation);
      // 恢复是尽力而为：识别事件接口不可用（旧盒子）时不影响正常创建路径。
      return null;
    }
  }

  /// 请求可能已经到达盒子但没拿到响应：此时"失败"不等于"没创建"。
  static bool _outcomeUnknown(ApiException error) {
    final cause = error.cause;
    if (cause is! DioException) return false;
    return switch (cause.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout || DioExceptionType.transformTimeout || DioExceptionType.connectionError || DioExceptionType.unknown => true,
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
