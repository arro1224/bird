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
    this.conflict = false,
    this.pendingConflictDecision,
    this.undoEntry,
  });
  final ReviewDetail? detail;
  final bool loading, saving, conflict;
  final String? message;
  final bool messageIsError;
  final UserDecision? pendingConflictDecision;
  final ReviewUndoEntry? undoEntry;
  bool get canUndo => undoEntry != null && !saving;
  PhotoDetailState copyWith({
    ReviewDetail? detail,
    bool? loading,
    bool? saving,
    String? message,
    bool? messageIsError,
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
    conflict: clearConflict ? false : conflict ?? this.conflict,
    pendingConflictDecision: clearConflict ? null : pendingConflictDecision ?? this.pendingConflictDecision,
    undoEntry: clearUndo ? null : undoEntry ?? this.undoEntry,
  );
}

class PhotoDetailCubit extends Cubit<PhotoDetailState> {
  PhotoDetailCubit(this._repository, [SessionRefreshCoordinator? refreshCoordinator, this._dataChanges]) : super(const PhotoDetailState());
  final ReviewRepository _repository;
  final AppDataChangeBus? _dataChanges;
  bool _loadInFlight = false;
  Future<void> load(String id) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    emit(PhotoDetailState(loading: true, undoEntry: state.undoEntry));
    try {
      emit(PhotoDetailState(detail: await _repository.detail(id), undoEntry: state.undoEntry));
    } catch (error) {
      emit(state.copyWith(loading: false, message: error.toString()));
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> save(UserDecision decision) async {
    final previous = state.detail?.decision ?? UserDecision(fileId: decision.fileId, keepState: KeepState.pending, updatedAt: DateTime.now());
    emit(state.copyWith(saving: true));
    final result = await _repository.save(decision);
    if (result.conflict) {
      emit(state.copyWith(saving: false, conflict: true, pendingConflictDecision: decision, message: result.message));
      return;
    }
    final undo = ReviewUndoEntry(before: previous, after: decision);
    await load(decision.fileId);
    _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'photo_review_saved');
    emit(
      state.copyWith(
        message: result.queued ? result.message : '修改已保存',
        messageIsError: false,
        undoEntry: undo,
      ),
    );
  }

  Future<void> undo() async {
    final entry = state.undoEntry;
    if (entry == null) return;
    emit(state.copyWith(saving: true));
    final result = await _repository.save(entry.before);
    if (result.conflict) {
      emit(state.copyWith(saving: false, conflict: true, pendingConflictDecision: entry.before, message: result.message));
      return;
    }
    await load(entry.before.fileId);
    _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'photo_review_undone');
    emit(state.copyWith(message: '已撤销最近一次修改', messageIsError: false, clearUndo: true));
  }

  Future<void> useRemote(String fileId) async {
    emit(state.copyWith(clearConflict: true));
    await load(fileId);
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
}
