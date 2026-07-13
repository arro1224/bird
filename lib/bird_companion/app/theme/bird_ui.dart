import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class BirdConnectionLine extends StatelessWidget {
  const BirdConnectionLine({super.key, this.label = '本地连接稳定'});
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.circle, color: Color(0xFF278165), size: 13),
      const SizedBox(width: 7),
      Text(
        label,
        style: const TextStyle(color: Color(0xFF278165), fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class BirdPill extends StatelessWidget {
  const BirdPill({super.key, required this.label, this.color = AppColors.brandLight, this.textColor = AppColors.brand});
  final String label;
  final Color color, textColor;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class BirdSectionTitle extends StatelessWidget {
  const BirdSectionTitle({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
}
