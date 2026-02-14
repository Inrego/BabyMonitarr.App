import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: AppTheme.caption.copyWith(
              color: AppColors.primaryWarm,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsToggleRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.body.copyWith(color: AppColors.textPrimary),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!, style: AppTheme.caption),
                ],
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
