import 'dart:convert';

class QrScanResult {
  final String? serverUrl;
  final String? apiKey;
  final String? errorMessage;

  const QrScanResult({this.serverUrl, this.apiKey, this.errorMessage});

  bool get isValid =>
      serverUrl != null &&
      serverUrl!.isNotEmpty &&
      apiKey != null &&
      apiKey!.isNotEmpty &&
      errorMessage == null;

  String get apiKeyPrefix =>
      apiKey != null && apiKey!.length >= 8 ? apiKey!.substring(0, 8) : apiKey ?? '';
}

class QrPayloadParser {
  static QrScanResult parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const QrScanResult(
        errorMessage: "This doesn't look like a BabyMonitarr QR code.",
      );
    }

    if (raw.startsWith('babymonitarr://setup')) {
      return _parseUri(raw);
    }

    // Fallback: try raw JSON
    return _tryJson(raw);
  }

  static QrScanResult _parseUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return const QrScanResult(
        errorMessage: "This doesn't look like a BabyMonitarr QR code.",
      );
    }

    final encoded = uri.queryParameters['d'];
    if (encoded == null || encoded.isEmpty) {
      return const QrScanResult(
        errorMessage: 'The QR code is missing connection details.',
      );
    }

    try {
      // Restore base64 padding
      var base64 = encoded.replaceAll('-', '+').replaceAll('_', '/');
      final remainder = base64.length % 4;
      if (remainder != 0) {
        base64 += '=' * (4 - remainder);
      }

      final jsonStr = utf8.decode(base64Decode(base64));
      final map = jsonDecode(jsonStr);
      return _extractFields(map);
    } catch (_) {
      return const QrScanResult(
        errorMessage: 'Could not read the QR code data. Please generate a new one.',
      );
    }
  }

  static QrScanResult _tryJson(String raw) {
    try {
      final map = jsonDecode(raw);
      return _extractFields(map);
    } catch (_) {
      return const QrScanResult(
        errorMessage: "This doesn't look like a BabyMonitarr QR code.",
      );
    }
  }

  static QrScanResult _extractFields(dynamic map) {
    if (map is! Map) {
      return const QrScanResult(
        errorMessage: "This doesn't look like a BabyMonitarr QR code.",
      );
    }

    final url = map['url'] as String?;
    final key = map['key'] as String?;

    if (url == null || url.isEmpty) {
      return const QrScanResult(
        errorMessage: 'The QR code is missing the server address.',
      );
    }

    if (key == null || key.isEmpty) {
      return const QrScanResult(
        errorMessage: 'The QR code is missing the API key.',
      );
    }

    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null || !parsedUrl.hasScheme || !parsedUrl.hasAuthority) {
      return const QrScanResult(
        errorMessage: 'The server address in the QR code is not valid.',
      );
    }

    return QrScanResult(serverUrl: url, apiKey: key);
  }
}
