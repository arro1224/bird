import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_critical_event_policy.dart';

final class BleDiagnosticJournalSnapshot {
  const BleDiagnosticJournalSnapshot(this.records, this.flows, this.writeFailures, this.maximumRecords,
      this.maximumBytes, this.retainedBytes, this.maximumProtectedRequests, this.protectCritical);
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic> flows;
  final int writeFailures, maximumRecords, maximumBytes, retainedBytes, maximumProtectedRequests;
  final bool protectCritical;
  Map<String, dynamic> retentionFor(String flowId, int retained) {
    final stats = flows[flowId] as Map?;
    final unknown = stats == null || stats['history_unknown'] == true;
    final criticalUnknown = unknown || stats['critical_history_unknown'] == true;
    final criticalDropped = stats?['critical_dropped'] as int? ?? 0;
    return {
      'retained': retained,
      'total_observed': stats?['total'],
      'dropped': stats?['dropped'],
      'history_unknown': unknown,
      'persistence_write_failures': writeFailures,
      'maximum_retained_records': maximumRecords,
      'maximum_journal_bytes': maximumBytes,
      'retained_journal_bytes': retainedBytes,
      if (protectCritical) ...{
        'maximum_protected_requests': maximumProtectedRequests,
        'critical_observed': stats?['critical_observed'],
        'critical_retained': records.where((r) => BleDiagnosticJournal.group(r) == flowId && BleCriticalEventPolicy.isCritical(r)).length,
        'critical_dropped': criticalDropped,
        'critical_events_missing': criticalUnknown || criticalDropped > 0,
        'critical_history_unknown': criticalUnknown,
        'critical_missing_reasons': [
          if (criticalUnknown) 'history_unknown',
          ...((stats?['critical_drop_reasons'] as Map?) ?? const {}).keys,
        ],
      },
      'truncated': unknown || (stats['dropped'] as int? ?? 0) > 0 || writeFailures > 0,
    };
  }
}

/// Records and loss accounting share one atomic cache value. Queue barriers fix
/// the export cutoff; count, UTF-8 bytes and protected request history are bounded.
final class BleDiagnosticJournal {
  BleDiagnosticJournal(this.storage, {required this.key, required this.legacyKeys,
    required this.maximumRecords, this.pinCurrentAttempt = false,
    this.maximumBytes = 2 * 1024 * 1024, this.maximumProtectedRequests = 4,
  }) : assert(maximumRecords > 0), assert(maximumBytes >= 1024), assert(maximumProtectedRequests > 0);
  final DiagnosticStorage storage;
  final String key;
  final List<String> legacyKeys;
  final int maximumRecords, maximumBytes, maximumProtectedRequests;
  final bool pinCurrentAttempt;
  Future<void> _queue = Future.value();
  int _writeFailures = 0;
  bool _unpersistedMetadataEvicted = false;
  final _unpersistedLosses = <String, Map<String, dynamic>>{};

  static String group(Map value) => (value['flow_id'] ?? value['scan_session_id'] ?? value['trace_id']).toString();
  static int _bytes(Object value) => utf8.encode(jsonEncode(value)).length;
  static Map<String, dynamic> _newStats(bool unknown) => {
    'total': 0, 'dropped': 0, 'history_unknown': unknown,
    'critical_observed': 0, 'critical_dropped': 0,
    'critical_history_unknown': unknown, 'critical_drop_reasons': <String, dynamic>{},
  };
  Map<String, dynamic> _state() {
    final current = storage.read<Map>(key);
    if (current != null) {
      final state = Map<String, dynamic>.from(jsonDecode(jsonEncode(current)) as Map);
      // Older caches counted ordinary loss without identifying critical loss.
      for (final entry in (state['flows'] as Map).entries) {
        final stats = entry.value as Map;
        if (!stats.containsKey('critical_observed')) {
          stats['critical_observed'] = (state['records'] as List).where((r) => group(r as Map) == entry.key && BleCriticalEventPolicy.isCritical(r)).length;
          stats['critical_dropped'] = 0;
          stats['critical_drop_reasons'] = <String, dynamic>{};
          stats['critical_history_unknown'] = stats['history_unknown'] == true || (stats['dropped'] as int? ?? 0) > 0;
        }
      }
      state['protected_requests'] ??= _recentRequests(state['records'] as List);
      state['retention_schema_version'] = 2;
      return state;
    }
    List<dynamic> legacy = const [];
    for (final legacyKey in legacyKeys) {
      final value = storage.read<List<dynamic>>(legacyKey);
      if (value != null) { legacy = value; break; }
    }
    final records = legacy.whereType<Map>().map(Map<String, dynamic>.from).toList();
    final flows = <String, dynamic>{};
    for (final record in records) {
      final stats = flows.putIfAbsent(group(record), () => _newStats(true)) as Map;
      stats['total'] = (stats['total'] as int) + 1;
      if (BleCriticalEventPolicy.isCritical(record)) stats['critical_observed'] = (stats['critical_observed'] as int) + 1;
    }
    return {'records': records, 'flows': flows, 'next_sequence': 1, 'protected_requests': _recentRequests(records), 'retention_schema_version': 2};
  }

  List<String> _recentRequests(List records) {
    if (!pinCurrentAttempt) return [];
    final requests = <String>[];
    for (final record in records.cast<Map>()) {
      final request = BleCriticalEventPolicy.requestKey(record, group(record));
      if (request != null && !requests.contains(request)) requests.add(request);
      if (requests.length == maximumProtectedRequests) break;
    }
    return requests;
  }

  void _addUnpersistedLosses(Map<String, dynamic> state) {
    if (_unpersistedMetadataEvicted) state['metadata_evicted'] = true;
    final flows = state['flows'] as Map;
    for (final entry in _unpersistedLosses.entries) {
      final stats = flows.putIfAbsent(entry.key, () => _newStats(state['metadata_evicted'] == true)) as Map;
      for (final name in ['total', 'dropped', 'critical_observed', 'critical_dropped']) {
        stats[name] = (stats[name] as int? ?? 0) + (entry.value[name] as int);
      }
      if ((entry.value['critical_dropped'] as int) > 0) {
        final reasons = stats['critical_drop_reasons'] as Map;
        reasons['persistence_write_failure'] = (reasons['persistence_write_failure'] as int? ?? 0) + (entry.value['critical_dropped'] as int);
      }
    }
  }

  List<Map<String, dynamic>> readAll() => (_state()['records'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  Future<T> _enqueue<T>(FutureOr<T> Function() work) {
    final operation = _queue.then((_) => work());
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  void _drop(Map record, Map flows, String reason) {
    final stats = flows[group(record)] as Map?;
    if (stats == null) return;
    stats['dropped'] = (stats['dropped'] as int) + 1;
    if (BleCriticalEventPolicy.isCritical(record)) {
      stats['critical_dropped'] = (stats['critical_dropped'] as int) + 1;
      final reasons = stats['critical_drop_reasons'] as Map;
      reasons[reason] = (reasons[reason] as int? ?? 0) + 1;
    }
  }

  void _trim(Map<String, dynamic> state) {
    final records = state['records'] as List, flows = state['flows'] as Map;
    final protected = (state['protected_requests'] as List).toSet();
    final anchors = <Map>{};
    if (pinCurrentAttempt && records.isNotEmpty) {
      final latest = records.firstWhere((r) => (r as Map)['attempt_id'] != null, orElse: () => const <String, dynamic>{}) as Map;
      final owned = records.where((r) => latest['attempt_id'] != null && (r as Map)['attempt_id'] == latest['attempt_id']).cast<Map>().toList();
      final starts = owned.where(BleCriticalEventPolicy.isCritical);
      if (starts.isNotEmpty && maximumRecords > 1) anchors.add(starts.last);
      final terminal = owned.where((r) => r['terminal_outcome'] != null || r['event_type'] == 'security_write_terminal');
      if (terminal.isNotEmpty && maximumRecords > 2) anchors.add(terminal.first);
    }
    bool protectedCritical(Map record) => pinCurrentAttempt && BleCriticalEventPolicy.isCritical(record) &&
        protected.contains(BleCriticalEventPolicy.requestKey(record, group(record)));
    void removeRecord(String capacity) {
      var index = records.length - 1;
      final ordinary = records.lastIndexWhere((r) => !anchors.contains(r) && !BleCriticalEventPolicy.isCritical(r as Map));
      final expired = records.lastIndexWhere((r) => !anchors.contains(r) && !protectedCritical(r as Map));
      if (ordinary >= 0) {
        index = ordinary;
      } else if (expired >= 0) {
        index = expired;
      } else {
        while (index > 0 && anchors.contains(records[index])) { index--; }
      }
      final removed = records.removeAt(index) as Map;
      final reason = capacity == 'byte_capacity' ? capacity : protectedCritical(removed) ? 'critical_event_capacity' : 'older_request_window';
      _drop(removed, flows, reason);
    }
    while (records.length > maximumRecords) { removeRecord('record_capacity'); }
    while (flows.length > 128) { flows.remove(flows.keys.first); state['metadata_evicted'] = true; }
    while (_bytes(state) > maximumBytes) {
      if (records.isNotEmpty) {
        removeRecord('byte_capacity');
      } else if (flows.isNotEmpty) {
        flows.remove(flows.keys.first); state['metadata_evicted'] = true;
      } else {
        (state['protected_requests'] as List).clear();
      }
    }
  }

  Future<void> record(Map<String, Object?> record) {
    final frozen = Map<String, dynamic>.from(jsonDecode(jsonEncode(record)) as Map);
    return _enqueue(() async {
      final state = _state();
      _addUnpersistedLosses(state);
      final sequence = state['next_sequence'] as int;
      state['next_sequence'] = sequence + 1;
      frozen['record_sequence'] = sequence;
      (state['records'] as List).insert(0, frozen);
      final flows = state['flows'] as Map;
      final flow = group(frozen);
      final stats = flows.putIfAbsent(flow, () => _newStats(state['metadata_evicted'] == true)) as Map;
      stats['total'] = (stats['total'] as int) + 1;
      if (BleCriticalEventPolicy.isCritical(frozen)) stats['critical_observed'] = (stats['critical_observed'] as int) + 1;
      final request = pinCurrentAttempt ? BleCriticalEventPolicy.requestKey(frozen, flow) : null;
      final protected = state['protected_requests'] as List;
      if (request != null && !protected.contains(request)) protected.insert(0, request);
      while (protected.length > maximumProtectedRequests) { protected.removeLast(); }
      final pendingFailures = _writeFailures;
      state['write_failures'] = (state['write_failures'] as int? ?? 0) + pendingFailures;
      _trim(state);
      try { await storage.write(key, state); }
      catch (_) {
        _writeFailures++;
        final loss = _unpersistedLosses.putIfAbsent(flow, () => _newStats(false));
        loss['total'] = (loss['total'] as int) + 1;
        loss['dropped'] = (loss['dropped'] as int) + 1;
        if (BleCriticalEventPolicy.isCritical(frozen)) {
          loss['critical_observed'] = (loss['critical_observed'] as int) + 1;
          loss['critical_dropped'] = (loss['critical_dropped'] as int) + 1;
        }
        while (_unpersistedLosses.length > 128) { _unpersistedLosses.remove(_unpersistedLosses.keys.first); _unpersistedMetadataEvicted = true; }
        rethrow;
      }
      _unpersistedLosses.clear(); _unpersistedMetadataEvicted = false;
      _writeFailures -= pendingFailures;
    });
  }

  Future<void> flush() => _queue;
  Future<BleDiagnosticJournalSnapshot> snapshot() => _enqueue(() {
    final state = _state();
    _addUnpersistedLosses(state);
    _trim(state);
    return BleDiagnosticJournalSnapshot(
      (state['records'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList(),
      Map<String, dynamic>.from(state['flows'] as Map), _writeFailures + (state['write_failures'] as int? ?? 0),
      maximumRecords, maximumBytes, _bytes(state), maximumProtectedRequests, pinCurrentAttempt,
    );
  });
  Future<void> clear() => _enqueue(() async {
    await storage.remove(key);
    for (final legacyKey in legacyKeys) { await storage.remove(legacyKey); }
    _writeFailures = 0; _unpersistedLosses.clear(); _unpersistedMetadataEvicted = false;
  });
}
