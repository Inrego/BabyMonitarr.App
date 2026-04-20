import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_logger.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/room_provider.dart';
import '../utils/audio_level_scale.dart';
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
      body: Consumer2<SettingsProvider, RoomProvider>(
        builder: (context, settings, rooms, _) {
          final connection = context.watch<ConnectionProvider>();
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              // Monitoring section
              SettingsSection(
                title: 'MONITORING',
                children: [
                  _buildVolumeSlider(
                    context,
                    settings,
                    rooms,
                    connection.isConnected && rooms.isLoaded,
                  ),
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
                                    fontFamily: settings.hasApiKey
                                        ? 'monospace'
                                        : null,
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
                                  ? AppColors.successGreen.withValues(
                                      alpha: 0.15,
                                    )
                                  : AppColors.primaryWarm.withValues(
                                      alpha: 0.15,
                                    ),
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
                              icon: const Icon(Icons.qr_code_scanner, size: 16),
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
                              icon: const Icon(Icons.edit_outlined, size: 16),
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
              const SizedBox(height: 24),

              _DiagnosticsSection(),
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
    final controller = TextEditingController(text: settings.apiKey ?? '');
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
                  onPressed: () => setDialogState(() => obscure = !obscure),
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
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
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

  Widget _buildVolumeSlider(
    BuildContext context,
    SettingsProvider settings,
    RoomProvider rooms,
    bool hasRemoteThreshold,
  ) {
    final thresholdDb = AudioLevelScale.clampDb(
      hasRemoteThreshold
          ? rooms.globalSettings.soundThreshold
          : settings.settings.alertVolume,
    );
    final minLabel = AudioLevelScale.minDb.toStringAsFixed(0);
    final maxLabel = AudioLevelScale.maxDb.toStringAsFixed(0);

    return _AlertThresholdSlider(
      thresholdDb: thresholdDb,
      settings: settings,
      rooms: rooms,
      hasRemoteThreshold: hasRemoteThreshold,
      minLabel: minLabel,
      maxLabel: maxLabel,
    );
  }
}

class _AlertThresholdSlider extends StatefulWidget {
  final double thresholdDb;
  final SettingsProvider settings;
  final RoomProvider rooms;
  final bool hasRemoteThreshold;
  final String minLabel;
  final String maxLabel;

  const _AlertThresholdSlider({
    required this.thresholdDb,
    required this.settings,
    required this.rooms,
    required this.hasRemoteThreshold,
    required this.minLabel,
    required this.maxLabel,
  });

  @override
  State<_AlertThresholdSlider> createState() => _AlertThresholdSliderState();
}

class _AlertThresholdSliderState extends State<_AlertThresholdSlider> {
  double? _pendingThresholdDb;

  @override
  void didUpdateWidget(covariant _AlertThresholdSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pendingThresholdDb != null &&
        (widget.thresholdDb - _pendingThresholdDb!).abs() < 0.1) {
      setState(() {
        _pendingThresholdDb = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final thresholdDb = _pendingThresholdDb ?? widget.thresholdDb;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Alert Threshold',
                style: AppTheme.body.copyWith(color: AppColors.textPrimary),
              ),
              Text(
                '${thresholdDb.toStringAsFixed(0)} dB',
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
              min: AudioLevelScale.minDb,
              max: AudioLevelScale.maxDb,
              divisions: (AudioLevelScale.maxDb - AudioLevelScale.minDb)
                  .round(),
              label: '${thresholdDb.toStringAsFixed(0)} dB',
              value: thresholdDb,
              onChanged: (v) {
                final nextThresholdDb = AudioLevelScale.clampDb(v);
                setState(() {
                  _pendingThresholdDb = nextThresholdDb;
                });
                widget.settings.setAlertVolume(nextThresholdDb);
              },
              onChangeEnd: (v) async {
                final nextThresholdDb = AudioLevelScale.clampDb(v);
                final updated = widget.settings.audioSettings.copyWith(
                  soundThreshold: nextThresholdDb,
                );
                widget.settings.updateAudioSettings(updated);
                if (!widget.hasRemoteThreshold) {
                  if (!mounted) return;
                  setState(() {
                    _pendingThresholdDb = null;
                  });
                  return;
                }
                try {
                  await widget.rooms.updateGlobalSettings(
                    widget.rooms.globalSettings.copyWith(
                      soundThreshold: nextThresholdDb,
                    ),
                  );
                } catch (_) {
                  if (!mounted) return;
                  setState(() {
                    _pendingThresholdDb = null;
                  });
                }
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${widget.minLabel} dB', style: AppTheme.caption),
              Text('${widget.maxLabel} dB', style: AppTheme.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final logDir = AppLogger.logDirectory?.path;
    final adbCommand = logDir == null || !Platform.isAndroid
        ? null
        : 'adb pull "$logDir" ./logs';

    return SettingsSection(
      title: 'DIAGNOSTICS',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: AppColors.primaryWarm,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Log directory', style: AppTheme.caption),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                logDir ?? 'Unavailable',
                style: AppTheme.body.copyWith(
                  color: AppColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (logDir != null)
                    TextButton.icon(
                      onPressed: () => _copy(context, logDir, 'Path copied'),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy path'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.tealAccent,
                        textStyle: AppTheme.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (adbCommand != null)
                    TextButton.icon(
                      onPressed: () =>
                          _copy(context, adbCommand, 'adb command copied'),
                      icon: const Icon(Icons.terminal, size: 16),
                      label: const Text('Copy adb pull'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.tealAccent,
                        textStyle: AppTheme.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Logs rotate daily; the last 7 days are kept.',
                style: AppTheme.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
