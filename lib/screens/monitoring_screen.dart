import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../providers/connection_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/settings_provider.dart';
import '../models/connection_state.dart';
import '../widgets/live_indicator.dart';
import '../widgets/sound_level_graph.dart';
import '../widgets/status_pill.dart';
import '../widgets/action_button.dart';
import '../widgets/connection_status_bar.dart';
import 'settings_screen.dart';
import '../widgets/server_url_dialog.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  static const _lifecycleChannel = MethodChannel('babymonitarr/lifecycle');

  bool _listeningIn = true;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  void _autoConnect() {
    final connection = context.read<ConnectionProvider>();
    final settings = context.read<SettingsProvider>();
    final audio = context.read<AudioProvider>();

    connection.setAudioProvider(audio);

    final url = settings.serverUrl;
    if (url != null &&
        url.isNotEmpty &&
        !connection.isConnected &&
        connection.connectionInfo.state !=
            MonitorConnectionState.connecting) {
      connection.connect(url);
    }
  }

  void _onStatusBarTap() {
    final settings = context.read<SettingsProvider>();
    final connection = context.read<ConnectionProvider>();
    final url = settings.serverUrl;

    if (url != null && url.isNotEmpty) {
      connection.connect(url);
    } else {
      _showServerUrlDialog();
    }
  }

  Future<void> _showServerUrlDialog() async {
    final settings = context.read<SettingsProvider>();
    final connection = context.read<ConnectionProvider>();

    final url = await showDialog<String>(
      context: context,
      builder: (_) => ServerUrlDialog(currentUrl: settings.serverUrl),
    );
    if (url != null && url.isNotEmpty) {
      await settings.setServerUrl(url);
      connection.connect(url);
    }
  }

  void _toggleListenIn() {
    final connection = context.read<ConnectionProvider>();
    setState(() {
      _listeningIn = !_listeningIn;
    });
    connection.webRtc.setAudioEnabled(_listeningIn);
  }

  String _formatTime() {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Future<void> _cleanupNativeWebRtcReceiver() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _lifecycleChannel
          .invokeMethod<void>('cleanupWebRtcOrientationReceiver');
    } catch (e) {
      debugPrint('Failed to cleanup native WebRTC receiver: $e');
    }
  }

  Future<void> _handleExit() async {
    if (_exiting) return;
    _exiting = true;

    final connection = context.read<ConnectionProvider>();
    await connection.disconnect();
    await _cleanupNativeWebRtcReceiver();
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleExit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 12),
                _buildHeader(),
                const SizedBox(height: 16),
                Consumer<ConnectionProvider>(
                  builder: (context, connection, _) {
                    return LiveIndicator(isLive: connection.isConnected);
                  },
                ),
                const SizedBox(height: 16),
                _buildCameraPlaceholder(),
                const SizedBox(height: 24),
                Consumer<AudioProvider>(
                  builder: (context, audio, _) {
                    return SoundLevelGraph(
                      history: audio.history,
                      currentDisplayLevel: audio.displayLevel,
                      currentStatus: audio.soundStatus,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Consumer<AudioProvider>(
                  builder: (context, audio, _) {
                    return StatusPill(alertState: audio.alertState);
                  },
                ),
                const SizedBox(height: 20),
                ActionButton(
                  label: _listeningIn ? 'Listening' : 'Listen In',
                  icon:
                      _listeningIn ? Icons.volume_up : Icons.volume_off_outlined,
                  isActive: _listeningIn,
                  onPressed: _toggleListenIn,
                ),
                const Spacer(),
                Consumer<ConnectionProvider>(
                  builder: (context, connection, _) {
                    return ConnectionStatusBar(
                      info: connection.connectionInfo,
                      onTap: _onStatusBarTap,
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Monitoring', style: AppTheme.subtitle),
        Text(_formatTime(), style: AppTheme.caption),
        IconButton(
          icon: const Icon(Icons.settings_outlined,
              color: AppColors.textSecondary),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCameraPlaceholder() {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_outlined,
              size: 32, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text('Video coming soon',
              style: AppTheme.caption
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
