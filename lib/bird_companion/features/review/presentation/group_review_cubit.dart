import 'dart:async';

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
  GroupReviewCubit(
    this._repository, [
    SessionRefreshCoordinator? refreshCoordinator,
    this._dataChanges,
  ]) : super(const GroupReviewState()) {
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => _reload());
    _dataSubscription = _dataChanges?.changes
        .where(
          (change) => change.affects(AppDataResource.photos) && !_localChangeReasons.contains(change.reason),
        )
        .listen((_) => _reload());
  }
  final ReviewRepository _repository;
  final AppDataChangeBus? _dataChanges;
  static const _localChangeReasons = {
    'group_review_saved',
    'group_photo_review_saved',
    'top_recommendations_saved',
  };
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;
  String? _batchId;
  String? _sceneId;
  bool _loadInFlight = false;

  Future<void> load(String batchId, {String? sceneId}) async {
    _batchId = batchId;
    _sceneId = sceneId;
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

  Future<void> _reload() async {
    final batchId = _batchId;
    if (batchId == null || batchId.isEmpty || isClosed) return;
    await load(batchId, sceneId: _sceneId);
  }

  Future<void> markGroup(BirdGroup group, KeepState keepState) async {
    if (state.actingGroupId != null) return;
    if (group.memberFileIds.isEmpty) {
      emit(state.copyWith(message: '本组没有可操作的照片'));
      return;
    }
    emit(state.copyWith(actingGroupId: group.id, clearError: true, clearMessage: true));
    final outcomes = await Future.wait(
      group.memberFileIds.map(
        (fileId) async {
          try {
            return _GroupSaveOutcome(
              fileId: fileId,
              result: await _repository.save(
                UserDecision(
                  fileId: fileId,
                  keepState: keepState,
                  updatedAt: DateTime.now(),
                  version: _versionFor(group, fileId),
                ),
                projectId: _batchId,
              ),
            );
          } catch (error) {
            return _GroupSaveOutcome(
              fileId: fileId,
              error: error,
            );
          }
        },
      ),
    );
    final savedIds = outcomes
        .where(
          (outcome) => outcome.result != null && !outcome.result!.conflict,
        )
        .map((outcome) => outcome.fileId)
        .toList(growable: false);
    final failed = outcomes.where((outcome) => outcome.error != null).toList(growable: false);
    final results = outcomes.map((outcome) => outcome.result).whereType<ReviewSaveResult>().toList(growable: false);
    final conflictCount = results.where((result) => result.conflict).length;
    if (savedIds.isNotEmpty) {
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'group_review_saved');
    }
    if (failed.length == outcomes.length) {
      emit(
        state.copyWith(
          error: failed.first.error,
          clearAction: true,
        ),
      );
      return;
    }
    final message = failed.isEmpty
        ? _resultMessage(results, success: '整组状态已更新')
        : [
            '已更新 ${savedIds.length}/${outcomes.length} 张',
            if (failed.isNotEmpty) '${failed.length} 张失败，请重试',
            if (conflictCount > 0) '$conflictCount 张存在版本冲突',
          ].join('；');
    emit(
      state.copyWith(
        groups: _withDecision(
          group.id,
          savedIds,
          keepState,
        ),
        clearAction: true,
        message: message,
      ),
    );
  }

  Future<void> markFile(BirdGroup group, String fileId, KeepState keepState) async {
    if (state.actingGroupId != null || fileId.isEmpty) return;
    emit(state.copyWith(actingGroupId: group.id, clearError: true, clearMessage: true));
    try {
      final result = await _repository.save(
        UserDecision(
          fileId: fileId,
          keepState: keepState,
          updatedAt: DateTime.now(),
          version: _versionFor(group, fileId),
        ),
        projectId: _batchId,
      );
      final message = _resultMessage([result], success: '照片状态已更新');
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'group_photo_review_saved');
      emit(state.copyWith(groups: result.conflict ? state.groups : _withDecision(group.id, [fileId], keepState), clearAction: true, message: message));
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
          return _repository.save(
            UserDecision(
              fileId: id,
              keepState: KeepState.keep,
              updatedAt: DateTime.now(),
              version: _versionFor(group, id),
            ),
            projectId: _batchId,
          );
        }),
      );
      final message = _resultMessage(results, success: '每组首选照片已保留');
      _dataChanges?.publish({AppDataResource.photos, AppDataResource.batches}, reason: 'top_recommendations_saved');
      final decisions = <String, KeepState>{
        for (final group in state.groups) (group.rankOrder.isNotEmpty ? group.rankOrder.first : group.representativeFileId): KeepState.keep,
      };
      emit(state.copyWith(groups: _withDecisions(decisions), clearAction: true, message: message));
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

  int? _versionFor(BirdGroup group, String fileId) => group.members.where((photo) => photo.id == fileId).map((photo) => photo.version).firstOrNull;

  List<BirdGroup> _withDecision(String groupId, Iterable<String> fileIds, KeepState keepState) => _withDecisions(
    {for (final fileId in fileIds) fileId: keepState},
    groupId: groupId,
  );

  List<BirdGroup> _withDecisions(Map<String, KeepState> decisions, {String? groupId}) => state.groups
      .map(
        (group) => groupId != null && group.id != groupId
            ? group
            : group.copyWith(
                members: group.members.map((photo) => decisions[photo.id] == null ? photo : photo.copyWith(keepState: decisions[photo.id]!.wireValue)).toList(growable: false),
              ),
      )
      .toList(growable: false);

  @override
  Future<void> close() async {
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}

class _GroupSaveOutcome {
  const _GroupSaveOutcome({
    required this.fileId,
    this.result,
    this.error,
  });

  final String fileId;
  final ReviewSaveResult? result;
  final Object? error;
}
