import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GroupReviewState {
  const GroupReviewState({this.groups = const [], this.loading = false, this.actingGroupId, this.error, this.message});
  final List<BirdGroup> groups;
  final bool loading;
  final String? actingGroupId;
  final Object? error;
  final String? message;
  GroupReviewState copyWith({List<BirdGroup>? groups, bool? loading, String? actingGroupId, Object? error, String? message, bool clearAction = false, bool clearError = false, bool clearMessage = false}) => GroupReviewState(
    groups: groups ?? this.groups,
    loading: loading ?? this.loading,
    actingGroupId: clearAction ? null : actingGroupId ?? this.actingGroupId,
    error: clearError ? null : error ?? this.error,
    message: clearMessage ? null : message ?? this.message,
  );
}

class GroupReviewCubit extends Cubit<GroupReviewState> {
  GroupReviewCubit(this._repository, [SessionRefreshCoordinator? refreshCoordinator, this._dataChanges]) : super(const GroupReviewState());
  final ReviewRepository _repository;
  final AppDataChangeBus? _dataChanges;
  bool _loadInFlight = false;

  Future<void> load(String batchId, {String? sceneId}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      emit(GroupReviewState(groups: await _repository.groups(batchId, sceneId: sceneId)));
    } catch (error) {
      emit(state.copyWith(loading: false, error: error));
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> markGroup(BirdGroup group, KeepState keepState) async {
    if (state.actingGroupId != null) return;
    emit(state.copyWith(actingGroupId: group.id, clearError: true, clearMessage: true));
    try {
      final results = await Future.wait(group.memberFileIds.map((fileId) => _repository.save(UserDecision(fileId: fileId, keepState: keepState, updatedAt: DateTime.now()))));
      final message = _resultMessage(results, success: '整组状态已更新');
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'group_review_saved');
      emit(state.copyWith(clearAction: true, message: message));
    } catch (error) {
      emit(state.copyWith(error: error, clearAction: true));
    }
  }

  Future<void> markFile(BirdGroup group, String fileId, KeepState keepState) async {
    if (state.actingGroupId != null || fileId.isEmpty) return;
    emit(state.copyWith(actingGroupId: group.id, clearError: true, clearMessage: true));
    try {
      final result = await _repository.save(UserDecision(fileId: fileId, keepState: keepState, updatedAt: DateTime.now()));
      final message = _resultMessage([result], success: '照片状态已更新');
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'group_photo_review_saved');
      emit(state.copyWith(clearAction: true, message: message));
    } catch (error) {
      emit(state.copyWith(error: error, clearAction: true));
    }
  }

  /// Keeps one recommendation per group. It must not reuse markGroup(),
  /// because that method intentionally changes every member of a group.
  Future<void> keepTopRecommendations() async {
    if (state.actingGroupId != null || state.groups.isEmpty) return;
    emit(state.copyWith(actingGroupId: '__top_recommendations__', clearError: true, clearMessage: true));
    try {
      final results = await Future.wait(
        state.groups.map((group) {
          final id = group.rankOrder.isNotEmpty ? group.rankOrder.first : group.representativeFileId;
          return _repository.save(UserDecision(fileId: id, keepState: KeepState.keep, updatedAt: DateTime.now()));
        }),
      );
      final message = _resultMessage(results, success: '每组首选照片已保留');
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'top_recommendations_saved');
      emit(state.copyWith(clearAction: true, message: message));
    } catch (error) {
      emit(state.copyWith(error: error, clearAction: true));
    }
  }

  String _resultMessage(List<ReviewSaveResult> results, {required String success}) {
    final conflict = results.where((result) => result.conflict).firstOrNull;
    if (conflict != null) return conflict.message ?? '盒子端已有更新，请打开照片详情处理冲突';
    final queued = results.where((result) => result.queued).firstOrNull;
    if (queued != null) return queued.message ?? '设备离线，修改将在重连后同步';
    return success;
  }
}
