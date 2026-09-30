import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/talkback_status.dart';
import '../providers/talkback_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Press-and-hold Talk button plus the camera speaker volume for a room.
/// Renders nothing for rooms without a Nest camera speaker.
class TalkbackPanel extends StatefulWidget {
  final int roomId;

  const TalkbackPanel({super.key, required this.roomId});

  static const talkButtonKey = Key('talkback-button');
  static const messageKey = Key('talkback-message');
  static const volumeSliderKey = Key('talkback-volume');

  @override
  State<TalkbackPanel> createState() => _TalkbackPanelState();
}

class _TalkbackPanelState extends State<TalkbackPanel>
    with WidgetsBindingObserver {
  late final TalkbackProvider _talkback;
  bool _pointerDown = false;

  int get _roomId => widget.roomId;

  @override
  void initState() {
    super.initState();
    _talkback = context.read<TalkbackProvider>();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_talkback.loadStatus(_roomId));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never leave the mic and camera speaker on behind the user's back.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _release();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Deferred: stopping notifies listeners, which is not allowed while the
    // tree is being unmounted.
    final talkback = _talkback;
    final roomId = _roomId;
    unawaited(Future.microtask(() => talkback.stopTalking(roomId)));
    super.dispose();
  }

  void _press() {
    if (!_talkback.canTalk(_roomId)) return;
    _pointerDown = true;
    unawaited(_talkback.startTalking(_roomId));
  }

  void _release() {
    if (!_pointerDown) return;
    _pointerDown = false;
    unawaited(_talkback.stopTalking(_roomId));
  }

  @override
  Widget build(BuildContext context) {
    final talkback = context.watch<TalkbackProvider>();
    final status = talkback.statusFor(_roomId);
    if (status == null || !status.supported) return const SizedBox.shrink();

    final phase = talkback.phaseFor(_roomId);
    final message = _messageFor(talkback, status, phase);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTalkButton(talkback, status, phase),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message,
              key: TalkbackPanel.messageKey,
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          _buildVolume(talkback),
        ],
      ),
    );
  }

  String? _messageFor(
    TalkbackProvider talkback,
    TalkbackStatus status,
    TalkPhase phase,
  ) {
    if (phase != TalkPhase.idle) return null;
    final error = talkback.errorFor(_roomId);
    if (!status.available) return status.displayMessage;
    if (talkback.isBusyElsewhere(_roomId)) {
      return TalkbackReason.describe(TalkbackReason.busy);
    }
    if (error != null) return error.message;
    // camera_error keeps the button enabled: the last attempt failed, the
    // next press retries.
    if (status.unavailableReason != null) return status.displayMessage;
    return null;
  }

  Widget _buildTalkButton(
    TalkbackProvider talkback,
    TalkbackStatus status,
    TalkPhase phase,
  ) {
    final enabled = phase != TalkPhase.idle || talkback.canTalk(_roomId);

    final String label;
    final Widget icon;
    final Color bg;
    final Color fg;
    switch (phase) {
      case TalkPhase.connecting:
        label = 'Connecting…';
        icon = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryWarm,
          ),
        );
        bg = AppColors.primaryWarm.withValues(alpha: 0.2);
        fg = AppColors.primaryWarm;
      case TalkPhase.talking:
        label = 'Talking – release to stop';
        icon = const Icon(Icons.mic, size: 22);
        bg = AppColors.primaryWarm;
        fg = AppColors.background;
      case TalkPhase.idle:
        if (!enabled) {
          label = talkback.isBusyElsewhere(_roomId)
              ? 'Someone is talking'
              : 'Talk unavailable';
          icon = const Icon(Icons.mic_off, size: 22);
          bg = AppColors.surfaceLight;
          fg = AppColors.textSecondary;
        } else {
          label = 'Hold to talk';
          icon = const Icon(Icons.mic_none, size: 22);
          bg = AppColors.primaryWarm.withValues(alpha: 0.2);
          fg = AppColors.primaryWarm;
        }
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Listener(
        key: TalkbackPanel.talkButtonKey,
        onPointerDown: enabled ? (_) => _press() : null,
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 64,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(color: fg),
                child: icon,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVolume(TalkbackProvider talkback) {
    final volume = talkback.volumeFor(_roomId);
    return Row(
      children: [
        const Icon(Icons.volume_down, size: 20, color: AppColors.textSecondary),
        Expanded(
          child: Slider(
            key: TalkbackPanel.volumeSliderKey,
            value: volume,
            max: 2.0,
            divisions: 40,
            label: '${(volume * 100).round()} %',
            onChanged: (value) => talkback.setVolume(_roomId, value),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${(volume * 100).round()} %',
            textAlign: TextAlign.end,
            style: AppTheme.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
