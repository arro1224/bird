import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Internal test entry only. The normal delivery target remains lib/main.dart.
// All business reads use the actual Python backend; no Dart fake gateway.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Python continuous summary opens real file details on Android', (tester) async {
    HttpOverrides.global = null;
    final client = ApiClient()..configure(Uri.parse(const String.fromEnvironment('BIRDBOX_UI_BASE', defaultValue: 'http://127.0.0.1:8768')));
    final paired = await client.post('/api/v1/device/pair', data: {'pairing_code': '123456', 'client_name': 'Android page verification'}, idempotencyKey: 'android-ui-${DateTime.now().microsecondsSinceEpoch}');
    client.setSession(accessToken: paired['access_token'] as String);
    final api = SmartFollowApi(client);
    final sessions = await api.sessions();
    expect(sessions.items, isNotEmpty);
    final session = sessions.items.first;
    expect(session.copiedFileCount, 2);
    final repository = SmartFollowRepository(api);
    await tester.pumpWidget(MaterialApp(home: SmartFollowRunPage(repository: repository, sessionId: session.sessionId)));
    for (var i = 0; i < 50 && find.text('查看复制文件明细').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('持续复制进度'), findsOneWidget);
    await tester.ensureVisible(find.text('查看复制文件明细'));
    await tester.tap(find.text('查看复制文件明细'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    for (var i = 0; i < 50 && find.text('A001.jpg').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('复制文件明细'), findsOneWidget);
    expect(find.text('A001.jpg'), findsOneWidget);
    expect(find.text('A002.JPG'), findsOneWidget);
    expect(find.textContaining('已复制'), findsAtLeastNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 60)));
    // Leave a short observable final page, then release the real HTTP client.
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
    await client.dispose();
  });
}
