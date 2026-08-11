import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/domain/review_undo_entry.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PhotoDetailState {
  const PhotoDetailState({
    this.detail,
    this.loading = false,
    this.saving = false,
    this.message,
    this.messageIsError = false,
    this.error,
    this.conflict = false,
    this.pendingConflictDecision,
    this.undoEntry,
  });
  final ReviewDetail? detail;
  final bool loading, saving, conflict;
  final String? message;
  final bool messageIsError;
  final Object? error;
  final UserDecision? pendingConflictDecision;
  final ReviewUndoEntry? undoEntry;
  bool get canUndo => undoEntry != null && !saving;
  PhotoDetailState copyWith({
    ReviewDetail? detail,
    bool? loading,
    bool? saving,
    String? message,
    bool? messageIsError,
    Object? error,
    bool? conflict,
    UserDecision? pendingConflictDecision,
    ReviewUndoEntry? undoEntry,
    bool clearConflict = false,
    bool clearUndo = false,
  }) => PhotoDetailState(
    detail: detail ?? this.detail,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    message: message,
    messageIsError: messageIsError ?? this.messageIsError,
    error: error ?? this.error,
    conflict: clearConflict ? false : conflict ?? this.conflict,
    pendingConflictDecision: clearConflict ? null : pendingConflictDecision ?? this.pendingConflictDecision,
    undoEntry: clearUndo ? null : undoEntry ?? this.undoEntry,
  );
}

class PhotoDetailCubit extends Cubit<PhotoDetailState> {
  PhotoDetailCubit(
    this._repository, [
    SessionRefreshCoordinator? refreshCoordinator,
    this._dataChanges,
    this.projectId,
  ]) : super(const PhotoDetailState());
  final ReviewRepository _repository;
  final AppDataChangeBus? _dataChanges;
  final String? projectId;
  bool _loadInFlight = false;
  Future<void> load(String id) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    emit(PhotoDetailState(loading: true, undoEntry: state.undoEntry));
    try {
      emit(PhotoDetailState(detail: await _repository.detail(id), undoEntry: state.undoEntry));
    } catch (error) {
      emit(PhotoDetailState(error: error, undoEntry: state.undoEntry));
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> save(
    UserDecision decision, {
    String successMessage = '修改已保存',
  }) async {
    final previous =
        state.detail?.decision ??
        UserDecision(
          fileId: decision.fileId,
          keepState: KeepState.pending,
          updatedAt: DateTime.now(),
          version: state.detail?.photo.summary.version,
        );
    emit(state.copyWith(saving: true));
    try {
      final result = await _repository.save(
        decision,
        projectId: projectId,
      );
      if (result.conflict) {
        emit(state.copyWith(saving: false, conflict: true, pendingConflictDecision: decision, message: result.message));
        return;
      }
      final undo = ReviewUndoEntry(before: previous, after: decision);
      final refreshed = await _refreshedDetail(decision.fileId);
      final updated = refreshed == null ? null : _withDecision(refreshed, decision);
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'photo_review_saved');
      emit(
        state.copyWith(
          detail: updated,
          saving: false,
          message: result.queued ? result.message : successMessage,
          messageIsError: false,
          undoEntry: undo,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          saving: false,
          message: error is ProtocolCompatibilityException ? '照片缺少有效版本，请刷新后重试' : '保存失败，请稍后重试',
          messageIsError: true,
          error: error,
        ),
      );
    }
  }

  Future<void> undo() async {
    final entry = state.undoEntry;
    if (entry == null) return;
    emit(state.copyWith(saving: true));
    final result = await _repository.save(
      entry.before,
      projectId: projectId,
    );
    if (result.conflict) {
      emit(state.copyWith(saving: false, conflict: true, pendingConflictDecision: entry.before, message: result.message));
      return;
    }
    final refreshed = await _refreshedDetail(entry.before.fileId);
    final updated = refreshed == null ? null : _withDecision(refreshed, entry.before);
    _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'photo_review_undone');
    emit(state.copyWith(detail: updated, saving: false, message: '已撤销最近一次修改', messageIsError: false, clearUndo: true));
  }

  Future<void> useRemote(String fileId) async {
    emit(state.copyWith(saving: true));
    try {
      final repository = _repository;
      if (repository is RemoteReviewConflictResolver) {
        await (repository as RemoteReviewConflictResolver).acceptRemoteDecision(
          fileId,
          projectId: projectId,
        );
      }
      final remote = await _repository.detail(fileId);
      emit(
        state.copyWith(
          detail: remote,
          saving: false,
          clearConflict: true,
          clearUndo: true,
          message: '已使用盒子中的最新内容',
          messageIsError: false,
        ),
      );
      _dataChanges?.publish(
        {AppDataResource.photos, AppDataResource.batches},
        reason: 'photo_review_remote_accepted',
      );
    } catch (error) {
      emit(
        state.copyWith(
          saving: false,
          message: '无法获取盒子中的最新内容，请稍后重试',
          messageIsError: true,
          error: error,
        ),
      );
    }
  }

  Future<void> keepLocal() async {
    emit(state.copyWith(clearConflict: true));
    emit(
      state.copyWith(
        message: '盒子内容未被覆盖：当前协议未提供强制保存能力，请稍后在照片详情中重试。',
        messageIsError: true,
      ),
    );
  }

  Future<ReviewDetail?> _refreshedDetail(String fileId) async {
    try {
      return await _repository.detail(fileId);
    } catch (_) {
      return state.detail;
    }
  }

  ReviewDetail _withDecision(ReviewDetail detail, UserDecision decision) {
    final remoteDecision = detail.decision;
    final effectiveDecision = UserDecision(
      fileId: decision.fileId,
      keepState: decision.keepState,
      userScore: decision.userScore,
      userSpeciesId: decision.userSpeciesId,
      userSpecies: decision.userSpecies,
      userTags: decision.userTags,
      updatedAt: decision.updatedAt ?? remoteDecision?.updatedAt,
      version: remoteDecision?.version ?? decision.version,
    );
    final photo = detail.photo;
    return ReviewDetail(
      photo: PhotoDetail(
        summary: photo.summary.copyWith(keepState: decision.keepState.wireValue),
        subjects: photo.subjects,
        tags: photo.tags,
        exif: photo.exif,
      ),
      decision: effectiveDecision,
      history: detail.history,
    );
  }
}
