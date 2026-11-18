import 'dart:async';

import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/core/widgets/tab_back_dispatch.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'nov18_navigation_test_support.dart';

class _TabHost extends StatelessWidget {
  const _TabHost({required this.navigator, required this.root, required this.observer});
  final GlobalKey<NavigatorState> navigator;
  final Widget root;
  final NavigatorObserver observer;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) dispatchTabBack(navigator.currentState, result);
    },
    child: Navigator(
      key: navigator,
      observers: [observer],
      onGenerateRoute: (settings) => settings.name == Navigator.defaultRouteName ? MaterialPageRoute<void>(settings: settings, builder: (_) => root) : BirdAppRouter.onGenerateRoute(settings),
    ),
  );
}

Future<(B4Dependencies, CopyConfigCubit, GlobalKey<NavigatorState>, B4RouteObserver)> openCopy(WidgetTester tester, String entry) async {
  final deps = B4Dependencies();
  addTearDown(deps.close);
  final navigator = GlobalKey<NavigatorState>();
  final observer = B4RouteObserver();
  await pumpB4(
    tester,
    _TabHost(
      navigator: navigator,
      observer: observer,
      root: entry == '相册' ? const GalleryPage(batchId: 'project-1', totalCount: 14, rootMode: true) : TaskExperienceRoot(onOpenGallery: (_) {}),
    ),
    deps,
  );
  final control = find.byKey(Key(entry == '相册' ? 'album-copy-project-button' : 'task-action-copy'));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  if (entry == '相册') {
    final callback = tester.widget<IconButton>(control).onPressed!;
    callback();
    callback();
  } else {
    final callback = tester.widget<InkWell>(control).onTap;
    expect(callback, isNotNull, reason: '真实任务页权威读取完成后复制入口应可用');
    callback!();
    callback();
  }
  await tester.pumpAndSettle();
  expect(find.byType(CopyConfirmationPage), findsOneWidget);
  expect(observer.count(BirdRoutes.copyConfirmation), 1);
  final target = find.byKey(const Key('storage-device-target-目标设备'));
  await tester.scrollUntilVisible(target, 250, scrollable: find.byType(Scrollable).last);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  final conflict = find.text('两份都保留（文件名加 (1)(2)）');
  await tester.scrollUntilVisible(conflict, 250, scrollable: find.byType(Scrollable).last);
  await tester.ensureVisible(conflict);
  await tester.pumpAndSettle();
  await tester.tap(conflict);
  await tester.pumpAndSettle();
  final cubit = tester.element(find.byType(CopyContentStep)).read<CopyConfigCubit>();
  expect(cubit.state.targetMediaId, 'target');
  expect(cubit.state.conflictStrategy, ConflictStrategy.keepBoth);
  return (deps, cubit, navigator, observer);
}

void main() {
  for (final entry in ['相册', '任务']) {
    for (final back in ['顶部返回', '底部返回', '系统返回']) {
      testWidgets('$entry真实复制页：$back只回配置且保留选择，再返回退出', (tester) async {
        final (deps, cubit, navigator, _) = await openCopy(tester, entry);
        await tester.tap(find.byKey(const Key('copy-content-next')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('copy-final-confirmation-step')), findsOneWidget);
        expect(deps.copyRepository.createCalls, 0);
        if (back == '顶部返回') {
          await tester.tap(find.byKey(const Key('copy-flow-back')));
        } else if (back == '底部返回') {
          await tester.tap(find.byKey(const Key('copy-return-to-edit')));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('copy-content-step')), findsOneWidget);
        expect(navigator.currentState!.canPop(), true);
        expect(cubit.state.targetMediaId, 'target');
        expect(cubit.state.conflictStrategy, ConflictStrategy.keepBoth);
        expect(cubit.state.pairPolicy, PairPolicy.rawOnly);
        expect(deps.copyRepository.createCalls, 0);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(CopyConfirmationPage), findsNothing);
        expect(navigator.currentState!.canPop(), false);
        expect(deps.copyRepository.createCalls, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('$entry真实复制页：确认页重新预检时拦截返回，取消后保留配置', (tester) async {
      final (deps, cubit, _, _) = await openCopy(tester, entry);
      await tester.tap(find.byKey(const Key('copy-content-next')));
      await tester.pumpAndSettle();
      final read = Completer<CopyPreview>();
      deps.copyRepository.makePreview = (_) => read.future;
      final refresh = cubit.fetchPreview();
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.loadingPreview, true);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const Key('copy-final-confirmation-step')), findsOneWidget);
      expect(deps.copyRepository.createCalls, 0);
      await tester.tap(find.text('取消核对'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('copy-return-to-edit')));
      await tester.pump();
      read.complete(deps.copyRepository.previewFor(cubit.state.draft));
      expect(await refresh, false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('copy-content-step')), findsOneWidget);
      expect(cubit.state.targetMediaId, 'target');
      expect(cubit.state.conflictStrategy, ConflictStrategy.keepBoth);
      expect(deps.copyRepository.createCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$entry真实复制页：创建中禁止退出与重复提交，成功只记一项', (tester) async {
      final (deps, cubit, _, _) = await openCopy(tester, entry);
      await tester.tap(find.byKey(const Key('copy-content-next')));
      await tester.pumpAndSettle();
      deps.copyRepository.pendingCreate = Completer<CopyJobSummary>();
      final submit = tester.widget<FilledButton>(find.byKey(const Key('copy-final-submit'))).onPressed!;
      submit();
      submit();
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.submitting, true);
      expect(deps.copyRepository.createCalls, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(CopyConfirmationPage), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('copy-flow-back'))).onPressed, null);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('copy-return-to-edit'))).onPressed, null);
      deps.copyRepository.pendingCreate!.complete(const CopyJobSummary(copyJobId: 'created-job', state: 'queued', eventSeq: 0));
      await tester.pumpAndSettle();
      expect(deps.copyRepository.createCalls, 1);
      expect(find.byKey(const Key('copy-submit-result-close')), findsOneWidget);
      expect(deps.settingsStore.read().batchTargetPreferences['project-1'], 'target');
      await tester.tap(find.byKey(const Key('copy-submit-result-close')));
      await tester.pumpAndSettle();
      expect(find.byType(CopyConfirmationPage), findsNothing);
      expect(deps.activeCopyJobs.forDevice('box-a'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
