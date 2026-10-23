import 'dart:async';

import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/copy/data/active_copy_job_store.dart';
import 'package:aves/bird_companion/features/copy/data/copy_request_diagnostics.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 复制任务详情状态（阶段 D 实施计划批次 4）。
class CopyJobDetailState {
  const CopyJobDetailState({
    this.detail,
    this.events = const [],
    this.lastEventSeq = 0,
    this.failedItems = const [],
    this.failedHasMore = false,
    this.failedCursor,
    this.report,
    this.loading = false,
    this.acting = false,
    this.error,
    this.eventsError,
    this.reportError,
    this.failedItemsError,
    this.jobMissing = false,
    this.notice,
    this.devices = const [],
    this.sourceNameSnapshot,
    this.targetNameSnapshot,
  });

  final CopyJobDetail? detail;

  /// 按 seq 升序累积的事件（缺 seq 的事件不参与增量去重，直接丢弃）。
  final List<CopyJobEvent> events;
  final int lastEventSeq;

  /// 失败项累积分页（后端 cursor 分页，不前端去重——迁移对照 §3.6）。
  final List<CopyJobItem> failedItems;
  final bool failedHasMore;
  final String? failedCursor;

  final CopyReport? report;
  final bool loading;
  final bool acting;
  final Object? error;
  final Object? eventsError;
  final Object? reportError;
  final Object? failedItemsError;
  final bool jobMissing;

  /// 操作结果提示（SnackBar 文案），页面消费后置空。
  final String? notice;
  final List<StorageDeviceSummary> devices;
  final CopyJobDeviceSnapshot? sourceNameSnapshot, targetNameSnapshot;

  bool get isTerminal => detail?.state.isTerminal ?? false;

  CopyJobDetailState copyWith({
    CopyJobDetail? detail,
    List<CopyJobEvent>? events,
    int? lastEventSeq,
    List<CopyJobItem>? failedItems,
    bool? failedHasMore,
    String? failedCursor,
    CopyReport? report,
    bool clearReport = false,
    bool? loading,
    bool? acting,
    Object? error,
    bool clearError = false,
    Object? eventsError,
    bool clearEventsError = false,
    Object? reportError,
    bool clearReportError = false,
    Object? failedItemsError,
    bool clearFailedItemsError = false,
    bool? jobMissing,
    String? notice,
    bool clearNotice = false,
    List<StorageDeviceSummary>? devices,
  }) => CopyJobDetailState(
    detail: detail ?? this.detail,
    events: events ?? this.events,
    lastEventSeq: lastEventSeq ?? this.lastEventSeq,
    failedItems: failedItems ?? this.failedItems,
    failedHasMore: failedHasMore ?? this.failedHasMore,
    failedCursor: failedCursor ?? this.failedCursor,
    report: clearReport ? null : report ?? this.report,
    loading: loading ?? this.loading,
    acting: acting ?? this.acting,
    error: clearError ? null : error ?? this.error,
    eventsError: clearEventsError ? null : eventsError ?? this.eventsError,
    reportError: clearReportError ? null : reportError ?? this.reportError,
    failedItemsError: clearFailedItemsError ? null : failedItemsError ?? this.failedItemsError,
    jobMissing: jobMissing ?? this.jobMissing,
    notice: clearNotice ? null : notice ?? this.notice,
    devices: devices ?? this.devices,
    sourceNameSnapshot: _retainSnapshot(sourceNameSnapshot, detail?.sourceDevice),
    targetNameSnapshot: _retainSnapshot(targetNameSnapshot, detail?.targetDevice),
  );
}

CopyJobDeviceSnapshot? _retainSnapshot(CopyJobDeviceSnapshot? previous, CopyJobDeviceSnapshot? next) {
  if (previous?.mediaId != null && next?.mediaId != null && previous!.mediaId != next!.mediaId) return next;
  return previous?.presentationLabel != null ? previous : next ?? previous;
}

/// 复制任务详情状态机：详情 + 增量事件 + 失败项分页 + 报告 + 动作。
class CopyJobDetailCubit extends Cubit<CopyJobDetailState> {
  CopyJobDetailCubit(this._repository, {required this.copyJobId, this.deviceId, this.activeJobs, this.canRead, this.diagnostics, this.detailReader, this.deviceReader, Stream<void>? sessionRefreshes}) : super(const CopyJobDetailState()) {
    _sessionSubscription = sessionRefreshes?.listen((_) => sessionChanged());
  }

  final CopyJobRepository _repository;
  final String copyJobId;
  final String? deviceId;
  final ActiveCopyJobStore? activeJobs;
  final bool Function()? canRead;
  final CopyRequestDiagnostics? diagnostics;
  final Future<CopyJobDetail> Function(String trigger)? detailReader;
  final Future<CopyDeviceList> Function()? deviceReader;
  Future<void>? _deviceNamesRead;
  int? _deviceNamesGeneration;
  bool _deviceNamesLoaded = false;
  Completer<CopyDeviceList>? _deviceNamesCancellation;
  StreamSubscription<void>? _sessionSubscription;
  Timer? _timer;
  bool _automatic = false;
  bool _foreground = true;
  int _detailFailures = 0;
  int _terminalEventAttempts = 0;
  bool _terminalEventsLoaded = false;
  String _trigger = 'initial';
  bool _eventGapRetryUsed = false;
  int _loadGeneration = 0;
  int? _detailReadGeneration;
  Future<void>? _detailRead;
  int? _eventsGeneration;
  Future<void>? _eventsRead;
  int? _reportGeneration;
  Future<void>? _reportRead;
  int? _failuresGeneration;
  Future<void>? _failuresRead;
  bool _failuresLoaded = false;
  bool _loadingMoreFailures = false;
  int _reportAttempts = 0;
  int _failureAttempts = 0;
  static const maximumTerminalAttempts = 5;

  bool get _readable => canRead?.call() ?? true;
  bool get deviceAvailable => _readable;
  bool _current(int generation) => !isClosed && generation == _loadGeneration && _readable;

  bool get needsTerminalRefresh =>
      state.isTerminal &&
      ((state.report == null && _reportAttempts < maximumTerminalAttempts) || (!_failuresLoaded && _failureAttempts < maximumTerminalAttempts) || (!_terminalEventsLoaded && _terminalEventAttempts < maximumTerminalAttempts));

  void startPolling({bool foreground = true}) {
    _automatic = true;
    _foreground = foreground;
    if (!_readable) {
      sessionChanged();
    } else if (_foreground) {
      unawaited(load());
    }
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground && _automatic) {
      _trigger = 'foreground';
      unawaited(pollTick());
    }
    _schedule();
  }

  void sessionChanged() {
    if (isClosed) return;
    if (!_readable) {
      ++_loadGeneration;
      _deviceNamesLoaded = false;
      _deviceNamesCancellation?.complete(const CopyDeviceList(devices: []));
      _deviceNamesCancellation = null;
      _timer?.cancel();
      emit(state.copyWith(loading: false, acting: false, devices: const [], error: StateError('请连接创建此任务的盒子后继续读取。')));
    } else if (_foreground && _automatic) {
      _trigger = 'session_recovery';
      unawaited(load());
    }
  }

  Duration _backoff(int failures) => Duration(
    seconds: switch (failures) {
      <= 1 => 2,
      2 => 4,
      3 => 8,
      _ => 15,
    },
  );

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_automatic || !_foreground || !_readable || isClosed || state.acting || state.loading || state.jobMissing) return;
    if (state.isTerminal && !needsTerminalRefresh) return;
    final attempts = _reportAttempts > _failureAttempts ? _reportAttempts : _failureAttempts;
    final interval = _detailFailures > 0
        ? _backoff(_detailFailures)
        : state.isTerminal
        ? _backoff(attempts > _terminalEventAttempts ? attempts : _terminalEventAttempts)
        : Duration(seconds: state.detail?.state.isWaitingDevice == true ? 5 : 2);
    _timer = Timer(interval, () {
      _timer = null;
      _trigger = 'poll';
      unawaited(pollTick());
    });
  }

  Future<T> _request<T>(String endpoint, Future<T> Function() request) => diagnostics == null ? request() : diagnostics!.request(endpoint, copyJobId, request, deviceId: deviceId, trigger: _trigger);

  Future<void> _remember(CopyJobDetail detail) async {
    final device = deviceId, store = activeJobs;
    if (device == null || store == null) return;
    try {
      await store.remember(device, copyJobId, detail.state, stateVersion: detail.stateVersion);
    } catch (error) {
      diagnostics?.record('active_task_store', copyJobId, deviceId: device, error: error);
    }
  }

  /// 全量加载（进入页面 / 版本冲突后的自动刷新 / 手动下拉 / 事件缺口恢复）。
  Future<void> load() {
    if (isClosed || state.acting || !_readable) return Future<void>.value();
    if (_detailRead != null && _detailReadGeneration == _loadGeneration) return _detailRead!;
    _reportAttempts = 0;
    _failureAttempts = 0;
    _terminalEventAttempts = 0;
    return _readDetail(full: true);
  }

  Future<void> _readDetail({required bool full}) {
    final generation = _loadGeneration;
    if (_detailRead != null && _detailReadGeneration == generation) return _detailRead!;
    _detailReadGeneration = generation;
    final future = _performRead(generation, full: full);
    _detailRead = future;
    return future;
  }

  Future<void> _performRead(int generation, {required bool full}) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      Future<CopyJobDetail> request() => _request('detail', () async {
        final detail = await _repository.getJob(copyJobId);
        if (detail.copyJobId != copyJobId) throw const ProtocolCompatibilityException('copy_job_id', '任务身份与请求不一致');
        return detail;
      });
      final detail = detailReader == null ? await request() : await detailReader!(_trigger);
      if (!_current(generation)) return;
      _detailFailures = 0;
      emit(state.copyWith(detail: detail, loading: false, clearError: true, jobMissing: false, clearReport: !detail.state.isTerminal));
      if (full || !_deviceNamesLoaded) unawaited(refreshDeviceNames());
      unawaited(_remember(detail));
    } catch (error) {
      if (!_current(generation)) return;
      _detailFailures++;
      final missing = error is ApiException && error.statusCode == 404;
      emit(state.copyWith(loading: false, error: error, jobMissing: missing));
      if (missing && deviceId != null && activeJobs != null) {
        try {
          await activeJobs!.forget(deviceId!, copyJobId);
        } catch (error) {
          diagnostics?.record('active_task_store', copyJobId, deviceId: deviceId, error: error);
        }
      }
      return;
    } finally {
      if (_detailReadGeneration == generation) {
        _detailRead = null;
        _detailReadGeneration = null;
      }
      if (_current(generation)) _schedule();
    }
    if (!_current(generation)) return;
    // Each endpoint has its own in-flight guard. Slow event/report reads cannot
    // prevent the next detail tick, and failures never discard a valid detail.
    await Future.wait([
      _readEvents(generation, full: full),
      if (state.isTerminal) _loadReportAndFailures(generation),
    ]);
  }

  /// 轮询 tick：loading 中幂等跳过；运行态拉增量事件，终态补报告。
  Future<void> pollTick() async {
    if (state.acting || isClosed || !_readable || state.jobMissing) return;
    if (state.isTerminal) {
      await Future.wait([
        _loadReportAndFailures(_loadGeneration),
        if (!_terminalEventsLoaded && _terminalEventAttempts < maximumTerminalAttempts) _readEvents(_loadGeneration, full: false),
      ]);
    } else {
      await _readDetail(full: state.detail == null);
    }
  }

  Future<void> retrySupplemental() async {
    if (isClosed || !_readable || state.acting || state.jobMissing) return;
    _reportAttempts = 0;
    _failureAttempts = 0;
    _terminalEventAttempts = 0;
    unawaited(refreshDeviceNames());
    await Future.wait([
      _readEvents(_loadGeneration, full: false),
      if (state.isTerminal) _loadReportAndFailures(_loadGeneration),
    ]);
  }

  /// Optional names are independent of detail/events/report/actions. A slow or
  /// failed storage endpoint must never block the task loop.
  Future<void> refreshDeviceNames() {
    if (deviceReader == null || isClosed || !_readable) return Future.value();
    final generation = _loadGeneration;
    if (_deviceNamesRead != null && _deviceNamesGeneration == generation) return _deviceNamesRead!;
    _deviceNamesGeneration = generation;
    final cancellation = Completer<CopyDeviceList>();
    _deviceNamesCancellation = cancellation;
    return _deviceNamesRead = _performDeviceNamesRead(generation, cancellation);
  }

  Future<void> _performDeviceNamesRead(int generation, Completer<CopyDeviceList> cancellation) async {
    try {
      final result = await Future.any([deviceReader!(), cancellation.future]).timeout(const Duration(seconds: 15));
      if (!_current(generation)) return;
      emit(state.copyWith(devices: List.unmodifiable(result.devices)));
    } catch (_) {
      // Keep frozen task snapshots and task controls available.
    } finally {
      if (_deviceNamesGeneration == generation) {
        _deviceNamesLoaded = true;
        _deviceNamesRead = null;
        _deviceNamesGeneration = null;
        _deviceNamesCancellation = null;
      }
    }
  }

  Future<void> _readEvents(int generation, {required bool full}) {
    if (_eventsRead != null && _eventsGeneration == generation) return _eventsRead!;
    _eventsGeneration = generation;
    final future = _performEventsRead(generation, full: full);
    _eventsRead = future;
    return future;
  }

  Future<void> _performEventsRead(int generation, {required bool full}) async {
    if (state.isTerminal) _terminalEventAttempts++;
    try {
      final lastSeqBefore = state.lastEventSeq;
      final eventPage = await _allEventPages(generation, afterSeq: full ? null : lastSeqBefore);
      if (!_current(generation)) return;
      // 缺口判断必须在合并前：合并后 lastEventSeq 已被推进，跳号会被掩盖。
      final hasGap = !full && lastSeqBefore > 0 && eventPage.events.isNotEmpty && eventPage.events.first.seq != null && eventPage.events.first.seq! > lastSeqBefore + 1;
      emit(_mergeEventPage(state, eventPage).copyWith(clearEventsError: true));
      if (state.isTerminal) _terminalEventsLoaded = true;
      if (!hasGap) {
        // 连续一次无缺口的增量页才清标记（缺口源仍在时保持，防无限重拉）。
        _eventGapRetryUsed = false;
        return;
      }
      // 缺口恢复：从 0 重拉一次；恢复后仍不连续说明事件流损坏，报错防死循环。
      if (_eventGapRetryUsed) {
        emit(
          state.copyWith(eventsError: StateError('事件流出现缺口，请手动刷新')),
        );
        return;
      }
      _eventGapRetryUsed = true;
      await _reloadEventsFromZero(generation);
    } catch (error) {
      if (!_current(generation)) return;
      _terminalEventsLoaded = false;
      emit(state.copyWith(eventsError: error));
    } finally {
      if (_eventsGeneration == generation) {
        _eventsRead = null;
        _eventsGeneration = null;
      }
      if (_current(generation)) _schedule();
    }
  }

  /// 从 0 重拉事件（缺口恢复）；恢复后仍跳号则报错防死循环。
  Future<void> _reloadEventsFromZero(int generation) async {
    try {
      final eventPage = await _allEventPages(generation);
      if (!_current(generation)) return;
      final merged = _mergeEventPage(state, eventPage);
      if (_hasInternalGap(merged.events)) {
        emit(
          merged.copyWith(eventsError: StateError('事件流出现缺口，请手动刷新')),
        );
        return;
      }
      emit(merged.copyWith(clearEventsError: true));
    } catch (error) {
      if (!_current(generation)) return;
      emit(state.copyWith(eventsError: error));
    }
  }

  /// 事件 seq 集合内部存在跳号（与增量缺口同一假设：seq 连续）。
  Future<CopyJobEventPage> _allEventPages(int generation, {int? afterSeq}) async {
    final events = <CopyJobEvent>[];
    var cursor = afterSeq;
    while (_current(generation)) {
      final page = await _request('events', () => _repository.jobEvents(copyJobId, afterSeq: cursor));
      if (!_current(generation)) break;
      events.addAll(page.events);
      if (!page.hasMore) break;
      final next = page.events.lastOrNull?.seq;
      if (next == null || next <= (cursor ?? 0)) {
        throw StateError('事件分页未推进，请手动刷新');
      }
      cursor = next;
    }
    return CopyJobEventPage(events: events, hasMore: false);
  }

  bool _hasInternalGap(List<CopyJobEvent> events) {
    final seqs = events.where((event) => event.seq != null).map((event) => event.seq!).toList()..sort();
    for (var i = 1; i < seqs.length; i++) {
      if (seqs[i] > seqs[i - 1] + 1) return true;
    }
    return false;
  }

  Future<void> loadMoreFailedItems() async {
    if (!state.failedHasMore || state.acting || isClosed || _loadingMoreFailures || !_readable || state.jobMissing) return;
    final generation = _loadGeneration;
    _loadingMoreFailures = true;
    try {
      final page = await _request(
        'failed_items_page',
        () => _repository.jobItems(
          copyJobId,
          cursor: state.failedCursor,
          state: 'failed',
        ),
      );
      if (!_current(generation)) return;
      emit(
        state.copyWith(
          failedItems: [...state.failedItems, ...page.items],
          failedHasMore: page.hasMore,
          failedCursor: page.nextCursor,
          clearFailedItemsError: true,
        ),
      );
    } catch (error) {
      if (!_current(generation)) return;
      emit(state.copyWith(failedItemsError: error));
    } finally {
      _loadingMoreFailures = false;
    }
  }

  /// 执行任务动作（§13.6）。版本冲突时自动重拉详情并提示。
  Future<void> act(CopyAllowedAction action) async {
    final detail = state.detail;
    if (detail == null || state.acting || isClosed || !_readable || state.jobMissing) return;
    if (!detail.allowedActions.contains(action)) return;
    // An action supersedes every read started before it, including event pages.
    final generation = ++_loadGeneration;
    _deviceNamesCancellation?.complete(const CopyDeviceList(devices: []));
    _deviceNamesCancellation = null;
    _failuresLoaded = false;
    _terminalEventsLoaded = false;
    _timer?.cancel();
    emit(state.copyWith(acting: true, loading: false, clearNotice: true, clearError: true));
    try {
      if (action.wire == CopyAllowedAction.safeRemoveSource.wire || action.wire == CopyAllowedAction.safeRemoveTarget.wire) {
        final source = action.wire == CopyAllowedAction.safeRemoveSource.wire;
        final mediaId = (source ? detail.sourceDevice : detail.targetDevice)?.mediaId;
        if (mediaId == null || mediaId.trim().isEmpty) {
          throw StateError('设备信息不可用，无法安全移除');
        }
        final result = await _request(
          'safe_remove',
          () => _repository.safeRemoveDevice(
            mediaId,
            role: source ? 'source' : 'target',
            expectedCopyJobId: copyJobId,
          ),
        );
        if (!result.safeToRemove) {
          throw StateError(result.reason ?? '设备当前仍被复制任务占用');
        }
        if (!_current(generation)) return;
        emit(state.copyWith(acting: false, notice: '现在可以拔出设备（保持期 60 秒）'));
        await load();
        return;
      }
      await _request(
        'action_${action.wire}',
        () => _repository.jobAction(
          copyJobId,
          action.wire,
          expectedStateVersion: detail.stateVersion,
        ),
      );
      if (!_current(generation)) return;
      emit(state.copyWith(acting: false, notice: '${action.label}指令已送达'));
      await load();
    } on Object catch (error) {
      if (!_current(generation)) return;
      final message = UserMessageMapper.fromError(error);
      final conflict = error is ApiException && error.code == 'COPY_STATE_VERSION_CONFLICT';
      emit(
        state.copyWith(
          acting: false,
          notice: conflict ? '任务状态已更新，已刷新' : '${message.title}：${message.message}',
        ),
      );
      if (conflict) await load();
    } finally {
      if (_current(generation)) _schedule();
    }
  }

  /// 合并一页事件：按 seq 去重升序。缺口检测由调用方 [pollTick] 处理
  /// （[load] 从 0 拉全量，无需检测）。
  CopyJobDetailState _mergeEventPage(
    CopyJobDetailState base,
    CopyJobEventPage page,
  ) {
    final known = {for (final event in base.events) event.seq: event};
    for (final event in page.events) {
      if (event.seq == null) continue;
      known[event.seq] = event;
    }
    final merged = known.values.toList()..sort((a, b) => a.seq!.compareTo(b.seq!));
    return base.copyWith(
      events: merged,
      lastEventSeq: merged.isEmpty ? base.lastEventSeq : merged.last.seq!,
    );
  }

  Future<void> _loadReportAndFailures(int generation) => Future.wait([
    if (state.report == null && _reportAttempts < maximumTerminalAttempts) _readReport(generation),
    if (!_failuresLoaded && _failureAttempts < maximumTerminalAttempts) _readFailures(generation),
  ]);

  Future<void> _readReport(int generation) {
    if (_reportRead != null && _reportGeneration == generation) return _reportRead!;
    _reportGeneration = generation;
    final future = _performReportRead(generation);
    _reportRead = future;
    return future;
  }

  Future<void> _performReportRead(int generation) async {
    _reportAttempts++;
    try {
      final report = await _request('report', () => _repository.jobReport(copyJobId));
      if (!_current(generation)) return;
      if (report.copyJobId != null && report.copyJobId != copyJobId) throw const ProtocolCompatibilityException('copy_job_id', '报告与当前任务不一致');
      emit(state.copyWith(report: report, clearReportError: true));
    } catch (error) {
      if (!_current(generation)) return;
      emit(state.copyWith(reportError: error));
    } finally {
      if (_reportGeneration == generation) {
        _reportRead = null;
        _reportGeneration = null;
      }
      if (_current(generation)) _schedule();
    }
  }

  Future<void> _readFailures(int generation) {
    if (_failuresRead != null && _failuresGeneration == generation) return _failuresRead!;
    _failuresGeneration = generation;
    final future = _performFailuresRead(generation);
    _failuresRead = future;
    return future;
  }

  Future<void> _performFailuresRead(int generation) async {
    _failureAttempts++;
    try {
      final page = await _request('failed_items', () => _repository.jobItems(copyJobId, state: 'failed'));
      if (!_current(generation)) return;
      _failuresLoaded = true;
      emit(
        state.copyWith(
          failedItems: page.items,
          failedHasMore: page.hasMore,
          failedCursor: page.nextCursor,
          clearFailedItemsError: true,
        ),
      );
    } catch (error) {
      if (_current(generation)) emit(state.copyWith(failedItemsError: error));
    } finally {
      if (_failuresGeneration == generation) {
        _failuresRead = null;
        _failuresGeneration = null;
      }
      if (_current(generation)) _schedule();
    }
  }

  /// 页面消费提示后调用。
  void consumeNotice() {
    if (!isClosed) emit(state.copyWith(clearNotice: true));
  }

  @override
  Future<void> close() async {
    ++_loadGeneration;
    _automatic = false;
    _timer?.cancel();
    _deviceNamesCancellation?.complete(const CopyDeviceList(devices: []));
    _deviceNamesCancellation = null;
    await _deviceNamesRead;
    await _sessionSubscription?.cancel();
    return super.close();
  }
}
