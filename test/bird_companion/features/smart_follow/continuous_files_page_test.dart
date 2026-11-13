import 'dart:async';

import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_gateway.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/continuous_queue_models.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_files_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'continuous_summary_contract_test.dart' show envelope;

class QueueGateway extends FakeSmartFollowBackend implements SmartFollowQueueGateway {
  final queries = <(String?, String?)>[];
  Completer<SmartFollowFilePage>? pending;
  @override
  Future<SmartFollowSession> session(String sessionId) async => SmartFollowSession.fromJson(envelope());
  @override
  Future<SmartFollowFilePage> fileItems(String sessionId, {String? cursor, String? state, int pageSize = 50}) async {
    queries.add((cursor, state));
    if (pending != null) return pending!.future;
    return SmartFollowFilePage.fromJson({
      'items': [
        {'item_id': cursor == null ? 'item-a' : 'item-b', 'file_id': 'file-a', 'name': cursor == null ? 'A.jpg' : 'B.jpg', 'state': state ?? 'copied', 'attempt_count': 1},
      ],
      'has_more': cursor == null && state == null,
      'next_cursor': cursor == null && state == null ? 'opaque-page-2==' : null,
    });
  }
}

void main() {
  late QueueGateway gateway;
  late SmartFollowRepository repository;
  setUp(() {
    gateway = QueueGateway();
    repository = SmartFollowRepository(gateway);
  });
  tearDown(() => repository.dispose());

  testWidgets('file details preserve opaque cursor and reset when filtering', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SmartFollowFilesPage(repository: repository, sessionId: 'follow-example')));
    await tester.pumpAndSettle();
    expect(find.text('A.jpg'), findsOneWidget);
    await tester.tap(find.text('加载更多文件'));
    await tester.pumpAndSettle();
    expect(find.text('B.jpg'), findsOneWidget);
    expect(gateway.queries.last, ('opaque-page-2==', null));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('受阻待处理').last);
    await tester.pumpAndSettle();
    expect(gateway.queries.last, (null, 'blocked'));
    expect(find.text('B.jpg'), findsNothing);
  });
  testWidgets('device change hides old files and rejects a delayed page', (tester) async {
    await repository.refresh('follow-example');
    gateway.pending = Completer<SmartFollowFilePage>();
    await tester.pumpWidget(MaterialApp(home: SmartFollowFilesPage(repository: repository, sessionId: 'follow-example')));
    await tester.pump();
    repository.resetForDeviceChange();
    gateway.pending!.complete(SmartFollowFilePage.fromJson({
      'items': [{'item_id': 'old', 'file_id': 'old', 'name': 'OLD.jpg', 'state': 'copied'}], 'has_more': false,
    }));
    await tester.pumpAndSettle();
    expect(find.text('OLD.jpg'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('continuous run uses summary not zero legacy counters or child batches', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SmartFollowRunPage(repository: repository, sessionId: 'follow-example')));
    await tester.pumpAndSettle();
    expect(find.text('识别 2 / 2'), findsOneWidget);
    expect(find.text('当前计划 2 个文件'), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-files')), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-child-jobs')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
