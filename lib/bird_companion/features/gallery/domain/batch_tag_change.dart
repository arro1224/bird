import 'dart:convert';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/tag_input.dart';

class BatchTagChange {
  BatchTagChange.add({required this.photos, required this.tags}) : _remove = false;
  BatchTagChange.remove({required this.photos, required this.tags}) : _remove = true;

  final List<PhotoSummary> photos;
  final List<String> tags;
  final bool _remove;

  // Each group has the same actual changes, so its undo can reverse exactly those changes.
  late final List<BatchTagChangeGroup> groups = _buildGroups();

  List<BatchTagChangeGroup> _buildGroups() {
    final requested = normalizeUserTags(tags);
    if (requested.isEmpty) return const [];
    if (_remove) requested.sort();
    final groups = <String, BatchTagChangeGroup>{};
    for (final photo in photos) {
      final existing = normalizeUserTags(photo.userTags).toSet();
      final changed = requested.where((tag) => existing.contains(tag) == _remove).toList();
      if (changed.isEmpty) continue;
      final key = jsonEncode(changed);
      groups.putIfAbsent(key, () => BatchTagChangeGroup(tags: changed)).photos.add(photo);
    }
    return groups.values.toList();
  }
}

class BatchTagChangeGroup {
  BatchTagChangeGroup({required this.tags});
  final List<String> tags;
  final List<PhotoSummary> photos = [];
  List<String> get ids => photos.map((photo) => photo.id).toList();
}
