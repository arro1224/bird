import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/core/widgets/navigation_guard.dart';
import 'package:flutter/material.dart';

void openAlbumHistory(BuildContext context) {
  guardBirdNavigation(context, () => Navigator.of(context).pushNamed(BirdRoutes.batches));
}

class AlbumHistoryAppBarAction extends StatelessWidget {
  const AlbumHistoryAppBarAction({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('album-history-appbar-button'),
    label: '拍摄记录',
    button: true,
    onTap: () => openAlbumHistory(context),
    child: ExcludeSemantics(
      child: IconButton(
        tooltip: '拍摄记录',
        onPressed: () => openAlbumHistory(context),
        icon: const Icon(Icons.history_rounded),
      ),
    ),
  );
}

class AlbumHistorySecondaryAction extends StatelessWidget {
  const AlbumHistorySecondaryAction({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('album-history-secondary-button'),
    onPressed: () => openAlbumHistory(context),
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.only(left: 4),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text('查看全部拍摄记录', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Icon(Icons.chevron_right_rounded, size: 18),
      ],
    ),
  );
}
