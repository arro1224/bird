import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';

class PhotoPage {
  const PhotoPage({required this.items, required this.hasMore, this.nextCursor, this.fromCache = false, this.cachedAt});
  final List<PhotoSummary> items;
  final bool hasMore;
  final String? nextCursor;
  final bool fromCache;
  final DateTime? cachedAt;
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
  Future<BatchOperationOutcome> batchOperation(String batchId, List<String> ids, String operation, {Object? value});
}
