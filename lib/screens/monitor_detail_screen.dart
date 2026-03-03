import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../models/audio_state.dart';
import '../models/room.dart';
import '../providers/audio_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/room_icons.dart';
import '../widgets/live_indicator.dart';
import '../widgets/sound_level_graph.dart';
import '../widgets/status_pill.dart';

class MonitorDetailScreen extends StatelessWidget {
  final Room room;
  final RTCVideoRenderer? videoRenderer;

  const MonitorDetailScreen({
    super.key,
    required this.room,
    this.videoRenderer,
  });

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final audio = context.watch<AudioProvider>();
    final roomAudio = audio.snapshotForRoom(room.id);
    final listening = connection.isListeningToRoom(room.id);
    final muted = connection.isAudioMutedForRoom(room.id);
    final isLive = listening || videoRenderer?.srcObject != null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              iconForRoom(room.icon),
              size: 20,
              color: AppColors.primaryWarm,
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(room.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 10),
            LiveIndicator(isLive: isLive),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildVideoSection(),
            const SizedBox(height: 16),
            _buildAudioSection(audio, listening),
            const SizedBox(height: 16),
            Center(child: StatusPill(alertState: roomAudio.alertState)),
            const SizedBox(height: 16),
            _buildControls(context, connection, listening, muted),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection() {
    if (videoRenderer?.srcObject != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: RTCVideoView(
            videoRenderer!,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                iconForRoom(room.icon),
                size: 40,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              Text('No video stream', style: AppTheme.caption),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioSection(AudioProvider audio, bool listening) {
    if (listening) {
      final roomAudio = audio.snapshotForRoom(room.id);
      final soundStatus = roomAudio.alertState == AlertState.alerting
          ? SoundStatus.alert
          : (roomAudio.currentLevel?.status ?? SoundStatus.quiet);
      return SoundLevelGraph(
        history: roomAudio.history,
        currentDisplayLevel: roomAudio.currentLevel?.displayLevel ?? 0,
        currentStatus: soundStatus,
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.graphic_eq,
                size: 36,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              Text(
                'Not listening to this room',
                style: AppTheme.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    ConnectionProvider connection,
    bool listening,
    bool muted,
  ) {
    return Row(
      children: [
        Expanded(
          child: listening
              ? _controlButton(
                  label: muted ? 'Unmute' : 'Mute',
                  icon: muted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  active: !muted,
                  onPressed: () => connection.toggleAudioMuteForRoom(room.id),
                )
              : _controlButton(
                  label: 'Start Listening',
                  icon: Icons.headphones,
                  active: false,
                  onPressed: () async {
                    try {
                      await connection.startListeningToRoom(room.id);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to start listening: $e'),
                        ),
                      );
                    }
                  },
                ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _stopMonitoringButton(context)),
      ],
    );
  }

  Widget _controlButton({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback? onPressed,
  }) {
    final Color bg;
    final Color fg;
    if (active) {
      bg = AppColors.primaryWarm.withValues(alpha: 0.2);
      fg = AppColors.primaryWarm;
    } else {
      bg = AppColors.surface;
      fg = AppColors.textSecondary;
    }

    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: AppTheme.caption.copyWith(color: fg)),
    );
  }

  Widget _stopMonitoringButton(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async {
        final connection = context.read<ConnectionProvider>();
        final settings = context.read<SettingsProvider>();
        if (connection.isListeningToRoom(room.id)) {
          try {
            await connection.stopListeningToRoom(room.id);
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Audio failed to stop: $e')));
            return;
          }
        }
        try {
          await settings.removeMonitoringRoom(room.id);
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to stop monitoring: $e')),
          );
          return;
        }
        if (!context.mounted) return;
        Navigator.pop(context);
      },
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondaryWarm.withValues(alpha: 0.2),
        foregroundColor: AppColors.secondaryWarm,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.stop_circle_outlined, size: 18),
      label: Text(
        'Stop',
        style: AppTheme.caption.copyWith(color: AppColors.secondaryWarm),
      ),
    );
  }
}
