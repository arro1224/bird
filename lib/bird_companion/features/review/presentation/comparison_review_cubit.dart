import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ComparisonReviewState {
  const ComparisonReviewState({
    this.items = const [],
    this.loading = false,
    this.savingId,
    this.savingBoth = false,
    this.error,
    this.message,
    this.messageIsError = false,
  });
  final List<ReviewDetail> items;
  final bool loading;
  final String? savingId;
  final bool savingBoth;
  final Object? error;
  final String? message;
  final bool messageIsError;

  bool get saving => savingId != null || savingBoth;
}

class ComparisonReviewCubit extends Cubit<ComparisonReviewState> {
  ComparisonReviewCubit(
    this._repository, [
    this._refreshCoordinator,
    this._dataChanges,
    this.projectId,
  ]) : super(const ComparisonReviewState());
  final ReviewRepository _repository;
  final SessionRefreshCoordinator? _refreshCoordinator;
  final AppDataChangeBus? _dataChanges;
  final String? projectId;

  Future<void> load(List<String> ids) async {
    emit(const ComparisonReviewState(loading: true));
    try {
      emit(
        ComparisonReviewState(
          items: await Future.wait(
            ids.take(2).map(_repository.detail),
          ),
        ),
      );
    } catch (error) {
      emit(ComparisonReviewState(error: error));
    }
  }

  Future<void> mark(String fileId, KeepState value) async {
    if (state.saving || !state.items.any((item) => item.photo.summary.id == fileId)) return;
    final nextStates = <String, KeepState>{fileId: value};
    // A comparison can have only one featured photo, but changing a normal
    // keep/discard state must never rewrite the other photo's decision.
    if (value == KeepState.featured) {
      for (final item in state.items) {
        final id = item.photo.summary.id;
        if (id != fileId && _decisionState(item) == KeepState.featured) {
          nextStates[id] = KeepState.keep;
        }
      }
    }
    await _saveStates(nextStates, savingId: fileId);
  }

  Future<void> keepBoth() async {
    if (state.saving || state.items.length < 2) return;
    final nextStates = {
      for (final item in state.items.take(2)) item.photo.summary.id: _decisionState(item) == KeepState.featured ? KeepState.featured : KeepState.keep,
    };
    await _saveStates(
      nextStates,
      savingBoth: true,
      successMessage: '已保留两张照片',
    );
  }

  Future<void> keepAll() async {
    if (state.saving || state.items.length < 2) return;
    final nextStates = {
      for (final item in state.items) item.photo.summary.id: _decisionState(item) == KeepState.featured ? KeepState.featured : KeepState.keep,
    };
    await _saveStates(
      nextStates,
      savingBoth: true,
      successMessage: '已保留全部对比照片',
    );
  }

  Future<void> _saveStates(
    Map<String, KeepState> nextStates, {
    String? savingId,
    bool savingBoth = false,
    String successMessage = '照片状态已更新',
  }) async {
    final originalItems = state.items;
    emit(
      ComparisonReviewState(
        items: originalItems,
        savingId: savingId,
        savingBoth: savingBoth,
      ),
    );
    try {
      final changedItems = originalItems.where((item) {
        final nextState = nextStates[item.photo.summary.id];
        return nextState != null && _decisionState(item) != nextState;
      }).toList();
      final updatedAt = DateTime.now();
      final results = await Future.wait(
        changedItems.map(
          (item) => _repository.save(
            _decisionWithState(item, nextStates[item.photo.summary.id]!, updatedAt),
            projectId: projectId,
          ),
        ),
      );
      final conflict = results.where((result) => result.conflict).firstOrNull;
      if (conflict != null) {
        emit(
          ComparisonReviewState(
            items: originalItems,
            message: '照片状态已在盒子端更新，请重新加载后再试。',
            messageIsError: true,
          ),
        );
        return;
      }
      final updated = originalItems
          .map(
            (item) => nextStates[item.photo.summary.id] == null
                ? item
                : _detailWithState(
                    item,
                    nextStates[item.photo.summary.id]!,
                    updatedAt,
                  ),
          )
          .toList();
      _refreshCoordinator?.requestRefresh();
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'comparison_review_saved');
      emit(
        ComparisonReviewState(
          items: updated,
          message: results.where((result) => result.queued).firstOrNull?.message ?? successMessage,
        ),
      );
    } catch (error) {
      emit(ComparisonReviewState(items: originalItems, error: error));
    }
  }
}

KeepState _decisionState(ReviewDetail detail) => detail.decision?.keepState ?? KeepStateWireValue.fromWire(detail.photo.summary.keepState);

UserDecision _decisionWithState(
  ReviewDetail detail,
  KeepState keepState,
  DateTime updatedAt,
) {
  final previous = detail.decision;
  return UserDecision(
    fileId: detail.photo.summary.id,
    keepState: keepState,
    userScore: previous?.userScore,
    userSpeciesId: previous?.userSpeciesId,
    userSpecies: previous?.userSpecies,
    userTags: previous?.userTags ?? const [],
    updatedAt: updatedAt,
    version: previous?.version,
  );
}

ReviewDetail _detailWithState(
  ReviewDetail detail,
  KeepState keepState,
  DateTime updatedAt,
) => ReviewDetail(
  photo: PhotoDetail(
    summary: detail.photo.summary.copyWith(keepState: keepState.wireValue),
    subjects: detail.photo.subjects,
    tags: detail.photo.tags,
    exif: detail.photo.exif,
  ),
  decision: _decisionWithState(detail, keepState, updatedAt),
  history: detail.history,
);
