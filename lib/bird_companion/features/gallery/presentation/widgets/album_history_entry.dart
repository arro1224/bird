import 'package:aves/bird_companion/app/app_router.dart';
import 'package:flutter/material.dart';

void openAlbumHistory(BuildContext context) {
  Navigator.of(context).pushNamed(BirdRoutes.batches);
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
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('album-history-secondary-button'),
    onPressed: () => openAlbumHistory(context),
    icon: const Icon(Icons.history_rounded, size: 20),
    label: const Text('查看全部拍摄记录'),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 14),
    ),
  );
}
