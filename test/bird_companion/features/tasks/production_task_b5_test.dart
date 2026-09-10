import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/bird_sync_service.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_version_batch_coordinator.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B5 manual AI analysis', () {
    test('uses only the frozen path and request body', () async {
      final client = _B5ApiClient();

      final job = await JobApi(client).createAnalysis(
        'project-b5',
        const AnalysisJobRequest(),
      );

      expect(job.type, BirdJobType.analysis);
      expect(client.lastPath, '/api/v1/projects/project-b5/analysis-jobs');
      expect(client.lastData, <String, dynamic>{
        'mode': 'standard',
        'include_grouping': true,
      });
    });

    test('rejects a response for another task type or project', () async {
      final wrongType = _B5ApiClient()..analysisType = 'copy';
      final wrongProject = _B5ApiClient()..analysisProjectId = 'project-other';

      await expectLater(
        JobApi(wrongType).createAnalysis(
          'project-b5',
          const AnalysisJobRequest(),
        ),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
      await expectLater(
        JobApi(wrongProject).createAnalysis(
          'project-b5',
          const AnalysisJobRequest(),
        ),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
      await expectLater(
        JobApi(_B5ApiClient()).createAnalysis(
          '  ',
          const AnalysisJobRequest(),
        ),
        throwsArgumentError,
      );
    });
  });

  test('single decision sends only frozen fields with the supplied key', () async {
    final client = _B5ApiClient();
    final patch = UserDecisionPatch(
      fileId: 'file-b5',
      keepState: const PatchField.value(KeepState.keep),
      updatedAt: DateTime.utc(2026, 8, 10),
      version: 4,
    );

    await ReviewApi(client).save(
      patch,
      idempotencyKey: 'review-b5-key',
    );

    expect(client.lastPath, '/api/v1/files/file-b5/decision');
    expect(client.lastData, <String, dynamic>{
      'keep_state': 'keep',
      'version': 4,
    });
    expect(client.lastIdempotencyKey, 'review-b5-key');
    expect(client.lastData, isNot(contains('updated_at')));
  });

  test('mixed photo versions are split and missing versions are isolated', () async {
    final photos = _B5PhotoRepository();
    final reviews = _B5ReviewRepository();
    final coordinator = PhotoVersionBatchCoordinator(photos, reviews);

    final result = await coordinator.apply(
      projectId: 'project-b5',
      fileIds: const <String>['file-1', 'file-2', 'file-3', 'file-4'],
      currentPhotos: <PhotoSummary>[
        _photo('file-1', version: 1),
        _photo('file-2', version: 2),
      ],
      operation: 'keep',
    );

    expect(photos.calls, <String>['1:file-1', '2:file-2,file-3']);
    expect(result.succeededIds, <String>['file-1', 'file-2', 'file-3']);
    expect(result.failed.keys, <String>['file-4']);
  });

  test('offline replay strips routing metadata and reuses operation ids', () async {
    final store = PendingOperationStore.memory();
    await store.save(
      PendingOperation(
        id: 'decision-op-b5',
        type: PendingOperationType.updateReview,
        payload: const <String, dynamic>{
          'file_id': 'file-1',
          'project_id': 'project-b5',
          'updated_at': '2026-08-10T00:00:00Z',
          'keep_state': 'keep',
          'version': 3,
        },
        createdAt: DateTime.utc(2026, 8, 10),
        deviceId: 'box-b5',
        projectId: 'project-b5',
        fileId: 'file-1',
      ),
    );
    await store.save(
      PendingOperation(
        id: 'batch-op-b5',
        type: PendingOperationType.batchReview,
        payload: const <String, dynamic>{
          'project_id': 'project-b5',
          'batch_id': 'project-b5',
          'file_ids': <String>['file-2'],
          'operation': 'add_tags',
          'value': <String>['湿地'],
          'version': 5,
        },
        createdAt: DateTime.utc(2026, 8, 10, 0, 1),
        deviceId: 'box-b5',
        projectId: 'project-b5',
      ),
    );
    final client = _B5ApiClient();
    final service = BirdSyncService(
      ConnectivityMonitor(),
      SyncCoordinator(store),
      client,
      null,
      () => 'box-b5',
    );

    final result = await service.synchronize();

    expect(result.syncedCount, 2);
    expect(client.idempotencyKeys, <String>[
      'decision-op-b5',
      'batch-op-b5',
    ]);
    expect(client.payloads[0], <String, dynamic>{
      'keep_state': 'keep',
      'version': 3,
    });
    expect(client.payloads[1], <String, dynamic>{
      'file_ids': <String>['file-2'],
      'operation': 'add_tags',
      'value': <String>['湿地'],
      'version': 5,
    });
  });
}

class _B5ApiClient extends ApiClient {
  String analysisType = 'analysis';
  String analysisProjectId = 'project-b5';
  String? lastPath;
  Object? lastData;
  String? lastIdempotencyKey;
  final List<String> idempotencyKeys = <String>[];
  final List<Object?> payloads = <Object?>[];

  @override
  Uri? get baseUri => Uri.parse('http://127.0.0.1:8080');

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    String? idempotencyKey,
    Map<String, String>? headers,
  }) async {
    lastPath = path;
    lastData = data;
    lastIdempotencyKey = idempotencyKey;
    if (idempotencyKey != null) {
      idempotencyKeys.add(idempotencyKey);
      payloads.add(data);
    }
    if (path.endsWith('/analysis-jobs')) {
      return <String, dynamic>{
        'job_id': 'job-analysis-b5',
        'job_type': analysisType,
        'job_state': 'queued',
        'progress': 0,
        'total_count': 10,
        'finished_count': 0,
        'failed_count': 0,
        'skipped_count': 0,
        'available_actions': <String>['cancel'],
        'version': 1,
        'source_project_id': analysisProjectId,
      };
    }
    return const <String, dynamic>{};
  }
}

PhotoSummary _photo(String id, {int? version}) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'JPEG',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  version: version,
);

class _B5PhotoRepository implements PhotoRepository {
  final List<String> calls = <String>[];

  @override
  Future<BatchOperationOutcome> batchOperation(
    String batchId,
    List<String> ids,
    String operation, {
    required int version,
    Object? value,
  }) async {
    calls.add('$version:${ids.join(',')}');
    return BatchOperationOutcome(succeededIds: ids);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _B5ReviewRepository implements ReviewRepository {
  @override
  Future<ReviewDetail> detail(String fileId) async {
    if (fileId == 'file-4') throw StateError('missing version');
    return ReviewDetail(photo: PhotoDetail(summary: _photo(fileId, version: 2)));
  }

  @override
  Future<List<BirdGroup>> groups(
    String batchId, {
    String? sceneId,
  }) async => const <BirdGroup>[];

  @override
  Future<ReviewSaveResult> save(
    UserDecision value, {
    String? projectId,
  }) async => const ReviewSaveResult();
}
