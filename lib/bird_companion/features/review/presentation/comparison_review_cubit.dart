import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ComparisonReviewState {
  const ComparisonReviewState({this.items = const [], this.loading = false, this.savingId, this.error});
  final List<ReviewDetail> items;
  final bool loading;
  final String? savingId;
  final Object? error;
}

class ComparisonReviewCubit extends Cubit<ComparisonReviewState> {
  ComparisonReviewCubit(this._repository, [this._refreshCoordinator, this._dataChanges]) : super(const ComparisonReviewState());
  final ReviewRepository _repository;
  final SessionRefreshCoordinator? _refreshCoordinator;
  final AppDataChangeBus? _dataChanges;

  Future<void> load(List<String> ids) async {
    emit(const ComparisonReviewState(loading: true));
    try {
      emit(ComparisonReviewState(items: await Future.wait(ids.take(4).map(_repository.detail))));
    } catch (error) {
      emit(ComparisonReviewState(error: error));
    }
  }

  Future<void> mark(String fileId, KeepState value) async {
    emit(ComparisonReviewState(items: state.items, savingId: fileId));
    try {
      await _repository.save(UserDecision(fileId: fileId, keepState: value, updatedAt: DateTime.now()));
      final refreshed = await _repository.detail(fileId);
      _refreshCoordinator?.requestRefresh();
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'comparison_review_saved');
      emit(ComparisonReviewState(items: state.items.map((item) => item.photo.summary.id == fileId ? refreshed : item).toList()));
    } catch (error) {
      emit(ComparisonReviewState(items: state.items, error: error));
    }
  }
}
