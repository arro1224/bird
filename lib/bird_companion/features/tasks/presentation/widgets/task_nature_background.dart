import 'package:aves/bird_companion/app/theme/bird_asset_catalog.dart';
import 'package:flutter/material.dart';

class TaskNatureBackground extends StatelessWidget {
  const TaskNatureBackground({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(BirdAssetCatalog.mountains, fit: BoxFit.cover),
      Opacity(
        opacity: .55,
        child: Image.asset(BirdAssetCatalog.paper, fit: BoxFit.cover),
      ),
      Positioned(
        left: 38,
        top: 140,
        width: 44,
        child: Opacity(opacity: .34, child: Image.asset(BirdAssetCatalog.birdAscending)),
      ),
      Positioned(
        right: 64,
        top: 150,
        width: 58,
        child: Opacity(opacity: .32, child: Image.asset(BirdAssetCatalog.birdGliding)),
      ),
      Positioned(
        right: -30,
        top: 80,
        width: 180,
        height: 360,
        child: Opacity(
          opacity: .38,
          child: Image.asset(BirdAssetCatalog.reedsRight),
        ),
      ),
      Positioned(
        left: -38,
        bottom: 10,
        width: 180,
        height: 350,
        child: Opacity(
          opacity: .42,
          child: Image.asset(BirdAssetCatalog.reedsLeft),
        ),
      ),
    ],
  );
}
