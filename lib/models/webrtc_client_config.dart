class WebRtcIceServerConfig {
  final String urls;
  final String? username;
  final String? credential;

  const WebRtcIceServerConfig({
    required this.urls,
    this.username,
    this.credential,
  });

  factory WebRtcIceServerConfig.fromJson(Map<String, dynamic> json) {
    return WebRtcIceServerConfig(
      urls: (json['urls'] as String?)?.trim() ?? '',
      username: (json['username'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['username'] as String).trim(),
      credential: (json['credential'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['credential'] as String).trim(),
    );
  }

  Map<String, dynamic> toPeerConfig() {
    return {
      'urls': urls,
      if (username != null) 'username': username,
      if (credential != null) 'credential': credential,
    };
  }
}

class WebRtcClientConfig {
  final List<WebRtcIceServerConfig> iceServers;

  const WebRtcClientConfig({required this.iceServers});

  factory WebRtcClientConfig.fromJson(Map<String, dynamic> json) {
    final rawIceServers = json['iceServers'];
    if (rawIceServers is! List) {
      return WebRtcClientConfig.fallback();
    }

    final servers = rawIceServers
        .whereType<Map>()
        .map((raw) => raw.map((k, v) => MapEntry(k.toString(), v)))
        .map(WebRtcIceServerConfig.fromJson)
        .where((server) => server.urls.isNotEmpty)
        .toList(growable: false);

    if (servers.isEmpty) {
      return WebRtcClientConfig.fallback();
    }

    return WebRtcClientConfig(iceServers: servers);
  }

  factory WebRtcClientConfig.fallback() {
    return const WebRtcClientConfig(
      iceServers: [WebRtcIceServerConfig(urls: 'stun:stun.l.google.com:19302')],
    );
  }

  Map<String, dynamic> toPeerConnectionConfig() {
    return {
      'iceServers': iceServers.map((server) => server.toPeerConfig()).toList(),
    };
  }
}
