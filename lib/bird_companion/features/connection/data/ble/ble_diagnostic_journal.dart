import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';

final class BleDiagnosticJournalSnapshot {
  const BleDiagnosticJournalSnapshot(this.records, this.flows, this.writeFailures, this.maximumRecords);
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic> flows;
  final int writeFailures, maximumRecords;
  Map<String, dynamic> retentionFor(String flowId, int retained) {
    final stats = flows[flowId] as Map?;
    return {
      'retained': retained,
      'total_observed': stats?['total'],
      'dropped': stats?['dropped'],
      'history_unknown': stats == null || stats['history_unknown'] == true,
      'persistence_write_failures': writeFailures,
      'maximum_retained_records': maximumRecords,
      'truncated': stats == null || stats['history_unknown'] == true || (stats['dropped'] as int? ?? 0) > 0 || writeFailures > 0,
    };
  }
}

/// One atomic cache value holds records and loss accounting. Queue barriers
/// capture a fixed cutoff even if callbacks continue arriving during export.
final class BleDiagnosticJournal {
  BleDiagnosticJournal(this.storage, {required this.key, required this.legacyKeys, required this.maximumRecords, this.pinCurrentAttempt = false}) : assert(maximumRecords > 0);
  final DiagnosticStorage storage;
  final String key;
  final List<String> legacyKeys;
  final int maximumRecords;
  final bool pinCurrentAttempt;
  Future<void> _queue = Future.value();
  int _writeFailures = 0;
  final _unpersistedLosses = <String, int>{};

  void _addUnpersistedLosses(Map<String, dynamic> state) {
    final flows = state['flows'] as Map;
    for (final entry in _unpersistedLosses.entries) {
      final stats = flows.putIfAbsent(entry.key, () => <String, dynamic>{'total': 0, 'dropped': 0, 'history_unknown': state['metadata_evicted'] == true}) as Map;
      stats['total'] = (stats['total'] as int) + entry.value;
      stats['dropped'] = (stats['dropped'] as int) + entry.value;
    }
  }

  static String group(Map value) => (value['flow_id'] ?? value['scan_session_id'] ?? value['trace_id']).toString();
  Map<String, dynamic> _state() {
    final current = storage.read<Map>(key);
    if (current != null) return Map<String, dynamic>.from(jsonDecode(jsonEncode(current)) as Map);
    List<dynamic> legacy = const [];
    for (final legacyKey in legacyKeys) {
      final value = storage.read<List<dynamic>>(legacyKey);
      if (value != null) {
        legacy = value;
        break;
      }
    }
    final records = legacy.whereType<Map>().map(Map<String, dynamic>.from).toList();
    final flows = <String, dynamic>{};
    for (final record in records) {
      final stats = flows.putIfAbsent(group(record), () => <String, dynamic>{'total': 0, 'dropped': 0, 'history_unknown': true}) as Map;
      stats['total'] = (stats['total'] as int) + 1;
    }
    return {'records': records, 'flows': flows, 'next_sequence': 1};
  }

  List<Map<String, dynamic>> readAll() => (_state()['records'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();

  Future<T> _enqueue<T>(FutureOr<T> Function() work) {
    final operation = _queue.then((_) => work());
    _queue = operation.then<void>(
      (_) {},
      onError: (Object _) {
        _writeFailures++;
      },
    );
    return operation;
  }

  Future<void> record(Map<String, Object?> record) {
    final frozen = Map<String, dynamic>.from(jsonDecode(jsonEncode(record)) as Map);
    return _enqueue(() async {
      final state = _state();
      _addUnpersistedLosses(state);
      final sequence = state['next_sequence'] as int;
      state['next_sequence'] = sequence + 1;
      frozen['record_sequence'] = sequence;
      final records = (state['records'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      records.insert(0, frozen);
      final flows = Map<String, dynamic>.from(state['flows'] as Map);
      final flow = group(frozen);
      final stats = flows.putIfAbsent(flow, () => <String, dynamic>{'total': 0, 'dropped': 0, 'history_unknown': state['metadata_evicted'] == true}) as Map;
      stats['total'] = (stats['total'] as int) + 1;
      final attempt = pinCurrentAttempt ? records.firstWhere((r) => r['attempt_id'] != null, orElse: () => const {})['attempt_id'] : null;
      final anchors = <Map<String, dynamic>>{};
      if (attempt != null && maximumRecords > 1) {
        final owned = records.where((r) => r['attempt_id'] == attempt).toList();
        if (owned.isNotEmpty) anchors.add(owned.last);
        final terminals = owned.where((r) => r['terminal_outcome'] != null || r['event_type'] == 'security_write_terminal');
        if (terminals.isNotEmpty && maximumRecords > 2) anchors.add(terminals.first);
      }
      while (records.length > maximumRecords) {
        var index = records.length - 1;
        while (index > 0 && anchors.contains(records[index])) {
          index--;
        }
        final removed = records.removeAt(index);
        final dropped = flows[group(removed)] as Map?;
        if (dropped != null) dropped['dropped'] = (dropped['dropped'] as int) + 1;
      }
      // Loss metadata is bounded too. Missing old history is explicitly unknown.
      var metadataEvicted = state['metadata_evicted'] == true;
      while (flows.length > 128) {
        flows.remove(flows.keys.firstWhere((key) => key != flow));
        metadataEvicted = true;
      }
      final pendingFailures = _writeFailures;
      try {
        await storage.write(key, {'records': records, 'flows': flows, 'next_sequence': sequence + 1, 'metadata_evicted': metadataEvicted, 'write_failures': (state['write_failures'] as int? ?? 0) + pendingFailures});
      } catch (_) {
        _unpersistedLosses.update(flow, (value) => value + 1, ifAbsent: () => 1);
        rethrow;
      }
      _unpersistedLosses.clear();
      _writeFailures -= pendingFailures;
    });
  }

  Future<void> flush() => _queue;
  Future<BleDiagnosticJournalSnapshot> snapshot() => _enqueue(() {
    final state = _state();
    _addUnpersistedLosses(state);
    return BleDiagnosticJournalSnapshot(
      (state['records'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList(),
      Map<String, dynamic>.from(state['flows'] as Map),
      _writeFailures + (state['write_failures'] as int? ?? 0),
      maximumRecords,
    );
  });
  Future<void> clear() => _enqueue(() async {
    await storage.remove(key);
    for (final legacyKey in legacyKeys) {
      await storage.remove(legacyKey);
    }
    _writeFailures = 0;
    _unpersistedLosses.clear();
  });
}
