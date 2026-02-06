import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class LiveIndicator extends StatefulWidget {
  final bool isLive;

  const LiveIndicator({super.key, this.isLive = true});

  @override
  State<LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isLive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(LiveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isLive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLive) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.liveRed.withValues(alpha: _opacityAnimation.value),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'LIVE',
              style: AppTheme.caption.copyWith(
                color: AppColors.liveRed,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        );
      },
    );
  }
}
