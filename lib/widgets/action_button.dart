import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback? onPressed;

  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.isActive = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? AppColors.primaryWarm : AppColors.surface,
          foregroundColor: isActive
              ? AppColors.background
              : AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: isActive
                ? BorderSide.none
                : const BorderSide(color: AppColors.surfaceLight),
          ),
          textStyle: AppTheme.subtitle,
        ),
      ),
    );
  }
}
