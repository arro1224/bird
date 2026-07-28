import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:flutter/material.dart';

typedef PhotoMasonryItemBuilder =
    Widget Function(
      BuildContext context,
      PhotoSummary photo,
      int index,
    );

/// A lazy three-column photo sliver with a stable, uniform tile height.
class PhotoMasonryGrid extends StatelessWidget {
  const PhotoMasonryGrid({
    super.key,
    required this.photos,
    required this.itemBuilder,
    this.crossAxisCount = 3,
    this.spacing = 6,
    this.itemAspectRatio = .78,
  });

  final List<PhotoSummary> photos;
  final PhotoMasonryItemBuilder itemBuilder;
  final int crossAxisCount;
  final double spacing;
  final double itemAspectRatio;

  @override
  Widget build(BuildContext context) => SliverGrid.builder(
    key: const ValueKey('photo-masonry-grid'),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: itemAspectRatio,
    ),
    itemCount: photos.length,
    itemBuilder: (context, index) {
      final photo = photos[index];
      return KeyedSubtree(
        key: ValueKey('photo-masonry-item-${photo.id}'),
        child: itemBuilder(context, photo, index),
      );
    },
  );
}
