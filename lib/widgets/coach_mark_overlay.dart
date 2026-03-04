import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class CoachMarkOverlay {
  static OverlayEntry? _entry;

  static void show({
    required BuildContext context,
    required GlobalKey targetKey,
    required String title,
    required String message,
    required VoidCallback onDismiss,
  }) {
    final renderBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final targetPosition = renderBox.localToGlobal(Offset.zero);
    final targetSize = renderBox.size;

    _entry = OverlayEntry(
      builder: (context) => _CoachMarkWidget(
        targetPosition: targetPosition,
        targetSize: targetSize,
        title: title,
        message: message,
        onDismiss: () {
          _entry?.remove();
          _entry = null;
          onDismiss();
        },
      ),
    );

    Overlay.of(context).insert(_entry!);
  }

  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _CoachMarkWidget extends StatelessWidget {
  final Offset targetPosition;
  final Size targetSize;
  final String title;
  final String message;
  final VoidCallback onDismiss;

  const _CoachMarkWidget({
    required this.targetPosition,
    required this.targetSize,
    required this.title,
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tooltipTop = targetPosition.dy + targetSize.height + 12;

    return GestureDetector(
      onTap: onDismiss,
      child: Material(
        color: Colors.black54,
        child: Stack(
          children: [
            // Highlight border around target
            Positioned(
              left: targetPosition.dx - 4,
              top: targetPosition.dy - 4,
              child: Container(
                width: targetSize.width + 8,
                height: targetSize.height + 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primaryWarm, width: 2),
                ),
              ),
            ),
            // Tooltip bubble
            Positioned(
              right: 16,
              top: tooltipTop,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primaryWarm.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb,
                            size: 18, color: AppColors.primaryWarm),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: AppTheme.subtitle.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: AppTheme.caption.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Tap anywhere to dismiss',
                        style: AppTheme.caption.copyWith(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
