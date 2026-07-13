import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CopyConfirmationState {
  const CopyConfirmationState({this.mode = 'keep', this.loading = false, this.estimate, this.targetId, this.error, this.submitted = false, this.jobId});
  final String mode;
  final bool loading, submitted;
  final CopyEstimate? estimate;
  final String? targetId;
  final Object? error;
  final String? jobId;
  StorageTarget? get selectedTarget => estimate?.targets.where((target) => target.id == targetId).firstOrNull;
  bool get hasEnoughSpace => selectedTarget != null && selectedTarget!.online && selectedTarget!.freeBytes >= (estimate?.requiredBytes ?? 0);
  String? get submissionBlockReason => targetId == null
      ? '请选择一个可用的目标存储盘'
      : !hasEnoughSpace
      ? '目标盘空间不足或已断开，请更换存储盘后再创建任务'
      : null;
  CopyConfirmationState copyWith({String? mode, bool? loading, CopyEstimate? estimate, String? targetId, Object? error, bool clearError = false, bool? submitted, String? jobId}) => CopyConfirmationState(
    mode: mode ?? this.mode,
    loading: loading ?? this.loading,
    estimate: estimate ?? this.estimate,
    targetId: targetId ?? this.targetId,
    error: clearError ? null : error ?? this.error,
    submitted: submitted ?? this.submitted,
    jobId: jobId ?? this.jobId,
  );
}

class CopyConfirmationCubit extends Cubit<CopyConfirmationState> {
  CopyConfirmationCubit(this._repository, this.batchId, [this._dataChanges]) : super(const CopyConfirmationState());
  final CopyRepository _repository;
  final String batchId;
  final AppDataChangeBus? _dataChanges;
  Future<void> load([String? mode]) async {
    final value = mode ?? state.mode;
    emit(state.copyWith(loading: true, mode: value, clearError: true, submitted: false));
    try {
      final estimate = await _repository.estimate(batchId, value);
      final target = estimate.targets.where((item) => item.online && item.freeBytes >= estimate.requiredBytes).firstOrNull;
      emit(state.copyWith(loading: false, estimate: estimate, targetId: target?.id));
    } catch (error) {
      emit(state.copyWith(loading: false, error: error));
    }
  }

  Future<void> submit() async {
    final target = state.targetId;
    if (target == null || state.loading || state.submitted || !state.hasEnoughSpace) return;
    emit(state.copyWith(loading: true));
    try {
      final job = await _repository.create(batchId, state.mode, target);
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device, AppDataResource.batches}, reason: 'copy_job_created');
      emit(state.copyWith(loading: false, submitted: true, jobId: job.id));
    } catch (error) {
      emit(state.copyWith(loading: false, error: error));
    }
  }

  void selectTarget(String id) => emit(state.copyWith(targetId: id));
}
