import 'dart:convert';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/ble_diagnostic_export_dialog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BleDiagnosticExport build(List<Map<String, dynamic>> events) => BleDiagnosticExport(
    traceId: 'ble-test-trace',
    scans: const [
      {'end_reason': 'timeout', 'raw_result_count': 3},
    ],
    events: events,
    generatedAt: DateTime.utc(2026, 10, 4),
  );

  test('large Unicode trace is lossless, valid JSON and bounded per part', () {
    final events = List.generate(1000, (i) => <String, dynamic>{'event_type': 'event_$i', 'sanitized_message': '鸟🐦\\"\n\u0001' * 100});
    final export = build(events);
    final parts = export.parts.map((s) {
      expect(utf8.encode(s).length, lessThanOrEqualTo(4096));
      return jsonDecode(s) as Map<String, dynamic>;
    }).toList();
    expect(parts.length, greaterThan(1));
    expect(parts.map((e) => e['part']), orderedEquals(List.generate(parts.length, (i) => i + 1)));
    expect(parts.every((e) => e['total_parts'] == parts.length), isTrue);
    final restored = parts.map((e) => e['payload'] as String).join();
    expect(restored, export.fullJson);
    final checksum = sha256.convert(utf8.encode(restored)).toString();
    expect(parts.every((e) => e['full_sha256'] == checksum), isTrue);
    expect((jsonDecode(restored) as Map)['connection_events'], events);
    expect(utf8.encode(export.summaryJson).length, lessThanOrEqualTo(4096));
  });

  test('summary keeps first root error and latest state, explicitly not full evidence', () {
    final export = build([
      {'event_type': 'write_failed', 'gatt_status': 5, 'error_code': 'authentication_required', 'bond_state': 'not_bonded'},
      {'event_type': 'disconnect', 'error_code': 'invalid_state'},
      {'event_type': 'bond_state_changed', 'bond_state': 'bonded'},
    ]);
    final value = jsonDecode(export.summaryJson) as Map;
    expect(value['full_record_included'], isFalse);
    expect(value['retained_event_count'], 3);
    expect(value['first_error']['gatt_status'], 5);
    expect(value['latest_state']['bond_state'], 'bonded');
  });

  test('empty trace and oversized fields remain parseable and bounded', () {
    expect((jsonDecode(build([]).summaryJson) as Map)['first_error'], isNull);
    final value = {
      for (final key in [
        'event_type',
        'operation_name',
        'platform_method',
        'pending_operation',
        'native_state',
        'security_phase',
        'bond_state',
        'actual_bond_state',
        'characteristic_uuid',
        'request_id',
        'result_code',
        'error_code',
        'bond_initiation_source',
      ])
        key: '🐦' * 10000,
    };
    expect(utf8.encode(build([value]).summaryJson).length, lessThanOrEqualTo(4096));
  });

  testWidgets('copy summary and numbered parts without auto advancing or truncation', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final export = build([
      {'sanitized_message': '鸟' * 4000},
    ]);
    await tester.pumpWidget(MaterialApp(home: BleDiagnosticExportDialog(export: export)));
    await tester.tap(find.text('复制短摘要'));
    await tester.pumpAndSettle();
    expect(clipboard, export.summaryJson);
    await tester.tap(find.text('复制当前段'));
    await tester.pumpAndSettle();
    expect(clipboard, export.parts[0]);
    expect(find.text('完整记录：第 1 / ${export.parts.length} 段'), findsOneWidget);
    await tester.tap(find.text('下一段'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制当前段'));
    await tester.pumpAndSettle();
    expect(clipboard, export.parts[1]);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') throw PlatformException(code: 'clipboard_unavailable');
      return null;
    });
    await tester.tap(find.text('复制当前段'));
    await tester.pumpAndSettle();
    expect(find.text('复制失败，请重试'), findsOneWidget);
  });
}
