import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../models/audio_state.dart';

class StatusPill extends StatelessWidget {
  final AlertState alertState;

  const StatusPill({super.key, required this.alertState});

  @override
  Widget build(BuildContext context) {
    final isAlerting = alertState == AlertState.alerting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isAlerting
            ? AppColors.liveRed.withValues(alpha: 0.15)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: isAlerting
            ? Border.all(color: AppColors.liveRed.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAlerting ? Icons.warning_amber : Icons.visibility,
            size: 16,
            color: isAlerting ? AppColors.liveRed : AppColors.tealAccent,
          ),
          const SizedBox(width: 8),
          Text(
            isAlerting ? 'Alerts: Active!' : 'Alerts: Watching',
            style: AppTheme.caption.copyWith(
              color: isAlerting ? AppColors.liveRed : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
