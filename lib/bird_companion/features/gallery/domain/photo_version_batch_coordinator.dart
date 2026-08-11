import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';

/// Applies the frozen one-version batch request without requiring every
/// selected photo to share that version.
class PhotoVersionBatchCoordinator {
  const PhotoVersionBatchCoordinator(
    this._photoRepository,
    this._reviewRepository,
  );

  final PhotoRepository _photoRepository;
  final ReviewRepository _reviewRepository;

  Future<BatchOperationOutcome> apply({
    required String projectId,
    required List<String> fileIds,
    required Iterable<PhotoSummary> currentPhotos,
    required String operation,
    Object? value,
  }) async {
    final selectedIds = fileIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList(growable: false);
    final currentById = {
      for (final photo in currentPhotos) photo.id: photo,
    };
    final grouped = <int, List<String>>{};
    final failed = <String, String>{};

    for (final id in selectedIds) {
      var version = currentById[id]?.version;
      if (version == null) {
        try {
          final detail = await _reviewRepository.detail(id);
          version = detail.decision?.version ?? detail.photo.summary.version;
        } catch (_) {
          failed[id] = '无法获取照片版本，请刷新后重试';
          continue;
        }
      }
      if (version == null || version < 0) {
        failed[id] = '照片缺少有效版本，请刷新后重试';
        continue;
      }
      grouped.putIfAbsent(version, () => <String>[]).add(id);
    }

    final succeeded = <String>[];
    var queued = false;
    for (final entry in grouped.entries) {
      try {
        final outcome = await _photoRepository.batchOperation(
          projectId,
          entry.value,
          operation,
          version: entry.key,
          value: value,
        );
        succeeded.addAll(outcome.succeededIds);
        failed.addAll(outcome.failed);
        queued = queued || outcome.queued;
      } catch (_) {
        failed.addEntries(
          entry.value.map(
            (id) => MapEntry(id, '批量操作失败，请刷新后重试'),
          ),
        );
      }
    }

    return BatchOperationOutcome(
      succeededIds: succeeded.toSet().toList(growable: false),
      failed: failed,
      queued: queued,
    );
  }
}
