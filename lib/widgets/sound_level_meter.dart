import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../models/audio_state.dart';

class SoundLevelMeter extends StatefulWidget {
  final double level;
  final SoundStatus status;

  const SoundLevelMeter({super.key, required this.level, required this.status});

  @override
  State<SoundLevelMeter> createState() => _SoundLevelMeterState();
}

class _SoundLevelMeterState extends State<SoundLevelMeter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _arcAnimation;
  double _previousLevel = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _arcAnimation = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(SoundLevelMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      _arcAnimation = Tween<double>(
        begin: _previousLevel,
        end: widget.level.clamp(0, 100),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _previousLevel = widget.level.clamp(0, 100);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _arcColor {
    switch (widget.status) {
      case SoundStatus.quiet:
        return AppColors.tealAccent;
      case SoundStatus.moderate:
        return AppColors.primaryWarm;
      case SoundStatus.active:
        return AppColors.secondaryWarm;
      case SoundStatus.alert:
        return AppColors.liveRed;
    }
  }

  String get _statusText {
    switch (widget.status) {
      case SoundStatus.quiet:
        return 'Quiet';
      case SoundStatus.moderate:
        return 'Moderate';
      case SoundStatus.active:
        return 'Active';
      case SoundStatus.alert:
        return 'Alert!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _arcAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 220,
          height: 220,
          child: CustomPaint(
            painter: _MeterPainter(
              level: _arcAnimation.value,
              arcColor: _arcColor,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.level.toStringAsFixed(0),
                    style: AppTheme.display.copyWith(
                      color: _arcColor,
                      fontSize: 48,
                    ),
                  ),
                  Text('dB', style: AppTheme.caption),
                  const SizedBox(height: 4),
                  Text(
                    _statusText,
                    style: AppTheme.caption.copyWith(
                      color: _arcColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double level;
  final Color arcColor;

  _MeterPainter({required this.level, required this.arcColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const startAngle = 0.75 * pi;
    const sweepTotal = 1.5 * pi;

    // Background arc
    final bgPaint = Paint()
      ..color = AppColors.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      bgPaint,
    );

    // Level arc
    if (level > 0) {
      final sweepAngle = (level / 100) * sweepTotal;
      final levelPaint = Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        levelPaint,
      );
    }

    // Tick marks
    final tickPaint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (int i = 0; i <= 10; i++) {
      final angle = startAngle + (i / 10) * sweepTotal;
      final outerPoint = Offset(
        center.dx + cos(angle) * (radius + 6),
        center.dy + sin(angle) * (radius + 6),
      );
      final innerPoint = Offset(
        center.dx + cos(angle) * (radius - 2),
        center.dy + sin(angle) * (radius - 2),
      );
      canvas.drawLine(innerPoint, outerPoint, tickPaint);
    }
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.arcColor != arcColor;
}
