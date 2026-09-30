import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../models/remote_ice_candidate.dart';
import '../models/talkback_status.dart';
import '../services/talkback_audio_control.dart';
import '../services/talkback_hub.dart';
import '../services/talkback_uplink_service.dart';
import 'connection_provider.dart';

final _log = Logger('TalkbackProvider');

/// What this app is doing with the Talk button (as opposed to the server's
/// [TalkbackState], which covers every client).
enum TalkPhase { idle, connecting, talking }

/// Why the last press did not end in (or ended) talking. Shown under the
/// Talk button until the next press.
enum TalkErrorKind { micPermissionDenied, rejected, failed, endedByServer }

class TalkError {
  final TalkErrorKind kind;
  final String message;
  const TalkError(this.kind, this.message);
}

/// Push-to-talk into a room's Nest camera. See the backend's docs/TALKBACK.md.
///
/// One talk session at a time. Press runs the uplink negotiation and
/// `StartTalkback` in parallel; release stops talking first, then drops the
/// uplink (and so the mic). The room's incoming audio is muted while talking.
class TalkbackProvider extends ChangeNotifier {
  static const Duration volumeDebounce = Duration(milliseconds: 300);

  TalkbackProvider({
    TalkbackUplink Function()? uplinkFactory,
    Future<bool> Function()? requestMicPermission,
  }) : _uplinkFactory = uplinkFactory ?? TalkbackUplinkService.new,
       _requestMicPermission = requestMicPermission ?? _defaultMicPermission;

  final TalkbackUplink Function() _uplinkFactory;
  final Future<bool> Function() _requestMicPermission;

  TalkbackHub? _hub;
  TalkbackAudioControl? _audio;
  Object? _boundOwner;
  StreamSubscription<TalkbackStatus>? _statusSub;
  StreamSubscription<RemoteIceCandidate>? _iceSub;
  StreamSubscription<HubConnectionState>? _connectionSub;

  final Map<int, TalkbackStatus> _statuses = <int, TalkbackStatus>{};
  final Map<int, TalkError> _errors = <int, TalkError>{};
  final Map<int, double> _pendingVolumes = <int, double>{};
  final Map<int, Timer> _volumeTimers = <int, Timer>{};

  _TalkSession? _session;
  bool _disposed = false;

  TalkbackStatus? statusFor(int roomId) => _statuses[roomId];
  TalkError? errorFor(int roomId) => _errors[roomId];

  TalkPhase phaseFor(int roomId) {
    final session = _session;
    if (session == null || session.roomId != roomId || session.finished) {
      return TalkPhase.idle;
    }
    return session.phase;
  }

  /// True when someone other than this app is talking in the room.
  bool isBusyElsewhere(int roomId) =>
      (_statuses[roomId]?.busy ?? false) && phaseFor(roomId) == TalkPhase.idle;

  bool canTalk(int roomId) {
    final status = _statuses[roomId];
    if (status == null || !status.supported || !status.available) return false;
    if (_session != null && _session!.roomId != roomId) return false;
    return !isBusyElsewhere(roomId);
  }

  /// Talkback gain for the slider: the value being dragged, else the server's.
  double volumeFor(int roomId) =>
      _pendingVolumes[roomId] ?? _statuses[roomId]?.volume ?? 1.0;

  void bindConnection(ConnectionProvider connection) {
    if (identical(_boundOwner, connection)) return;
    _boundOwner = connection;
    attach(hub: connection.signalR, audio: connection);
  }

  @visibleForTesting
  void attach({required TalkbackHub hub, required TalkbackAudioControl audio}) {
    _statusSub?.cancel();
    _iceSub?.cancel();
    _connectionSub?.cancel();
    _hub = hub;
    _audio = audio;
    _statusSub = hub.onTalkbackStatusChanged.listen(_onStatus);
    _iceSub = hub.onTalkbackIceCandidate.listen(_onRemoteIceCandidate);
    _connectionSub = hub.connectionState.listen(_onConnectionState);
  }

  /// Fetches the room's talkback status. Safe to call on every screen open.
  Future<void> loadStatus(int roomId) async {
    final hub = _hub;
    if (hub == null || !hub.isConnected) return;
    try {
      final status = await hub.getTalkbackStatus(roomId);
      if (_disposed) return;
      _statuses[roomId] = status;
      notifyListeners();
    } catch (e, st) {
      _log.warning('Failed to load talkback status for room $roomId', e, st);
    }
  }

  /// Button pressed. Returns when talking has started or failed.
  Future<void> startTalking(int roomId) async {
    final hub = _hub;
    final audio = _audio;
    if (hub == null || audio == null || _session != null) return;
    if (!canTalk(roomId)) return;

    final session = _TalkSession(roomId);
    _session = session;
    _errors.remove(roomId);
    notifyListeners();
    _log.info('Talk pressed for room $roomId');

    final granted = await _safeMicPermission();
    if (!identical(_session, session)) return;
    if (!granted) {
      _log.info('Microphone permission denied');
      _errors[roomId] = const TalkError(
        TalkErrorKind.micPermissionDenied,
        'Microphone permission is needed to talk. '
        'Allow it in the system settings.',
      );
      _session = null;
      notifyListeners();
      return;
    }
    if (session.releaseRequested) {
      await _finish(session);
      return;
    }

    session.audioBegun = true;
    await _safely('beginTalkback', () => audio.beginTalkback(roomId));
    if (session.finished) return;

    final uplinkFuture = _negotiateUplink(hub, session);
    final startFuture = _startSpeaker(hub, roomId);
    final uplinkError = await uplinkFuture;
    final startResult = await startFuture;
    if (!identical(_session, session)) {
      // Torn down meanwhile (SignalR dropped, provider disposed) before the
      // speaker went live; make sure it doesn't stay on.
      if (startResult.success) {
        await _safely('stopTalkback', () => hub.stopTalkback(roomId));
      }
      return;
    }

    if (startResult.success) session.speakerLive = true;

    if (session.releaseRequested) {
      await _finish(session);
      return;
    }
    if (!startResult.success) {
      if (!startResult.cancelled) {
        _log.info(
          'StartTalkback for room $roomId rejected: '
          '${startResult.reason} ${startResult.message ?? ''}',
        );
        _errors[roomId] = TalkError(
          TalkErrorKind.rejected,
          startResult.displayMessage,
        );
      }
      await _finish(session);
      return;
    }
    if (uplinkError != null) {
      _errors[roomId] = uplinkError;
      await _finish(session);
      return;
    }

    session.phase = TalkPhase.talking;
    _log.info('Talking in room $roomId');
    notifyListeners();
  }

  /// Button released (or screen left / app backgrounded).
  Future<void> stopTalking(int roomId) async {
    final session = _session;
    if (session == null || session.roomId != roomId) return;
    if (session.releaseRequested) return;
    session.releaseRequested = true;
    _log.info('Talk released for room $roomId');

    if (session.phase == TalkPhase.connecting) {
      // The in-flight press finishes the teardown; tell the server now so an
      // opening Foyer stream is cancelled and the speaker never goes live.
      unawaited(_safely('stopTalkback', () => _hub!.stopTalkback(roomId)));
      return;
    }
    await _finish(session);
  }

  /// Sets the room's talkback gain (0.0–2.0), debounced.
  void setVolume(int roomId, double volume) {
    final clamped = TalkbackStatus.clampVolume(volume);
    _pendingVolumes[roomId] = clamped;
    notifyListeners();
    _volumeTimers.remove(roomId)?.cancel();
    _volumeTimers[roomId] = Timer(volumeDebounce, () {
      _volumeTimers.remove(roomId);
      unawaited(_sendVolume(roomId, clamped));
    });
  }

  Future<void> _sendVolume(int roomId, double volume) async {
    final hub = _hub;
    try {
      if (hub == null || !hub.isConnected) return;
      await hub.setTalkbackVolume(roomId, volume);
      final status = _statuses[roomId];
      if (status != null) _statuses[roomId] = status.copyWith(volume: volume);
    } catch (e, st) {
      _log.warning('Failed to set talkback volume for room $roomId', e, st);
    } finally {
      // A newer drag may have started while this call was in flight.
      if (!_disposed && !_volumeTimers.containsKey(roomId)) {
        _pendingVolumes.remove(roomId);
        notifyListeners();
      }
    }
  }

  Future<TalkError?> _negotiateUplink(
    TalkbackHub hub,
    _TalkSession session,
  ) async {
    final roomId = session.roomId;
    final uplink = _uplinkFactory();
    session.uplink = uplink;
    try {
      final config = await hub.getWebRtcConfig();
      final offer = await hub.startTalkbackUplink(roomId);
      final answer = await uplink.handleOffer(
        offer,
        clientConfig: config,
        onIceCandidate: (candidate) {
          final value = candidate.candidate;
          if (value == null || value.isEmpty) return;
          unawaited(
            _safely(
              'addTalkbackIceCandidate',
              () => hub.addTalkbackIceCandidate(
                roomId,
                value,
                candidate.sdpMid,
                candidate.sdpMLineIndex,
              ),
            ),
          );
        },
      );
      await hub.setTalkbackRemoteDescription(roomId, 'answer', answer);
      return null;
    } on MicrophoneUnavailableException catch (e, st) {
      _log.warning('Talkback mic unavailable for room $roomId', e, st);
      return const TalkError(
        TalkErrorKind.micPermissionDenied,
        'The microphone could not be opened.',
      );
    } catch (e, st) {
      _log.warning('Talkback uplink failed for room $roomId', e, st);
      return const TalkError(
        TalkErrorKind.failed,
        'Could not send your voice to the server. Try again.',
      );
    }
  }

  Future<TalkbackStartResult> _startSpeaker(TalkbackHub hub, int roomId) async {
    try {
      return await hub.startTalkback(roomId);
    } catch (e, st) {
      _log.warning('StartTalkback failed for room $roomId', e, st);
      return const TalkbackStartResult(
        success: false,
        reason: TalkbackReason.cameraError,
      );
    }
  }

  /// Tears a session down: speaker off, uplink off (releases the mic), local
  /// audio restored. Each step is best-effort so one failure can't strand the
  /// mic open.
  Future<void> _finish(_TalkSession session, {bool serverGone = false}) async {
    if (session.finished) return;
    session.finished = true;
    final roomId = session.roomId;
    final hub = _hub;
    if (!_disposed) notifyListeners();

    if (hub != null && !serverGone) {
      if (session.speakerLive || session.phase == TalkPhase.talking) {
        await _safely('stopTalkback', () => hub.stopTalkback(roomId));
      }
      if (session.uplink != null) {
        await _safely(
          'stopTalkbackUplink',
          () => hub.stopTalkbackUplink(roomId),
        );
      }
    }
    final uplink = session.uplink;
    if (uplink != null) await _safely('uplink.close', uplink.close);
    final audio = _audio;
    if (session.audioBegun && audio != null) {
      await _safely('endTalkback', () => audio.endTalkback(roomId));
    }

    if (identical(_session, session)) _session = null;
    _log.info('Talk session for room $roomId ended');
    if (!_disposed) notifyListeners();
  }

  void _onStatus(TalkbackStatus status) {
    _statuses[status.roomId] = status;
    final session = _session;
    if (session != null &&
        session.roomId == status.roomId &&
        session.phase == TalkPhase.talking &&
        !session.releaseRequested &&
        status.state != TalkbackState.talking) {
      // Server stopped us: watchdog, 5-minute cap, or a Foyer failure.
      _log.info(
        'Server ended talking in room ${status.roomId} '
        '(state ${status.state.name}, ${status.message ?? 'no message'})',
      );
      _errors[status.roomId] = TalkError(
        TalkErrorKind.endedByServer,
        status.message ?? 'Talking stopped',
      );
      unawaited(_finish(session));
    }
    notifyListeners();
  }

  void _onRemoteIceCandidate(RemoteIceCandidate candidate) {
    final session = _session;
    final uplink = session?.uplink;
    if (session == null || uplink == null) return;
    if (session.roomId != candidate.roomId) return;
    unawaited(
      _safely(
        'uplink.addRemoteCandidate',
        () => uplink.addRemoteCandidate(
          candidate.candidate,
          candidate.sdpMid,
          candidate.sdpMLineIndex,
        ),
      ),
    );
  }

  void _onConnectionState(HubConnectionState state) {
    if (state == HubConnectionState.Connected) {
      // The server dropped our talker and uplink with the old connection;
      // refresh what we show but never resume talking on our own.
      for (final roomId in _statuses.keys.toList(growable: false)) {
        unawaited(loadStatus(roomId));
      }
      return;
    }
    if (state != HubConnectionState.Disconnected) return;
    final session = _session;
    if (session == null) return;
    _log.info('SignalR dropped while talking in room ${session.roomId}');
    _errors[session.roomId] = const TalkError(
      TalkErrorKind.failed,
      'Lost the connection to the server',
    );
    unawaited(_finish(session, serverGone: true));
  }

  Future<bool> _safeMicPermission() async {
    try {
      return await _requestMicPermission();
    } catch (e, st) {
      _log.warning('Microphone permission request failed', e, st);
      return false;
    }
  }

  static Future<bool> _defaultMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _safely(String step, Future<void> Function() action) async {
    try {
      await action();
    } catch (e, st) {
      _log.warning('Talkback step $step failed', e, st);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final session = _session;
    if (session != null) unawaited(_finish(session));
    _statusSub?.cancel();
    _iceSub?.cancel();
    _connectionSub?.cancel();
    for (final timer in _volumeTimers.values) {
      timer.cancel();
    }
    _volumeTimers.clear();
    super.dispose();
  }
}

class _TalkSession {
  final int roomId;
  TalkPhase phase = TalkPhase.connecting;
  TalkbackUplink? uplink;
  bool audioBegun = false;
  bool speakerLive = false;
  bool releaseRequested = false;
  bool finished = false;

  _TalkSession(this.roomId);
}
