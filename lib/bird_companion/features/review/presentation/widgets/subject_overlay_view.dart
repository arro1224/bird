import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/files/media_cache_identity.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class SubjectOverlayView extends StatelessWidget {
  const SubjectOverlayView({super.key, required this.photo, required this.subjects});
  final PhotoDetail photo;
  final List<SubjectBox> subjects;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Keep the approved near-square review viewport on every camera format.
      // The original dimensions still drive cache decoding below.
      final naturalHeight = constraints.maxWidth / 1.22;
      // Do not use the original camera resolution as physical widget height.
      // A capped responsive preview keeps the review controls reachable on a
      // 390×844 phone as well as on larger Android screens.
      final height = naturalHeight.clamp(240.0, 360.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo.summary.preview.previewUri?.toString().isNotEmpty == true)
                CachedNetworkImage(
                  imageUrl: photo.summary.preview.previewUri.toString(),
                  cacheKey: mediaCacheIdentity(
                    uri: photo.summary.preview.previewUri!,
                    mediaId: photo.summary.id,
                    variant: 'preview',
                  ),
                  fit: BoxFit.cover,
                  memCacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(320, 1440),
                  memCacheHeight: (height * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(240, 1080),
                  placeholder: (_, _) => const ColoredBox(
                    color: Color(0xffdfe7d8),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, _, _) => const ColoredBox(color: Color(0xff24352d)),
                )
              else
                const ColoredBox(color: Color(0xff24352d)),
              for (final subject in subjects)
                Positioned(
                  left: subject.x * constraints.maxWidth,
                  top: subject.y * height,
                  width: subject.width * constraints.maxWidth,
                  height: subject.height * height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.lightGreenAccent, width: 2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
