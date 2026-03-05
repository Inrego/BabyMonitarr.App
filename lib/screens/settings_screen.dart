import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/connection_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/server_url_dialog.dart';
import 'qr_scan_screen.dart';

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
              // Monitoring section
              SettingsSection(
                title: 'MONITORING',
                children: [
                  _buildVolumeSlider(context, settings),
                  const Divider(
                    height: 1,
                    color: AppColors.surfaceLight,
                    indent: 16,
                    endIndent: 16,
                  ),
                  SettingsToggleRow(
                    label: 'Vibrate on Alert',
                    description: 'Vibrate when a sound alert is triggered',
                    value: settings.settings.vibrationEnabled,
                    onChanged: (v) => settings.setVibrationEnabled(v),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Connection section
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'CONNECTION',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.primaryWarm,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Server URL row
                    GestureDetector(
                      onTap: () => _showServerUrlDialog(context, settings),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.link,
                              size: 20,
                              color: AppColors.primaryWarm,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Server URL', style: AppTheme.caption),
                                  const SizedBox(height: 2),
                                  Text(
                                    settings.serverUrl ?? 'Not configured',
                                    style: AppTheme.body.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(
                      height: 1,
                      color: AppColors.surfaceLight,
                      indent: 16,
                      endIndent: 16,
                    ),
                    // API Key row
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.vpn_key_outlined,
                            size: 20,
                            color: AppColors.primaryWarm,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('API Key', style: AppTheme.caption),
                                const SizedBox(height: 2),
                                Text(
                                  settings.hasApiKey
                                      ? '${settings.apiKeyPrefix}...'
                                      : 'Not configured',
                                  style: AppTheme.body.copyWith(
                                    color: AppColors.textPrimary,
                                    fontFamily:
                                        settings.hasApiKey ? 'monospace' : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: settings.hasApiKey
                                  ? AppColors.successGreen.withValues(alpha: 0.15)
                                  : AppColors.primaryWarm.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              settings.hasApiKey ? 'Active' : 'Not Set',
                              style: AppTheme.caption.copyWith(
                                color: settings.hasApiKey
                                    ? AppColors.successGreen
                                    : AppColors.primaryWarm,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      height: 1,
                      color: AppColors.surfaceLight,
                      indent: 16,
                      endIndent: 16,
                    ),
                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const QrScanScreen(isReconfigure: true),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.qr_code_scanner,
                                size: 16,
                              ),
                              label: const Text('Scan QR'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.tealAccent,
                                textStyle: AppTheme.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: AppColors.surfaceLight,
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () =>
                                  _showApiKeyDialog(context, settings),
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 16,
                              ),
                              label: const Text('Enter Key'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                textStyle: AppTheme.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
    BuildContext context,
    SettingsProvider settings,
  ) async {
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

  Future<void> _showApiKeyDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final controller = TextEditingController(
      text: settings.apiKey ?? '',
    );
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) {
        var obscure = true;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text('API Key', style: AppTheme.subtitle),
            content: TextField(
              controller: controller,
              obscureText: obscure,
              autocorrect: false,
              style: AppTheme.body.copyWith(
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'Paste your API key',
                hintStyle: AppTheme.body.copyWith(
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.surfaceLight),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () =>
                      setDialogState(() => obscure = !obscure),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, controller.text.trim()),
                child: Text(
                  'Save',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.primaryWarm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (key != null && key.isNotEmpty && context.mounted) {
      await settings.setApiKey(key);
      if (context.mounted) {
        final connection = context.read<ConnectionProvider>();
        await connection.disconnect();
        connection.connect(settings.serverUrl!);
      }
    }
  }

  Widget _buildVolumeSlider(BuildContext context, SettingsProvider settings) {
    // Map alert volume (0.0 - 1.0) to a dB display (-30 to 0)
    final volumeDb = (settings.settings.alertVolume * 30 - 30).roundToDouble();
    final volumeLabel = _volumeLabel(settings.settings.alertVolume);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Alert Volume',
                style: AppTheme.body.copyWith(color: AppColors.textPrimary),
              ),
              Text(
                '$volumeLabel (${volumeDb.toStringAsFixed(0)} dB)',
                style: AppTheme.caption.copyWith(color: AppColors.primaryWarm),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: settings.settings.alertVolume,
              onChanged: (v) => settings.setAlertVolume(v),
              onChangeEnd: (v) {
                final dbValue = v * 30 - 30;
                final updated = settings.getUpdatedAudioSettings(
                  volumeAdjustmentDb: dbValue,
                );
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
