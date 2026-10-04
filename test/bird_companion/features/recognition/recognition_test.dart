import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/recognition/recognition_repository.dart';
import 'package:aves/bird_companion/features/recognition/recognition_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryCache implements LocalCache {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async => values[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> page({int after = 0, String job = 'job-1'}) => {
  'recognition_job_id': job,
  'items': after == 0
      ? [
          {'event_seq': 1, 'recognition_job_id': job, 'project_id': 'project-1', 'file_id': 'photo-1'},
        ]
      : [],
  'last_event_seq': 1,
  'has_more': false,
  'committed_count': 1,
  'failed_count': 0,
  'state': 'running',
  'smart_follow_session_id': 'follow-1',
};

Map<String, dynamic> follow() => {
  'session_id': 'follow-1',
  'state_version': 3,
  'state': 'following',
  'eligible_count': 1,
  'pending_count': 1,
  'child_job_count': 0,
  'copied_asset_count': 0,
  'allowed_actions': [],
};

class WidgetApi extends ApiClient {
  int followVersion = 3;
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    if (path.endsWith('recognition-capabilities')) {
      return {
        'incremental_recognition_results': {'available': true},
        'smart_follow_copy': {'available': true},
      };
    }
    if (path.endsWith('storage/devices')) {
      return {
        'devices': [
          {'can_be_target': true, 'media_id': 'usb-1', 'display_name': '测试目标盘'},
        ],
      };
    }
    if (path.contains('recognition-events')) return page(after: queryParameters?['after_event_seq'] as int? ?? 0);
    return {...follow(), 'state_version': followVersion};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real HTTP envelope, replay cursor, duplicate wakeup and state action', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    server.listen((request) async {
      requests.add({'path': request.uri.path, 'cursor': request.uri.queryParameters['after_event_seq'], 'key': request.headers.value('Idempotency-Key')});
      Map<String, dynamic> data;
      if (request.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['expected_state_version'], 3);
        data = follow();
      } else if (request.uri.path.endsWith('recognition-events')) {
        data = page(after: int.parse(request.uri.queryParameters['after_event_seq']!));
      } else {
        data = follow();
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': data}));
      await request.response.close();
    });
    final api = ApiClient()..configure(Uri.parse('http://127.0.0.1:${server.port}'));
    final cache = MemoryCache();
    final bus = AppDataChangeBus();
    final changes = <AppDataChange>[];
    final subscription = bus.changes.listen(changes.add);
    final repository = RecognitionRepository(api, cache, bus, () => 'box-1');
    await repository.sync('job-1');
    await repository.sync('job-1');
    await Future<void>.delayed(Duration.zero);
    expect(changes.whereType<RecognitionFactsChanged>().length, 1);
    expect(cache.read<int>('recognition-cursor:box-1:job-1'), 1);
    expect(repository.snapshot('job-1')?['smart_follow'], follow());
    await repository.action('job-1', 'resume_recognition');
    expect(requests.any((r) => r['key'] == 'follow-1-resume_recognition-3'), true);
    repository.dispose();
    await subscription.cancel();
    await bus.dispose();
    await api.dispose();
    await server.close(force: true);
  });

  testWidgets('default is recognition only; enabling returns target and policy', (tester) async {
    final api = WidgetApi();
    final bus = AppDataChangeBus();
    final repo = RecognitionRepository(api, MemoryCache(), bus, () => 'box-1');
    Map<String, dynamic>? config;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecognitionOptions(repository: repo, onChanged: (value) => config = value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(config, isNull);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('smart-follow-switch'))).value, false);
    await tester.tap(find.byKey(const Key('smart-follow-switch')));
    await tester.pumpAndSettle();
    expect(config, {'target_media_id': 'usb-1', 'pair_policy': 'raw_only', 'conflict_strategy': 'skip'});
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await bus.dispose();
    await api.dispose();
  });

  test('older session response cannot remove the newer follow snapshot', () async {
    final api = WidgetApi();
    final bus = AppDataChangeBus();
    final repo = RecognitionRepository(api, MemoryCache(), bus, () => 'box-1');
    await repo.sync('job-1');
    api.followVersion = 2;
    await repo.sync('job-1');
    expect((repo.snapshot('job-1')!['smart_follow'] as Map)['state_version'], 3);
    repo.dispose();
    await bus.dispose();
    await api.dispose();
  });

  testWidgets('recognition and copy counts are displayed separately', (tester) async {
    final api = WidgetApi();
    final bus = AppDataChangeBus();
    final repo = RecognitionRepository(api, MemoryCache(), bus, () => 'box-1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecognitionPanel(repository: repo, jobId: 'job-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('已产生结果 1 张 · 识别失败 0 张'), findsOneWidget);
    expect(find.text('合格 1 张 · 待复制 1 张'), findsOneWidget);
    expect(find.text('复制批次 0 个 · 已复制 0 组照片'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await bus.dispose();
    await api.dispose();
  });
}
