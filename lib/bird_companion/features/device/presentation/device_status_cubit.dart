import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/device/domain/device_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum DeviceStatusPhase { loading, ready, failure }

class DeviceStatusState extends Equatable {
  const DeviceStatusState({this.phase = DeviceStatusPhase.loading, this.status, this.error, this.isControllingJob = false});

  final DeviceStatusPhase phase;
  final DeviceStatus? status;
  final Object? error;
  final bool isControllingJob;

  DeviceStatusState copyWith({DeviceStatusPhase? phase, DeviceStatus? status, Object? error, bool? isControllingJob, bool clearError = false}) {
    return DeviceStatusState(
      phase: phase ?? this.phase,
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
      isControllingJob: isControllingJob ?? this.isControllingJob,
    );
  }

  @override
  List<Object?> get props => [phase, status, error, isControllingJob];
}

class DeviceStatusCubit extends Cubit<DeviceStatusState> {
  DeviceStatusCubit(this._repository, this._sessionCubit, [SessionRefreshCoordinator? refreshCoordinator, AppDataChangeBus? dataChanges]) : _dataChanges = dataChanges, super(const DeviceStatusState()) {
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => load());
    _dataSubscription = dataChanges?.changes.where((change) => change.affects(AppDataResource.device) || change.affects(AppDataResource.jobs)).listen((_) => load());
  }

  final DeviceRepository _repository;
  final DeviceSessionCubit _sessionCubit;
  final AppDataChangeBus? _dataChanges;
  StreamSubscription<DeviceStatus>? _subscription;
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;
  bool _loadInFlight = false;

  Future<void> load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    emit(state.copyWith(phase: DeviceStatusPhase.loading, clearError: true));
    try {
      final status = await _repository.fetchStatus();
      // Do not re-run the global reconnect pipeline for every ordinary status
      // refresh. That used to emit another refresh event, which called load()
      // again and formed an infinite refresh loop on real devices.
      final current = _sessionCubit.state;
      if (!current.isConnected || current.device?.baseUri != status.connection.baseUri) {
        await _sessionCubit.setConnectedFromStatus(status);
      }
      emit(state.copyWith(phase: DeviceStatusPhase.ready, status: status));
      await _subscription?.cancel();
      _subscription = _repository.watchStatus().listen((eventStatus) => emit(state.copyWith(phase: DeviceStatusPhase.ready, status: eventStatus)));
    } catch (error) {
      _sessionCubit.disconnected('无法读取盒子状态。');
      emit(state.copyWith(phase: DeviceStatusPhase.failure, error: error));
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> controlCurrentJob(String action) async {
    final job = state.status?.currentJob;
    if (job == null) return;
    emit(state.copyWith(isControllingJob: true, clearError: true));
    try {
      await _repository.controlJob(jobId: job.id, action: action);
      await load();
      _dataChanges?.publish({AppDataResource.device, AppDataResource.jobs}, reason: 'job_$action');
      emit(state.copyWith(isControllingJob: false));
    } catch (error) {
      emit(state.copyWith(phase: DeviceStatusPhase.failure, error: error, isControllingJob: false));
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}
