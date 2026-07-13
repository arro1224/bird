import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class GroupPhotoStrip extends StatelessWidget {
  const GroupPhotoStrip({super.key, required this.group, required this.onOpen});
  final BirdGroup group;
  final ValueChanged<String> onOpen;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 92,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: group.memberFileIds.length,
      itemBuilder: (context, index) {
        final id = group.memberFileIds[index];
        final matches = group.members.where((photo) => photo.id == id);
        final photo = matches.isEmpty ? null : matches.first;
        final url = photo?.preview.thumbnailUri?.toString();
        return InkWell(
          onTap: () => onOpen(id),
          child: Container(
            width: 82,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: index < 3 ? Colors.green : Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url?.isNotEmpty == true)
                  CachedNetworkImage(
                    imageUrl: url!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xffdfe9e1)),
                  )
                else
                  const ColoredBox(color: Color(0xffdfe9e1)),
                Positioned(
                  left: 4,
                  top: 4,
                  child: CircleAvatar(radius: 10, child: Text('${index + 1}', style: const TextStyle(fontSize: 10))),
                ),
                Positioned(
                  left: 3,
                  right: 3,
                  bottom: 3,
                  child: Text(
                    photo?.filename ?? id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Colors.white, shadows: [Shadow(blurRadius: 3)]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
