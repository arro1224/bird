import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/features/device/domain/device_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_page.dart';
import 'package:aves/bird_companion/features/gallery/presentation/selection_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart';
import 'package:aves/bird_companion/features/review/data/review_checkpoint_store.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      {'operation': 'add_tags', 'ids': ['photo-0'], 'tags': ['晨拍'], 'version': 3},
      {'operation': 'add_tags', 'ids': ['photo-1'], 'tags': ['水鸟', '晨拍'], 'version': 3},
    ]);
    expect(photos.tagsFor('photo-1'), ['湿地', '水鸟', '晨拍']);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(photos.operations.skip(2), [
      {'operation': 'remove_tags', 'ids': ['photo-0'], 'tags': ['晨拍'], 'version': 4},
      {'operation': 'remove_tags', 'ids': ['photo-1'], 'tags': ['水鸟', '晨拍'], 'version': 4},
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

class _Dependencies implements BirdCompanionDependencies {
  _Dependencies(int count) : photoRepository = _Photos(count);

  @override
  final _Photos photoRepository;
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
  final _Session deviceSessionCubit = _Session();
  @override
  final SessionRefreshCoordinator refreshCoordinator = SessionRefreshCoordinator();
  @override
  final AppDataChangeBus dataChangeBus = AppDataChangeBus();
  @override
  final DeviceRepository deviceRepository = _OfflineDevice();
  @override
  final MediaAssetService mediaAssetService = _UnusedMediaService();
  @override
  final MediaAssetCoordinator mediaAssetCoordinator = _UnusedMediaCoordinator();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session extends Cubit<DeviceSessionState> implements DeviceSessionCubit {
  _Session() : super(const DeviceSessionState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineDevice implements DeviceRepository {
  @override
  Future<DeviceStatus> fetchStatus() async => throw StateError('offline');

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
  Future<PhotoPage> page(String batchId, PhotoQuery query) async => PhotoPage(
    items: photos,
    hasMore: false,
  );

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
