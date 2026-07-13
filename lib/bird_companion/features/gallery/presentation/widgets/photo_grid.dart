import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:flutter/material.dart';

class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.items, required this.selectedIds, required this.onTap, required this.onToggle, required this.loading, required this.hasMore});
  final List<PhotoSummary> items;
  final Set<String> selectedIds;
  final ValueChanged<PhotoSummary> onTap, onToggle;
  final bool loading, hasMore;
  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    itemCount: items.length + (loading || hasMore ? 1 : 0),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: .72),
    itemBuilder: (context, index) {
      if (index >= items.length) return Center(child: loading ? const CircularProgressIndicator() : const SizedBox.shrink());
      final photo = items[index];
      return PhotoTile(photo: photo, selected: selectedIds.contains(photo.id), onTap: () => onTap(photo), onLongPress: () => onToggle(photo));
    },
  );
}
