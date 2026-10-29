import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
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
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  final PhotoRepository photoRepository;
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

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) async => PhotoPage(
    items: photos,
    hasMore: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
