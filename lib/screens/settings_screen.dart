import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/connection_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/theme_card.dart';
import '../widgets/server_url_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings', style: AppTheme.subtitle),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              // Appearance section
              SettingsSection(
                title: 'APPEARANCE',
                children: [
                  SettingsToggleRow(
                    label: 'Dark Mode',
                    value: settings.settings.darkModeEnabled,
                    onChanged: (v) => settings.setDarkMode(v),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Theme section
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'THEME',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.primaryWarm,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ThemeCard(
                    label: 'Warm',
                    colors: const [
                      AppColors.primaryWarm,
                      AppColors.secondaryWarm,
                    ],
                    isSelected: settings.settings.selectedTheme == 'warm',
                    onTap: () => settings.setTheme('warm'),
                  ),
                  ThemeCard(
                    label: 'Cool',
                    colors: const [
                      AppColors.tealAccent,
                      Color(0xFF7BA7D7),
                    ],
                    isSelected: settings.settings.selectedTheme == 'cool',
                    onTap: () => settings.setTheme('cool'),
                  ),
                  ThemeCard(
                    label: 'Auto',
                    colors: const [
                      AppColors.primaryWarm,
                      AppColors.tealAccent,
                    ],
                    isSelected: settings.settings.selectedTheme == 'auto',
                    onTap: () => settings.setTheme('auto'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Monitoring section
              SettingsSection(
                title: 'MONITORING',
                children: [
                  _buildVolumeSlider(context, settings),
                  const Divider(
                      height: 1, color: AppColors.surfaceLight, indent: 16, endIndent: 16),
                  SettingsToggleRow(
                    label: 'Gentle Alerts',
                    description: 'Uses soft sounds and vibrations',
                    value: settings.settings.vibrationEnabled,
                    onChanged: (v) => settings.setVibrationEnabled(v),
                  ),
                  const Divider(
                      height: 1, color: AppColors.surfaceLight, indent: 16, endIndent: 16),
                  SettingsToggleRow(
                    label: 'Smart Filtering',
                    description: 'Ignore background noise',
                    value: settings.audioSettings.filterEnabled,
                    onChanged: (v) {
                      final updated =
                          settings.getUpdatedAudioSettings(filterEnabled: v);
                      settings.updateAudioSettings(updated);
                      context.read<ConnectionProvider>().syncAudioSettings();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Server info
              GestureDetector(
                onTap: () => _showServerUrlDialog(context, settings),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Server URL',
                              style: AppTheme.caption,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              settings.serverUrl ?? 'Not configured',
                              style: AppTheme.body
                                  .copyWith(color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showServerUrlDialog(
      BuildContext context, SettingsProvider settings) async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => ServerUrlDialog(currentUrl: settings.serverUrl),
    );
    if (url != null && url.isNotEmpty) {
      await settings.setServerUrl(url);
      if (context.mounted) {
        final connection = context.read<ConnectionProvider>();
        await connection.disconnect();
        connection.connect(url);
      }
    }
  }

  Widget _buildVolumeSlider(
      BuildContext context, SettingsProvider settings) {
    // Map alert volume (0.0 - 1.0) to a dB display (-30 to 0)
    final volumeDb =
        (settings.settings.alertVolume * 30 - 30).roundToDouble();
    final volumeLabel = _volumeLabel(settings.settings.alertVolume);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Alert Volume',
                  style:
                      AppTheme.body.copyWith(color: AppColors.textPrimary)),
              Text(
                '$volumeLabel (${volumeDb.toStringAsFixed(0)} dB)',
                style: AppTheme.caption
                    .copyWith(color: AppColors.primaryWarm),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: settings.settings.alertVolume,
              onChanged: (v) => settings.setAlertVolume(v),
              onChangeEnd: (v) {
                final dbValue = v * 30 - 30;
                final updated = settings.getUpdatedAudioSettings(
                    volumeAdjustmentDb: dbValue);
                settings.updateAudioSettings(updated);
                context.read<ConnectionProvider>().syncAudioSettings();
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Whisper', style: AppTheme.caption),
              Text('Loud', style: AppTheme.caption),
            ],
          ),
        ],
      ),
    );
  }

  String _volumeLabel(double value) {
    if (value < 0.25) return 'Whisper';
    if (value < 0.5) return 'Soft';
    if (value < 0.75) return 'Normal';
    return 'Loud';
  }
}
