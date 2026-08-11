import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/files/media_cache_identity.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class SubjectOverlayView extends StatelessWidget {
  const SubjectOverlayView({
    super.key,
    required this.photo,
    required this.subjects,
    this.onPrevious,
    this.onNext,
    this.navigationEnabled = true,
  });

  final PhotoDetail photo;
  final List<SubjectBox> subjects;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool navigationEnabled;

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
              for (var subjectIndex = 0; subjectIndex < subjects.length; subjectIndex++)
                Positioned(
                  left: subjects[subjectIndex].x * constraints.maxWidth,
                  top: subjects[subjectIndex].y * height,
                  width: subjects[subjectIndex].width * constraints.maxWidth,
                  height: subjects[subjectIndex].height * height,
                  child: DecoratedBox(
                    key: ValueKey('subject-box-$subjectIndex'),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.lightGreenAccent, width: 2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              if (onPrevious != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _PhotoNavigationButton(
                      key: const ValueKey('photo-previous-button'),
                      icon: Icons.chevron_left_rounded,
                      tooltip: '上一张',
                      enabled: navigationEnabled,
                      onPressed: onPrevious!,
                    ),
                  ),
                ),
              if (onNext != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _PhotoNavigationButton(
                      key: const ValueKey('photo-next-button'),
                      icon: Icons.chevron_right_rounded,
                      tooltip: '下一张',
                      enabled: navigationEnabled,
                      onPressed: onNext!,
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

class _PhotoNavigationButton extends StatelessWidget {
  const _PhotoNavigationButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.paperStrong.withValues(alpha: enabled ? .52 : .30),
      shape: BoxShape.circle,
    ),
    child: IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      color: AppColors.inkMuted,
      disabledColor: AppColors.inkMuted.withValues(alpha: .42),
      iconSize: 40,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 52, height: 52),
      icon: Icon(icon),
    ),
  );
}
