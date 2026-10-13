import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/ble22/phone_inspection_semantics.dart';
import 'ble11_dual_avd_test.dart' as transport;

// Test entrypoint only. The runner writes the selected scenario to app-private
// storage, so both roles and all scenarios execute the identical frozen APK.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(stabilizePhoneInspectionSemantics(binding));
  final directory = Directory('${Directory.systemTemp.parent.path}/files');
  late Map config;
  transport.main(
    scenarioResolver: () async {
      config = jsonDecode(await File('${directory.path}/ble22-config.json').readAsString()) as Map;
      return config['scenario'] as String;
    },
    onEvidence: (evidence) async {
      final result = <String, Object?>{
        'scenario': config['scenario'],
        'run_id': config['run_id'],
        'app_evidence': evidence,
        'test_harness': {'platform_semantics': 'enabled_before_test_baseline', 'production_accessibility_coverage': false},
        'export_status': 'pending',
      };
      // Persist actual transport evidence before any export work can stall.
      // A pending checkpoint is never an accepted diagnostic artifact.
      void checkpoint(String stage) {
        result['export_stage'] = stage;
        final pending = File('${directory.path}/ble22-last-result.json.tmp');
        pending.writeAsStringSync(jsonEncode(result), flush: true);
        pending.renameSync('${directory.path}/ble22-last-result.json');
      }

      checkpoint('connection_event_store');
      final store = BleConnectionDiagnosticStore(_MemoryStorage());
      try {
        for (final value in evidence['events'] as List) {
          await store.record(BleConnectionDiagnosticEvent.fromJson(Map<String, dynamic>.from(value as Map)));
        }
        checkpoint('connection_event_snapshot');
        final snapshot = await store.snapshot();
        final traceId = snapshot.records.isEmpty ? 'ble22-empty' : snapshot.records.first['trace_id'] as String;
        const files = MethodChannelBirdBoxBleDiagnosticFilePlatform();
        checkpoint('export_build_identity');
        final exporterBuild = await files.buildIdentity();
        final export = BleDiagnosticExport(
          traceId: traceId,
          scans: const [],
          events: snapshot.records,
          generatedAt: DateTime.now(),
          exporterBuild: exporterBuild,
          retention: {
            'connection_events': snapshot.retentionFor(traceId, snapshot.records.length),
            'scan_sessions': {'retained': 0, 'truncated': false},
            'observations_dropped': 0,
            'scope': 'actual_connection_events_only_scan_ui_export_pending',
          },
        );
        checkpoint('native_file_prepare');
        final artifact = await files.prepare(export);
        result['export'] = {'file_name': artifact.fileName, 'mime_type': artifact.mimeType, 'bytes': artifact.bytes, 'sha256': artifact.sha256, 'payload_sha256': export.payloadSha256};
        result['export_status'] = 'prepared';
      } catch (error) {
        result['export_status'] = 'failed';
        result['export_failure_stage'] = result['export_stage'];
        result['export_error_kind'] = error.runtimeType.toString();
        rethrow;
      } finally {
        try {
          checkpoint('finished');
          // ignore: avoid_print
          print('BLE22_PHONE_RESULT ${jsonEncode(result)}');
        } finally {
          await store.dispose();
        }
      }
    },
  );
}

final class _MemoryStorage implements DiagnosticStorage {
  final _values = <String, Object?>{};
  @override
  T? read<T>(String key) => _values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async => _values[key] = value;
  @override
  Future<void> remove(String key) async => _values.remove(key);
}
