import 'dart:async';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/cache_metrics_service.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/files/log_download_service.dart';
import 'package:aves/bird_companion/core/sync/conflict_resolver.dart';
import 'package:aves/bird_companion/core/sync/bird_sync_service.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/connection_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:aves/bird_companion/features/connection/data/mdns_device_discovery_source.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/device/data/device_repository_impl.dart';
import 'package:aves/bird_companion/features/device/data/device_status_api.dart';
import 'package:aves/bird_companion/features/device/domain/device_repository.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/data/batch_repository_impl.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_repository_impl.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/data/copy_repository_impl.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_repository_impl.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:flutter/widgets.dart';

/// 为拍鸟伴侣功能提供全局、可替换的依赖入口。
///
/// 网络客户端、缓存、Repository 和 Cubit 会在后续功能模块实现后从这里统一注入，
/// 页面不应自行创建这些长生命周期对象。
class BirdCompanionDependencies {
  BirdCompanionDependencies._({
    required this.apiClient,
    required this.eventClient,
    required this.connectivityMonitor,
    required this.cache,
    required this.pendingOperationStore,
    required this.syncCoordinator,
    required this.conflictResolver,
    required this.connectionRepository,
    required this.deviceRepository,
    required this.batchRepository,
    required this.photoRepository,
    required this.reviewRepository,
    required this.copyRepository,
    required this.jobRepository,
    required this.deviceSessionCubit,
    required this.birdSyncService,
    required this.refreshCoordinator,
    required this.logDownloadService,
    required this.dataChangeBus,
    required this.cacheMetricsService,
  });

  final ApiClient apiClient;
  final EventClient eventClient;
  final ConnectivityMonitor connectivityMonitor;
  final LocalCache cache;
  final PendingOperationStore pendingOperationStore;
  final SyncCoordinator syncCoordinator;
  final ConflictResolver conflictResolver;
  final ConnectionRepository connectionRepository;
  final DeviceRepository deviceRepository;
  final BatchRepository batchRepository;
  final PhotoRepository photoRepository;
  final ReviewRepository reviewRepository;
  final CopyRepository copyRepository;
  final JobRepository jobRepository;
  final DeviceSessionCubit deviceSessionCubit;
  final BirdSyncService birdSyncService;
  final SessionRefreshCoordinator refreshCoordinator;
  final LogDownloadService logDownloadService;
  final AppDataChangeBus dataChangeBus;
  final CacheMetricsService cacheMetricsService;

  static Future<BirdCompanionDependencies> create() async {
    final cache = await LocalCache.open();
    final apiClient = ApiClient();
    final eventClient = EventClient();
    final connectionRepository = ConnectionRepositoryImpl(
      ConnectionApi(apiClient, eventClient),
      cache,
      CompositeDeviceDiscoverySource([MdnsDeviceDiscoverySource(), KnownDeviceDiscoverySource(() async => const [])]),
    );
    final connectivityMonitor = ConnectivityMonitor();
    final pendingOperationStore = PendingOperationStore(cache);
    final refreshCoordinator = SessionRefreshCoordinator();
    final dataChangeBus = AppDataChangeBus();
    final birdSyncService = BirdSyncService(connectivityMonitor, SyncCoordinator(pendingOperationStore), apiClient, dataChangeBus);
    final deviceSessionCubit = DeviceSessionCubit(
      connectionRepository,
      connectivityMonitor,
      eventClient,
      refreshCoordinator,
      onConnectionRecovered: () async {
        await birdSyncService.synchronize();
      },
    );
    final dependencies = BirdCompanionDependencies._(
      apiClient: apiClient,
      eventClient: eventClient,
      connectivityMonitor: connectivityMonitor,
      cache: cache,
      pendingOperationStore: pendingOperationStore,
      syncCoordinator: SyncCoordinator(pendingOperationStore),
      conflictResolver: const ConflictResolver(),
      connectionRepository: connectionRepository,
      deviceRepository: DeviceRepositoryImpl(DeviceStatusApi(apiClient), eventClient, apiClient),
      batchRepository: BatchRepositoryImpl(BatchApi(apiClient), cache, () => deviceSessionCubit.state.device?.id ?? apiClient.baseUri?.authority ?? 'unbound'),
      photoRepository: PhotoRepositoryImpl(PhotoApi(apiClient), connectivityMonitor, pendingOperationStore, cache, () => deviceSessionCubit.state.device?.id ?? apiClient.baseUri?.authority ?? 'unbound'),
      reviewRepository: ReviewRepositoryImpl(ReviewApi(apiClient), connectivityMonitor, pendingOperationStore, cache, () => deviceSessionCubit.state.device?.id ?? apiClient.baseUri?.authority ?? 'unbound'),
      copyRepository: CopyRepositoryImpl(CopyApi(apiClient)),
      jobRepository: JobRepositoryImpl(JobApi(apiClient)),
      deviceSessionCubit: deviceSessionCubit,
      birdSyncService: birdSyncService,
      refreshCoordinator: refreshCoordinator,
      logDownloadService: LogDownloadService(apiClient),
      dataChangeBus: dataChangeBus,
      cacheMetricsService: CacheMetricsService(),
    );
    dependencies.birdSyncService.start();
    const testBaseUrl = String.fromEnvironment('BIRD_TEST_BASE_URL');
    if (testBaseUrl.isNotEmpty) {
      final uri = Uri.tryParse(testBaseUrl);
      if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
        try {
          final status = await connectionRepository.connect(uri, networkMode: NetworkMode.manual);
          await deviceSessionCubit.setConnectedFromStatus(status);
        } catch (_) {
          // The regular connection page remains available when a test box is
          // not running. Production builds do not define this value.
        }
      }
    }
    return dependencies;
  }

  void dispose() {
    unawaited(eventClient.dispose());
    unawaited(deviceSessionCubit.close());
    unawaited(birdSyncService.dispose());
    unawaited(refreshCoordinator.dispose());
    unawaited(dataChangeBus.dispose());
    unawaited(cache.close());
  }
}

class BirdCompanionScope extends InheritedWidget {
  const BirdCompanionScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final BirdCompanionDependencies dependencies;

  static BirdCompanionDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BirdCompanionScope>();
    assert(scope != null, 'BirdCompanionScope is missing from the widget tree.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(BirdCompanionScope oldWidget) => dependencies != oldWidget.dependencies;
}
