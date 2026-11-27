import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_copy_environment.dart';

void main() {
  test('job review counts and cancellation survive parsing and task mapping', () {
    final job = BirdJobStatus.fromJson(const {
      'job_id': 'analysis', 'job_type': 'analysis', 'job_state': 'running',
      'progress': 1, 'workflow_stage': 'finalizing', 'pending_review_count': 38,
      'pending_cancellation': true, 'total_count': 40, 'finished_count': 40,
      'failed_count': 0, 'skipped_count': 0, 'available_actions': <String>[],
    });
    final task = JobStatusViewAdapter.toTaskSummary(job)!;
    expect(task.pendingReviewCount, 38);
    expect(task.pendingCancellation, isTrue);
    expect(task.isFinishing, isTrue);
    expect(BirdJobStatus.fromJson(job.toJson()), job);
  });

  test('bounded preview retains review count and changed review state requires confirmation', () async {
    final repo = FakeCopyEnvironment()..pendingReviewCount = 0;
    final cubit = CopyConfigCubit(repo, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
    addTearDown(cubit.close);
    await cubit.initialize();
    cubit.selectTarget('target');
    cubit.setConflictStrategy(ConflictStrategy.skip);
    expect(await cubit.fetchPreview(), isTrue);
    expect(cubit.state.preview!.pendingReviewCount, 0);
    repo.pendingReviewCount = 1;
    expect(await cubit.submit(), isFalse);
    expect(repo.createCalls, 0);
    expect(cubit.state.preview!.pendingReviewCount, 1);
  });

  testWidgets('review first opens pending photos and never creates a copy automatically', (tester) async {
    final repo = FakeCopyEnvironment()..pendingReviewCount = 1;
    final cubit = CopyConfigCubit(repo, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
    addTearDown(cubit.close);
    await cubit.initialize();
    cubit.selectTarget('target');
    cubit.setConflictStrategy(ConflictStrategy.skip);
    await cubit.fetchPreview();
    GalleryArgs? args;
    await tester.pumpWidget(MaterialApp(
      onGenerateRoute: (settings) {
        args = settings.arguments as GalleryArgs;
        return MaterialPageRoute<void>(builder: (context) => Scaffold(body: TextButton(onPressed: () => Navigator.pop(context), child: const Text('返回复制'))));
      },
      home: BlocProvider.value(value: cubit, child: const CopyConfigFlow(batchId: 'batch')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copy-content-next')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始复制'));
    await tester.tap(find.text('开始复制'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('先去确认'));
    await tester.pumpAndSettle();
    expect(args?.batchId, 'batch');
    expect(args?.initialQuery.keepState, 'pending');
    expect(repo.createCalls, 0);
    await tester.tap(find.text('返回复制'));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 0);
    expect(cubit.state.preview, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final count in <int?>[1, null]) {
    testWidgets('copy requires explicit confirmation when count is $count', (tester) async {
      final repo = FakeCopyEnvironment()..pendingReviewCount = count;
      final cubit = CopyConfigCubit(repo, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
      addTearDown(cubit.close);
      await cubit.initialize();
      cubit.selectTarget('target');
      cubit.setConflictStrategy(ConflictStrategy.skip);
      await cubit.fetchPreview();
      await tester.pumpWidget(MaterialApp(home: BlocProvider.value(value: cubit, child: const CopyConfigFlow(batchId: 'batch'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('copy-content-next')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始复制'));
      await tester.tap(find.text('开始复制'));
      await tester.pumpAndSettle();
      expect(find.text(count == null ? '待确认数量暂不可用' : '其中 1 个文件还没确认'), findsOneWidget);
      expect(repo.createCalls, 0);
      await tester.tap(find.text('仍然复制当前范围'));
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1, reason: 'block=${cubit.state.submissionBlockReason}; notice=${cubit.state.planNotice}; active=${cubit.state.pageActive}; error=${cubit.state.error}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
