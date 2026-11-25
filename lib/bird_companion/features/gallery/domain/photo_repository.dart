import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/core/models/batch_tag_action.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';

enum PhotoCacheScope { none, complete, partial }

class PhotoQueryProgress {
  const PhotoQueryProgress({
    required this.scannedCount,
    required this.matchedCount,
    this.complete = false,
    this.fromCache = false,
    this.previewItems,
  });

  final int scannedCount;
  final int matchedCount;
  final bool complete;
  final bool fromCache;

  /// The first visible batch of matches, before the remaining pages finish.
  final List<PhotoSummary>? previewItems;
}

class PhotoQueryCancellationToken {
  PhotoQueryCancellationToken({this.isCurrent});

  final bool Function()? isCurrent;
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted || isCurrent?.call() == false;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const PhotoQueryCancelled();
  }
}

class PhotoQueryCancelled implements Exception {
  const PhotoQueryCancelled();
}

typedef PhotoQueryProgressCallback = void Function(PhotoQueryProgress progress);

class PhotoPage {
  const PhotoPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.fromCache = false,
    this.cachedAt,
    this.resultComplete = true,
    this.cacheScope = PhotoCacheScope.none,
    this.scannedCount = 0,
    this.matchedCount,
  });
  final List<PhotoSummary> items;
  final bool hasMore;
  final String? nextCursor;
  final bool fromCache;
  final DateTime? cachedAt;
  final bool resultComplete;
  final PhotoCacheScope cacheScope;
  final int scannedCount;
  final int? matchedCount;
}

class BatchOperationOutcome {
  const BatchOperationOutcome({required this.succeededIds, this.failed = const {}, this.queued = false, this.projectVersion, this.conflict = false, this.currentProjectVersion, this.errorCode});
  final List<String> succeededIds;
  final Map<String, String> failed;
  final bool queued;
  final int? projectVersion;
  final bool conflict;
  final int? currentProjectVersion;
  final String? errorCode;

  factory BatchOperationOutcome.fromResponse(List<String> ids, Map<String, dynamic> response) {
    final version = ProtocolValidation.optionalNonNegativeInt(response, 'version');
    if (version == null) throw const ProtocolCompatibilityException('version', '批量回包缺少项目版本');
    final result = BatchTagActionResult.fromResponse(ids, response);
    return BatchOperationOutcome(succeededIds: result.succeededIds, failed: result.failed, projectVersion: version);
  }

  Map<String, dynamic> toReceipt() => {
    'version': projectVersion,
    'succeeded_ids': succeededIds,
    'failed': [
      for (final entry in failed.entries) {'file_id': entry.key, 'reason': entry.value},
    ],
  };
}

/// Captures device identity across the project read and its batch mutation.
abstract interface class ProjectBatchReviewRepository {
  Future<int> readProjectVersion(String projectId);
  Future<BatchOperationOutcome> reviewBatch(String projectId, List<String> ids, String operation, {Object? value});
}

abstract interface class PhotoRepository {
  Future<PhotoPage> page(String batchId, PhotoQuery query);
  Future<List<SceneSummary>> scenes(String batchId);
  Future<List<SpeciesCandidate>> searchSpecies(String query);

  /// [version] is the project CAS; it must never come from PhotoSummary.version.
  Future<BatchOperationOutcome> batchOperation(
    String batchId,
    List<String> ids,
    String operation, {
    required int version,
    Object? value,
  });
}

/// Optional App-internal capability for long-running local gallery queries.
/// This does not add to or change the birdbox-v1 network contract.
abstract interface class PhotoQueryExecutionRepository {
  Future<PhotoPage> pageWithProgress(
    String batchId,
    PhotoQuery query, {
    PhotoQueryProgressCallback? onProgress,
    PhotoQueryCancellationToken? cancellationToken,
  });

  Future<void> invalidateLocalQueries(String batchId, {Iterable<AppDataChange> changes = const []});
}
