import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class FeaturePill extends StatelessWidget {
  final String label;
  final IconData? icon;

  const FeaturePill({super.key, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.tealAccent),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTheme.caption.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
