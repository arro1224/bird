import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class ConnectionBackground extends StatelessWidget {
  const ConnectionBackground({super.key, required this.child});

  static const wetlandAsset = 'assets/bird_companion/connection/wetland_background.png';

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: AppColors.paper),
      ExcludeSemantics(
        child: Opacity(
          opacity: .58,
          child: Image.asset(
            wetlandAsset,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEFFFFDF8), Color(0x45FFFDF8), Color(0x12FFFDF8)],
            stops: [0, .38, 1],
          ),
        ),
      ),
      child,
    ],
  );
}
