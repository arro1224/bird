import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum AlbumMaterializationPhase { idle, preparing, ready, timedOut }

class AlbumMaterializationState {
  const AlbumMaterializationState({
    this.phase = AlbumMaterializationPhase.idle,
    this.projectId,
    this.batch,
    this.confirmedEmpty = false,
    this.lastError,
  });

  final AlbumMaterializationPhase phase;
  final String? projectId;
  final BatchSummary? batch;
  final bool confirmedEmpty;
  final Object? lastError;

  bool get preparing => phase == AlbumMaterializationPhase.preparing;
  bool get ready => phase == AlbumMaterializationPhase.ready;
  bool get timedOut => phase == AlbumMaterializationPhase.timedOut;
}

/// Waits only for the current project and its first photo page to become
/// readable. Thumbnail and preview readiness remain the gallery's concern.
class AlbumMaterializationCubit extends Cubit<AlbumMaterializationState> {
  AlbumMaterializationCubit(
    this._batches,
    this._photos,
    this._dataChanges, {
    required this.activeDeviceId,
    Stream<String?>? deviceChanges,
    this.timeout = const Duration(seconds: 8),
    this.initialRetryDelay = const Duration(milliseconds: 120),
    this.maximumRetryDelay = const Duration(seconds: 1),
  }) : super(const AlbumMaterializationState()) {
    _dataSubscription = _dataChanges.changes
        .where(
          (change) => change.affects(AppDataResource.batches) || change.affects(AppDataResource.photos),
        )
        .listen(_onDataChange);
    _deviceSubscription = deviceChanges?.listen(_onDeviceChanged);
  }

  final BatchRepository _batches;
  final PhotoRepository _photos;
  final AppDataChangeBus _dataChanges;
  final String? Function() activeDeviceId;
  final Duration timeout;
  final Duration initialRetryDelay;
  final Duration maximumRetryDelay;

  StreamSubscription<AppDataChange>? _dataSubscription;
  StreamSubscription<String?>? _deviceSubscription;
  Completer<void>? _wakeSignal;
  int _generation = 0;
  String? _requestedDeviceId;

  void materialize(String projectId) {
    final normalized = projectId.trim();
    if (normalized.isEmpty) return;
    final generation = ++_generation;
    _completeWakeSignal();
    _requestedDeviceId = activeDeviceId()?.trim();
    emit(
      AlbumMaterializationState(
        phase: AlbumMaterializationPhase.preparing,
        projectId: normalized,
      ),
    );
    unawaited(_waitUntilReadable(normalized, generation));
  }

  void retry() {
    final projectId = state.projectId;
    if (projectId != null) materialize(projectId);
  }

  void settle() {
    if (!state.ready) return;
    _requestedDeviceId = null;
    emit(const AlbumMaterializationState());
  }

  Future<void> _waitUntilReadable(String projectId, int generation) async {
    final deadline = DateTime.now().add(timeout);
    var retryDelay = initialRetryDelay;
    Object? lastError;

    while (_isCurrent(generation, projectId)) {
      try {
        final batch = await _batches.current();
        if (!_isCurrent(generation, projectId)) return;
        if (batch?.id == projectId) {
          final page = await _photos.page(projectId, const PhotoQuery());
          if (!_isCurrent(generation, projectId)) return;
          final confirmedEmpty = batch!.totalFiles == 0 && page.items.isEmpty && page.resultComplete;
          if (page.items.isNotEmpty || confirmedEmpty) {
            emit(
              AlbumMaterializationState(
                phase: AlbumMaterializationPhase.ready,
                projectId: projectId,
                batch: batch,
                confirmedEmpty: confirmedEmpty,
              ),
            );
            return;
          }
        }
      } catch (error) {
        lastError = error;
      }

      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await _waitForDataOrDelay(
        retryDelay < remaining ? retryDelay : remaining,
        generation,
      );
      final doubled = Duration(milliseconds: retryDelay.inMilliseconds * 2);
      retryDelay = doubled < maximumRetryDelay ? doubled : maximumRetryDelay;
    }

    if (_isCurrent(generation, projectId)) {
      emit(
        AlbumMaterializationState(
          phase: AlbumMaterializationPhase.timedOut,
          projectId: projectId,
          lastError: lastError,
        ),
      );
    }
  }

  Future<void> _waitForDataOrDelay(
    Duration delay,
    int generation,
  ) async {
    if (!_isCurrentGeneration(generation)) return;
    final signal = Completer<void>();
    _wakeSignal = signal;
    await Future.any<void>([
      signal.future,
      Future<void>.delayed(delay),
    ]);
    if (identical(_wakeSignal, signal)) _wakeSignal = null;
  }

  void _onDataChange(AppDataChange change) {
    if (!state.preparing) return;
    if (change is AnalysisCompleted && change.projectId != state.projectId) {
      return;
    }
    _completeWakeSignal();
  }

  void _onDeviceChanged(String? deviceId) {
    if (!state.preparing && !state.ready && !state.timedOut) return;
    if (deviceId?.trim() == _requestedDeviceId) return;
    _generation += 1;
    _requestedDeviceId = null;
    _completeWakeSignal();
    if (!isClosed) emit(const AlbumMaterializationState());
  }

  bool _isCurrent(int generation, String projectId) => _isCurrentGeneration(generation) && state.projectId == projectId;

  bool _isCurrentGeneration(int generation) => !isClosed && generation == _generation && activeDeviceId()?.trim() == _requestedDeviceId;

  void _completeWakeSignal() {
    final signal = _wakeSignal;
    _wakeSignal = null;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  @override
  Future<void> close() async {
    _generation += 1;
    _completeWakeSignal();
    await _dataSubscription?.cancel();
    await _deviceSubscription?.cancel();
    return super.close();
  }
}
