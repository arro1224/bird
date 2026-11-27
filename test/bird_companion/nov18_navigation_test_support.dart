import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/connection_attempt_recorder.dart';
import 'package:aves/bird_companion/features/copy/data/active_copy_job_store.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_recovery.dart';
import 'package:aves/bird_companion/features/device/domain/device_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/recognition/recognition_repository.dart';
import 'package:aves/bird_companion/features/review/data/review_checkpoint_store.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';
import 'package:aves/bird_companion/features/storage/domain/storage_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'features/copy/fakes/fake_copy_environment.dart';
import 'features/smart_follow/entry/creation_fixtures.dart';
import 'nov18_repair_test_support.dart';

/// Synthetic reads, real production pages/controllers and copy configuration.
/// No physical box or file copying is represented by this fixture.
class B4Dependencies extends Fake implements BirdCompanionDependencies {
  @override
  bool get isEmbeddedDemo => false;
  final creation = CreationEnvironment();
  @override
  final cache = RepairMemoryCache();
  @override
  final pendingOperationStore = PendingOperationStore.memory();
  @override
  final B4Session deviceSessionCubit = B4Session();
  @override
  final dataChangeBus = AppDataChangeBus();
  @override
  final refreshCoordinator = SessionRefreshCoordinator();
  @override
  final eventClient = EventClient();
  @override
  final apiClient = ApiClient();
  @override
  final MediaAssetService mediaAssetService = _UnusedMediaService();
  @override
  final MediaAssetCoordinator mediaAssetCoordinator = _UnusedMediaCoordinator();
  @override
  late final settingsStore = BirdSettingsStore(cache);
  @override
  final FakeCopyEnvironment copyRepository = FakeCopyEnvironment();
  @override
  FakeCopyEnvironment get copyJobRepository => copyRepository;
  @override
  final B4Batches batchRepository = B4Batches();
  @override
  final B4Jobs jobRepository = B4Jobs();
  @override
  late final deviceRepository = B4Device(deviceSessionCubit);
  @override
  final photoRepository = B4Photos();
  @override
  final storageRepository = B4Storage();
  @override
  final reviewCheckpointStore = ReviewCheckpointStore.memory();
  @override
  late final recognitionRepository = RecognitionRepository(apiClient, cache, dataChangeBus, () => deviceSessionCubit.state.device?.id);
  @override
  SmartFollowRepository get smartFollowRepository => creation.follows;
  @override
  SmartFollowCreationService get smartFollowCreation => creation.service;
  @override
  late final connectionAttempts = ConnectionAttemptRecorder(cache, BleConnectionDiagnosticStore(cache));
  @override
  late final activeCopyJobs = ActiveCopyJobStore(cache);
  @override
  late final copyJobRecovery = CopyJobRecovery(
    repository: copyRepository,
    store: activeCopyJobs,
    currentDeviceId: () => deviceSessionCubit.state.device?.id,
    isConnected: () => deviceSessionCubit.state.isConnected,
    sessionChanges: deviceSessionCubit.stream.map((_) {}),
    refreshes: refreshCoordinator.changes.map((_) {}),
  );

  Future<void> close() async {
    copyJobRecovery.dispose();
    activeCopyJobs.dispose();
    recognitionRepository.dispose();
    creation.follows.dispose();
    await deviceSessionCubit.close();
    await eventClient.dispose();
    await apiClient.dispose();
    await pendingOperationStore.dispose();
    await dataChangeBus.dispose();
    await refreshCoordinator.dispose();
  }
}

class B4Session extends Cubit<DeviceSessionState> implements DeviceSessionCubit {
  B4Session() : super(DeviceSessionState(phase: DeviceSessionPhase.connected, device: connection('box-a')));
  static DeviceConnection connection(String id) => DeviceConnection(id: id, name: 'K7', baseUri: Uri.parse('http://127.0.0.1/$id'), networkMode: NetworkMode.manual);
  Completer<bool>? verification;
  int verificationCalls = 0;
  void switchDevice() => emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: connection('box-b')));
  @override
  String? get activeAttemptId => null;
  @override
  bool get provisioningHandoffActive => false;
  @override
  Future<bool> verifySavedSession({Duration timeout = const Duration(seconds: 20), String? expectedDeviceId, String intent = 'explicit_reconnect', bool restart = false}) async {
    verificationCalls++;
    return verification == null ? false : verification!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class B4Batches extends Fake implements BatchRepository {
  static final batch = BatchSummary(
    id: 'project-1',
    name: '返修验收',
    createdAt: DateTime(2026, 11, 18),
    totalFiles: 14,
    analyzedCount: 14,
    reviewCount: 6,
    recognizedCount: 5,
    filteredCount: 3,
    keepCount: 0,
    discardCount: 0,
    pendingCopyCount: 5,
    copyState: 'idle',
  );
  int reads = 0;
  Future<BatchSummary?> Function()? readCurrent;
  @override
  Future<BatchSummary?> current() async {
    reads++;
    return readCurrent == null ? batch : readCurrent!();
  }
}

class B4Jobs extends Fake implements JobRepository {
  int reads = 0;
  @override
  Future<JobPage> page({String? state, String? type, String? cursor, int pageSize = 50}) async {
    reads++;
    return const JobPage(items: [], hasMore: false);
  }
}

class B4Device extends Fake implements DeviceRepository {
  B4Device(this.session);
  final B4Session session;
  @override
  Future<DeviceStatus> fetchStatus() async => DeviceStatus(connection: session.state.device!, card: const CardStatus(inserted: true, readable: true), batteryPercent: 80, storageFreeBytes: 1000000);
  @override
  Stream<DeviceStatus> watchStatus() => const Stream.empty();
}

class B4Photos extends Fake implements PhotoRepository {
  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) async => PhotoPage(
    items: [
      for (var i = 0; i < 14; i++) PhotoSummary(id: 'photo-$i', filename: 'DSC_$i.ARW', format: 'RAW', preview: const PreviewRef(), analysisState: AnalysisState.completed, keepState: 'pending', version: 1),
    ],
    hasMore: false,
  );
}

class B4Storage extends Fake implements StorageRepository {
  @override
  Future<CardScanResult> currentScan() async => const CardScanResult(state: CardScanState.detected, cardId: 'card-1', photoCount: 14, rawCount: 14);
}

class _UnusedMediaService extends Fake implements MediaAssetService {}

class _UnusedMediaCoordinator extends Fake implements MediaAssetCoordinator {}

class B4RouteObserver extends NavigatorObserver {
  final pushes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes.add(route);
  int count(String name) => pushes.where((route) => route.settings.name == name).length;
}

Future<void> pumpB4(WidgetTester tester, Widget root, B4Dependencies dependencies, {RouteFactory? routes, List<NavigatorObserver> observers = const []}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    BirdCompanionScope(
      dependencies: dependencies,
      child: MaterialApp(navigatorObservers: observers, onGenerateRoute: routes, home: root),
    ),
  );
  await tester.pumpAndSettle();
}
