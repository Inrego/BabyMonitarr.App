import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class BackgroundRestrictionCard extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const BackgroundRestrictionCard({super.key, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondaryWarm.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.battery_alert_outlined,
                color: AppColors.secondaryWarm,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Background usage is restricted',
                  style: AppTheme.subtitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your phone may pause BabyMonitarr while the screen is off, '
            'which silences audio overnight. Allow background usage to keep '
            'monitoring running.',
            style: AppTheme.caption.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onOpenSettings,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryWarm,
                foregroundColor: AppColors.background,
              ),
              child: const Text('Open settings'),
            ),
          ),
        ],
      ),
    );
  }
}
