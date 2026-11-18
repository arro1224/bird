import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/features/device/domain/device_repository.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_sheet.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_page.dart';
import 'package:aves/bird_companion/features/gallery/presentation/selection_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart';
import 'package:aves/bird_companion/features/review/data/review_checkpoint_store.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('分类快捷入口清除互斥条件，统计更新保留滚动和选中集合', (tester) async {
    final dependencies = _Dependencies(49, connected: true);
    addTearDown(dependencies.deviceSessionCubit.close);
    addTearDown(dependencies.refreshCoordinator.dispose);
    addTearDown(dependencies.dataChangeBus.dispose);
    addTearDown(dependencies.pendingOperationStore.dispose);
    await _pumpAlbum(
      tester,
      dependencies,
      initialQuery: const PhotoQuery(recognitionState: 'recognized', analysisState: 'completed', minConfidence: .99, search: 'old search', keepState: 'keep'),
    );
    final gallery = tester.element(find.byKey(const ValueKey('album-filter-button'))).read<GalleryCubit>();
    final reviewChip = find.byKey(const ValueKey('gallery-category-needs_review'));
    await tester.ensureVisible(reviewChip);
    await tester.tap(reviewChip);
    await tester.pumpAndSettle();
    expect(gallery.state.query.recognitionState, 'needs_review');
    expect(gallery.state.query.analysisState, null);
    expect(gallery.state.query.keepState, null);
    expect(gallery.state.query.search, null);
    expect(gallery.state.query.minConfidence, null);
    final photo = find.byKey(const ValueKey('photo-0'));
    await tester.longPress(photo);
    await tester.pumpAndSettle();
    final selected = tester.element(photo).read<SelectionCubit>();
    expect(selected.state.ids, {'photo-0'});
    final photoScroll = find.byKey(const PageStorageKey<String>('photo-gallery-scroll-project-1'));
    await tester.drag(photoScroll, const Offset(0, -350));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(find.descendant(of: photoScroll, matching: find.byType(Scrollable)).first).position;
    final offset = position.pixels;
    gallery.applyBatchSummary(
      BatchSummary(
        id: 'project-1',
        name: 'test',
        createdAt: DateTime.utc(2026, 11, 18),
        totalFiles: 49,
        analyzedCount: 14,
        reviewCount: 6,
        recognizedCount: 5,
        filteredCount: 3,
        keepCount: 1,
        discardCount: 0,
        pendingCopyCount: 0,
        copyState: 'idle',
        countsUpdatedAt: DateTime.now(),
        countsDeviceId: 'box-a',
      ),
      deviceId: 'box-a',
    );
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(offset, 1));
    expect(selected.state.ids, {'photo-0'});
    expect(gallery.state.pendingCount, 6);
    expect(gallery.state.query.recognitionState, 'needs_review');
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('设备弹层、断线缓存、冲突与重连入口在相册首页协同工作', (tester) async {
    final dependencies = _Dependencies(4, connected: true);
    final reading = Completer<void>();
    dependencies.deviceRepository
      ..beforeFetch = reading.future
      ..failStatus = true;
    await _pumpAlbum(tester, dependencies, initialQuery: const PhotoQuery(keepState: 'pending'));
    expect(find.byTooltip('盒子已连接，正在读取状态'), findsOneWidget);
    reading.complete();
    await tester.pumpAndSettle();

    final status = find.byKey(const ValueKey('album-device-status'));
    expect(find.byTooltip('盒子已连接，电量未知'), findsOneWidget);
    expect(find.text('78%'), findsNothing);
    dependencies.deviceRepository
      ..beforeFetch = null
      ..failStatus = false;
    await tester.tap(status);
    await tester.pumpAndSettle();
    final toolbar = find.byType(AppBar);
    final photo = find.byKey(const ValueKey('photo-0'));
    final notice = find.byKey(const Key('gallery-candidate-notice'));
    final noticeText = find.byKey(const Key('gallery-candidate-notice-text'));
    final reconnect = find.byKey(const Key('gallery-candidate-notice-action'));
    const conflict = Key('gallery-conflict-open-button');
    expect(find.descendant(of: toolbar, matching: status), findsOneWidget);
    expect(tester.getSize(status).height, 48);
    expect(find.byTooltip('盒子已连接，电量 78%'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(dependencies.deviceRepository.fetches, 2);
    expect(notice, findsNothing);

    await tester.tap(status);
    await tester.pumpAndSettle();
    final sheet = find.byType(DeviceStatusSheet);
    final details = find.text('查看设备详情');
    await tester.scrollUntilVisible(
      details,
      180,
      scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('设备详情路由'), findsOneWidget);
    expect(sheet, findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(status);
    await tester.pumpAndSettle();

    final gallery = tester.element(photo).read<GalleryCubit>();
    dependencies.deviceSessionCubit.setPhase(DeviceSessionPhase.disconnected);
    dependencies.photoRepository.pageOverride = (_) async => PhotoPage(
      items: dependencies.photoRepository.photos.take(2).toList(),
      hasMore: false,
      fromCache: true,
      resultComplete: false,
      cacheScope: PhotoCacheScope.partial,
    );
    unawaited(gallery.refresh());
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(find.byTooltip('盒子未连接'), findsOneWidget);
    expect(find.text('78%'), findsNothing);
    expect(notice, findsOneWidget);
    expect(tester.widget<Text>(noticeText).data, contains('2 张照片'));
    expect(photo, findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('album-copy-project-button'))).onPressed, isNull);

    await dependencies.pendingOperationStore.save(
      PendingOperation(
        id: 'conflict',
        type: PendingOperationType.updateReview,
        deviceId: _Dependencies._box.id,
        projectId: 'project-1',
        fileId: 'photo-0',
        payload: const {},
        createdAt: DateTime(2026, 11, 17),
        status: PendingOperationStatus.conflict,
      ),
    );
    unawaited(gallery.refresh());
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    await tester.tap(find.byKey(conflict));
    await tester.pumpAndSettle();
    expect(find.text('冲突照片 photo-0'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(reconnect);
    await tester.pumpAndSettle();
    expect(find.text('重连路由'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(status);
    await tester.pumpAndSettle();
    expect(find.text('重连路由'), findsOneWidget);
    expect(dependencies.deviceSessionCubit.reconnectRequests, 2);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    dependencies.deviceSessionCubit.setPhase(DeviceSessionPhase.reconnecting);
    await tester.pumpAndSettle();
    expect(find.byTooltip('盒子重连中'), findsOneWidget);
    expect(tester.widget<Text>(noticeText).data, contains('正在恢复盒子连接'));
    expect(reconnect, findsNothing);
    expect(find.byKey(conflict), findsOneWidget);

    dependencies.photoRepository.pageOverride = null;
    dependencies.deviceSessionCubit.setPhase(DeviceSessionPhase.connected);
    dependencies.refreshCoordinator.requestRefresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(find.byKey(conflict), findsOneWidget);
    expect(gallery.state.query.keepState, 'pending');
    expect(find.byTooltip('盒子已连接，电量 78%'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首次筛选只显示一处进度，取消后可重试，断线无缓存可重连', (tester) async {
    final dependencies = _Dependencies(2, connected: true);
    final pendingPage = Completer<PhotoPage>();
    dependencies.photoRepository.pageOverride = (_) => pendingPage.future;
    await _pumpAlbum(tester, dependencies, initialQuery: const PhotoQuery(recognitionState: 'recognized'));
    await tester.pump();
    expect(find.text('正在读取照片列表…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('正在读取照片列表…'), findsNothing);
    expect(find.text('筛选未完成'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '重新筛选'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('album-copy-project-button'))).onPressed, isNull);
    pendingPage.complete(const PhotoPage(items: [], hasMore: false));
    await tester.pumpAndSettle();
    expect(find.text('筛选未完成'), findsOneWidget);

    dependencies.deviceSessionCubit.setPhase(DeviceSessionPhase.disconnected);
    await tester.pumpAndSettle();
    expect(find.text('离线时没有符合当前条件的照片'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '重新连接'), findsOneWidget);
    expect(find.byKey(const Key('gallery-candidate-notice')), findsNothing);

    final gallery = tester.element(find.byKey(const ValueKey('album-filter-button'))).read<GalleryCubit>();
    dependencies.deviceSessionCubit.setPhase(DeviceSessionPhase.connected);
    dependencies.photoRepository.pageOverride = null;
    await gallery.refresh(query: const PhotoQuery());
    await tester.pumpAndSettle();
    final photo = find.byKey(const ValueKey('photo-0'));
    expect(photo, findsOneWidget);

    final delayedFilter = Completer<PhotoPage>();
    dependencies.photoRepository.pageOverride = (_) => delayedFilter.future;
    unawaited(gallery.refresh(query: const PhotoQuery(recognitionState: 'recognized')));
    expect(gallery.state.filtering, isTrue);
    await tester.pump();
    await tester.pump();
    expect(photo, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(photo, findsOneWidget);
    expect(find.text('照片结果不完整'), findsOneWidget);
    delayedFilter.complete(const PhotoPage(items: [], hasMore: false));
    await tester.pumpAndSettle();
    expect(photo, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏相册的筛选入口固定，两处拍摄记录可达且保留滚动位置', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 680);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final dependencies = _Dependencies(49, connected: true);
    addTearDown(dependencies.deviceSessionCubit.close);
    addTearDown(dependencies.refreshCoordinator.dispose);
    addTearDown(dependencies.dataChangeBus.dispose);
    addTearDown(dependencies.pendingOperationStore.dispose);
    const batchName = '2026.07.16 崇明东滩潮间带水鸟观测长批次名称';
    const historyRoute = ValueKey('history-route');

    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: dependencies,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          routes: {BirdRoutes.batches: (_) => const Scaffold(key: historyRoute)},
          home: const GalleryPage(
            batchId: 'project-1',
            batchName: batchName,
            totalCount: 49,
            rootMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.text(batchName);
    final history = find.byKey(const Key('album-history-secondary-button'));
    expect(tester.getCenter(title).dy, closeTo(tester.getCenter(history).dy, 1));
    expect(tester.getBottomRight(title).dx, lessThan(tester.getTopLeft(history).dx));
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.byKey(historyRoute), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    final quickFilters = find.byKey(const ValueKey('album-quick-filters'));
    final filter = find.byKey(const ValueKey('album-filter-button'));
    final filterBefore = tester.getRect(filter);
    expect(filterBefore.size, const Size(48, 48));
    final chipScroll = find.descendant(of: quickFilters, matching: find.byType(Scrollable));
    final chipPosition = tester.state<ScrollableState>(chipScroll).position;
    expect(chipPosition.maxScrollExtent, greaterThan(0));
    await tester.dragFrom(tester.getCenter(quickFilters), const Offset(-170, 0));
    await tester.pumpAndSettle();
    expect(chipPosition.pixels, greaterThan(0));
    final featured = find.widgetWithText(ChoiceChip, '精选');
    chipPosition.jumpTo(chipPosition.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopRight(featured).dx, lessThanOrEqualTo(tester.getTopRight(quickFilters).dx + 1));
    expect(tester.getRect(filter), filterBefore);

    final gallery = tester.element(filter).read<GalleryCubit>();
    await tester.tap(filter);
    await tester.pumpAndSettle();
    final sheet = find.byType(FilterSheet);
    final options = find.descendant(of: sheet, matching: find.byType(Scrollable));
    final recognized = find.descendant(of: sheet, matching: find.text('识别度高'));
    await tester.scrollUntilVisible(recognized, 150, scrollable: options);
    await tester.pumpAndSettle();
    await tester.tap(recognized);
    await tester.pump();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(find.text('识别结果：识别度高'), findsOneWidget);
    expect(gallery.state.query.toCopyFilterV1()?['recognition_state'], 'recognized');
    final clear = find.byKey(const ValueKey('active-filter-clear'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('active-filter-summary')), findsNothing);
    expect(gallery.state.query.toCopyFilterV1(), isNull);

    final photoScroll = find.byKey(const PageStorageKey<String>('photo-gallery-scroll-project-1'));
    await tester.drag(photoScroll, const Offset(0, -430));
    await tester.pumpAndSettle();
    final scrollPosition = tester.state<ScrollableState>(find.descendant(of: photoScroll, matching: find.byType(Scrollable)).first).position;
    final savedOffset = scrollPosition.pixels;
    expect(savedOffset, greaterThan(100));
    await tester.tap(find.byKey(const Key('album-history-appbar-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(historyRoute), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(scrollPosition.pixels, closeTo(savedOffset, 1));
    tester.view.physicalSize = const Size(300, 680);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-device-status')).hitTestable(), findsOneWidget);
    expect(find.byTooltip('拍摄记录').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('复制当前拍摄'), findsOneWidget);
    expect(find.text('新增或切换设备'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('批量添加按每张照片补齐标签，撤销保留原有标签', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final dependencies = _Dependencies(3);
    addTearDown(dependencies.deviceSessionCubit.close);
    addTearDown(dependencies.refreshCoordinator.dispose);
    addTearDown(dependencies.dataChangeBus.dispose);
    addTearDown(dependencies.pendingOperationStore.dispose);
    final photos = dependencies.photoRepository;
    photos.tagsById['photo-2'] = ['湿地', '水鸟', '晨拍'];
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: dependencies,
        child: const MaterialApp(
          home: GalleryPage(batchId: 'project-1', batchName: '测试拍摄', totalCount: 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('photo-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-1')));
    await tester.tap(find.byKey(const ValueKey('photo-2')));
    await tester.pump();
    expect(tester.widget<SelectionActionBar>(find.byType(SelectionActionBar)).count, 3);
    await tester.tap(find.text('添加标签'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    final apply = find.widgetWithText(FilledButton, '应用');
    expect(find.text('所选照片已有标签'), findsOneWidget);
    expect(find.widgetWithText(Chip, '湿地'), findsOneWidget);
    expect(find.widgetWithText(Chip, '水鸟'), findsOneWidget);
    expect(find.widgetWithText(Chip, '晨拍'), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
    await tester.enterText(field, '湿地');
    await tester.pump();
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(photos.operations, isEmpty);

    await tester.enterText(field, '湿地，水鸟, 晨拍，水鸟');
    await tester.pump();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('已添加 2 张照片的标签'), findsOneWidget);
    expect(photos.operations, [
      {
        'operation': 'add_tags',
        'ids': ['photo-0'],
        'tags': ['晨拍'],
        'version': 3,
      },
      {
        'operation': 'add_tags',
        'ids': ['photo-1'],
        'tags': ['水鸟', '晨拍'],
        'version': 3,
      },
    ]);
    expect(photos.tagsFor('photo-1'), ['湿地', '水鸟', '晨拍']);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(photos.operations.skip(2), [
      {
        'operation': 'remove_tags',
        'ids': ['photo-0'],
        'tags': ['晨拍'],
        'version': 4,
      },
      {
        'operation': 'remove_tags',
        'ids': ['photo-1'],
        'tags': ['水鸟', '晨拍'],
        'version': 4,
      },
    ]);
    expect(photos.tagsFor('photo-0'), ['湿地', '水鸟']);
    expect(photos.tagsFor('photo-1'), ['湿地']);
    expect(photos.tagsFor('photo-2'), ['湿地', '水鸟', '晨拍']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('批量删除从详情列出标签，仅处理含该标签的照片并精确撤销', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final dependencies = _Dependencies(2);
    addTearDown(dependencies.deviceSessionCubit.close);
    addTearDown(dependencies.refreshCoordinator.dispose);
    addTearDown(dependencies.dataChangeBus.dispose);
    addTearDown(dependencies.pendingOperationStore.dispose);
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: dependencies,
        child: const MaterialApp(
          home: GalleryPage(batchId: 'project-1', batchName: '测试拍摄', totalCount: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('photo-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-1')));
    await tester.pump();
    expect(tester.widget<SelectionActionBar>(find.byType(SelectionActionBar)).count, 2);
    tester.widget<SelectionActionBar>(find.byType(SelectionActionBar)).onRemoveTags();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '水鸟'), findsOneWidget);
    expect(find.widgetWithText(InputChip, '湿地'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('删除标签：水鸟'));
    await tester.pump();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    final photos = dependencies.photoRepository;
    expect(photos.operations, [
      {
        'operation': 'remove_tags',
        'ids': ['photo-0'],
        'tags': ['水鸟'],
        'version': 3,
      },
    ]);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(photos.operations.last['operation'], 'add_tags');
    expect(photos.operations.last['ids'], ['photo-0']);
    expect(photos.operations.last['tags'], ['水鸟']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('批量添加部分失败后保留失败选择，详情只显示已成功添加的标签', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final dependencies = _Dependencies(2);
    addTearDown(dependencies.deviceSessionCubit.close);
    addTearDown(dependencies.refreshCoordinator.dispose);
    addTearDown(dependencies.dataChangeBus.dispose);
    addTearDown(dependencies.pendingOperationStore.dispose);
    final photos = dependencies.photoRepository..rejectIds.add('photo-1');
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: dependencies,
        child: const MaterialApp(
          onGenerateRoute: BirdAppRouter.onGenerateRoute,
          home: GalleryPage(batchId: 'project-1', batchName: '测试拍摄', totalCount: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('photo-0'));
    final second = find.byKey(const ValueKey('photo-1'));
    await tester.longPress(first);
    await tester.pumpAndSettle();
    await tester.tap(second);
    await tester.pump();
    await tester.tap(find.text('添加标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '晨拍');
    await tester.pump();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(find.text('已添加 1 张的标签，1 张失败'), findsOneWidget);
    expect(tester.widget<PhotoTile>(first).selected, isFalse);
    expect(tester.widget<PhotoTile>(second).selected, isTrue);
    expect(photos.tagsFor('photo-1'), ['湿地']);
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    await tester.tap(first);
    await tester.pumpAndSettle();
    final addTag = find.widgetWithText(OutlinedButton, '添加标签');
    await tester.scrollUntilVisible(addTag, 250);
    await tester.tap(addTag);
    await tester.pumpAndSettle();
    expect(find.text('已有标签'), findsOneWidget);
    expect(find.widgetWithText(Chip, '晨拍'), findsOneWidget);
    expect(find.widgetWithText(Chip, '水鸟'), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final rootMode in [true, false]) {
    for (final count in [5, 49]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          '${rootMode ? '相册首页' : '拍摄记录相册'} $count 张照片 / $scale 倍字体：多选时最后一张可见且可勾选',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(360, 720);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final dependencies = _Dependencies(count);
            addTearDown(dependencies.deviceSessionCubit.close);
            addTearDown(dependencies.refreshCoordinator.dispose);
            addTearDown(dependencies.dataChangeBus.dispose);
            addTearDown(dependencies.pendingOperationStore.dispose);

            await tester.pumpWidget(
              BirdCompanionScope(
                dependencies: dependencies,
                child: MaterialApp(
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      padding: const EdgeInsets.only(bottom: 24),
                    ),
                    child: child!,
                  ),
                  home: GalleryPage(
                    batchId: 'project-1',
                    batchName: '测试拍摄',
                    totalCount: count,
                    rootMode: rootMode,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final scrollable = find
                .descendant(
                  of: find.byKey(const PageStorageKey<String>('photo-gallery-scroll-project-1')),
                  matching: find.byType(Scrollable),
                )
                .first;
            final first = find.byKey(const ValueKey('photo-0'));
            await tester.scrollUntilVisible(first, 150, scrollable: scrollable);
            await tester.longPress(first);
            await tester.pumpAndSettle();
            expect(find.byType(SelectionActionBar), findsOneWidget);

            final last = find.byKey(ValueKey('photo-${count - 1}'));
            await tester.scrollUntilVisible(last, 200, scrollable: scrollable);
            final position = tester.state<ScrollableState>(scrollable).position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();

            final panelTop = tester.getTopLeft(find.byType(SelectionActionBar)).dy;
            expect(
              tester.getBottomLeft(last).dy,
              lessThanOrEqualTo(panelTop),
              reason: '滚动到底后，最后一张照片应完整位于批量操作面板上方',
            );
            await tester.tap(last);
            await tester.pump();
            expect(tester.widget<PhotoTile>(last).selected, isTrue);
            await tester.longPress(last);
            await tester.pump();
            expect(tester.widget<PhotoTile>(last).selected, isFalse);

            // Leaving selection restores the full photo viewport.
            await tester.tap(find.byTooltip('退出多选'));
            await tester.pumpAndSettle();
            expect(find.byType(SelectionActionBar), findsNothing);
            final selection = tester.element(last).read<SelectionCubit>();
            expect(selection.state.ids, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}

Future<void> _pumpAlbum(WidgetTester tester, _Dependencies dependencies, {PhotoQuery initialQuery = const PhotoQuery()}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 914);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(dependencies.deviceSessionCubit.close);
  addTearDown(dependencies.refreshCoordinator.dispose);
  addTearDown(dependencies.dataChangeBus.dispose);
  addTearDown(dependencies.pendingOperationStore.dispose);
  await tester.pumpWidget(
    BirdCompanionScope(
      dependencies: dependencies,
      child: MaterialApp(
        routes: {
          BirdRoutes.settingsDeviceDetails: (_) => const Scaffold(body: Text('设备详情路由')),
          BirdRoutes.connection: (_) => const Scaffold(body: Text('重连路由')),
          BirdRoutes.photoDetail: (context) {
            final args = ModalRoute.of(context)!.settings.arguments as PhotoDetailArgs;
            return Scaffold(body: Text('冲突照片 ${args.fileId}'));
          },
        },
        home: GalleryPage(
          batchId: 'project-1',
          batchName: '测试拍摄',
          totalCount: dependencies.photoRepository.photos.length,
          initialQuery: initialQuery,
          rootMode: true,
        ),
      ),
    ),
  );
}

class _Dependencies implements BirdCompanionDependencies {
  _Dependencies(int count, {bool connected = false}) : photoRepository = _Photos(count), deviceSessionCubit = _Session(connected ? _box : null), deviceRepository = _Device(connected ? _box : null);

  static final _box = DeviceConnection(
    id: 'box-a',
    name: 'K7',
    baseUri: Uri.parse('http://127.0.0.1'),
    networkMode: NetworkMode.manual,
  );

  @override
  final _Photos photoRepository;
  @override
  final BatchRepository batchRepository = _UnusedBatches();
  @override
  late final ReviewRepository reviewRepository = _TagReviews(photoRepository);
  @override
  final LocalCache cache = _MemoryCache();
  @override
  late final SettingsStore settingsStore = BirdSettingsStore(cache);
  @override
  final PendingOperationStore pendingOperationStore = PendingOperationStore.memory();
  @override
  final ReviewCheckpointStore reviewCheckpointStore = ReviewCheckpointStore.memory();
  @override
  final _Session deviceSessionCubit;
  @override
  final SessionRefreshCoordinator refreshCoordinator = SessionRefreshCoordinator();
  @override
  final AppDataChangeBus dataChangeBus = AppDataChangeBus();
  @override
  final _Device deviceRepository;
  @override
  final MediaAssetService mediaAssetService = _UnusedMediaService();
  @override
  final MediaAssetCoordinator mediaAssetCoordinator = _UnusedMediaCoordinator();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedBatches extends Fake implements BatchRepository {}

class _Session extends Cubit<DeviceSessionState> implements DeviceSessionCubit {
  _Session(DeviceConnection? connection)
    : super(
        DeviceSessionState(
          phase: connection == null ? DeviceSessionPhase.disconnected : DeviceSessionPhase.connected,
          device: connection,
        ),
      );

  int reconnectRequests = 0;

  void setPhase(DeviceSessionPhase phase) => emit(state.copyWith(phase: phase));

  @override
  String? get activeAttemptId => null;

  @override
  bool get provisioningHandoffActive => false;

  @override
  Future<bool> verifySavedSession({
    Duration timeout = const Duration(seconds: 20),
    String? expectedDeviceId,
    String intent = 'explicit_reconnect',
    bool restart = false,
  }) async {
    reconnectRequests++;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Device implements DeviceRepository {
  _Device(this.connection);

  final DeviceConnection? connection;
  int fetches = 0;
  Future<void>? beforeFetch;
  bool failStatus = false;

  @override
  Future<DeviceStatus> fetchStatus() async {
    fetches++;
    await beforeFetch;
    final device = connection;
    if (device == null || failStatus) throw StateError('状态暂不可用');
    return DeviceStatus(
      connection: device,
      card: const CardStatus(inserted: true, readable: true),
      batteryPercent: 78,
      storageFreeBytes: 338 * 1024 * 1024 * 1024,
    );
  }

  @override
  Stream<DeviceStatus> watchStatus() => StreamController<DeviceStatus>.broadcast(sync: true).stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedMediaService implements MediaAssetService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedMediaCoordinator implements MediaAssetCoordinator {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryCache implements LocalCache {
  final _values = <String, Object?>{};

  @override
  T? read<T>(String key) => _values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async => _values[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Photos implements PhotoRepository {
  _Photos(int count)
    : photos = List.generate(
        count,
        (index) => PhotoSummary(
          id: 'photo-$index',
          filename: 'photo-$index.jpg',
          format: 'JPEG',
          preview: const PreviewRef(),
          analysisState: AnalysisState.completed,
          keepState: 'pending',
          version: 1,
        ),
      );

  final List<PhotoSummary> photos;
  final operations = <Map<String, Object?>>[];
  final tagsById = <String, List<String>>{};
  final versionsById = <String, int>{};
  final rejectIds = <String>{};
  Future<PhotoPage> Function(PhotoQuery query)? pageOverride;

  List<String> tagsFor(String id) => tagsById[id] ?? ['湿地', if (id == 'photo-0') '水鸟'];

  @override
  Future<BatchOperationOutcome> batchOperation(String batchId, List<String> ids, String operation, {required int version, Object? value}) async {
    operations.add({'operation': operation, 'ids': ids, 'tags': value, 'version': version});
    final succeeded = ids.where((id) => !rejectIds.contains(id)).toList();
    for (final id in succeeded) {
      final tags = tagsFor(id).toSet();
      final changed = value as List<String>;
      if (operation == 'add_tags') {
        tags.addAll(changed);
      } else if (operation == 'remove_tags') {
        tags.removeAll(changed);
      }
      tagsById[id] = tags.toList();
      versionsById[id] = version + 1;
      final index = photos.indexWhere((photo) => photo.id == id);
      photos[index] = PhotoSummary.fromJson({...photos[index].toJson(), 'version': versionsById[id]});
    }
    return BatchOperationOutcome(
      succeededIds: succeeded,
      failed: {
        for (final id in ids)
          if (rejectIds.contains(id)) id: '暂时无法写入',
      },
    );
  }

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) async {
    final override = pageOverride;
    if (override != null) return override(query);
    return PhotoPage(items: photos, hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TagReviews implements ReviewRepository {
  _TagReviews(this.photos);

  final _Photos photos;

  @override
  Future<ReviewDetail> detail(String id) async => ReviewDetail(
    photo: PhotoDetail(
      summary: PhotoSummary(
        id: id,
        filename: '$id.jpg',
        format: 'JPEG',
        preview: const PreviewRef(),
        analysisState: AnalysisState.completed,
        version: 3,
      ),
    ),
    decision: UserDecision(
      fileId: id,
      keepState: KeepState.pending,
      userTags: photos.tagsFor(id),
      version: photos.versionsById[id] ?? 3,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
