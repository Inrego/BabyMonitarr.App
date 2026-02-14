enum MonitorConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum ConnectionQuality { strong, good, fair, weak, unknown }

class ConnectionInfo {
  final MonitorConnectionState state;
  final ConnectionQuality quality;
  final double packetLossPercent;
  final String? errorMessage;
  final int reconnectAttempts;

  const ConnectionInfo({
    this.state = MonitorConnectionState.disconnected,
    this.quality = ConnectionQuality.unknown,
    this.packetLossPercent = 0,
    this.errorMessage,
    this.reconnectAttempts = 0,
  });

  ConnectionInfo copyWith({
    MonitorConnectionState? state,
    ConnectionQuality? quality,
    double? packetLossPercent,
    String? errorMessage,
    int? reconnectAttempts,
  }) {
    return ConnectionInfo(
      state: state ?? this.state,
      quality: quality ?? this.quality,
      packetLossPercent: packetLossPercent ?? this.packetLossPercent,
      errorMessage: errorMessage ?? this.errorMessage,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
    );
  }

  bool get isConnected => state == MonitorConnectionState.connected;

  String get qualityLabel {
    switch (quality) {
      case ConnectionQuality.strong:
        return 'Strong';
      case ConnectionQuality.good:
        return 'Good';
      case ConnectionQuality.fair:
        return 'Fair';
      case ConnectionQuality.weak:
        return 'Weak';
      case ConnectionQuality.unknown:
        return 'Unknown';
    }
  }
}
