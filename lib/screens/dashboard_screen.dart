import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import '../services/pip_service.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/live_indicator.dart';
import '../widgets/zoomable_video_view.dart';
import 'monitor_detail_screen.dart';
import 'monitor_settings_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final Map<int, _VideoRoomSession> _videoSessions = <int, _VideoRoomSession>{};
  StreamSubscription? _videoIceSub;
  StreamSubscription? _signalRStateSub;
  RoomProvider? _boundRoomProvider;
  SettingsProvider? _boundSettingsProvider;
  Set<int> _lastMonitoringRoomIds = const <int>{};
  bool _initialized = false;
  bool _syncInProgress = false;
  bool _resumeRecoveryInProgress = false;
  bool _restoringActiveListening = false;
  Timer? _clockTimer;
  final PipService _pipService = PipService();
  bool _pipSupported = false;
  final GlobalKey _keepScreenOnKey = GlobalKey();
  final Map<int, GlobalKey> _videoPreviewKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    connection.setRoomProvider(rooms);
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

    _pipSupported = await _pipService.isPipSupported();
    _pipService.isInPipMode.addListener(_onPipModeChanged);
    _pipService.isPreparingForPip.addListener(_onPipModeChanged);

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
      session.connectionState =
          RTCPeerConnectionState.RTCPeerConnectionStateNew;

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
        session.connectionState = state;
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
      session.connectionState =
          RTCPeerConnectionState.RTCPeerConnectionStateFailed;
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
    final connection = context.read<ConnectionProvider>();
    if (_pipService.activePipRoomId == roomId) {
      await _pipService.exitPip();
    }
    _videoPreviewKeys.remove(roomId);
    final session = _videoSessions.remove(roomId);
    if (session == null) return;

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

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
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

    _maybeShowKeepScreenOnTip();
  }

  void _maybeShowKeepScreenOnTip() {
    final settings = context.read<SettingsProvider>();
    if (settings.hasSeenKeepScreenOnTip) return;

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      CoachMarkOverlay.show(
        context: context,
        targetKey: _keepScreenOnKey,
        title: 'Keep Screen Awake',
        message:
            'Tap here to keep your screen on while monitoring. '
            'This prevents the display from sleeping so you can '
            'always see your baby.',
        onDismiss: () {
          context.read<SettingsProvider>().markKeepScreenOnTipSeen();
        },
      );
    });
  }

  Future<void> _stopMonitoring(int roomId) async {
    final connection = context.read<ConnectionProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    if (_pipService.activePipRoomId == roomId) {
      await _pipService.exitPip();
    }
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

  void _onPipModeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onPipPressed(int roomId) async {
    if (_pipService.activePipRoomId == roomId) {
      await _pipService.exitPip();
    } else {
      final success = await _pipService.enterPip(roomId: roomId);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Picture-in-Picture is not available')),
        );
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindRoomProvider(context.read<RoomProvider>());
    _bindSettingsProvider(context.read<SettingsProvider>());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (_pipService.isInPipMode.value) {
        _pipService.isPipActive().then((isActive) {
          if (!isActive && mounted) {
            _pipService.exitPip();
          }
        });
      }
      unawaited(_recoverVideoSessionsAfterResume());
    }
  }

  Future<void> _recoverVideoSessionsAfterResume() async {
    if (!mounted ||
        !_initialized ||
        _videoSessions.isEmpty ||
        _resumeRecoveryInProgress) {
      return;
    }
    final connection = context.read<ConnectionProvider>();
    if (!connection.isConnected) return;

    _resumeRecoveryInProgress = true;
    try {
      final sessionEntries = _videoSessions.entries.toList(growable: false);
      final originalSessionsByRoomId = <int, _VideoRoomSession>{
        for (final entry in sessionEntries) entry.key: entry.value,
      };
      final healthChecks = await Future.wait(
        sessionEntries.map(
          (entry) => _isVideoSessionHealthy(entry.key, entry.value),
        ),
      );

      final unhealthyRoomIds = <int>[];
      for (var i = 0; i < sessionEntries.length; i++) {
        if (!healthChecks[i]) {
          unhealthyRoomIds.add(sessionEntries[i].key);
        }
      }

      if (unhealthyRoomIds.isEmpty || !mounted) return;

      for (final roomId in unhealthyRoomIds) {
        final session = _videoSessions[roomId];
        final originalSession = originalSessionsByRoomId[roomId];
        if (!identical(session, originalSession)) continue;
        await _disposeVideoSession(roomId, notifyServer: false);
      }

      while (_syncInProgress && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) return;
      await _syncVideoSessions();
    } finally {
      _resumeRecoveryInProgress = false;
    }
  }

  Future<bool> _isVideoSessionHealthy(
    int roomId,
    _VideoRoomSession session,
  ) async {
    if (!mounted || !identical(_videoSessions[roomId], session)) return true;
    if (session.error != null) return false;
    if (!session.isConnected) return false;
    if (session.renderer.srcObject == null) return false;

    final state = session.connectionState;
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
      return false;
    }

    final pc = session.peerConnection;
    if (pc == null) return false;

    final firstSnapshot = await _captureInboundVideoStats(pc);
    if (!mounted || !identical(_videoSessions[roomId], session)) return true;
    if (firstSnapshot == null) {
      // If stats are unavailable on this platform, leave the session alone.
      return true;
    }
    if (!firstSnapshot.hasAnyMedia) return false;

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted || !identical(_videoSessions[roomId], session)) return true;

    final secondSnapshot = await _captureInboundVideoStats(pc);
    if (secondSnapshot == null) return true;

    return secondSnapshot.hasProgressSince(firstSnapshot);
  }

  Future<_InboundVideoStatsSnapshot?> _captureInboundVideoStats(
    RTCPeerConnection pc,
  ) async {
    try {
      final stats = await pc.getStats();
      double bytesReceived = 0;
      double packetsReceived = 0;
      double framesDecoded = 0;
      var foundVideoReport = false;

      for (final report in stats) {
        if (!_isInboundVideoReport(report)) continue;
        foundVideoReport = true;
        bytesReceived += _toDouble(report.values['bytesReceived']);
        packetsReceived += _toDouble(report.values['packetsReceived']);
        framesDecoded +=
            _toDouble(report.values['framesDecoded']) +
            _toDouble(report.values['framesReceived']);
      }

      if (!foundVideoReport) return null;
      return _InboundVideoStatsSnapshot(
        bytesReceived: bytesReceived,
        packetsReceived: packetsReceived,
        framesDecoded: framesDecoded,
      );
    } catch (e) {
      debugPrint('Error reading inbound video stats: $e');
      return null;
    }
  }

  bool _isInboundVideoReport(StatsReport report) {
    if (report.type != 'inbound-rtp') return false;

    final values = report.values;
    final mediaType = (values['kind'] ?? values['mediaType'] ?? '')
        .toString()
        .toLowerCase();
    if (mediaType.isNotEmpty) {
      return mediaType == 'video';
    }

    return values.containsKey('framesDecoded') ||
        values.containsKey('framesReceived') ||
        values.containsKey('frameWidth') ||
        values.containsKey('frameHeight');
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CoachMarkOverlay.dismiss();
    _clockTimer?.cancel();
    _videoIceSub?.cancel();
    _signalRStateSub?.cancel();
    _boundRoomProvider?.removeListener(_onRoomProviderChanged);
    _boundSettingsProvider?.removeListener(_onSettingsProviderChanged);
    _pipService.isInPipMode.removeListener(_onPipModeChanged);
    _pipService.isPreparingForPip.removeListener(_onPipModeChanged);
    _pipService.dispose();
    _disposeAllVideoSessions(notifyServer: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // On Android, the activity IS the PIP window — show a minimal video-only
    // UI optimised for the small PIP size. On iOS, PIP is handled natively via
    // AVPictureInPictureController so the Flutter UI should stay unchanged.
    if (Platform.isAndroid &&
        (_pipService.isInPipMode.value ||
            _pipService.isPreparingForPip.value)) {
      final pipSession = _videoSessions[_pipService.activePipRoomId];
      if (pipSession?.renderer.srcObject != null) {
        return Scaffold(
          body: RTCVideoView(
            pipSession!.renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        );
      }
    }

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
    final keepScreenOn = context.watch<SettingsProvider>().keepScreenOn;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Clock – truly centered on the full header width
        Text(clock, style: AppTheme.caption),
        // Left and right items on top
        Row(
          children: [
            SvgPicture.asset('assets/icon/icon.svg', height: 34),
            const SizedBox(width: 8),
            GestureDetector(
              key: _keepScreenOnKey,
              onTap: () => context.read<SettingsProvider>().setKeepScreenOn(
                !keepScreenOn,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                padding: EdgeInsets.symmetric(
                  horizontal: keepScreenOn ? 12 : 8,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: keepScreenOn
                      ? AppColors.primaryWarm.withValues(alpha: 0.2)
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      keepScreenOn ? Icons.lightbulb : Icons.lightbulb_outline,
                      size: 22,
                      color: keepScreenOn
                          ? AppColors.primaryWarm
                          : AppColors.textSecondary,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: keepScreenOn
                          ? Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                'Awake',
                                style: AppTheme.caption.copyWith(
                                  color: AppColors.primaryWarm,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _openSettings,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
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
    final isAlerting = listening && roomAudio.alertState == AlertState.alerting;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: isAlerting
            ? Border.all(color: AppColors.secondaryWarm, width: 2.0)
            : null,
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
                style: AppTheme.caption.copyWith(
                  color: isAlerting
                      ? AppColors.secondaryWarm
                      : AppColors.textPrimary,
                ),
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
              if (_pipSupported && session?.isConnected == true) ...[
                const SizedBox(width: 8),
                _pipButton(
                  active: _pipService.activePipRoomId == room.id,
                  onPressed: () => _onPipPressed(room.id),
                ),
              ],
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
      final key = _videoPreviewKeys.putIfAbsent(room.id, () => GlobalKey());
      return ZoomableVideoView(
        key: key,
        renderer: session!.renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        aspectRatio: 16 / 9,
        borderRadius: BorderRadius.circular(14),
        zoomEnabled: _pipService.activePipRoomId != room.id,
        onTap: () => _openMonitorDetail(room),
      );
    }

    final isLoading = session != null && session.isLoading;
    final hasError = session?.error != null;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
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

  Widget _pipButton({required bool active, required VoidCallback onPressed}) {
    final bg = active
        ? AppColors.primaryWarm.withValues(alpha: 0.2)
        : AppColors.surface;
    final fg = active ? AppColors.primaryWarm : AppColors.textSecondary;

    return SizedBox(
      height: 40,
      width: 40,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Icon(Icons.picture_in_picture_alt, size: 18, color: fg),
        ),
      ),
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
  RTCPeerConnectionState? connectionState;
  String? error;

  _VideoRoomSession({required this.renderer});
}

class _InboundVideoStatsSnapshot {
  final double bytesReceived;
  final double packetsReceived;
  final double framesDecoded;

  const _InboundVideoStatsSnapshot({
    required this.bytesReceived,
    required this.packetsReceived,
    required this.framesDecoded,
  });

  bool get hasAnyMedia =>
      bytesReceived > 0 || packetsReceived > 0 || framesDecoded > 0;

  bool hasProgressSince(_InboundVideoStatsSnapshot previous) {
    return bytesReceived > previous.bytesReceived ||
        packetsReceived > previous.packetsReceived ||
        framesDecoded > previous.framesDecoded;
  }
}
