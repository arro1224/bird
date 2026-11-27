import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_local_filter_engine.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';

/// A read-only projection. Neither cached facts nor durable write intents change.
class PhotoCachedQuery {
  const PhotoCachedQuery(this.cache, this.operations, this.namespace, this.deviceId, this.projectId);
  final LocalCache cache;
  final List<PendingOperation> operations;
  final String namespace, projectId;
  final String? deviceId;
  static const cursorPrefix = 'cache-v1-';

  List<PendingOperation> get scopedOperations => operations
      .where((op) => deviceId != null && op.deviceId == deviceId && op.projectId == projectId && op.status != PendingOperationStatus.conflict && (op.type == PendingOperationType.updateReview || op.type == PendingOperationType.batchReview))
      .toList();

  List<PhotoSummary> project(Iterable<PhotoSummary> photos) {
    final byId = {for (final photo in photos) photo.id: photo};
    for (final op in scopedOperations) {
      for (final id in op.remainingFileIds) {
        final photo = byId[id];
        if (photo == null) continue;
        final fields = <String, dynamic>{...photo.toJson()};
        if (op.type == PendingOperationType.updateReview) {
          for (final field in const ['keep_state', 'user_tags', 'user_species_id', 'user_species', 'user_score']) {
            if (op.payload.containsKey(field)) fields[field] = op.payload[field];
          }
        } else {
          final action = op.payload['operation'];
          if (const {'keep', 'discard', 'pending', 'featured'}.contains(action)) fields['keep_state'] = action;
          if (action == 'add_tags' || action == 'remove_tags') {
            final tags = photo.userTags.toSet();
            final changed = (op.payload['value'] as List? ?? const []).map((tag) => tag.toString());
            action == 'add_tags' ? tags.addAll(changed) : tags.removeAll(changed);
            fields['user_tags'] = tags.toList();
          }
        }
        // Operation.version may be a project CAS. It is never a photo version.
        byId[id] = PhotoSummary.fromJson(fields);
      }
    }
    return byId.values.toList();
  }

  PhotoPage? page(PhotoQuery query) {
    final byId = <String, PhotoSummary>{};
    final times = <String, DateTime?>{};
    DateTime? cachedAt;
    var foundSnapshot = false;
    void collect(Map raw) {
      foundSnapshot = true; // A cached empty result is still useful evidence.
      final savedAt = DateTime.tryParse(raw['cached_at']?.toString() ?? '');
      if (savedAt != null && (cachedAt == null || savedAt.isAfter(cachedAt!))) cachedAt = savedAt;
      for (final item in (raw['items'] as List? ?? const []).whereType<Map>()) {
        final photo = PhotoSummary.fromJson(Map<String, dynamic>.from(item));
        final previous = byId[photo.id];
        final previousTime = times[photo.id];
        if (previous != null) {
          // Prefer newer photo facts, then cache time. A null version is an
          // explicit invalidation and must not regain an old optimistic value.
          if (previous.version != null && photo.version != null && previous.version! > photo.version!) continue;
          if (previousTime != null && (savedAt == null || savedAt.isBefore(previousTime)) && (photo.version ?? -1) <= (previous.version ?? -1)) continue;
        }
        byId[photo.id] = photo;
        times[photo.id] = savedAt;
      }
    }

    for (final prefix in ['album:query-candidates:$namespace:$projectId:', 'album:photos:$namespace:$projectId:']) {
      for (final key in cache.keysWithPrefix(prefix)) {
        final raw = cache.read<Map>(key);
        if (raw != null) collect(raw);
      }
    }
    if (!foundSnapshot) return null;
    for (final id in byId.keys.toList()) {
      final detail = cache.read<Map>('album:detail:$namespace:$id');
      final file = detail?['file'];
      if (file is! Map) continue;
      final photo = PhotoSummary.fromJson(Map<String, dynamic>.from(file));
      if (photo.id != id) continue;
      final previous = byId[id]!;
      if (photo.version != null && previous.version != null && photo.version! < previous.version!) continue;
      byId[id] = photo;
    }
    final known = project(byId.values);
    const engine = PhotoLocalFilterEngine();
    final items = engine.filterAndSort(known, query);
    final offset = query.cursor?.startsWith(cursorPrefix) == true ? int.tryParse(query.cursor!.substring(cursorPrefix.length)) ?? 0 : 0;
    final start = offset.clamp(0, items.length), end = (offset.clamp(0, items.length) + query.pageSize).clamp(0, items.length);
    return PhotoPage(
      items: items.sublist(start, end),
      hasMore: end < items.length,
      nextCursor: end < items.length ? '$cursorPrefix$end' : null,
      fromCache: true,
      cachedAt: cachedAt,
      // Filtered or historical snapshots do not prove a complete project.
      resultComplete: false,
      cacheScope: PhotoCacheScope.partial,
      scannedCount: known.length,
      matchedCount: items.length,
      cachedCounts: PhotoCachedCounts(
        recognized: engine.countMatches(known, const PhotoQuery(recognitionState: 'recognized')),
        needsReview: engine.countMatches(known, const PhotoQuery(recognitionState: 'needs_review')),
        filtered: engine.countMatches(known, const PhotoQuery(analysisState: 'skipped')),
        kept: engine.countMatches(known, const PhotoQuery(keepState: 'keep')),
        discarded: engine.countMatches(known, const PhotoQuery(keepState: 'discard')),
      ),
    );
  }
}
