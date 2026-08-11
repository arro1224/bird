import 'dart:io';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R3 production copy flow', () {
    testWidgets(
      'step 2 and step 3 preserve one cubit state and submit a fresh version',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(430, 980);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final repository = _CopyRepository();
        final cubit = CopyConfirmationCubit(
          repository,
          'project-1',
          null,
          'keep',
          'target-1',
          true,
          true,
        );
        addTearDown(cubit.close);
        await cubit.load();
        cubit.selectTarget('target-2');
        await cubit.load('all');
        String? submittedJobId;

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(
              value: cubit,
              child: CopyConfirmationFlow(
                batchId: 'project-1',
                lowBatteryPercent: 12,
                onSubmitted: (jobId) => submittedJobId = jobId,
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('copy-content-step')), findsOneWidget);
        expect(find.text('步骤 2 / 3 · 选择复制内容'), findsOneWidget);
        expect(find.text('预计使用：238.7 GB'), findsNWidgets(2));

        await tester.tap(find.byKey(const Key('copy-xmp-toggle')));
        await tester.pump();
        expect(cubit.state.xmpEnabled, isFalse);

        await tester.tap(find.byKey(const Key('copy-content-next')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('copy-final-confirmation-step')),
          findsOneWidget,
        );
        expect(find.text('步骤 3 / 3 · 最后确认'), findsOneWidget);
        expect(find.text('2,012 张'), findsOneWidget);
        expect(find.text('238.7 GB'), findsOneWidget);
        expect(find.text('未开启'), findsOneWidget);
        expect(find.text('任务开始后由盒子计算'), findsOneWidget);
        expect(find.text('开启'), findsOneWidget);
        expect(find.byKey(const Key('copy-low-battery-warning')), findsOneWidget);

        await tester.tap(find.byKey(const Key('copy-return-to-edit')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('copy-content-step')), findsOneWidget);
        expect(cubit.state.mode, 'all');
        expect(cubit.state.targetId, 'target-2');
        expect(cubit.state.xmpEnabled, isFalse);

        await tester.tap(find.byKey(const Key('copy-content-next')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('copy-final-submit')));
        await tester.pumpAndSettle();

        expect(repository.estimateCalls, 3);
        expect(repository.createdMode, 'all');
        expect(repository.createdTargetId, 'target-2');
        expect(repository.createdXmpEnabled, isFalse);
        expect(repository.createdVerifyAfterCopy, isTrue);
        expect(repository.createdVersion, 7);
        expect(submittedJobId, 'job-copy-r3');
      },
    );

    testWidgets('system back from final confirmation returns to editing', (
      tester,
    ) async {
      final repository = _CopyRepository();
      final cubit = CopyConfirmationCubit(repository, 'project-1');
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: const CopyConfirmationFlow(
              batchId: 'project-1',
              onSubmitted: _ignoreSubmitted,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('copy-content-next')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('copy-final-confirmation-step')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('copy-content-step')), findsOneWidget);
    });

    testWidgets('an unavailable target keeps final submission disabled', (
      tester,
    ) async {
      const unavailable = CopyConfirmationState(
        mode: 'all',
        targetId: 'offline',
        estimate: CopyEstimate(
          mode: 'all',
          fileCount: 100,
          requiredBytes: 10 * 1024 * 1024,
          pendingCount: 0,
          version: 3,
          targets: [
            StorageTarget(
              id: 'offline',
              name: 'USB',
              freeBytes: 100 * 1024 * 1024,
              totalBytes: 200 * 1024 * 1024,
              online: false,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CopyFinalConfirmationStep(
            state: unavailable,
            onBack: () {},
            onSubmit: () {},
          ),
        ),
      );

      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('copy-final-submit')),
      );
      expect(submit.onPressed, isNull);
      expect(find.textContaining('空间不足或已断开'), findsOneWidget);
    });

    testWidgets('both production steps fit a 360 by 800 viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = _CopyRepository();
      final cubit = CopyConfirmationCubit(repository, 'project-1');
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: const CopyConfirmationFlow(
              batchId: 'project-1',
              onSubmitted: _ignoreSubmitted,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('copy-content-next')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('copy-final-confirmation-step')),
        findsOneWidget,
      );
    });

    test('production page uses two steps and replacement navigation', () {
      final source = File(
        'lib/bird_companion/features/copy/presentation/'
        'copy_confirmation_page.dart',
      ).readAsStringSync();

      expect(source, contains('CopyContentStep('));
      expect(source, contains('CopyFinalConfirmationStep('));
      expect(source, contains('pushReplacementNamed('));
      expect(source, contains('context.read<CopyConfirmationCubit>().submit'));
      expect(source, isNot(contains('CopyConfirmDialog(')));
      expect(source, contains('任务开始后由盒子计算'));
    });
  });
}

void _ignoreSubmitted(String _) {}

class _CopyRepository implements CopyRepository {
  int estimateCalls = 0;
  String? createdMode;
  String? createdTargetId;
  bool? createdXmpEnabled;
  bool? createdVerifyAfterCopy;
  int? createdVersion;

  @override
  Future<CopyEstimate> estimate(String batchId, String mode) async {
    estimateCalls += 1;
    return CopyEstimate(
      mode: mode,
      fileCount: 2012,
      requiredBytes: (238.7 * 1024 * 1024 * 1024).round(),
      pendingCount: 12,
      version: 7,
      targets: const [
        StorageTarget(
          id: 'target-1',
          name: 'Samsung T7 Shield',
          freeBytes: 1200 * 1024 * 1024 * 1024,
          totalBytes: 2000 * 1024 * 1024 * 1024,
          online: true,
        ),
        StorageTarget(
          id: 'target-2',
          name: 'Backup SSD',
          freeBytes: 900 * 1024 * 1024 * 1024,
          totalBytes: 1000 * 1024 * 1024 * 1024,
          online: true,
        ),
      ],
    );
  }

  @override
  Future<BirdJobStatus> create(
    String batchId,
    String mode,
    String targetId, {
    required bool xmpEnabled,
    required bool verifyAfterCopy,
    required int version,
  }) async {
    createdMode = mode;
    createdTargetId = targetId;
    createdXmpEnabled = xmpEnabled;
    createdVerifyAfterCopy = verifyAfterCopy;
    createdVersion = version;
    return const BirdJobStatus(
      id: 'job-copy-r3',
      type: BirdJobType.copy,
      state: BirdJobState.queued,
    );
  }
}
