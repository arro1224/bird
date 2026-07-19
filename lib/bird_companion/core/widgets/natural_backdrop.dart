import 'dart:math' as math;

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Lightweight, resolution-independent decoration inspired by the supplied
/// wetland references. It keeps the UI offline-safe and avoids a raster asset
/// or SVG runtime dependency.
class NaturalBackdrop extends StatelessWidget {
  const NaturalBackdrop({super.key, required this.child, this.dense = false});

  final Widget child;
  final bool dense;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
      IgnorePointer(
        child: CustomPaint(painter: _WetlandPainter(dense: dense)),
      ),
      child,
    ],
  );
}

class _WetlandPainter extends CustomPainter {
  const _WetlandPainter({required this.dense});

  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final grain = Paint()..color = AppColors.brandDark.withValues(alpha: .018);
    var seed = 7319;
    for (var index = 0; index < (dense ? 240 : 150); index++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final x = (seed % 10000) / 10000 * size.width;
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final y = (seed % 10000) / 10000 * size.height;
      canvas.drawCircle(Offset(x, y), .45, grain);
    }

    final nature = Paint()
      ..color = AppColors.brandSoft.withValues(alpha: dense ? .12 : .075)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    _drawReeds(canvas, size, nature);
    _drawBird(canvas, Offset(size.width * .70, size.height * .07), 17, nature);
    _drawBird(canvas, Offset(size.width * .82, size.height * .105), 10, nature);
    _drawBird(canvas, Offset(size.width * .61, size.height * .12), 8, nature);

    final water = Paint()
      ..color = AppColors.brandSoft.withValues(alpha: .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final base = math.min(size.height * .28, 230.0);
    for (var index = 0; index < 4; index++) {
      final y = base + index * 6;
      canvas.drawArc(Rect.fromCenter(center: Offset(size.width * .50, y), width: size.width * (.48 + index * .08), height: 8), 0, math.pi, false, water);
    }
  }

  void _drawReeds(Canvas canvas, Size size, Paint paint) {
    final base = math.min(size.height * .30, 250.0);
    for (var side = 0; side < 2; side++) {
      final origin = side == 0 ? 0.0 : size.width;
      final direction = side == 0 ? 1.0 : -1.0;
      for (var index = 0; index < 11; index++) {
        final x = origin + direction * (7 + index * 6.5);
        final height = 34.0 + (index % 4) * 13;
        final top = Offset(x + direction * (index.isEven ? 8 : -2), base - height);
        canvas.drawLine(Offset(x, base), top, paint);
        canvas.drawLine(top, top.translate(direction * 7, -5), paint);
        canvas.drawLine(top.translate(0, 9), top.translate(-direction * 6, 3), paint);
      }
    }
  }

  void _drawBird(Canvas canvas, Offset center, double width, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - width, center.dy)
      ..quadraticBezierTo(center.dx - width * .42, center.dy - width * .34, center.dx, center.dy)
      ..quadraticBezierTo(center.dx + width * .42, center.dy - width * .34, center.dx + width, center.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WetlandPainter oldDelegate) => oldDelegate.dense != dense;
}
