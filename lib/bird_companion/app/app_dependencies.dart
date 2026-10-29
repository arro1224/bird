import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/features/connection/data/connection_attempt_recorder.dart';
import 'package:flutter/services.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_attempt.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:dio/dio.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_snapshot_service.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/recognition/recognition_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/cache_metrics_service.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/files/log_download_service.dart';
import 'package:aves/bird_companion/core/media/media_asset_cache.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_http_client.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/sync/conflict_resolver.dart';
import 'package:aves/bird_companion/core/sync/bird_sync_service.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/connection_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_scan_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/mdns_device_discovery_source.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_dpp_platform.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
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
import 'package:aves/bird_companion/features/review/data/review_checkpoint_store.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/data/active_copy_job_store.dart';
import 'package:aves/bird_companion/features/copy/data/copy_request_diagnostics.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_recovery.dart';
import 'package:aves/bird_companion/features/copy/data/copy_repository_impl.dart';
import 'package:aves/bird_companion/features/copy/data/mock_copy_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_repository_impl.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:aves/bird_companion/features/storage/data/storage_api.dart';
import 'package:aves/bird_companion/features/storage/data/storage_repository_impl.dart';
import 'package:aves/bird_companion/features/storage/domain/storage_repository.dart';
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
    required this.provisioningRepository,
    required this.deviceRepository,
    required this.batchRepository,
    required this.photoRepository,
    required this.reviewRepository,
    required this.reviewCheckpointStore,
    required this.copyRepository,
    required this.copyJobRepository,
    required this.activeCopyJobs,
    required this.jobRepository,
    required this.storageRepository,
    required this.deviceSessionCubit,
    required this.birdSyncService,
    required this.refreshCoordinator,
    required this.logDownloadService,
    required this.dataChangeBus,
    required this.cacheMetricsService,
    required this.settingsStore,
    required this.sessionCoordinator,
    required this.mediaAssetCoordinator,
    required this.mediaAssetService,
    required this.bleScanDiagnosticStore,
    required this.bleConnectionDiagnosticStore,
    required this.connectionAttempts,
  }) {
    // R3：WebSocket 只当唤醒信号，仓储收到后重读会话（不拿 payload 数字改状态）。
    // 断线期间漏掉的通知由页面/前台的显式 refresh 补齐，不依赖这条订阅。
    smartFollowRepository.bindEvents(eventClient.events);
  }

  final ApiClient apiClient;
  late final recognitionRepository = RecognitionRepository(apiClient, cache, dataChangeBus, () => deviceSessionCubit.state.device?.id);

  /// SmartFollow 边识别边复制（F3）。页面经它读写会话，禁止直接拿 ApiClient
  /// 调 smart-follow 端点，否则快照合并与幂等规则会被绕过。
  late final smartFollowRepository = SmartFollowRepository(SmartFollowApi(apiClient));
  final EventClient eventClient;
  final ConnectivityMonitor connectivityMonitor;
  final LocalCache cache;
  final PendingOperationStore pendingOperationStore;
  final SyncCoordinator syncCoordinator;
  final ConflictResolver conflictResolver;
  final ConnectionRepository connectionRepository;
  final ProvisioningRepository provisioningRepository;
  final DeviceRepository deviceRepository;
  final BatchRepository batchRepository;
  final PhotoRepository photoRepository;
  final ReviewRepository reviewRepository;
  final ReviewCheckpointStore reviewCheckpointStore;
  final CopyRepository copyRepository;
  final CopyJobRepository copyJobRepository;
  final ActiveCopyJobStore activeCopyJobs;
  late final copyDiagnostics = CopyRequestDiagnostics.forJournal(bleConnectionDiagnosticStore);
  late final copyJobRecovery = CopyJobRecovery(
    repository: copyJobRepository,
    store: activeCopyJobs,
    currentDeviceId: () => deviceSessionCubit.state.device?.id,
    isConnected: () => deviceSessionCubit.state.isConnected,
    sessionChanges: deviceSessionCubit.stream.map((_) {}),
    refreshes: refreshCoordinator.changes.map((_) {}),
    diagnostics: copyDiagnostics,
  );
  final JobRepository jobRepository;
  final StorageRepository storageRepository;
  final DeviceSessionCubit deviceSessionCubit;
  final BirdSyncService birdSyncService;
  final SessionRefreshCoordinator refreshCoordinator;
  final LogDownloadService logDownloadService;
  final AppDataChangeBus dataChangeBus;
  final CacheMetricsService cacheMetricsService;
  final SettingsStore settingsStore;
  final SessionCoordinator sessionCoordinator;
  final MediaAssetCoordinator mediaAssetCoordinator;
  final MediaAssetService mediaAssetService;
  final BleScanDiagnosticStore bleScanDiagnosticStore;
  final BleConnectionDiagnosticStore bleConnectionDiagnosticStore;
  final bleDiagnosticFilePlatform = const MethodChannelBirdBoxBleDiagnosticFilePlatform();
  late final bleDiagnosticSnapshotService = BleDiagnosticSnapshotService(bleScanDiagnosticStore, bleConnectionDiagnosticStore, bleDiagnosticFilePlatform);
  final ConnectionAttemptRecorder connectionAttempts;
  StreamSubscription<EventConnectionState>? _sessionTrace;
  StreamSubscription? _deviceTrace;
  String? _traceDeviceId;

  static Future<BirdCompanionDependencies> create({
    bool connectEnvironmentTestEndpoint = true,
    bool restoreSavedSession = true,
    DirectApAuthorizationStore? directApAuthorizationStore,
    ClientIdentityStore? clientIdentityStore,
  }) async {
    final cache = await LocalCache.open();
    final apiClient = ApiClient();
    final eventClient = EventClient();
    final secureSessionStore = SerializedSecureSessionStore(AndroidKeystoreSessionStore());
    final sessionCoordinator = SessionCoordinator(
      apiClient,
      eventClient,
      secureSessionStore,
    );
    final pairingApi = PairingApi(apiClient);
    final bleScanDiagnosticStore = BleScanDiagnosticStore(cache);
    final bleConnectionDiagnosticStore = BleConnectionDiagnosticStore(cache);
    final connectionRepository = ConnectionRepositoryImpl(
      ConnectionApi(
        apiClient,
        pairingApi,
        sessionCoordinator,
      ),
      cache,
      CompositeDeviceDiscoverySource([MdnsDeviceDiscoverySource(), KnownDeviceDiscoverySource(() async => const [])]),
    );
    final provisioningRepository = ProvisioningRepositoryImpl(
      ble: PlatformBirdBoxBleDataSource(
        diagnosticSink: bleScanDiagnosticStore,
        connectionDiagnosticSink: bleConnectionDiagnosticStore,
      ),
      wifi: MethodChannelBirdBoxWifiPlatform(),
      dpp: MethodChannelBirdBoxDppPlatform(),
      clientIdentityStore: clientIdentityStore ?? AndroidKeystoreClientIdentityStore(),
      credentialStore: secureSessionStore,
      directApAuthorizationStore: directApAuthorizationStore ?? const EncryptedDirectApAuthorizationStore(),
      healthApi: HealthApi(apiClient),
      pairingApi: pairingApi,
      sessionCoordinator: sessionCoordinator,
      rememberDynamicAddress: (deviceId, baseUri, mode) => connectionRepository.rememberDynamicAddress(
        deviceId: deviceId,
        baseUri: baseUri,
        networkMode: switch (mode) {
          ProvisioningNetworkMode.directAp => NetworkMode.directAp,
          ProvisioningNetworkMode.infrastructureSta => NetworkMode.infrastructureSta,
          ProvisioningNetworkMode.none => NetworkMode.none,
        },
      ),
    );
    final connectivityMonitor = ConnectivityMonitor();
    final pendingOperationStore = PendingOperationStore(cache);
    final refreshCoordinator = SessionRefreshCoordinator();
    final dataChangeBus = AppDataChangeBus();
    late final DeviceSessionCubit deviceSessionCubit;
    late final ReviewRepositoryImpl reviewRepository;
    String? activeDeviceId() {
      final id = deviceSessionCubit.state.device?.id.trim();
      return id == null || id.isEmpty ? null : id;
    }

    String activeDeviceNamespace() => activeDeviceId() ?? apiClient.baseUri?.authority ?? 'unbound';

    final birdSyncService = BirdSyncService(
      connectivityMonitor,
      SyncCoordinator(pendingOperationStore),
      apiClient,
      dataChangeBus,
      activeDeviceId,
      (fileId) => reviewRepository.acceptRemoteDecision(fileId),
      (photo) => reviewRepository.acceptSyncedPhoto(photo),
    );
    final connectionAttempts = ConnectionAttemptRecorder(cache, bleConnectionDiagnosticStore);
    deviceSessionCubit = DeviceSessionCubit(
      connectionRepository,
      connectivityMonitor,
      eventClient,
      refreshCoordinator,
      sessionCoordinator: sessionCoordinator,
      diagnostic: connectionAttempts.record,
      transportChanges: connectivityMonitor.onTransportChanged,
      onConnectionRecovered: () async {
        await birdSyncService.synchronize();
      },
    );
    final mediaAssetCache = MediaAssetCache(
      etagStore: LocalCacheMediaAssetEtagStore(cache),
    );
    final mediaAssetCoordinator = MediaAssetCoordinator(
      eventClient: eventClient,
      activeDeviceId: activeDeviceId,
      cacheInvalidator: mediaAssetCache,
    );
    final mediaAssetService = MediaAssetService(
      httpClient: MediaAssetHttpClient(headersForUri: apiClient.mediaHeaders),
      cache: mediaAssetCache,
      coordinator: mediaAssetCoordinator,
    );
    reviewRepository = ReviewRepositoryImpl(
      ReviewApi(apiClient),
      connectivityMonitor,
      pendingOperationStore,
      cache,
      activeDeviceNamespace,
      activeDeviceId,
      dataChangeBus,
    );
    // 复制功能：mock/真实共用同一实例实现 CopyRepository + CopyJobRepository。
    final CopyRepository copyRepositoryImpl;
    final CopyJobRepository copyJobRepositoryImpl;
    if (useMockCopyRepository) {
      final mock = MockCopyRepository();
      copyRepositoryImpl = mock;
      copyJobRepositoryImpl = mock;
    } else {
      final real = CopyRepositoryImpl(CopyApi(apiClient));
      copyRepositoryImpl = real;
      copyJobRepositoryImpl = real;
    }
    final dependencies = BirdCompanionDependencies._(
      apiClient: apiClient,
      eventClient: eventClient,
      connectivityMonitor: connectivityMonitor,
      cache: cache,
      pendingOperationStore: pendingOperationStore,
      syncCoordinator: SyncCoordinator(pendingOperationStore),
      conflictResolver: const ConflictResolver(),
      connectionRepository: connectionRepository,
      provisioningRepository: provisioningRepository,
      deviceRepository: DeviceRepositoryImpl(DeviceStatusApi(apiClient), eventClient, apiClient),
      batchRepository: BatchRepositoryImpl(BatchApi(apiClient), cache, activeDeviceNamespace),
      photoRepository: PhotoRepositoryImpl(
        PhotoApi(apiClient),
        connectivityMonitor,
        pendingOperationStore,
        cache,
        activeDeviceNamespace,
        activeDeviceId,
      ),
      reviewRepository: reviewRepository,
      reviewCheckpointStore: ReviewCheckpointStore(cache),
      // 后端交付 birdbox-copy-v1 后将开关置 false 即切真实接口（迁移对照文档 §7）。
      // 任务闭环（RC3）与创建流程共用同一实例（阶段 D 实施计划 §3）。
      copyRepository: copyRepositoryImpl,
      copyJobRepository: copyJobRepositoryImpl,
      activeCopyJobs: useMockCopyRepository ? ActiveCopyJobStore.memory() : ActiveCopyJobStore(cache),
      jobRepository: JobRepositoryImpl(JobApi(apiClient)),
      storageRepository: StorageRepositoryImpl(StorageApi(apiClient)),
      deviceSessionCubit: deviceSessionCubit,
      birdSyncService: birdSyncService,
      refreshCoordinator: refreshCoordinator,
      logDownloadService: LogDownloadService(apiClient),
      dataChangeBus: dataChangeBus,
      cacheMetricsService: CacheMetricsService(),
      settingsStore: BirdSettingsStore(cache),
      sessionCoordinator: sessionCoordinator,
      mediaAssetCoordinator: mediaAssetCoordinator,
      mediaAssetService: mediaAssetService,
      bleScanDiagnosticStore: bleScanDiagnosticStore,
      bleConnectionDiagnosticStore: bleConnectionDiagnosticStore,
      connectionAttempts: connectionAttempts,
    );
    dependencies.birdSyncService.start();
    unawaited(dependencies.copyJobRecovery.recover());
    dependencies._sessionTrace = eventClient.connectionStates.listen((state) => dependencies.connectionAttempts.record({'event': 'session_ws_state', 'device_id': sessionCoordinator.activeDeviceId, 'ws_state': state.name}));
    dependencies._deviceTrace = deviceSessionCubit.stream.listen((state) {
      dependencies.connectionAttempts.record({'event': 'global_session_state', 'attempt_id': state.attemptId, 'operation_id': state.operationId, 'device_id': state.device?.id, 'phase': state.phase.name});
      // 换盒子就把 SmartFollow 的会话快照与能力缓存丢掉：session_id/能力属于某台盒子。
      final deviceId = state.device?.id.trim();
      if (deviceId != null && deviceId.isNotEmpty && deviceId != dependencies._traceDeviceId) {
        dependencies._traceDeviceId = deviceId;
        dependencies.smartFollowRepository.resetForDeviceChange();
      }
    });
    const testBaseUrl = String.fromEnvironment('BIRD_TEST_BASE_URL');
    const testPairingCode = String.fromEnvironment('BIRD_TEST_PAIRING_CODE');
    if (connectEnvironmentTestEndpoint && testBaseUrl.isNotEmpty) {
      final uri = Uri.tryParse(testBaseUrl);
      if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
        try {
          DeviceStatus status;
          try {
            status = await connectionRepository.connect(uri, networkMode: NetworkMode.manual);
          } on PairingRequiredException {
            if (testPairingCode.isEmpty) rethrow;
            status = await connectionRepository.pair(uri, networkMode: NetworkMode.manual, pairingCode: testPairingCode);
          }
          await deviceSessionCubit.setConnectedFromStatus(status);
        } catch (_) {
          // The regular connection page remains available when a test box is
          // not running. Production builds do not define this value.
        }
      }
    }
    if (restoreSavedSession && cache.read<Map>(DirectApHandoffCubit.pendingKey) == null && !deviceSessionCubit.state.isConnected) {
      try {
        final saved = await connectionRepository.savedDevice();
        if (saved != null) deviceSessionCubit.seedSavedDevice(saved);
      } catch (error) {
        connectionAttempts.record({'event': 'saved_device_read_failed', ...ConnectionAttempt.errorFields(error)});
      }
      unawaited(deviceSessionCubit.restoreSavedSession());
    }
    return dependencies;
  }

  /// Promotes a network endpoint confirmed by BLE provisioning into the
  /// application-wide authenticated device session.
  Future<void> completeProvisioning(ProvisioningCompletion completion, {CancelToken? cancelToken}) async {
    if (completion.networkMode == ProvisioningNetworkMode.none) {
      throw StateError('Provisioning completed without an active network.');
    }
    final repository = connectionRepository;
    final networkMode = switch (completion.networkMode) {
      ProvisioningNetworkMode.directAp => NetworkMode.directAp,
      ProvisioningNetworkMode.infrastructureSta => NetworkMode.infrastructureSta,
      ProvisioningNetworkMode.none => NetworkMode.none,
    };
    final status = repository is ConnectionRepositoryImpl
        ? await repository.connectExpected(
            completion.baseUri,
            networkMode: networkMode,
            expectedDeviceId: completion.deviceId,
            cancelToken: cancelToken,
          )
        : await repository.connect(completion.baseUri, networkMode: networkMode, cancelToken: cancelToken);
    if (status.connection.id != completion.deviceId) {
      throw StateError('Provisioned device identity does not match the connected box.');
    }
    cancelToken?.throwIfCancellationRequested();
    final attempt = ConnectionAttempt.forToken(cancelToken);
    attempt?.check();
    await deviceSessionCubit.setConnectedFromStatus(status, attempt: attempt);
  }

  Future<void> completeDirectApHandoff(PendingDirectAp pending, CancelToken token) async {
    final attempt = deviceSessionCubit.beginEndpointVerification(attemptId: pending.attemptId!, deviceId: pending.deviceId, operationId: pending.operationId, token: token);
    connectionAttempts.record({'event': 'network_identity_check_started', 'attempt_id': pending.attemptId, 'operation_id': pending.operationId, 'device_id': pending.deviceId, 'base_uri': pending.baseUri.toString()});
    Map<String, dynamic> phoneNetwork;
    try {
      phoneNetwork = Map<String, dynamic>.from(await const MethodChannel('bird_companion/birdbox_wifi/methods').invokeMapMethod<String, dynamic>('networkSnapshot') ?? const {});
    } catch (_) {
      phoneNetwork = const {'transport': 'unknown', 'ssid_available': false};
    }
    token.throwIfCancellationRequested();
    unawaited(
      bleConnectionDiagnosticStore.record(
        BleConnectionDiagnosticEvent(
          traceId: pending.operationId,
          flowId: pending.operationId,
          occurredAt: DateTime.now(),
          eventType: 'direct_ap_phone_network',
          source: 'app_network',
          operationName: 'direct_ap_handoff',
          sanitizedMessage: jsonEncode(phoneNetwork),
        ),
      ),
    );
    // Read public identity BEFORE sending pairing material or activating a token.
    await attempt.run(
      'identity',
      () => ConnectionApi(apiClient, PairingApi(apiClient), sessionCoordinator).verifyDirectApIdentity(pending.baseUri, pending.deviceId, token, networkMode: pending.isSta ? NetworkMode.infrastructureSta : NetworkMode.directAp),
    );
    token.throwIfCancellationRequested();
    final repository = provisioningRepository;
    if (repository is DirectApHttpPreparation) await attempt.run('authorization', () => (repository as DirectApHttpPreparation).prepareDirectApHttp(pending.completion, token));
    token.throwIfCancellationRequested();
    await completeProvisioning(pending.completion, cancelToken: token);
    connectionAttempts.record({
      'event': 'authenticated_http_ws_verified',
      'attempt_id': pending.attemptId,
      'operation_id': pending.operationId,
      'device_id': pending.deviceId,
      'http_result': 'protected_read_ok',
      'ws_state': eventClient.currentState.name,
    });
  }

  Future<Uri?> resolveStaEndpoint(String deviceId) async {
    final candidates = await connectionRepository.discover();
    for (final device in candidates) {
      if (device.id == deviceId && device.networkMode == NetworkMode.infrastructureSta) return device.baseUri;
    }
    final repository = provisioningRepository;
    final snapshot = repository is ProvisioningEndpointSnapshot ? (repository as ProvisioningEndpointSnapshot).lastNetworkSnapshot : null;
    return snapshot?.activeMode == ProvisioningNetworkMode.infrastructureSta ? snapshot?.baseUri : null;
  }

  PendingDirectAp? pendingVerifiedBleEndpoint(ProvisioningDeviceInfo info) {
    final repository = provisioningRepository;
    final snapshot = repository is ProvisioningEndpointSnapshot ? (repository as ProvisioningEndpointSnapshot).lastNetworkSnapshot : null;
    final endpoint = snapshot?.baseUri;
    if (snapshot == null || snapshot.busy || snapshot.lastError != null || endpoint == null || !{NetworkOperationState.staConnected, NetworkOperationState.apReady}.contains(snapshot.operationState)) return null;
    return PendingDirectAp(deviceId: info.deviceId, baseUri: endpoint, operationId: snapshot.operationId ?? 'existing-network', networkMode: snapshot.activeMode, attemptId: SecureRequestIdFactory().create());
  }

  DirectApHandoffCubit createDirectApHandoff() {
    final owner = Object();
    String? ownedIntentId;
    return DirectApHandoffCubit(
      store: cache,
      verify: completeDirectApHandoff,
      onBegin: (pending, restored) {
        final id = pending.attemptId!;
        if (restored) {
          if (deviceSessionCubit.provisioningHandoffActive) return false;
          deviceSessionCubit.beginNetworkIntent(id);
        }
        final accepted = deviceSessionCubit.acceptsNetworkIntent(id);
        if (accepted) ownedIntentId = id;
        return accepted;
      },
      isIntentCurrent: (pending) => deviceSessionCubit.acceptsNetworkIntent(pending.attemptId!),
      onVerificationStopped: (message) {
        if (ownedIntentId != null && deviceSessionCubit.acceptsNetworkIntent(ownedIntentId!)) deviceSessionCubit.disconnected(message ?? '盒子连接验证暂未完成，可以继续验证。');
      },
      activeChanged: (active) {
        deviceSessionCubit.setHandoffActive(owner, active);
        if (active) deviceSessionCubit.disconnected('正在验证盒子网络连接。');
        if (!active && ownedIntentId != null) deviceSessionCubit.endNetworkIntent(ownedIntentId!);
      },
      onCancel: (id) async {
        final repository = provisioningRepository;
        if (repository is DirectApHttpPreparation) await (repository as DirectApHttpPreparation).cancelDirectApHttp(id);
      },
      diagnostic: (event) {
        connectionAttempts.record(event);
        final trace = event['operation_id'] as String? ?? 'direct-ap';
        unawaited(
          bleConnectionDiagnosticStore.record(
            BleConnectionDiagnosticEvent(traceId: trace, flowId: trace, occurredAt: DateTime.now(), eventType: event['event'] as String, source: 'app_network', operationName: 'direct_ap_handoff', sanitizedMessage: jsonEncode(event)),
          ),
        );
      },
    );
  }

  void dispose() {
    copyJobRecovery.dispose();
    activeCopyJobs.dispose();
    unawaited(_sessionTrace?.cancel());
    unawaited(_deviceTrace?.cancel());
    recognitionRepository.dispose();
    smartFollowRepository.dispose();
    unawaited(provisioningRepository.dispose());
    unawaited(mediaAssetCoordinator.dispose());
    mediaAssetService.dispose();
    unawaited(eventClient.dispose());
    unawaited(sessionCoordinator.dispose());
    unawaited(apiClient.dispose());
    unawaited(deviceSessionCubit.close());
    unawaited(birdSyncService.dispose());
    unawaited(refreshCoordinator.dispose());
    unawaited(dataChangeBus.dispose());
    unawaited(pendingOperationStore.dispose());
    unawaited(bleScanDiagnosticStore.dispose());
    unawaited(bleConnectionDiagnosticStore.dispose());
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

  /// 独立预览/测试环境可能没有盒子会话，返回 null。
  static BirdCompanionDependencies? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BirdCompanionScope>()?.dependencies;

  @override
  bool updateShouldNotify(BirdCompanionScope oldWidget) => dependencies != oldWidget.dependencies;
}
