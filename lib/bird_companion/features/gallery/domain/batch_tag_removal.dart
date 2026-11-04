import 'dart:convert';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/tag_input.dart';

class BatchTagRemoval {
  const BatchTagRemoval({required this.photos, required this.tags});

  final List<PhotoSummary> photos;
  final List<String> tags;

  // Group by the tags actually present, so undo never adds a tag to a photo
  // that did not originally have it.
  List<BatchTagRemovalGroup> get groups {
    final groups = <String, BatchTagRemovalGroup>{};
    for (final photo in photos) {
      final removed = normalizeUserTags(photo.userTags).where(tags.contains).toList()..sort();
      if (removed.isEmpty) continue;
      final key = jsonEncode(removed);
      groups.putIfAbsent(key, () => BatchTagRemovalGroup(tags: removed)).ids.add(photo.id);
    }
    return groups.values.toList();
  }
}

class BatchTagRemovalGroup {
  BatchTagRemovalGroup({required this.tags});
  final List<String> tags;
  final List<String> ids = [];
}
