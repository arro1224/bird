import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';

/// Uses project CAS for one selection. The legacy class name is retained for
/// callers; photo/decision versions must never determine this request.
class PhotoVersionBatchCoordinator {
  const PhotoVersionBatchCoordinator(
    this._photoRepository,
    ReviewRepository reviewRepository,
  );

  final PhotoRepository _photoRepository;

  Future<BatchOperationOutcome> apply({
    required String projectId,
    required List<String> fileIds,
    required Iterable<PhotoSummary> currentPhotos,
    required String operation,
    Object? value,
    bool loadMissingVersions = true,
  }) async {
    final selectedIds = fileIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList(growable: false);
    if (selectedIds.isEmpty) return const BatchOperationOutcome(succeededIds: []);
    final repository = _photoRepository;
    if (repository is! ProjectBatchReviewRepository) {
      return BatchOperationOutcome(succeededIds: const [], failed: {for (final id in selectedIds) id: '无法核实批次最新状态，批量修改未提交'}, errorCode: 'PROJECT_VERSION_UNAVAILABLE');
    }
    try {
      return await (repository as ProjectBatchReviewRepository).reviewBatch(projectId, selectedIds, operation, value: value);
    } on ProtocolCompatibilityException {
      return BatchOperationOutcome(succeededIds: const [], failed: {for (final id in selectedIds) id: '无法核实批次最新状态，批量修改未提交'}, errorCode: 'PROJECT_VERSION_UNAVAILABLE');
    } catch (_) {
      return BatchOperationOutcome(succeededIds: const [], failed: {for (final id in selectedIds) id: '无法核实批次最新状态，请重连刷新后重试'});
    }
  }
}
