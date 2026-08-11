import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_asset_catalog.dart';
import 'package:flutter/material.dart';

class BirdSettingsAtmosphere extends StatelessWidget {
  const BirdSettingsAtmosphere({super.key, this.home = false});

  final bool home;

  @override
  Widget build(BuildContext context) => Stack(
    key: Key(home ? 'v1-device-background' : 'v1-settings-background'),
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: AppColors.paperStrong),
      Opacity(
        opacity: .34,
        child: Image.asset(
          BirdAssetCatalog.paper,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
      Positioned.fill(
        child: Opacity(
          opacity: home ? .24 : .16,
          child: Image.asset(
            BirdAssetCatalog.mountains,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
      ),
      Positioned(
        top: home ? 104 : 92,
        right: -38,
        width: 184,
        height: 430,
        child: Opacity(
          opacity: home ? .18 : .13,
          child: Image.asset(
            BirdAssetCatalog.reedsRight,
            fit: BoxFit.contain,
            alignment: Alignment.topRight,
          ),
        ),
      ),
      Positioned(
        left: -46,
        bottom: -24,
        width: 190,
        height: 470,
        child: Opacity(
          opacity: home ? .16 : .11,
          child: Image.asset(
            BirdAssetCatalog.reedsLeft,
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
          ),
        ),
      ),
      if (home) ...[
        Positioned(
          top: 102,
          right: 74,
          width: 30,
          height: 22,
          child: Opacity(
            opacity: .22,
            child: Image.asset(BirdAssetCatalog.birdGliding),
          ),
        ),
        Positioned(
          top: 124,
          right: 132,
          width: 24,
          height: 18,
          child: Opacity(
            opacity: .16,
            child: Image.asset(BirdAssetCatalog.birdAscending),
          ),
        ),
      ],
    ],
  );
}

class BirdDeviceLineArt extends StatelessWidget {
  const BirdDeviceLineArt({super.key, this.size = 92});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '拍鸟伴侣 K7 设备',
    child: CustomPaint(
      key: const Key('v1-device-illustration'),
      size: Size(size * .78, size),
      painter: _BirdDeviceLineArtPainter(),
    ),
  );
}

class _BirdDeviceLineArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 72;
    final stroke = 2.25 * scale;
    final paint = Paint()
      ..color = AppColors.forestPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = AppColors.forestPrimary
      ..style = PaintingStyle.fill;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .19, size.height * .14, size.width * .61, size.height * .68),
      Radius.circular(size.width * .1),
    );
    canvas.drawRRect(body, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .25, size.height * .2, size.width * .48, size.height * .57),
        Radius.circular(size.width * .07),
      ),
      paint,
    );

    final lensCenter = Offset(size.width * .49, size.height * .34);
    canvas.drawCircle(lensCenter, size.width * .13, paint);
    canvas.drawCircle(lensCenter, size.width * .055, paint);
    canvas.drawCircle(lensCenter, size.width * .021, fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .49, size.height * .5),
          width: size.width * .14,
          height: size.width * .14,
        ),
        Radius.circular(size.width * .025),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .3, size.height * .59, size.width * .38, size.height * .14),
        Radius.circular(size.width * .035),
      ),
      paint,
    );

    canvas.drawLine(Offset(size.width * .14, size.height * .22), Offset(size.width * .14, size.height * .68), paint);
    canvas.drawLine(Offset(size.width * .1, size.height * .08), Offset(size.width * .1, size.height * .63), paint);
    canvas.drawLine(Offset(size.width * .1, size.height * .63), Offset(size.width * .19, size.height * .68), paint);
    canvas.drawLine(Offset(size.width * .8, size.height * .28), Offset(size.width * .87, size.height * .31), paint);
    canvas.drawLine(Offset(size.width * .87, size.height * .31), Offset(size.width * .87, size.height * .49), paint);
    canvas.drawLine(Offset(size.width * .8, size.height * .53), Offset(size.width * .87, size.height * .56), paint);
    canvas.drawLine(Offset(size.width * .87, size.height * .56), Offset(size.width * .87, size.height * .69), paint);

    canvas.drawLine(Offset(size.width * .36, size.height * .82), Offset(size.width * .36, size.height * .88), paint);
    canvas.drawLine(Offset(size.width * .63, size.height * .82), Offset(size.width * .63, size.height * .88), paint);
    canvas.drawLine(Offset(size.width * .22, size.height * .88), Offset(size.width * .77, size.height * .88), paint);
    canvas.drawLine(Offset(size.width * .13, size.height * .94), Offset(size.width * .86, size.height * .94), paint);
    canvas.drawLine(Offset(size.width * .22, size.height * .88), Offset(size.width * .13, size.height * .94), paint);
    canvas.drawLine(Offset(size.width * .77, size.height * .88), Offset(size.width * .86, size.height * .94), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
