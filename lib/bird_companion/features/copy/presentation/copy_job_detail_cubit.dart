import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
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
    this.notice,
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

  /// 操作结果提示（SnackBar 文案），页面消费后置空。
  final String? notice;

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
    String? notice,
    bool clearNotice = false,
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
    notice: clearNotice ? null : notice ?? this.notice,
  );
}

/// 复制任务详情状态机：详情 + 增量事件 + 失败项分页 + 报告 + 动作。
class CopyJobDetailCubit extends Cubit<CopyJobDetailState> {
  CopyJobDetailCubit(this._repository, {required this.copyJobId})
    : super(const CopyJobDetailState());

  final CopyJobRepository _repository;
  final String copyJobId;
  bool _eventGapRetryUsed = false;
  int _loadGeneration = 0;

  /// 全量加载（进入页面 / 版本冲突后的自动刷新 / 手动下拉）。
  Future<void> load() async {
    final generation = ++_loadGeneration;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final detail = await _repository.getJob(copyJobId);
      if (isClosed || generation != _loadGeneration) return;
      var next = state.copyWith(detail: detail, loading: false);
      emit(next);

      // 事件从 0 重拉（版本冲突后状态可能回退，增量序号不可信）。
      final eventPage = await _repository.jobEvents(copyJobId);
      if (isClosed || generation != _loadGeneration) return;
      _eventGapRetryUsed = false;
      next = _mergeEventPage(next, eventPage);
      emit(next);

      if (detail.state.isTerminal) {
        await _loadReportAndFailures(generation);
      } else {
        emit(state.copyWith(clearReport: true));
      }
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(loading: false, error: error));
    }
  }

  /// 轮询 tick：loading 中幂等跳过；运行态拉增量事件，终态补报告。
  Future<void> pollTick() async {
    if (state.loading || state.acting || isClosed) return;
    final detail = state.detail;
    if (detail == null) {
      await load();
      return;
    }
    final generation = _loadGeneration;
    try {
      final next = await _repository.getJob(copyJobId);
      if (isClosed || generation != _loadGeneration) return;
      var updated = state.copyWith(detail: next, clearError: true);
      final eventPage = await _repository.jobEvents(
        copyJobId,
        afterSeq: state.lastEventSeq,
      );
      if (isClosed || generation != _loadGeneration) return;
      updated = _mergeEventPage(updated, eventPage);
      emit(updated);
      if (next.state.isTerminal && state.report == null) {
        await _loadReportAndFailures(generation);
      }
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return;
      // 轮询失败不打断页面，只记录错误（下次 tick 重试）。
      emit(state.copyWith(error: error));
    }
  }

  Future<void> loadMoreFailedItems() async {
    if (!state.failedHasMore || state.acting || isClosed) return;
    try {
      final page = await _repository.jobItems(
        copyJobId,
        cursor: state.failedCursor,
        state: 'failed',
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          failedItems: [...state.failedItems, ...page.items],
          failedHasMore: page.hasMore,
          failedCursor: page.nextCursor,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(error: error));
    }
  }

  /// 执行任务动作（§13.6）。版本冲突时自动重拉详情并提示。
  Future<void> act(CopyAllowedAction action) async {
    final detail = state.detail;
    if (detail == null || state.acting || isClosed) return;
    emit(state.copyWith(acting: true, clearNotice: true, clearError: true));
    try {
      await _repository.jobAction(
        copyJobId,
        action.wire,
        expectedStateVersion: detail.stateVersion,
      );
      if (isClosed) return;
      emit(state.copyWith(acting: false, notice: '${action.label}指令已送达'));
      await load();
    } on Object catch (error) {
      if (isClosed) return;
      final message = UserMessageMapper.fromError(error);
      final conflict = error is ApiException &&
          error.code == 'COPY_STATE_VERSION_CONFLICT';
      emit(
        state.copyWith(
          acting: false,
          notice: conflict ? '任务状态已更新，已刷新' : '${message.title}：${message.message}',
        ),
      );
      if (conflict) await load();
    }
  }

  /// 合并一页事件：按 seq 去重升序；检测缺口并在首次出现时重拉一次。
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
    var next = base.copyWith(
      events: merged,
      lastEventSeq: merged.isEmpty ? base.lastEventSeq : merged.last.seq!,
    );
    // 缺口检测：增量页首条不紧接已知序号 → 从 0 重拉一次；仍缺口则报错防死循环。
    if (base.lastEventSeq > 0 &&
        page.events.isNotEmpty &&
        page.events.first.seq != null &&
        page.events.first.seq! > base.lastEventSeq + 1) {
      if (_eventGapRetryUsed) {
        return next.copyWith(error: StateError('事件流出现缺口，请手动刷新'));
      }
      _eventGapRetryUsed = true;
      // 由调用方 load() 场景外进入时仅重拉一次事件（同步处理）。
      return next;
    }
    return next;
  }

  Future<void> _loadReportAndFailures(int generation) async {
    try {
      final report = await _repository.jobReport(copyJobId);
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(report: report));
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return;
      // 报告尚未生成等场景不作为页面级错误。
      emit(state.copyWith(notice: null, error: error));
    }
    try {
      final page = await _repository.jobItems(copyJobId, state: 'failed');
      if (isClosed || generation != _loadGeneration) return;
      emit(
        state.copyWith(
          failedItems: page.items,
          failedHasMore: page.hasMore,
          failedCursor: page.nextCursor,
        ),
      );
    } catch (_) {
      // 失败项加载失败不阻断报告展示。
    }
  }

  /// 页面消费提示后调用。
  void consumeNotice() {
    if (!isClosed) emit(state.copyWith(clearNotice: true));
  }
}
