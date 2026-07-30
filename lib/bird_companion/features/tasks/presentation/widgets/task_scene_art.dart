import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class TaskSuccessBadge extends StatelessWidget {
  const TaskSuccessBadge({super.key, this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.forestPrimary,
      border: Border.all(color: Colors.white.withValues(alpha: .92), width: 8),
      boxShadow: const [
        BoxShadow(
          color: Color(0x260E351D),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Icon(Icons.check_rounded, color: Colors.white, size: size * .58),
  );
}

class TaskExternalDriveArt extends StatelessWidget {
  const TaskExternalDriveArt({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('copy-target-drive-icon'),
    width: size,
    height: size * 1.06,
    child: CustomPaint(painter: _DrivePainter()),
  );
}

class TaskSdCardArt extends StatelessWidget {
  const TaskSdCardArt({super.key, this.checked = false, this.dimmed = false});

  final bool checked;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 200,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.forestSoft.withValues(alpha: dimmed ? .16 : .26),
          ),
        ),
        CustomPaint(
          size: const Size(118, 150),
          painter: _SdCardPainter(dimmed: dimmed),
        ),
        if (checked)
          const Positioned(
            right: 92,
            bottom: 18,
            child: TaskSuccessBadge(size: 64),
          ),
      ],
    ),
  );
}

class TaskEmptyBoxArt extends StatelessWidget {
  const TaskEmptyBoxArt({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    child: Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          top: 6,
          child: Icon(
            Icons.sd_card_rounded,
            size: 106,
            color: AppColors.forestPrimary.withValues(alpha: .62),
          ),
        ),
        Container(
          width: 190,
          height: 128,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: AppColors.forestDeep.withValues(alpha: .78),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x220E351D),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.camera_alt_outlined, color: AppColors.cream, size: 62),
        ),
      ],
    ),
  );
}

class _DrivePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bodyRect = Rect.fromLTWH(
      size.width * .14,
      size.height * .04,
      size.width * .72,
      size.height * .90,
    );
    final body = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(size.width * .14),
    );
    final bodyPath = Path()..addRRect(body);
    canvas.drawShadow(bodyPath, const Color(0x240E351D), 4, false);

    final bodyFill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFEAF0E5)],
      ).createShader(bodyRect);
    final outline = Paint()
      ..color = AppColors.forestDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(body, bodyFill);
    canvas.drawRRect(body, outline);

    final inset = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .25,
        size.height * .16,
        size.width * .50,
        size.height * .48,
      ),
      Radius.circular(size.width * .07),
    );
    canvas.drawRRect(inset, Paint()..color = const Color(0xFFDCE8D6));
    canvas.drawRRect(
      inset,
      Paint()
        ..color = const Color(0xFF9AB28E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final port = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .36,
        size.height * .79,
        size.width * .28,
        size.height * .065,
      ),
      Radius.circular(size.width * .025),
    );
    canvas.drawRRect(port, Paint()..color = AppColors.forestDeep);
    canvas.drawCircle(
      Offset(size.width * .72, size.height * .82),
      size.width * .025,
      Paint()..color = const Color(0xFF73A34D),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SdCardPainter extends CustomPainter {
  const _SdCardPainter({required this.dimmed});

  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final color = dimmed ? const Color(0xFF7E887A) : AppColors.forestPrimary;
    final path = Path()
      ..moveTo(size.width * .18, 0)
      ..lineTo(size.width * .88, 0)
      ..quadraticBezierTo(size.width, 0, size.width, size.width * .12)
      ..lineTo(size.width, size.height * .92)
      ..quadraticBezierTo(size.width, size.height, size.width * .88, size.height)
      ..lineTo(size.width * .12, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height * .88)
      ..lineTo(0, size.height * .18)
      ..close();
    canvas.drawShadow(path, const Color(0x330E351D), 10, false);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: dimmed ? .42 : .96));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final slotPaint = Paint()..color = AppColors.cream.withValues(alpha: dimmed ? .65 : .92);
    for (var i = 0; i < 6; i++) {
      final rect = Rect.fromLTWH(
        size.width * (.26 + i * .095),
        size.height * .09,
        size.width * .055,
        size.height * .17,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        slotPaint,
      );
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'SD',
        style: TextStyle(
          color: AppColors.cream,
          fontSize: size.width * .34,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, size.height * .45),
    );
  }

  @override
  bool shouldRepaint(covariant _SdCardPainter oldDelegate) => oldDelegate.dimmed != dimmed;
}
