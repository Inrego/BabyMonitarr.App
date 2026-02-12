import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../models/connection_state.dart';

class ConnectionStatusBar extends StatelessWidget {
  final ConnectionInfo info;
  final VoidCallback? onTap;

  const ConnectionStatusBar({super.key, required this.info, this.onTap});

  bool get _isTappable =>
      info.state == MonitorConnectionState.disconnected ||
      info.state == MonitorConnectionState.failed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isTappable ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDot(),
            const SizedBox(width: 8),
            Text(_statusText, style: AppTheme.caption),
            if (info.isConnected) ...[
              Text('  \u00B7  ', style: AppTheme.caption),
              Icon(_signalIcon, size: 14, color: _signalColor),
              const SizedBox(width: 4),
              Text(
                'Signal: ${info.qualityLabel}',
                style: AppTheme.caption.copyWith(color: _signalColor),
              ),
            ],
            if (_isTappable && onTap != null) ...[
              Text('  \u00B7  ', style: AppTheme.caption),
              Text(
                'Tap to reconnect',
                style: AppTheme.caption.copyWith(color: AppColors.primaryWarm),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDot() {
    Color color;
    switch (info.state) {
      case MonitorConnectionState.connected:
        color = AppColors.successGreen;
        break;
      case MonitorConnectionState.connecting:
      case MonitorConnectionState.reconnecting:
        color = AppColors.primaryWarm;
        break;
      case MonitorConnectionState.failed:
        color = AppColors.liveRed;
        break;
      case MonitorConnectionState.disconnected:
        color = AppColors.textSecondary;
        break;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String get _statusText {
    switch (info.state) {
      case MonitorConnectionState.connected:
        return 'Connected';
      case MonitorConnectionState.connecting:
        return 'Connecting...';
      case MonitorConnectionState.reconnecting:
        return 'Reconnecting...';
      case MonitorConnectionState.failed:
        return 'Connection failed';
      case MonitorConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  IconData get _signalIcon {
    switch (info.quality) {
      case ConnectionQuality.strong:
        return Icons.signal_cellular_4_bar;
      case ConnectionQuality.good:
        return Icons.signal_cellular_alt;
      case ConnectionQuality.fair:
        return Icons.signal_cellular_alt_2_bar;
      case ConnectionQuality.weak:
        return Icons.signal_cellular_alt_1_bar;
      case ConnectionQuality.unknown:
        return Icons.signal_cellular_alt;
    }
  }

  Color get _signalColor {
    switch (info.quality) {
      case ConnectionQuality.strong:
        return AppColors.successGreen;
      case ConnectionQuality.good:
        return AppColors.tealAccent;
      case ConnectionQuality.fair:
        return AppColors.primaryWarm;
      case ConnectionQuality.weak:
        return AppColors.liveRed;
      case ConnectionQuality.unknown:
        return AppColors.textSecondary;
    }
  }
}
