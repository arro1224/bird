import 'dart:io';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_page.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_list_tile.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_add_device_button.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_history_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history actions expose labels, 48dp targets and the batches route', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            BirdRoutes.batches: (_) => const Scaffold(
              key: Key('history-route'),
              body: Text('拍摄记录页'),
            ),
          },
          home: Scaffold(
            appBar: AppBar(actions: const [AlbumHistoryAppBarAction()]),
            body: const Center(child: AlbumHistorySecondaryAction()),
          ),
        ),
      );

      expect(find.byTooltip('拍摄记录'), findsOneWidget);
      expect(find.bySemanticsLabel('拍摄记录'), findsWidgets);
      final appBarTarget = tester.getSize(
        find.byKey(const Key('album-history-appbar-button')),
      );
      final secondaryTarget = tester.getSize(
        find.byKey(const Key('album-history-secondary-button')),
      );
      expect(appBarTarget.width, greaterThanOrEqualTo(48));
      expect(appBarTarget.height, greaterThanOrEqualTo(48));
      expect(secondaryTarget.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(const Key('album-history-appbar-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-route')), findsOneWidget);

      Navigator.of(tester.element(find.byKey(const Key('history-route')))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-history-secondary-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-route')), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('root album actions fit a narrow phone app bar', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('相册', style: TextStyle(fontSize: 28)),
            actions: [
              const AlbumHistoryAppBarAction(),
              IconButton(
                tooltip: '复制当前拍摄',
                onPressed: () {},
                icon: const Icon(Icons.copy_all_outlined),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AlbumAddDeviceButton(onPressed: () {}),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('拍摄记录'), findsOneWidget);
    expect(find.byTooltip('复制当前拍摄'), findsOneWidget);
    expect(find.byTooltip('新增或切换设备'), findsOneWidget);
  });

  test('root album wires history entries without the review breadcrumb', () {
    final gallerySource = File(
      'lib/bird_companion/features/gallery/presentation/gallery_page.dart',
    ).readAsStringSync();
    final albumHomeSource = File(
      'lib/bird_companion/features/gallery/presentation/album_home_page.dart',
    ).readAsStringSync();

    expect(gallerySource, contains('const AlbumHistoryAppBarAction()'));
    expect(gallerySource, contains('child: AlbumHistorySecondaryAction()'));
    expect(gallerySource, contains('alignment: Alignment.centerLeft'));
    expect(
      gallerySource,
      contains('EdgeInsets.only(top: 12, bottom: 8)'),
    );
    expect(gallerySource, isNot(contains('class _AlbumReviewPath')));
    expect(albumHomeSource, contains("actionLabel: '查看全部拍摄记录'"));
  });

  testWidgets('batch history keeps its scroll position after opening and returning', (
    tester,
  ) async {
    final repository = _HistoryRepository();
    final refreshCoordinator = SessionRefreshCoordinator();
    final dataChangeBus = AppDataChangeBus();
    addTearDown(refreshCoordinator.dispose);
    addTearDown(dataChangeBus.dispose);

    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: _TestDependencies(
          repository,
          refreshCoordinator,
          dataChangeBus,
        ),
        child: MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => settings.name == BirdRoutes.gallery
                ? const Scaffold(
                    key: Key('opened-history-gallery'),
                    body: Text('历史图库'),
                  )
                : const BatchListPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const listKey = PageStorageKey<String>('batch-history-scroll-gallery');
    await tester.drag(find.byKey(listKey), const Offset(0, -900));
    await tester.pumpAndSettle();
    final before = _scrollPosition(tester, listKey).pixels;
    expect(before, greaterThan(100));

    await tester.tap(find.byType(BatchListTile).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opened-history-gallery')), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const Key('opened-history-gallery'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(_scrollPosition(tester, listKey).pixels, closeTo(before, 1));
  });
}

ScrollPosition _scrollPosition(
  WidgetTester tester,
  PageStorageKey<String> listKey,
) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(listKey),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

class _HistoryRepository implements BatchRepository {
  _HistoryRepository()
    : currentBatch = _batch('current', '本次拍摄'),
      items = List.generate(
        30,
        (index) => _batch('history-$index', '过去拍摄 $index'),
      );

  final BatchSummary currentBatch;
  final List<BatchSummary> items;

  @override
  Future<BatchSummary?> current() async => currentBatch;

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) async => BatchPage(items: [currentBatch, ...items], hasMore: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDependencies implements BirdCompanionDependencies {
  const _TestDependencies(
    this.batchRepository,
    this.refreshCoordinator,
    this.dataChangeBus,
  );

  @override
  final BatchRepository batchRepository;

  @override
  final SessionRefreshCoordinator refreshCoordinator;

  @override
  final AppDataChangeBus dataChangeBus;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BatchSummary _batch(String id, String name) => BatchSummary(
  id: id,
  name: name,
  createdAt: DateTime.utc(2026, 9, 8),
  totalFiles: 24,
  analyzedCount: 24,
  reviewCount: 12,
  keepCount: 8,
  discardCount: 4,
  pendingCopyCount: 0,
  copyState: 'completed',
);
