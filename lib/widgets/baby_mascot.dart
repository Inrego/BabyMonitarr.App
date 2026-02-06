import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BabyMascot extends StatelessWidget {
  final double size;

  const BabyMascot({super.key, this.size = 200});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BabyMascotPainter(),
      ),
    );
  }
}

class _BabyMascotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2.5;

    // Face circle
    final facePaint = Paint()
      ..color = AppColors.primaryWarm.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, facePaint);

    // Hat
    final hatPaint = Paint()
      ..color = AppColors.tealAccent
      ..style = PaintingStyle.fill;

    final hatPath = Path();
    final hatTop = center.dy - radius * 0.95;
    final hatLeft = center.dx - radius * 0.7;
    final hatRight = center.dx + radius * 0.7;
    final hatBottom = center.dy - radius * 0.3;

    hatPath.moveTo(hatLeft, hatBottom);
    hatPath.quadraticBezierTo(
        center.dx, hatTop - radius * 0.3, hatRight, hatBottom);
    hatPath.close();
    canvas.drawPath(hatPath, hatPaint);

    // Hat brim
    final brimPaint = Paint()
      ..color = AppColors.tealAccent.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(center.dx, hatBottom), width: radius * 1.6, height: radius * 0.3),
      0,
      pi,
      true,
      brimPaint,
    );

    // Eyes
    final eyePaint = Paint()
      ..color = const Color(0xFF2B2B2E)
      ..style = PaintingStyle.fill;

    final leftEye = Offset(center.dx - radius * 0.3, center.dy + radius * 0.05);
    final rightEye = Offset(center.dx + radius * 0.3, center.dy + radius * 0.05);
    canvas.drawCircle(leftEye, radius * 0.08, eyePaint);
    canvas.drawCircle(rightEye, radius * 0.08, eyePaint);

    // Eye highlights
    final highlightPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        leftEye + Offset(radius * 0.02, -radius * 0.02), radius * 0.03, highlightPaint);
    canvas.drawCircle(
        rightEye + Offset(radius * 0.02, -radius * 0.02), radius * 0.03, highlightPaint);

    // Blush circles
    final blushPaint = Paint()
      ..color = AppColors.secondaryWarm.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(center.dx - radius * 0.45, center.dy + radius * 0.25), radius * 0.12, blushPaint);
    canvas.drawCircle(
        Offset(center.dx + radius * 0.45, center.dy + radius * 0.25), radius * 0.12, blushPaint);

    // Smile
    final smilePaint = Paint()
      ..color = const Color(0xFF2B2B2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(center.dx, center.dy + radius * 0.2),
          width: radius * 0.4,
          height: radius * 0.2),
      0.1,
      pi - 0.2,
      false,
      smilePaint,
    );

    // Stars
    _drawStar(canvas, Offset(size.width * 0.1, size.height * 0.15), 6, AppColors.primaryWarm.withValues(alpha: 0.6));
    _drawStar(canvas, Offset(size.width * 0.85, size.height * 0.1), 8, AppColors.tealAccent.withValues(alpha: 0.5));
    _drawStar(canvas, Offset(size.width * 0.9, size.height * 0.35), 5, AppColors.secondaryWarm.withValues(alpha: 0.4));

    // Moon
    final moonPaint = Paint()
      ..color = AppColors.primaryWarm.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.4), 10, moonPaint);
    canvas.drawCircle(
        Offset(size.width * 0.15 + 4, size.height * 0.4 - 2),
        10,
        Paint()..color = AppColors.background);
  }

  void _drawStar(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    for (int i = 0; i < 4; i++) {
      final angle = (i * pi / 2);
      final x = center.dx + cos(angle) * size;
      final y = center.dy + sin(angle) * size;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      final midAngle = angle + pi / 4;
      final mx = center.dx + cos(midAngle) * size * 0.4;
      final my = center.dy + sin(midAngle) * size * 0.4;
      path.lineTo(mx, my);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
