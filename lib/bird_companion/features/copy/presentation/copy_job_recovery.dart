import 'dart:async';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/copy/data/active_copy_job_store.dart';
import 'package:aves/bird_companion/features/copy/data/copy_request_diagnostics.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:flutter/foundation.dart';

/// Reads saved IDs only after a trusted session becomes usable. Never creates
/// jobs, navigates, or guesses progress from the persisted state.
class CopyJobRecovery extends ChangeNotifier {
  CopyJobRecovery({required this.repository, required this.store, required this.currentDeviceId, required this.isConnected, required Stream<void> sessionChanges, required Stream<void> refreshes, this.diagnostics}) {
    _sessionSubscription = sessionChanges.listen((_) => sessionChanged());
    _refreshSubscription = refreshes.listen((_) => sessionChanged());
  }

  final CopyJobRepository repository;
  final ActiveCopyJobStore store;
  final String? Function() currentDeviceId;
  final bool Function() isConnected;
  final CopyRequestDiagnostics? diagnostics;
  late final StreamSubscription<void> _sessionSubscription, _refreshSubscription;
  final _changes = StreamController<void>.broadcast(sync: true);
  Stream<void> get sessionRefreshes => _changes.stream;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _recovery;
  String? _recoveringDevice;
  bool _retryRequested = false;
  final _reads = <(String, String, int), Future<CopyJobDetail>>{};

  bool canRead(String deviceId) => !_disposed && isConnected() && currentDeviceId() == deviceId;

  /// The visible page and the startup recovery share a GET for the same task
  /// within one session generation, instead of racing two identical requests.
  Future<CopyJobDetail> readJob(String deviceId, String jobId, {String trigger = 'session_recovery'}) {
    if (!canRead(deviceId)) return Future.error(StateError('The original device is not connected'));
    final key = (deviceId, jobId, _generation);
    return _reads.putIfAbsent(key, () {
      Future<CopyJobDetail> request() async {
        final detail = await repository.getJob(jobId);
        if (detail.copyJobId != jobId) throw const ProtocolCompatibilityException('copy_job_id', '任务身份与请求不一致');
        return detail;
      }

      final future = diagnostics == null ? request() : diagnostics!.request('detail', jobId, request, deviceId: deviceId, trigger: trigger);
      return future.whenComplete(() {
        _reads.remove(key);
      });
    });
  }

  void sessionChanged() {
    if (_disposed) return;
    ++_generation;
    _changes.add(null);
    notifyListeners();
    unawaited(recover());
  }

  Future<void> recover() {
    final device = currentDeviceId();
    if (_disposed || device == null || !canRead(device)) return Future<void>.value();
    if (_recovery != null && _recoveringDevice == device) {
      _retryRequested = true;
      return _recovery!;
    }
    _recoveringDevice = device;
    final future = _recover(device);
    _recovery = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_recovery, future)) {
          _recovery = null;
          _recoveringDevice = null;
          if (_retryRequested && !_disposed) {
            _retryRequested = false;
            unawaited(recover());
          }
        }
      }),
    );
    return future;
  }

  Future<void> _recover(String device) async {
    // A session refresh while reading the same device is coalesced; switching
    // devices invalidates the response even if the first device later returns.
    for (final saved in store.activeForDevice(device)) {
      if (!canRead(device)) return;
      final generation = _generation;
      try {
        final detail = await readJob(device, saved.jobId);
        if (!canRead(device) || generation != _generation) continue;
        try {
          await store.remember(device, saved.jobId, detail.state, stateVersion: detail.stateVersion);
        } catch (error) {
          diagnostics?.record('active_task_store', saved.jobId, deviceId: device, error: error);
        }
      } on ApiException catch (error) {
        if (canRead(device) && generation == _generation && error.statusCode == 404) {
          try {
            await store.forget(device, saved.jobId);
          } catch (_) {
            // The memory reference has already been removed.
          }
        }
      } catch (_) {
        // Retain the ID through network and local storage failures.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_sessionSubscription.cancel());
    unawaited(_refreshSubscription.cancel());
    unawaited(_changes.close());
    super.dispose();
  }
}
