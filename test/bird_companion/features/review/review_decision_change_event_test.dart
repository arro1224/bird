import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online confirmation and offline queue publish complete review deltas', () async {
    final bus = AppDataChangeBus();
    final connectivity = _ConnectivityMonitor();
    final pending = PendingOperationStore.memory();
    final repository = ReviewRepositoryImpl(
      _ReviewApi(),
      connectivity,
      pending,
      _MemoryCache(),
      () => 'box-1',
      () => 'box-1',
      bus,
    );
    final changes = <ReviewDecisionChanged>[];
    final subscription = bus.changes.where((change) => change is ReviewDecisionChanged).cast<ReviewDecisionChanged>().listen(changes.add);
    addTearDown(subscription.cancel);
    addTearDown(bus.dispose);
    addTearDown(pending.dispose);

    final online = await repository.saveAuthoritative(
      const UserDecision(
        fileId: 'photo-1',
        keepState: KeepState.keep,
        version: 1,
      ),
      projectId: 'project-1',
    );
    connectivity.online = false;
    final queued = await repository.saveAuthoritative(
      UserDecision(
        fileId: 'photo-1',
        keepState: KeepState.discard,
        version: online.authoritativeDecision!.version,
      ),
      projectId: 'project-1',
    );
    await repository.acceptSyncedPhoto(
      const PhotoSummary(
        id: 'photo-1',
        filename: 'photo-1.jpg',
        format: 'jpg',
        preview: PreviewRef(),
        analysisState: AnalysisState.completed,
        keepState: 'discard',
        version: 3,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(online.authoritativeDecision?.version, 2);
    expect(queued.queued, isTrue);
    expect(changes, hasLength(3));
    expect(changes.first.deviceId, 'box-1');
    expect(changes.first.projectId, 'project-1');
    expect(changes.first.fileId, 'photo-1');
    expect(changes.first.beforeKeepState, KeepState.pending);
    expect(changes.first.afterKeepState, KeepState.keep);
    expect(changes.first.authoritativeVersion, 2);
    expect(changes.first.queued, isFalse);
    expect(changes[1].beforeKeepState, KeepState.keep);
    expect(changes[1].afterKeepState, KeepState.discard);
    expect(changes[1].authoritativeVersion, isNull);
    expect(changes[1].queued, isTrue);
    expect(changes.last.projectId, 'project-1');
    expect(changes.last.beforeKeepState, KeepState.discard);
    expect(changes.last.afterKeepState, KeepState.discard);
    expect(changes.last.authoritativeVersion, 3);
    expect(changes.last.queued, isFalse);
  });

  test('online save publishes with the device identity captured before the request', () async {
    final bus = AppDataChangeBus();
    final pending = PendingOperationStore.memory();
    var activeDeviceReads = 0;
    final repository = ReviewRepositoryImpl(
      _ReviewApi(),
      _ConnectivityMonitor(),
      pending,
      _MemoryCache(),
      () => 'box-1',
      () => ++activeDeviceReads == 1 ? 'box-1' : null,
      bus,
    );
    final changes = <ReviewDecisionChanged>[];
    final subscription = bus.changes.where((change) => change is ReviewDecisionChanged).cast<ReviewDecisionChanged>().listen(changes.add);
    addTearDown(subscription.cancel);
    addTearDown(bus.dispose);
    addTearDown(pending.dispose);

    await repository.saveAuthoritative(
      const UserDecision(
        fileId: 'photo-1',
        keepState: KeepState.keep,
        version: 1,
      ),
      projectId: 'project-1',
    );
    await Future<void>.delayed(Duration.zero);

    // One read captures the request identity and one best-effort read scopes
    // stale-queue cleanup. Publishing must not perform a third, lossy read.
    expect(activeDeviceReads, 2);
    expect(changes, hasLength(1));
    expect(changes.single.deviceId, 'box-1');
  });
}

class _ReviewApi extends ReviewApi {
  _ReviewApi() : super(ApiClient());

  @override
  Future<PhotoSummary> saveWithPhoto(
    UserDecisionPatch value, {
    String? idempotencyKey,
  }) async => PhotoSummary(
    id: value.fileId,
    filename: '${value.fileId}.jpg',
    format: 'jpg',
    preview: const PreviewRef(),
    analysisState: AnalysisState.completed,
    keepState: value.keepState.value?.wireValue ?? 'pending',
    version: 2,
  );
}

class _ConnectivityMonitor extends ConnectivityMonitor {
  bool online = true;

  @override
  Future<bool> get hasNetwork async => online;
}

class _MemoryCache implements LocalCache {
  final _values = <String, Object?>{};

  @override
  T? read<T>(String key) => _values[key] as T?;

  @override
  List<String> keysWithPrefix(String prefix) => _values.keys.where((key) => key.startsWith(prefix)).toList(growable: false);

  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
