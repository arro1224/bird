import 'dart:async';
import 'package:aves/bird_companion/core/diagnostics/app_build_identity.dart';
import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_recorder.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_widgets.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Storage implements DiagnosticStorage {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class _Files implements BirdBoxBleDiagnosticFilePlatform {
  int prepared = 0, saved = 0;
  @override
  Future<Map<String, dynamic>> buildIdentity() async => {'build_id': 'phone-test-build', 'version_name': '1.14.11', 'version_code': '176'};
  @override
  Future<BleDiagnosticFile> prepare(BleDiagnosticExport export) async {
    prepared++;
    expect(export.fullJson, contains('earlier-timeout'));
    return BleDiagnosticFile(token: 'file', fileName: 'BirdBox_Phone_test.json', mimeType: 'application/json', bytes: 600, sha256: export.payloadSha256);
  }

  @override
  Future<String> save(BleDiagnosticFile file) async {
    saved++;
    return 'saved';
  }

  @override
  Future<String> share(BleDiagnosticFile file) async => 'share_opened';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('visible route and lifecycle are recorded without navigation arguments', (tester) async {
    final recorder = PhoneDiagnosticRecorder(_Storage());
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      PhoneDiagnosticLifecycle(
        recorder: recorder,
        child: MaterialApp(
          navigatorKey: key,
          navigatorObservers: [PhoneDiagnosticNavigationObserver(recorder)],
          home: const Scaffold(),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: (_) => const Scaffold()),
        ),
      ),
    );
    unawaited(key.currentState!.pushNamed('/photo-detail', arguments: {'file_id': 'secret-navigation-argument'}));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final snapshot = await recorder.snapshot();
    expect((snapshot['events'] as List).any((e) => e['page'] == '/photo-detail' && e['lifecycle'] == 'paused'), true);
    expect(snapshot.toString(), isNot(contains('secret-navigation-argument')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await recorder.dispose();
  });
  test('actual build identity is cached rather than repeatedly hashing the installed APK', () async {
    var calls = 0;
    const channel = MethodChannelBirdBoxBleDiagnosticFilePlatform.channel;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getBuildIdentity');
      calls++;
      return {'build_id': 'real-native-build', 'version_name': '1.14.11', 'version_code': '176', 'apk_sha256': 'a' * 64};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final identity = AppBuildIdentity();
    final both = await Future.wait([identity.read(), identity.read()]);
    expect(calls, 1);
    expect(AppBuildIdentity.version(both.first), '1.14.11 (176)');
    expect(both.last['build_id'], 'real-native-build');
  });

  testWidgets('disconnected phone export remains usable, debounces preparation and saves retained failures', (tester) async {
    final ready = Completer<BleDiagnosticExport>();
    final files = _Files();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneDiagnosticExportButton(
            capture: () {
              calls++;
              return ready.future;
            },
            files: files,
          ),
        ),
      ),
    );
    await tester.tap(find.text('导出手机诊断'));
    await tester.pump();
    expect(find.text('正在准备手机诊断'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    expect(calls, 1);
    ready.complete(
      BleDiagnosticExport(
        traceId: 'after-recovery',
        scans: const [],
        events: const [],
        generatedAt: DateTime.utc(2026),
        exporterBuild: await files.buildIdentity(),
        phoneDiagnostics: {
          'events': [
            {'request_id': 'earlier-timeout', 'error_code': 'receiveTimeout'},
          ],
          'retention': {'truncated': false},
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('手机请求与状态记录 1 条'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ble-save-full-file')));
    await tester.tap(find.byKey(const Key('ble-save-full-file')));
    await tester.pumpAndSettle();
    expect(files.prepared, 1);
    expect(files.saved, 1);
    expect(find.textContaining('文件已保存'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}
