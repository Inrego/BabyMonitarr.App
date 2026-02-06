import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class ThemeCard extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final bool isSelected;
  final VoidCallback? onTap;

  const ThemeCard({
    super.key,
    required this.label,
    required this.colors,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: AppColors.primaryWarm, width: 2)
              : Border.all(color: AppColors.surfaceLight, width: 1),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: colors
                  .map((c) => Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTheme.caption.copyWith(
                color: isSelected
                    ? AppColors.primaryWarm
                    : AppColors.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 2),
              const Icon(Icons.check_circle,
                  size: 14, color: AppColors.primaryWarm),
            ],
          ],
        ),
      ),
    );
  }
}
