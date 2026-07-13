import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GroupReviewState {
  const GroupReviewState({this.groups = const [], this.loading = false, this.actingGroupId, this.error});
  final List<BirdGroup> groups;
  final bool loading;
  final String? actingGroupId;
  final Object? error;
  GroupReviewState copyWith({List<BirdGroup>? groups, bool? loading, String? actingGroupId, Object? error, bool clearAction = false, bool clearError = false}) =>
      GroupReviewState(groups: groups ?? this.groups, loading: loading ?? this.loading, actingGroupId: clearAction ? null : actingGroupId ?? this.actingGroupId, error: clearError ? null : error ?? this.error);
}

class GroupReviewCubit extends Cubit<GroupReviewState> {
  GroupReviewCubit(this._repository, [this._refreshCoordinator, this._dataChanges]) : super(const GroupReviewState());
  final ReviewRepository _repository;
  final SessionRefreshCoordinator? _refreshCoordinator;
  final AppDataChangeBus? _dataChanges;

  Future<void> load(String batchId) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      emit(GroupReviewState(groups: await _repository.groups(batchId)));
    } catch (error) {
      emit(state.copyWith(loading: false, error: error));
    }
  }

  Future<void> markGroup(BirdGroup group, KeepState keepState) async {
    if (state.actingGroupId != null) return;
    emit(state.copyWith(actingGroupId: group.id, clearError: true));
    try {
      await Future.wait(group.memberFileIds.map((fileId) => _repository.save(UserDecision(fileId: fileId, keepState: keepState, updatedAt: DateTime.now()))));
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'group_review_saved');
      emit(state.copyWith(clearAction: true));
    } catch (error) {
      emit(state.copyWith(error: error, clearAction: true));
    }
  }

  /// Keeps one recommendation per group. It must not reuse markGroup(),
  /// because that method intentionally changes every member of a group.
  Future<void> keepTopRecommendations() async {
    if (state.actingGroupId != null || state.groups.isEmpty) return;
    emit(state.copyWith(actingGroupId: '__top_recommendations__', clearError: true));
    try {
      await Future.wait(
        state.groups.map((group) {
          final id = group.rankOrder.isNotEmpty ? group.rankOrder.first : group.representativeFileId;
          return _repository.save(UserDecision(fileId: id, keepState: KeepState.keep, updatedAt: DateTime.now()));
        }),
      );
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'top_recommendations_saved');
      emit(state.copyWith(clearAction: true));
    } catch (error) {
      emit(state.copyWith(error: error, clearAction: true));
    }
  }
}
