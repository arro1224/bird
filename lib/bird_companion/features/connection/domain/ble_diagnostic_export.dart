import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Clipboard-friendly export of the already redacted, locally retained trace.
/// Summary is not full evidence. Full parts reconstruct [fullJson] verbatim.
final class BleDiagnosticExport {
  BleDiagnosticExport({
    required String traceId,
    required List<Map<String, dynamic>> scans,
    required List<Map<String, dynamic>> events,
    required DateTime generatedAt,
  }) {
    final build = _buildMetadata(scans, events);
    final header = <String, dynamic>{
      'schema_version': 3,
      'generated_at': generatedAt.toUtc().toIso8601String(),
      'trace_id': traceId,
      if (build.isNotEmpty) 'build': build,
    };
    fullJson = jsonEncode({...header, 'scan_sessions': scans, 'connection_events': events});
    final errors = events.where((e) => e['error_code'] != null || (e['gatt_status'] is int && (e['gatt_status'] as int) > 0) || RegExp('fail|error|timeout').hasMatch(e['event_type']?.toString() ?? ''));
    final summary = <String, dynamic>{
      ...header,
      'export_kind': 'summary',
      'full_record_included': false,
      'retained_event_count': events.length,
      'scan': scans.isEmpty ? null : _pick(scans.last, _scanKeys),
      'first_error': errors.isEmpty ? null : _pick(errors.first, _eventKeys),
      'latest_state': events.isEmpty ? null : _pick(events.last, _eventKeys),
    };
    var limit = 128;
    while (true) {
      final output = jsonEncode(_shorten(summary, limit));
      if (utf8.encode(output).length <= 4096) {
        summaryJson = output;
        break;
      }
      limit ~/= 2;
      summary['summary_strings_shortened'] = true;
    }
    // JSON escaping is accounted for before accepting each chunk. Never split
    // a Unicode scalar or truncate the actual retained trace.
    final chunks = <String>[];
    var chunk = StringBuffer();
    var escapedBytes = 0;
    for (final rune in fullJson.runes) {
      final scalar = String.fromCharCode(rune);
      final cost = utf8.encode(jsonEncode(scalar)).length - 2;
      if (escapedBytes + cost > 3000) {
        chunks.add(chunk.toString());
        chunk = StringBuffer();
        escapedBytes = 0;
      }
      chunk.write(scalar);
      escapedBytes += cost;
    }
    if (chunk.isNotEmpty) chunks.add(chunk.toString());
    final checksum = sha256.convert(utf8.encode(fullJson)).toString();
    parts = List.unmodifiable([
      for (var i = 0; i < chunks.length; i++)
        jsonEncode({
          'schema_version': 1,
          'export_kind': 'ble_trace_part',
          'encoding': 'concatenate_payload_strings_then_parse_json',
          'full_sha256': checksum,
          'part': i + 1,
          'total_parts': chunks.length,
          'payload': chunks[i],
        }),
    ]);
  }

  late final String summaryJson;
  late final String fullJson;
  late final List<String> parts;

  static Map<String, Object?> _buildMetadata(
    List<Map<String, dynamic>> scans,
    List<Map<String, dynamic>> events,
  ) {
    final records = <Map<String, dynamic>>[
      if (events.isNotEmpty) events.last,
      if (scans.isNotEmpty) scans.last,
    ];

    Object? firstValue(List<String> keys) {
      for (final record in records) {
        for (final key in keys) {
          final value = record[key];
          if (value is String && value.isNotEmpty) return value;
          if (value is int) return value;
        }
      }
      return null;
    }

    final packageId = firstValue(const ['package_id']);
    final flavor = firstValue(const ['build_flavor', 'scan_flavor']);
    final buildType = firstValue(const ['build_type']);
    final versionName = firstValue(const ['app_version_name']);
    final versionCode = firstValue(const ['app_version_code']);
    final gitCommit = firstValue(const ['git_commit']);
    final apkSha256 = firstValue(const ['apk_sha256']);
    return {
      'package_id': ?packageId,
      'flavor': ?flavor,
      'build_type': ?buildType,
      'version_name': ?versionName,
      'version_code': ?versionCode,
      'git_commit': ?gitCommit,
      'apk_sha256': ?apkSha256,
    };
  }

  static Object? _shorten(Object? value, int limit) {
    if (value is String) return value.runes.length > limit ? '${String.fromCharCodes(value.runes.take(limit))}…' : value;
    if (value is Map<String, dynamic>) return value.map((key, item) => MapEntry(key, _shorten(item, limit)));
    return value;
  }

  static Map<String, dynamic> _pick(Map<String, dynamic> value, List<String> keys) => {
    for (final key in keys)
      if (value[key] is String) key: _short(value[key] as String) else if (value[key] is num || value[key] is bool) key: value[key],
  };

  static String _short(String value) {
    final runes = value.runes.take(128).toList();
    return value.runes.length > 128 ? '${String.fromCharCodes(runes)}…' : value;
  }

  static const _scanKeys = ['scan_session_id', 'end_reason', 'raw_result_count', 'accepted_count', 'filtered_count', 'permission_after', 'adapter_after', 'android_scan_error_code', 'scan_permission_policy'];
  static const _eventKeys = [
    'occurred_at',
    'event_type',
    'operation_name',
    'platform_method',
    'pending_operation',
    'native_state',
    'security_phase',
    'gatt_status',
    'bond_state',
    'actual_bond_state',
    'characteristic_uuid',
    'request_id',
    'result_code',
    'error_code',
    'gatt_present',
    'link_ready',
    'connection_generation',
    'gatt_generation',
    'conditional_bond_fallback_attempted',
    'bond_initiation_source',
    'attempt_id',
    'write_api_accepted',
    'write_callback_received',
    'security_write_elapsed_ms',
    'fallback_trigger',
    'bond_state_at_trigger',
    'create_bond_invoked',
    'create_bond_returned',
    'create_bond_state_before',
    'create_bond_state_after',
    'create_bond_exception',
    'state_before',
    'state_after',
    'terminal_outcome',
    'cleanup_outcome',
  ];
}
