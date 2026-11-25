import 'dart:async';

import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_journal.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

/// Phone-only records use the existing bounded journal, separate from BLE so
/// ordinary HTTP traffic cannot displace pairing evidence. No payloads enter it.
final class PhoneDiagnosticRecorder {
  PhoneDiagnosticRecorder(this._storage, {this.maximumPending = 128, int maximumEvents = 1000, int maximumBytes = 2 * 1024 * 1024, this.flushInterval = const Duration(milliseconds: 250)})
    : _journal = BleDiagnosticJournal(_storage, key: journalKey, legacyKeys: const [], maximumRecords: maximumEvents, maximumBytes: maximumBytes, pinCurrentAttempt: true, maximumProtectedRequests: 8) {
    final metadata = _storage.read<Map>(metadataKey);
    _queueDropped = metadata?['queue_dropped'] as int? ?? 0;
  }

  static const journalKey = 'diagnostics:phone_requests:v1';
  static const metadataKey = 'diagnostics:phone_requests:metadata:v1';
  final DiagnosticStorage _storage;
  final BleDiagnosticJournal _journal;
  final int maximumPending;
  final Duration flushInterval;
  final processId = SecureRequestIdFactory().create();
  final _clock = Stopwatch()..start();
  final _pending = <Map<String, Object?>>[];
  Map<String, Object?> Function()? context;
  Timer? _timer;
  Future<void>? _writing;
  bool _closed = false;
  int _queueDropped = 0, _metadataWriteFailures = 0;
  String _lifecycle = 'unknown';
  int _tab = 0;
  final _pages = <String, String>{};

  Map<String, Object?> get currentContext => {
    ...?context?.call(),
    'page': _pages['root'] != null && _pages['root'] != '/' && _pages['root'] != '/shell' ? _pages['root'] : _pages['tab_$_tab'] ?? const ['album', 'tasks', 'device'][_tab],
    'lifecycle': _lifecycle,
  };

  void setLifecycle(String state) {
    if (_lifecycle == state) return;
    _lifecycle = state;
    record({'event': 'app_lifecycle_changed'});
    if (state != 'resumed') unawaited(flush());
  }

  void setActiveTab(int tab) {
    if (tab < 0 || tab > 2 || _tab == tab) return;
    _tab = tab;
    record({'event': 'route_changed'});
  }

  void setPage(String surface, String page) {
    if (_pages[surface] == page) return;
    _pages[surface] = page;
    record({'event': 'route_changed'});
  }

  static const _fields = {
    'event',
    'candidate_count',
    'candidate_source',
    'device_id',
    'attempt_id',
    'generation',
    'session_generation',
    'phase',
    'connection_state',
    'previous_state',
    'next_state',
    'intent',
    'request_id',
    'response_request_id',
    'cause_request_id',
    'probe_request_id',
    'reachability_check_id',
    'method',
    'route',
    'request_kind',
    'started_at',
    'ended_at',
    'elapsed_ms',
    'queue_ms',
    'connect_ms',
    'receive_ms',
    'timing_source',
    'http_status',
    'outcome',
    'error_class',
    'error_code',
    'cancelled',
    'timeout',
    'timeout_ms',
    'retry_delay_ms',
    'attempt',
    'final_trigger',
    'wifi_available',
    'has_network',
    'network_type',
    'ws_state',
    'close_code',
    'transport_generation',
    'phase_elapsed_ms',
    'deadline_ms',
    'superseded_reason',
    'cancel_source',
    'successor_action',
    'successor_attempt_id',
    'previous_generation',
    'next_generation',
    'recovery_elapsed_ms',
    'network_role',
    'network_mode',
    'project_id',
    'project_version_sent',
    'returned_project_version',
    'current_project_version',
    'version_scope',
    'batch_operation',
    'batch_operation_id',
    'file_count',
    'succeeded_count',
    'failed_count',
    'saved_device_present',
    'endpoint_source',
    'http_result',
    'build_id',
    'git_commit',
    'source_fingerprint',
    'apk_sha256',
    'version_name',
    'version_code',
    'package_id',
    'identity_status',
    'ws_generation',
  };

  void record(Map<String, dynamic> event) {
    if (_closed) return;
    // Inputs come from controlled instrumentation, not errors, HTTP headers,
    // response bodies or route arguments. Still accept only bounded scalars.
    final safe = <String, Object?>{};
    for (final entry in {...currentContext, ...event}.entries) {
      if (!_fields.contains(entry.key) && entry.key != 'page' && entry.key != 'lifecycle') continue;
      final value = entry.value;
      if (value == null || value is bool || value is num) {
        safe[entry.key] = value;
      } else if (value is String) {
        safe[entry.key] = value.length > 180 ? value.substring(0, 180) : value;
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    safe.addAll({
      'source': 'phone',
      'process_id': processId,
      'occurred_at': now,
      'monotonic_ms': _clock.elapsedMilliseconds,
      'flow_id': safe['attempt_id'] ?? processId,
      'event_type': safe['event'] ?? 'phone_event',
    });
    if (safe['outcome'] == 'failed') safe['error_code'] ??= 'operation_failed';
    if (_pending.length >= maximumPending) {
      final ordinary = _pending.indexWhere((record) => record['error_code'] == null);
      _pending.removeAt(ordinary < 0 ? 0 : ordinary);
      _queueDropped++;
    }
    _pending.add(safe);
    if (_pending.length >= 32) {
      unawaited(flush());
    } else {
      _timer ??= Timer(flushInterval, () {
        _timer = null;
        unawaited(flush());
      });
    }
  }

  Future<void> flush() {
    if (_writing != null) return _writing!;
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return Future.value();
    final batch = List<Map<String, Object?>>.of(_pending);
    _pending.clear();
    final write = _persist(batch);
    _writing = write;
    return write.whenComplete(() {
      if (!identical(_writing, write)) return;
      _writing = null;
      if (_pending.isNotEmpty && !_closed) {
        _timer ??= Timer(flushInterval, () {
          _timer = null;
          unawaited(flush());
        });
      }
    });
  }

  Future<void> _persist(List<Map<String, Object?>> batch) async {
    try {
      await _journal.recordBatch(batch);
    } catch (_) {
      // The journal accounts for failed persistence; diagnostics never throw
      // into a request, a lifecycle callback, or an automatic recovery.
    }
    try {
      await _storage.write(metadataKey, {'queue_dropped': _queueDropped});
    } catch (_) {
      _metadataWriteFailures++;
    }
  }

  Future<Map<String, dynamic>> snapshot() async {
    await flush();
    // Drain records buffered while the preceding bounded write was pending.
    if (_pending.isNotEmpty) await flush();
    final snapshot = await _journal.snapshot();
    final records = snapshot.records.reversed.toList();
    final flowIds = {...snapshot.flows.keys, ...records.map(BleDiagnosticJournal.group)};
    return {
      'schema_version': 1,
      'source': 'phone',
      'events': records,
      'retention': {
        'maximum_events': snapshot.maximumRecords,
        'maximum_bytes': snapshot.maximumBytes,
        'retained_events': records.length,
        'retained_bytes': snapshot.retainedBytes,
        'maximum_pending_events': maximumPending,
        'queue_dropped': _queueDropped,
        'persistence_write_failures': snapshot.writeFailures,
        'metadata_write_failures': _metadataWriteFailures,
        'snapshot_cutoff': 'journal_barrier_after_buffer_flush',
        'per_flow': {for (final id in flowIds) id: snapshot.retentionFor(id, records.where((r) => BleDiagnosticJournal.group(r) == id).length)},
        'truncated': _queueDropped > 0 || _metadataWriteFailures > 0 || snapshot.writeFailures > 0 || snapshot.flows.values.any((s) => (s as Map)['history_unknown'] == true || (s['dropped'] as int? ?? 0) > 0),
      },
      'box_logs': {'included': false, 'source': 'box', 'export_separately': true},
      'timing_note': 'Monotonic time is per process. HTTP total is observed; unsupported queue/connect/receive timings are null.',
    };
  }

  Future<void> dispose() async {
    _closed = true;
    _timer?.cancel();
    await flush();
    if (_pending.isNotEmpty) await flush();
  }
}
