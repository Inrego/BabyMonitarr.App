import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class MonitorAddressField extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  const MonitorAddressField({
    super.key,
    required this.controller,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Monitor Address',
            style: AppTheme.caption.copyWith(color: AppColors.primaryWarm)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitted?.call(),
          style: AppTheme.body.copyWith(color: AppColors.textPrimary),
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'e.g., http://babymonitor.local',
            hintStyle: AppTheme.body
                .copyWith(color: AppColors.textSecondary.withValues(alpha: 0.5)),
            filled: true,
            fillColor: AppColors.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.surfaceLight, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primaryWarm, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.liveRed, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.liveRed, width: 1.5),
            ),
            errorText: errorText,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            prefixIcon: const Icon(Icons.link, color: AppColors.primaryWarm),
          ),
        ),
      ],
    );
  }
}
