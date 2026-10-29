import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:flutter/foundation.dart';

class ActiveCopyJob {
  const ActiveCopyJob({required this.deviceId, required this.jobId, required this.state, required this.updatedAt, this.stateVersion = 0});

  final String deviceId;
  final String jobId;
  final CopyJobState state;
  final DateTime updatedAt;
  final int stateVersion;

  Map<String, Object> toJson() => {
    'device_id': deviceId,
    'job_id': jobId,
    'state': state.wire,
    'state_version': stateVersion,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  static ActiveCopyJob? parse(Object? value) {
    if (value is! Map) return null;
    final device = value['device_id'], job = value['job_id'], state = value['state'];
    final time = value['updated_at'];
    if (device is! String || device.trim().isEmpty || job is! String || job.trim().isEmpty || state is! String || time is! String) return null;
    final date = DateTime.tryParse(time);
    if (date == null) return null;
    final version = value['state_version'];
    return ActiveCopyJob(deviceId: device, jobId: job, state: CopyJobState.fromWire(state), updatedAt: date, stateVersion: version is int && version >= 0 ? version : 0);
  }
}

/// Bounded, device-scoped task references, not a second source of job truth.
/// Failed disk writes retain the in-memory reference so success is never retried
/// as a new POST. Mock repositories use [ActiveCopyJobStore.memory].
class ActiveCopyJobStore extends ChangeNotifier {
  ActiveCopyJobStore(DiagnosticStorage storage) : _storage = storage {
    try {
      final raw = storage.read<Object>(cacheKey);
      if (raw is Map && raw['schema_version'] == 1 && raw['jobs'] is List) {
        for (final value in raw['jobs'] as List) {
          final job = ActiveCopyJob.parse(value);
          if (job != null) _put(job);
        }
      }
    } catch (error) {
      persistenceError = error;
    }
  }

  ActiveCopyJobStore.memory() : _storage = null;

  static const cacheKey = 'copy:active-jobs:v1';
  static const maximumDevices = 8;
  static const maximumJobsPerDevice = 8;
  final DiagnosticStorage? _storage;
  final Map<String, List<ActiveCopyJob>> _jobs = {};
  Future<void> _writes = Future<void>.value();
  Object? persistenceError;

  List<ActiveCopyJob> forDevice(String deviceId) => List.unmodifiable(_jobs[deviceId] ?? const <ActiveCopyJob>[]);
  List<ActiveCopyJob> activeForDevice(String deviceId) => forDevice(deviceId).where((job) => !job.state.isTerminal).toList(growable: false);

  Future<void> remember(String deviceId, String jobId, CopyJobState state, {int stateVersion = 0}) {
    if (deviceId.trim().isEmpty || jobId.trim().isEmpty) throw ArgumentError('Device and job identities are required');
    final existing = forDevice(deviceId).where((job) => job.jobId == jobId).firstOrNull;
    if (existing != null && existing.stateVersion > stateVersion) return Future<void>.value();
    _put(ActiveCopyJob(deviceId: deviceId, jobId: jobId, state: state, updatedAt: DateTime.now(), stateVersion: stateVersion));
    notifyListeners();
    return _persist();
  }

  Future<void> forget(String deviceId, String jobId) {
    _jobs[deviceId]?.removeWhere((job) => job.jobId == jobId);
    if (_jobs[deviceId]?.isEmpty ?? false) _jobs.remove(deviceId);
    notifyListeners();
    return _persist();
  }

  void _put(ActiveCopyJob job) {
    final jobs = _jobs.remove(job.deviceId) ?? <ActiveCopyJob>[];
    jobs.removeWhere((old) => old.jobId == job.jobId);
    jobs.insert(0, job);
    // Keep active references ahead of historical results when pruning.
    jobs.sort((a, b) {
      final terminal = (a.state.isTerminal ? 1 : 0).compareTo(b.state.isTerminal ? 1 : 0);
      return terminal != 0 ? terminal : b.updatedAt.compareTo(a.updatedAt);
    });
    _jobs[job.deviceId] = jobs.take(maximumJobsPerDevice).toList();
    while (_jobs.length > maximumDevices) {
      _jobs.remove(_jobs.keys.first);
    }
  }

  Future<void> _persist() {
    final storage = _storage;
    if (storage == null) return Future<void>.value();
    final snapshot = {'schema_version': 1, 'jobs': _jobs.values.expand((jobs) => jobs).map((job) => job.toJson()).toList()};
    final operation = _writes.catchError((Object _) {}).then((_) async {
      try {
        await storage.write(cacheKey, snapshot);
        persistenceError = null;
      } catch (error) {
        persistenceError = error;
        rethrow;
      }
    });
    // Keep a handled queue tail even if a caller does not await a failed write.
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> flush() => _writes;
}
