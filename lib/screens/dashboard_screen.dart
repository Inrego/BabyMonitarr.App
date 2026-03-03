import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../models/audio_state.dart';
import '../models/remote_video_ice_candidate.dart';
import '../models/room.dart';
import '../providers/audio_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/room_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/room_icons.dart';
import '../widgets/live_indicator.dart';
import 'monitor_detail_screen.dart';
import 'monitor_settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Map<int, _VideoRoomSession> _videoSessions = <int, _VideoRoomSession>{};
  StreamSubscription? _videoIceSub;
  StreamSubscription? _signalRStateSub;
  RoomProvider? _boundRoomProvider;
  SettingsProvider? _boundSettingsProvider;
  Set<int> _lastMonitoringRoomIds = const <int>{};
  bool _initialized = false;
  bool _syncInProgress = false;
  bool _restoringActiveListening = false;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeData();
    });
  }

  Future<void> _initializeData() async {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final connection = context.read<ConnectionProvider>();
    final audio = context.read<AudioProvider>();
    final rooms = context.read<RoomProvider>();

    connection.setAudioProvider(audio);
    rooms.bindConnection(connection);
    _bindRoomProvider(rooms);
    _bindSettingsProvider(settings);

    final url = settings.serverUrl;
    if (url != null && url.isNotEmpty && !connection.isConnected) {
      try {
        await connection.connect(url);
      } catch (_) {
        // Connection errors are surfaced in UI state via provider.
      }
    }

    if (connection.isConnected) {
      await rooms.refreshAll();
    }

    _videoIceSub?.cancel();
    _videoIceSub = connection.signalR.onVideoIceCandidate.listen(
      _onVideoIceCandidate,
    );

    _signalRStateSub?.cancel();
    _signalRStateSub = connection.signalR.connectionState.listen((state) {
      if (!mounted) return;
      if (state == HubConnectionState.Connected) {
        unawaited(_handleSignalRConnected());
      } else if (state == HubConnectionState.Disconnected) {
        _disposeAllVideoSessions(notifyServer: false);
      }
      unawaited(_syncVideoSessions());
    });

    _initialized = true;
    if (mounted) {
      setState(() {});
    }
    await _syncVideoSessions();
    await _restoreActiveListeningIfNeeded();
  }

  Future<void> _handleSignalRConnected() async {
    if (!mounted) return;
    await context.read<RoomProvider>().refreshAll();
    await _syncVideoSessions();
    await _restoreActiveListeningIfNeeded();
  }

  void _bindRoomProvider(RoomProvider roomProvider) {
    if (identical(_boundRoomProvider, roomProvider)) return;
    _boundRoomProvider?.removeListener(_onRoomProviderChanged);
    _boundRoomProvider = roomProvider;
    _boundRoomProvider?.addListener(_onRoomProviderChanged);
  }

  void _onRoomProviderChanged() {
    if (!mounted) return;
    final roomProvider = context.read<RoomProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    if (roomProvider.isLoaded && !roomProvider.isLoading) {
      final validIds = roomProvider.rooms.map((r) => r.id).toSet();
      final monitoringIds = settingsProvider.monitoringRoomIds;
      final pruned = monitoringIds.intersection(validIds);
      if (pruned.length != monitoringIds.length) {
        unawaited(settingsProvider.setMonitoringRoomIds(pruned));
      }
    }

    unawaited(_syncVideoSessions());
    unawaited(_restoreActiveListeningIfNeeded());
  }

  void _bindSettingsProvider(SettingsProvider settingsProvider) {
    if (identical(_boundSettingsProvider, settingsProvider)) return;
    _boundSettingsProvider?.removeListener(_onSettingsProviderChanged);
    _boundSettingsProvider = settingsProvider;
    _lastMonitoringRoomIds = {...settingsProvider.monitoringRoomIds};
    _boundSettingsProvider?.addListener(_onSettingsProviderChanged);
  }

  void _onSettingsProviderChanged() {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final currentIds = settings.monitoringRoomIds;
    if (_lastMonitoringRoomIds.length == currentIds.length &&
        _lastMonitoringRoomIds.containsAll(currentIds)) {
      unawaited(_restoreActiveListeningIfNeeded());
      return;
    }
    _lastMonitoringRoomIds = {...currentIds};
    unawaited(_syncVideoSessions());
    unawaited(_restoreActiveListeningIfNeeded());
  }

  Future<void> _restoreActiveListeningIfNeeded() async {
    if (!mounted || !_initialized || _restoringActiveListening) return;

    final connection = context.read<ConnectionProvider>();
    final settings = context.read<SettingsProvider>();
    final roomProvider = context.read<RoomProvider>();

    if (!connection.isConnected) return;
    final desiredActiveRoomIds = settings.activeListeningRoomIds;
    if (desiredActiveRoomIds.isEmpty) return;

    final validRoomIds = <int>{};
    for (final roomId in desiredActiveRoomIds) {
      final room = roomProvider.roomById(roomId);
      if (room == null ||
          !settings.monitoringRoomIds.contains(roomId) ||
          !_canStartAudioForRoom(room)) {
        continue;
      }
      validRoomIds.add(roomId);
    }

    if (validRoomIds.length != desiredActiveRoomIds.length) {
      await settings.setActiveListeningRoomIds(validRoomIds);
    }

    final missingRoomIds = validRoomIds.difference(connection.listeningRoomIds);
    if (missingRoomIds.isEmpty) return;

    _restoringActiveListening = true;
    try {
      for (final roomId in missingRoomIds) {
        try {
          await connection.startListeningToRoom(roomId);
        } catch (e) {
          debugPrint('Failed restoring active listening room $roomId: $e');
        }
      }
    } finally {
      _restoringActiveListening = false;
    }
  }

  Future<void> _syncVideoSessions() async {
    if (!_initialized || _syncInProgress || !mounted) return;
    final connection = context.read<ConnectionProvider>();
    final roomProvider = context.read<RoomProvider>();
    final monitoringIds = context.read<SettingsProvider>().monitoringRoomIds;
    final desiredRoomIds = roomProvider.rooms
        .where(
          (room) =>
              monitoringIds.contains(room.id) && _canStartVideoForRoom(room),
        )
        .map((room) => room.id)
        .toSet();

    _syncInProgress = true;
    try {
      final currentIds = _videoSessions.keys.toList(growable: false);
      for (final roomId in currentIds) {
        if (!desiredRoomIds.contains(roomId)) {
          await _disposeVideoSession(
            roomId,
            notifyServer: connection.isConnected,
          );
        }
      }

      if (!connection.isConnected) return;

      for (final roomId in desiredRoomIds) {
        if (!_videoSessions.containsKey(roomId)) {
          await _startVideoSession(roomId);
        }
      }
    } finally {
      _syncInProgress = false;
    }
  }

  bool _canStartVideoForRoom(Room room) {
    if (!room.enableVideoStream) return false;
    if (room.streamSourceType == 'google_nest') {
      return room.nestDeviceId?.trim().isNotEmpty ?? false;
    }
    return room.cameraStreamUrl?.trim().isNotEmpty ?? false;
  }

  bool _canStartAudioForRoom(Room room) {
    if (!room.enableAudioStream) return false;
    if (room.streamSourceType == 'google_nest') {
      return room.nestDeviceId?.trim().isNotEmpty ?? false;
    }
    return room.cameraStreamUrl?.trim().isNotEmpty ?? false;
  }

  Future<void> _startVideoSession(int roomId) async {
    final connection = context.read<ConnectionProvider>();
    if (!connection.isConnected || _videoSessions.containsKey(roomId)) return;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final session = _VideoRoomSession(renderer: renderer);
    _videoSessions[roomId] = session;
    if (mounted) setState(() {});

    try {
      final offerSdp = await connection.signalR.startVideoStream(roomId);
      final rtcConfig = await connection.signalR.getWebRtcConfig();
      final pc = await createPeerConnection(rtcConfig.toPeerConnectionConfig());
      session.peerConnection = pc;

      pc.onIceCandidate = (candidate) {
        final raw = candidate.candidate;
        if (raw == null || raw.trim().isEmpty) return;
        unawaited(
          connection.signalR
              .addVideoIceCandidate(
                roomId,
                raw,
                candidate.sdpMid,
                candidate.sdpMLineIndex,
              )
              .catchError((Object error) {
                debugPrint(
                  'Error sending room $roomId video ICE candidate: $error',
                );
              }),
        );
      };

      pc.onTrack = (event) {
        if (event.track.kind != 'video') return;
        if (event.streams.isNotEmpty) {
          session.renderer.srcObject = event.streams.first;
        }
        session.isLoading = false;
        session.isConnected = true;
        session.error = null;
        if (mounted) setState(() {});
      };

      pc.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          session.isLoading = false;
          session.isConnected = true;
          session.error = null;
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          session.isConnected = false;
        }
        if (mounted) setState(() {});
      };

      await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
      session.remoteDescriptionSet = true;

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await connection.signalR.setVideoRemoteDescription(
        roomId,
        answer.type ?? 'answer',
        answer.sdp ?? '',
      );

      if (session.pendingCandidates.isNotEmpty) {
        for (final candidate in session.pendingCandidates) {
          try {
            await pc.addCandidate(candidate);
          } catch (e) {
            debugPrint('Error adding queued room $roomId ICE candidate: $e');
          }
        }
        session.pendingCandidates.clear();
      }
    } catch (e) {
      session.isLoading = false;
      session.isConnected = false;
      session.error = e.toString();
      if (mounted) setState(() {});
    }
  }

  void _onVideoIceCandidate(RemoteVideoIceCandidate candidate) {
    final session = _videoSessions[candidate.roomId];
    if (session == null) return;
    final normalized = candidate.candidate.startsWith('candidate:')
        ? candidate.candidate
        : 'candidate:${candidate.candidate}';
    final ice = RTCIceCandidate(
      normalized,
      candidate.sdpMid,
      candidate.sdpMLineIndex,
    );

    final pc = session.peerConnection;
    if (pc != null && session.remoteDescriptionSet) {
      unawaited(
        pc.addCandidate(ice).catchError((Object error) {
          debugPrint(
            'Error adding room ${candidate.roomId} remote ICE candidate: $error',
          );
        }),
      );
      return;
    }
    session.pendingCandidates.add(ice);
  }

  Future<void> _disposeVideoSession(
    int roomId, {
    required bool notifyServer,
  }) async {
    final session = _videoSessions.remove(roomId);
    if (session == null) return;
    final connection = context.read<ConnectionProvider>();

    if (notifyServer && connection.isConnected) {
      try {
        await connection.signalR.stopVideoStream(roomId);
      } catch (_) {
        // Session may already be closed server-side.
      }
    }

    final pc = session.peerConnection;
    session.peerConnection = null;
    try {
      await pc?.close();
    } catch (_) {}
    try {
      await pc?.dispose();
    } catch (_) {}

    session.renderer.srcObject = null;
    await session.renderer.dispose();
    if (mounted) setState(() {});
  }

  void _disposeAllVideoSessions({required bool notifyServer}) {
    final roomIds = _videoSessions.keys.toList(growable: false);
    for (final roomId in roomIds) {
      unawaited(_disposeVideoSession(roomId, notifyServer: notifyServer));
    }
  }

  Future<void> _openMonitorSettings({int? roomId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MonitorSettingsScreen(initialRoomId: roomId),
      ),
    );
    if (!mounted) return;
    final rooms = context.read<RoomProvider>();
    await rooms.refreshAll();
    await _syncVideoSessions();
  }

  void _openMonitorDetail(Room room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MonitorDetailScreen(
          room: room,
          videoRenderer: _videoSessions[room.id]?.renderer,
        ),
      ),
    );
  }

  Future<void> _onListenPressed(Room room) async {
    final connection = context.read<ConnectionProvider>();
    try {
      if (connection.isListeningToRoom(room.id)) {
        await connection.stopListeningToRoom(room.id);
        return;
      }
      await connection.startListeningToRoom(room.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start listening: $e')));
    }
  }

  Future<void> _startMonitoring(int roomId) async {
    final settingsProvider = context.read<SettingsProvider>();
    final connection = context.read<ConnectionProvider>();
    final roomProvider = context.read<RoomProvider>();
    await settingsProvider.addMonitoringRoom(roomId);
    await _syncVideoSessions();

    // Auto-start audio listening
    final room = roomProvider.rooms.where((r) => r.id == roomId).firstOrNull;
    if (room != null && _canStartAudioForRoom(room)) {
      try {
        await connection.startListeningToRoom(roomId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Audio failed to start: $e')));
      }
    }
  }

  Future<void> _stopMonitoring(int roomId) async {
    final connection = context.read<ConnectionProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    try {
      await settingsProvider.removeMonitoringRoom(roomId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to stop monitoring: $e')));
      return;
    }

    await _syncVideoSessions();

    if (connection.isListeningToRoom(roomId)) {
      try {
        await connection.stopListeningToRoom(roomId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Audio failed to stop: $e')));
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindRoomProvider(context.read<RoomProvider>());
    _bindSettingsProvider(context.read<SettingsProvider>());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _videoIceSub?.cancel();
    _signalRStateSub?.cancel();
    _boundRoomProvider?.removeListener(_onRoomProviderChanged);
    _boundSettingsProvider?.removeListener(_onSettingsProviderChanged);
    _disposeAllVideoSessions(notifyServer: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = context.watch<RoomProvider>();
    final connection = context.watch<ConnectionProvider>();
    final audio = context.watch<AudioProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final monitoringIds = settingsProvider.monitoringRoomIds;
    final now = TimeOfDay.now();
    final clock = now.format(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (connection.isConnected) {
              await rooms.refreshAll();
              await _syncVideoSessions();
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              _buildHeader(clock),
              const SizedBox(height: 20),
              if (!connection.isConnected) _buildDisconnectedBanner(),
              if (!connection.isConnected) const SizedBox(height: 12),
              if (rooms.rooms.isEmpty)
                _buildEmptyState()
              else
                ...rooms.rooms.map(
                  (room) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: monitoringIds.contains(room.id)
                        ? GestureDetector(
                            onTap: () => _openMonitorDetail(room),
                            child: _buildActiveRoomCard(
                              room: room,
                              session: _videoSessions[room.id],
                              listening: connection.isListeningToRoom(room.id),
                              muted: connection.isAudioMutedForRoom(room.id),
                              audio: audio,
                            ),
                          )
                        : _buildInactiveRoomCard(room: room),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String clock) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'All Monitors',
            style: AppTheme.title.copyWith(fontSize: 34),
          ),
        ),
        Text(clock, style: AppTheme.caption),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            onPressed: () => _openMonitorSettings(),
            icon: const Icon(Icons.add, color: AppColors.primaryWarm),
          ),
        ),
      ],
    );
  }

  Widget _buildDisconnectedBanner() {
    final settings = context.read<SettingsProvider>();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondaryWarm.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: AppColors.secondaryWarm),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Disconnected from ${settings.serverUrl ?? 'server'}. Pull to retry.',
              style: AppTheme.caption.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.bedroom_baby,
            size: 38,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 10),
          Text('No monitors configured', style: AppTheme.subtitle),
          const SizedBox(height: 4),
          Text(
            'Add a monitor to begin streaming audio and video.',
            style: AppTheme.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => _openMonitorSettings(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryWarm,
              foregroundColor: AppColors.background,
            ),
            child: const Text('Add Monitor'),
          ),
        ],
      ),
    );
  }

  Widget _buildInactiveRoomCard({required Room room}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryWarm.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconForRoom(room.icon),
                  color: AppColors.primaryWarm,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  room.name,
                  style: AppTheme.subtitle.copyWith(fontSize: 24),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Inactive',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.nightlight_round,
                  size: 32,
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Monitor is not active',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _startMonitoring(room.id),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryWarm,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Start Monitoring'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => _openMonitorSettings(roomId: room.id),
              icon: const Icon(
                Icons.settings,
                size: 14,
                color: AppColors.textSecondary,
              ),
              label: Text(
                'Settings',
                style: AppTheme.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRoomCard({
    required Room room,
    required _VideoRoomSession? session,
    required bool listening,
    required bool muted,
    required AudioProvider audio,
  }) {
    final isLive = listening || (session?.isConnected ?? false);
    final canListen = _canStartAudioForRoom(room);
    final roomAudio = audio.snapshotForRoom(room.id);
    final level = listening ? roomAudio.currentLevel?.level : null;
    final progress = level == null
        ? 0.0
        : ((level - -90.0) / 90.0).clamp(0.0, 1.0).toDouble();
    final levelLabel = level == null
        ? '-- dB'
        : '${level.toStringAsFixed(1)} dB';
    final secondaryLabel = listening
        ? _soundStatusLabel(
            roomAudio.alertState == AlertState.alerting
                ? SoundStatus.alert
                : (roomAudio.currentLevel?.status ?? SoundStatus.quiet),
          )
        : "Everything's peaceful";

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryWarm.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconForRoom(room.icon),
                  color: AppColors.primaryWarm,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  room.name,
                  style: AppTheme.subtitle.copyWith(fontSize: 24),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.tealAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Monitoring',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.tealAccent,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              LiveIndicator(isLive: isLive),
            ],
          ),
          const SizedBox(height: 10),
          _buildPreview(room: room, session: session),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation(AppColors.primaryWarm),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(levelLabel, style: AppTheme.caption),
              const Spacer(),
              Text(
                secondaryLabel,
                style: AppTheme.caption.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: listening
                    ? _cardButton(
                        label: muted ? 'Unmute' : 'Mute',
                        icon: muted
                            ? Icons.volume_off_outlined
                            : Icons.volume_up_outlined,
                        active: !muted,
                        onPressed: () => context
                            .read<ConnectionProvider>()
                            .toggleAudioMuteForRoom(room.id),
                      )
                    : _cardButton(
                        label: 'Listen',
                        icon: Icons.headphones,
                        active: false,
                        onPressed: canListen
                            ? () => _onListenPressed(room)
                            : null,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cardButton(
                  label: 'Stop',
                  icon: Icons.stop_circle_outlined,
                  active: false,
                  danger: true,
                  onPressed: () => _stopMonitoring(room.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreview({
    required Room room,
    required _VideoRoomSession? session,
  }) {
    if (session?.renderer.srcObject != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 190,
          child: RTCVideoView(
            session!.renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      );
    }

    final isLoading = session != null && session.isLoading;
    final hasError = session?.error != null;

    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                hasError
                    ? Icons.videocam_off_outlined
                    : _iconForRoom(room.icon),
                size: 34,
                color: AppColors.textSecondary,
              ),
            const SizedBox(height: 8),
            Text(
              isLoading
                  ? 'Starting video...'
                  : hasError
                  ? 'Video unavailable'
                  : 'No video stream',
              style: AppTheme.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardButton({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    final Color bg;
    final Color fg;
    if (danger) {
      bg = AppColors.secondaryWarm.withValues(alpha: 0.2);
      fg = AppColors.secondaryWarm;
    } else if (active) {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: AppTheme.caption),
    );
  }

  String _soundStatusLabel(SoundStatus status) {
    switch (status) {
      case SoundStatus.alert:
        return 'Alert noise';
      case SoundStatus.active:
        return 'Active';
      case SoundStatus.moderate:
        return 'Moderate';
      case SoundStatus.quiet:
        return 'Quiet';
    }
  }

  IconData _iconForRoom(String icon) => iconForRoom(icon);
}

class _VideoRoomSession {
  final RTCVideoRenderer renderer;
  RTCPeerConnection? peerConnection;
  final List<RTCIceCandidate> pendingCandidates = <RTCIceCandidate>[];
  bool remoteDescriptionSet = false;
  bool isLoading = true;
  bool isConnected = false;
  String? error;

  _VideoRoomSession({required this.renderer});
}
