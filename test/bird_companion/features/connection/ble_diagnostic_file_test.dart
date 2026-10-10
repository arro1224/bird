import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/ble_diagnostic_export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

BleDiagnosticExport export() => BleDiagnosticExport(traceId: 'flow', scans: const [], events: const [], generatedAt: DateTime.utc(2026));

class FileActions implements BirdBoxBleDiagnosticFilePlatform {
  String outcome = 'cancelled';
  bool shareUnavailable = false;
  int prepared = 0, saved = 0, shared = 0;
  @override
  Future<Map<String, dynamic>> buildIdentity() async => {};
  @override
  Future<BleDiagnosticFile> prepare(BleDiagnosticExport export) async {
    prepared++;
    return BleDiagnosticFile(token: 'token', fileName: 'BirdBox_BLE_test.json', mimeType: 'application/json', bytes: 500, sha256: export.payloadSha256);
  }

  @override
  Future<String> save(BleDiagnosticFile file) async {
    saved++;
    return outcome;
  }

  @override
  Future<String> share(BleDiagnosticFile file) async {
    shared++;
    if (shareUnavailable) throw PlatformException(code: 'share_unavailable');
    return 'share_opened';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannelBirdBoxBleDiagnosticFilePlatform();
  const channel = MethodChannelBirdBoxBleDiagnosticFilePlatform.channel;
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  test('verified JSON sends exact UTF8 payload digest and validates final file identity', () async {
    final e = export();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'prepare');
      expect(call.arguments['fullJson'], e.fullJson);
      expect(call.arguments['payloadSha256'], e.payloadSha256);
      return {'token': 'id', 'fileName': 'BirdBox_BLE_test.json', 'mimeType': 'application/json', 'bytes': 123, 'sha256': e.payloadSha256, 'payloadSha256': e.payloadSha256, 'verified': true};
    });
    final f = await platform.prepare(e);
    expect(f.sha256, e.payloadSha256);
  });
  test('unverified, corrupt and traversal file results cannot become shareable', () async {
    final e = export();
    for (final alteration in [
      {'verified': false},
      {'sha256': 'f' * 64},
      {'payloadSha256': 'f' * 64},
      {'fileName': '../outside.json'},
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => {'token': 'id', 'fileName': 'test.json', 'mimeType': 'application/json', 'bytes': 123, 'sha256': e.payloadSha256, 'payloadSha256': e.payloadSha256, 'verified': true, ...alteration},
      );
      await expectLater(platform.prepare(e), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'file_verification_failed')));
    }
  });
  test('ZIP file checksum may differ from full payload but both must be supplied', () async {
    final e = export();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => {'token': 'id', 'fileName': 'test.zip', 'mimeType': 'application/zip', 'bytes': 100, 'sha256': 'c' * 64, 'payloadSha256': e.payloadSha256, 'verified': true},
    );
    expect((await platform.prepare(e)).sha256, 'c' * 64);
  });
  test('share chooser outcome cannot claim successful save or transmission', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {'outcome': 'saved'});
    await expectLater(platform.share(const BleDiagnosticFile(token: 'id', fileName: 'f.json', mimeType: 'application/json', bytes: 1, sha256: 'digest')), throwsA(isA<PlatformException>()));
  });
  testWidgets('share unavailable offers save; cancel stays retryable and success requires saved result', (tester) async {
    final files = FileActions()..shareUnavailable = true;
    await tester.pumpWidget(
      MaterialApp(
        home: BleDiagnosticExportDialog(export: export(), files: files),
      ),
    );
    await tester.tap(find.byKey(const Key('ble-share-full-file')));
    await tester.pumpAndSettle();
    expect(find.text('分享暂不可用，请使用“保存文件”'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ble-save-full-file')));
    await tester.tap(find.byKey(const Key('ble-save-full-file')));
    await tester.pumpAndSettle();
    expect(find.text('已取消保存，可再次选择位置'), findsOneWidget);
    expect(find.text('文件已保存，写入内容已重新读取并校验'), findsNothing);
    files.outcome = 'saved';
    await tester.ensureVisible(find.byKey(const Key('ble-save-full-file')));
    await tester.tap(find.byKey(const Key('ble-save-full-file')));
    await tester.pumpAndSettle();
    expect(find.text('文件已保存，写入内容已重新读取并校验'), findsOneWidget);
    expect(files.prepared, 1);
    expect(files.saved, 2);
  });
  testWidgets('share launch is shown as chooser open with final SHA available', (tester) async {
    final files = FileActions();
    final e = export();
    await tester.pumpWidget(
      MaterialApp(
        home: BleDiagnosticExportDialog(export: e, files: files),
      ),
    );
    await tester.tap(find.byKey(const Key('ble-share-full-file')));
    await tester.pumpAndSettle();
    expect(find.text('已打开系统分享面板。请以接收端实际收到文件为准。'), findsOneWidget);
    expect(find.text('文件已保存，写入内容已重新读取并校验'), findsNothing);
    expect(find.byKey(const Key('ble-final-file-sha256')), findsOneWidget);
  });
}
