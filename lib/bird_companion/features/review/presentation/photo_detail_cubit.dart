import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/tag_input.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/domain/review_save_receipt.dart';
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
  void _emitIfOpen(PhotoDetailState next) {
    if (!isClosed) emit(next);
  }

  bool _loadInFlight = false;
  Future<void> load(String id) async {
    if (isClosed || _loadInFlight || state.saving) return;
    _loadInFlight = true;
    _emitIfOpen(PhotoDetailState(loading: true, undoEntry: state.undoEntry));
    try {
      _emitIfOpen(PhotoDetailState(detail: await _repository.detail(id), undoEntry: state.undoEntry));
    } catch (error) {
      _emitIfOpen(PhotoDetailState(error: error, undoEntry: state.undoEntry));
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> addTags(String fileId, List<String> tags) async {
    final detail = state.detail;
    if (detail == null || detail.photo.summary.id != fileId) return;
    final existingTags = detail.userTags;
    final existingNames = normalizeUserTags(existingTags).toSet();
    final additions = normalizeUserTags(tags).where((tag) => !existingNames.contains(tag)).toList();
    if (additions.isEmpty) return;

    final decision = detail.decision;
    await save(
      UserDecision(
        fileId: fileId,
        keepState: decision?.keepState ?? KeepStateWireValue.fromWire(detail.photo.summary.keepState),
        userScore: decision?.userScore,
        userSpeciesId: decision?.userSpeciesId,
        userSpecies: decision?.userSpecies,
        userTags: [...existingTags, ...additions],
        updatedAt: DateTime.now(),
        version: decision?.version ?? detail.photo.summary.version,
      ),
      successMessage: '标签添加成功',
    );
  }

  Future<void> save(
    UserDecision decision, {
    String successMessage = '修改已保存',
  }) async {
    if (isClosed || state.saving) return;
    if (state.conflict) {
      _emitIfOpen(
        state.copyWith(
          message: '请先载入盒子最新版本，或保留当前本机草稿。',
          messageIsError: true,
        ),
      );
      return;
    }
    final previous =
        state.detail?.decision ??
        UserDecision(
          fileId: decision.fileId,
          keepState: KeepStateWireValue.fromWire(state.detail?.photo.summary.keepState),
          userTags: state.detail?.userTags ?? const [],
          updatedAt: DateTime.now(),
          version: state.detail?.photo.summary.version,
        );
    _emitIfOpen(state.copyWith(saving: true));
    try {
      final receipt = await _saveWithReceipt(
        decision,
        projectId: projectId,
      );
      if (receipt.conflict) {
        final current = state.detail;
        _emitIfOpen(
          state.copyWith(
            detail: current == null ? null : _withDecision(current, decision),
            saving: false,
            conflict: true,
            pendingConflictDecision: decision,
          ),
        );
        return;
      }
      final accepted = receipt.authoritativeDecision ?? decision;
      final undo = ReviewUndoEntry(before: previous, after: accepted);
      final updated = await _detailAfterSave(receipt, accepted);
      _emitIfOpen(
        state.copyWith(
          detail: updated,
          saving: false,
          message: receipt.queued ? receipt.message : successMessage,
          messageIsError: false,
          undoEntry: undo,
        ),
      );
    } catch (error) {
      _emitIfOpen(
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
    if (isClosed || state.saving || state.conflict || entry == null) return;
    final currentVersion = state.detail?.decision?.version ?? state.detail?.photo.summary.version ?? entry.after.version;
    final desired = _decisionWithVersion(entry.before, currentVersion);
    _emitIfOpen(state.copyWith(saving: true));
    try {
      final receipt = await _saveWithReceipt(
        desired,
        projectId: projectId,
      );
      if (receipt.conflict) {
        final current = state.detail;
        _emitIfOpen(
          state.copyWith(
            detail: current == null ? null : _withDecision(current, desired),
            saving: false,
            conflict: true,
            pendingConflictDecision: desired,
          ),
        );
        return;
      }
      final accepted = receipt.authoritativeDecision ?? desired;
      final updated = await _detailAfterSave(receipt, accepted);
      _emitIfOpen(state.copyWith(detail: updated, saving: false, message: '已撤销最近一次修改', messageIsError: false, clearUndo: true));
    } catch (error) {
      _emitIfOpen(state.copyWith(saving: false, message: '撤销失败，请稍后重试', messageIsError: true, error: error));
    }
  }

  Future<void> useRemote(String fileId) async {
    if (isClosed || state.saving) return;
    _emitIfOpen(state.copyWith(saving: true));
    try {
      final repository = _repository;
      if (repository is RemoteReviewConflictResolver) {
        await (repository as RemoteReviewConflictResolver).acceptRemoteDecision(
          fileId,
          projectId: projectId,
        );
      }
      final remote = await _repository.detail(fileId);
      _emitIfOpen(
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
      _emitIfOpen(
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
    _emitIfOpen(
      state.copyWith(
        message: '本机草稿已保留，但尚未写入盒子。载入盒子最新版本前不会再次提交。',
        messageIsError: false,
      ),
    );
  }

  Future<ReviewSaveReceipt> _saveWithReceipt(
    UserDecision decision, {
    String? projectId,
  }) async {
    final repository = _repository;
    if (repository is AuthoritativeReviewWriter) {
      return (repository as AuthoritativeReviewWriter).saveAuthoritative(
        decision,
        projectId: projectId,
      );
    }
    return ReviewSaveReceipt.fromLegacy(
      await repository.save(decision, projectId: projectId),
    );
  }

  Future<ReviewDetail?> _detailAfterSave(
    ReviewSaveReceipt receipt,
    UserDecision decision,
  ) async {
    final authoritativePhoto = receipt.authoritativePhoto;
    final current = state.detail;
    if (authoritativePhoto != null && current != null) {
      return ReviewDetail(
        photo: PhotoDetail(
          summary: authoritativePhoto.copyWith(
            keepState: decision.keepState.wireValue,
          ),
          subjects: current.photo.subjects,
          tags: current.photo.tags,
          exif: current.photo.exif,
        ),
        decision: decision,
        history: current.history,
      );
    }
    final refreshed = await _refreshedDetail(decision.fileId);
    return refreshed == null ? null : _withDecision(refreshed, decision);
  }

  UserDecision _decisionWithVersion(
    UserDecision decision,
    int? version,
  ) => UserDecision(
    fileId: decision.fileId,
    keepState: decision.keepState,
    userScore: decision.userScore,
    userSpeciesId: decision.userSpeciesId,
    userSpecies: decision.userSpecies,
    userTags: decision.userTags,
    updatedAt: DateTime.now(),
    version: version,
  );

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
