import 'package:aves/bird_companion/app/theme/bird_asset_catalog.dart';
import 'package:flutter/material.dart';

class TaskNatureBackground extends StatelessWidget {
  const TaskNatureBackground({
    super.key,
    this.reedOpacity = .38,
    this.mountainOpacity = .68,
    this.showTopBirds = true,
    this.showBottomReeds = true,
  });

  final double reedOpacity;
  final double mountainOpacity;
  final bool showTopBirds;
  final bool showBottomReeds;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Opacity(
        key: const Key('task-paper-texture-layer'),
        opacity: .9,
        child: Image.asset(BirdAssetCatalog.paper, fit: BoxFit.cover),
      ),
      Align(
        alignment: const Alignment(0, -.22),
        child: Opacity(
          key: const Key('task-ink-mountain-layer'),
          opacity: mountainOpacity,
          child: Image.asset(
            BirdAssetCatalog.mountains,
            width: MediaQuery.sizeOf(context).width * 1.85,
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
      if (showTopBirds) ...[
        Positioned(
          left: 34,
          top: 118,
          width: 44,
          child: Opacity(opacity: .22, child: Image.asset(BirdAssetCatalog.birdAscending)),
        ),
        Positioned(
          right: 60,
          top: 126,
          width: 60,
          child: Opacity(opacity: .24, child: Image.asset(BirdAssetCatalog.birdGliding)),
        ),
      ],
      if (showBottomReeds) ...[
        Positioned(
          key: const Key('task-reeds-right-layer'),
          right: -42,
          top: 76,
          width: 190,
          height: 390,
          child: Opacity(
            opacity: reedOpacity,
            child: Image.asset(BirdAssetCatalog.reedsRight, fit: BoxFit.contain),
          ),
        ),
        Positioned(
          key: const Key('task-reeds-left-layer'),
          left: -46,
          bottom: -18,
          width: 190,
          height: 390,
          child: Opacity(
            opacity: reedOpacity,
            child: Image.asset(BirdAssetCatalog.reedsLeft, fit: BoxFit.contain),
          ),
        ),
      ],
    ],
  );
}
