import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_scan_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_journal.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';

final class BleDiagnosticSnapshotService {
  const BleDiagnosticSnapshotService(this.scans, this.connections, this.files);
  final BleScanDiagnosticStore scans;
  final BleConnectionDiagnosticStore connections;
  final BirdBoxBleDiagnosticFilePlatform files;

  Future<BleDiagnosticExport> capture(String scanId, {bool includeRetainedHistory = false}) async {
    // Enqueue both barriers synchronously: later writes belong to a later export.
    final snapshots = await Future.wait([scans.snapshot(), connections.snapshot()]);
    final scanSnapshot = snapshots[0], connectionSnapshot = snapshots[1];
    final matching = scanSnapshot.records.where((r) => r['scan_session_id'] == scanId);
    final flowId = matching.isEmpty ? scanId : BleDiagnosticJournal.group(matching.first);
    final selectedScans = scanSnapshot.records.where((r) => includeRetainedHistory || BleDiagnosticJournal.group(r) == flowId).toList()..sort(_compare);
    final scanIds = selectedScans.map((s) => s['scan_session_id']).toSet();
    final events = connectionSnapshot.records.where((r) => includeRetainedHistory || BleDiagnosticJournal.group(r) == flowId || (r['flow_id'] == null && scanIds.contains(r['trace_id']))).toList()..sort(_compare);
    final retention = {
      'export_scope': includeRetainedHistory ? 'all_locally_retained_attempts_not_unbounded_raw_history' : 'requested_flow_only',
      'requested_trace_id': scanId,
      'included_flow_ids': {
        for (final r in [...selectedScans, ...events]) BleDiagnosticJournal.group(r),
      }.toList(),
      'scan_sessions': scanSnapshot.retentionFor(flowId, selectedScans.where((r) => BleDiagnosticJournal.group(r) == flowId).length),
      'connection_events': connectionSnapshot.retentionFor(flowId, events.where((r) => BleDiagnosticJournal.group(r) == flowId).length),
      if (includeRetainedHistory)
        'per_flow_retention': {
          for (final id in {...scanSnapshot.flows.keys, ...connectionSnapshot.flows.keys})
            id: {
              'scans': scanSnapshot.retentionFor(id, selectedScans.where((r) => BleDiagnosticJournal.group(r) == id).length),
              'events': connectionSnapshot.retentionFor(id, events.where((r) => BleDiagnosticJournal.group(r) == id).length),
            },
        },
      'observations_dropped': selectedScans.fold<int>(0, (n, s) => n + (s['observations_dropped'] as int? ?? ((s['raw_result_count'] as int? ?? 0) - (s['observations'] as List? ?? const []).length).clamp(0, 1 << 30))),
      'retention_policy': 'critical_events_first_bounded_requests_records_and_utf8_bytes_v2',
      'snapshot_cutoff': 'records_enqueued_before_joint_queue_barriers',
    };
    Map<String, dynamic>? build;
    try {
      build = await files.buildIdentity();
    } catch (_) {
      /* Recorded build fields remain usable offline. */
    }
    return BleDiagnosticExport(traceId: flowId, scans: selectedScans, events: events, generatedAt: DateTime.now(), retention: retention, exporterBuild: build);
  }

  static int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final time = (a['occurred_at'] ?? a['started_at'] ?? '').toString().compareTo((b['occurred_at'] ?? b['started_at'] ?? '').toString());
    return time != 0 ? time : (a['record_sequence'] as int? ?? 0).compareTo(b['record_sequence'] as int? ?? 0);
  }
}
