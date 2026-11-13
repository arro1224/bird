import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
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
  const BatchOperationOutcome({required this.succeededIds, this.failed = const {}, this.queued = false});
  final List<String> succeededIds;
  final Map<String, String> failed;
  final bool queued;
}

abstract interface class PhotoRepository {
  Future<PhotoPage> page(String batchId, PhotoQuery query);
  Future<List<SceneSummary>> scenes(String batchId);
  Future<List<SpeciesCandidate>> searchSpecies(String query);
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
