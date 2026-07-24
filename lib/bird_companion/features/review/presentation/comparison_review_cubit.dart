import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ComparisonReviewState {
  const ComparisonReviewState({this.items = const [], this.loading = false, this.savingId, this.error, this.message});
  final List<ReviewDetail> items;
  final bool loading;
  final String? savingId;
  final Object? error;
  final String? message;
}

class ComparisonReviewCubit extends Cubit<ComparisonReviewState> {
  ComparisonReviewCubit(this._repository, [this._refreshCoordinator, this._dataChanges]) : super(const ComparisonReviewState());
  final ReviewRepository _repository;
  final SessionRefreshCoordinator? _refreshCoordinator;
  final AppDataChangeBus? _dataChanges;

  Future<void> load(List<String> ids) async {
    emit(const ComparisonReviewState(loading: true));
    try {
      emit(ComparisonReviewState(items: await Future.wait(ids.take(2).map(_repository.detail))));
    } catch (error) {
      emit(ComparisonReviewState(error: error));
    }
  }

  Future<void> mark(String fileId, KeepState value) async {
    emit(ComparisonReviewState(items: state.items, savingId: fileId));
    try {
      final originalItems = state.items;
      final nextStates = {
        for (final item in originalItems)
          item.photo.summary.id: item.photo.summary.id == fileId
              ? value
              : value.isRetained
              ? KeepState.discard
              : _decisionState(item),
      };
      final changedItems = originalItems.where((item) {
        final nextState = nextStates[item.photo.summary.id]!;
        return _decisionState(item) != nextState;
      }).toList();
      final updatedAt = DateTime.now();
      final results = await Future.wait(
        changedItems.map(
          (item) => _repository.save(
            _decisionWithState(item, nextStates[item.photo.summary.id]!, updatedAt),
          ),
        ),
      );
      final conflict = results.where((result) => result.conflict).firstOrNull;
      if (conflict != null) {
        emit(ComparisonReviewState(items: originalItems, message: conflict.message ?? '盒子端已有更新，请返回照片详情处理冲突'));
        return;
      }
      final updated = originalItems.map((item) => _detailWithState(item, nextStates[item.photo.summary.id]!, updatedAt)).toList();
      _refreshCoordinator?.requestRefresh();
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'comparison_review_saved');
      emit(
        ComparisonReviewState(
          items: updated,
          message: results.where((result) => result.queued).firstOrNull?.message ?? '照片状态已更新',
        ),
      );
    } catch (error) {
      emit(ComparisonReviewState(items: state.items, error: error));
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
