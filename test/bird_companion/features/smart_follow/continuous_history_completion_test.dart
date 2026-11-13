import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_gateway.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/continuous_queue_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/grouped_copy_history_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'continuous_summary_contract_test.dart' show envelope;
import 'finish/completion_fixtures.dart';

Map<String, dynamic> fullSummary() => {
  'execution_mode': 'continuous_queue', 'phase': 'completed',
  'recognition_total': 2, 'recognition_processed': 2, 'eligible_asset_count': 2,
  'planned_file_count': 2, 'copied_bytes': 61260,
  'file_counts': {for (final state in SmartFollowFileItem.stateLabels.keys) state: state == 'copied' ? 2 : 0},
};

class HistoryGateway extends FakeSmartFollowBackend implements SmartFollowHistoryGateway {
  final cursors = <String?>[];
  @override
  Future<GroupedCopyHistoryPage> groupedHistory({String? cursor}) async {
    cursors.add(cursor);
    return GroupedCopyHistoryPage.fromJson({
      'items': [
        {'kind': 'smart_follow', 'session_id': 'follow-example', 'data': envelope()},
        if (cursor != null) {'kind': 'copy', 'copy_job_id': 'ordinary', 'state': 'completed'},
      ],
      'has_more': cursor == null, 'next_cursor': cursor == null ? 'opaque-history==' : null,
    });
  }
}

class ParentChildRepository implements CopyJobRepository {
  @override
  Future<CopyJobDetail> getJob(String id) async => const CopyJobDetail(copyJobId: 'child', state: CopyJobState.paused, stateVersion: 1, eventSeq: 0, allowedActions: [], origin: 'smart_follow', parentSessionId: 'parent-original');
  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);
  @override
  Future<CopyJobItemPage> jobItems(String id, {String? cursor, String? state}) async => const CopyJobItemPage(items: [], hasMore: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('old child page opens only the explicit parent route', (tester) async {
    RouteSettings? opened;
    await tester.pumpWidget(MaterialApp(
      home: CopyJobDetailPage(copyJobId: 'child', repository: ParentChildRepository(), canRead: () => true),
      onGenerateRoute: (settings) {
        opened = settings;
        return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Parent task')));
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copy-open-parent-session')));
    await tester.pumpAndSettle();
    expect(opened!.name, BirdRoutes.smartFollowRun);
    expect(opened!.arguments, 'parent-original');
    expect(find.text('Parent task'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('legacy child retains explicit parent identity and never infers a missing association', () {
    final raw = {'copy_job_id': 'copy-child', 'state': 'completed', 'state_version': 2};
    expect(CopyJobDetail.fromJson(raw).parentSessionId, isNull);
    final detail = CopyJobDetail.fromJson({...raw, 'origin': 'smart_follow', 'parent_session_id': 'parent-original'});
    expect(detail.parentSessionId, 'parent-original');
    expect(detail.origin, 'smart_follow');
    expect(() => CopyJobDetail.fromJson({...raw, 'parent_session_id': 9}), throwsException);
  });
  testWidgets('grouped history deduplicates parents and routes real copy/session IDs', (tester) async {
    final backend = HistoryGateway();
    final repository = SmartFollowRepository(backend);
    addTearDown(repository.dispose);
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(home: GroupedCopyHistoryPageView(
      repository: repository, onOpenCopy: (id) => opened.add('copy:$id'), onOpenSession: (id) => opened.add('session:$id'),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多任务'));
    await tester.pumpAndSettle();
    expect(backend.cursors, [null, 'opaque-history==']);
    expect(find.byKey(const ValueKey('smart_follow:follow-example')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('smart_follow:follow-example')));
    await tester.tap(find.byKey(const ValueKey('copy:ordinary')));
    expect(opened, ['session:follow-example', 'copy:ordinary']);
  });
  test('grouped history rejects false parent association', () {
    expect(() => GroupedCopyHistoryItem.fromJson({'kind': 'smart_follow', 'session_id': 'wrong', 'data': envelope()}), throwsException);
  });
  testWidgets('v2 completion uses summary without reading legacy child reports', (tester) async {
    final env = CompletionEnvironment();
    addTearDown(env.dispose);
    env.backend.data = {
      'session_id': 'sf_fake', 'recognition_job_id': 'rec_fake', 'state': 'completed',
      'state_version': 3, 'execution_mode': 'continuous_queue', 'summary': fullSummary(),
    };
    await tester.pumpWidget(MaterialApp(home: SmartFollowCompletionPage(controller: env.controller, onOpenRun: () {}, onOpenChild: (_) {})));
    await tester.pumpAndSettle();
    final result = env.controller.result!;
    expect(result.summaryComplete, isTrue);
    expect(result.copiedFiles, 2);
    expect(result.copiedBytes, 61260);
    expect(env.backend.cursors, isEmpty);
    expect(env.childReads, isEmpty);
    expect(env.reportReads, isEmpty);
    expect(find.text('跟随复制已完成'), findsOneWidget);
    expect(find.byKey(const Key('sf-completion-history')), findsNothing);
  });
  test('v2 inconsistent file total cannot be a complete report', () async {
    final env = CompletionEnvironment();
    addTearDown(env.dispose);
    env.backend.data = {
      'session_id': 'sf_fake', 'recognition_job_id': 'rec_fake', 'state': 'completed',
      'state_version': 3, 'execution_mode': 'continuous_queue', 'summary': {...fullSummary(), 'planned_file_count': 99},
    };
    await env.controller.refresh();
    expect(env.controller.result!.summaryComplete, isFalse);
    expect(env.controller.result!.title, contains('报告待补齐'));
  });
}
