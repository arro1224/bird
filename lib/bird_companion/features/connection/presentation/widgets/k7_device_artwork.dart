import 'package:flutter/material.dart';

class K7DeviceArtwork extends StatelessWidget {
  const K7DeviceArtwork({super.key, this.size = 120});

  static const asset = 'assets/bird_companion/connection/k7_front.png';

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    semanticLabel: '拍鸟伴侣 K7 设备',
  );
}
