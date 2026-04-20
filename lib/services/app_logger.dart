import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static const String _filePrefix = 'babymonitarr-';
  static const String _fileSuffix = '.log';
  static const Duration _retention = Duration(days: 7);

  static Directory? _logDir;
  static IOSink? _sink;
  static String? _currentDateKey;
  static bool _initialized = false;

  static Directory? get logDirectory => _logDir;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen(_onRecord);

    try {
      _logDir = await _resolveLogDirectory();
      if (!await _logDir!.exists()) {
        await _logDir!.create(recursive: true);
      }
      await _pruneOldFiles(_logDir!);
      _openSinkForToday();
      Logger('AppLogger').info(
        'Logging to ${_logDir!.path}',
      );
    } catch (e, st) {
      debugPrint('AppLogger: failed to initialize file logging: $e');
      debugPrint('$st');
    }
  }

  static Future<Directory> _resolveLogDirectory() async {
    Directory? base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory();
    }
    base ??= await getApplicationDocumentsDirectory();
    return Directory('${base.path}${Platform.pathSeparator}logs');
  }

  static Future<void> _pruneOldFiles(Directory dir) async {
    final cutoff = DateTime.now().subtract(_retention);
    final cutoffKey = _dateKey(cutoff);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_filePrefix) || !name.endsWith(_fileSuffix)) {
        continue;
      }
      final key = name.substring(
        _filePrefix.length,
        name.length - _fileSuffix.length,
      );
      if (key.compareTo(cutoffKey) < 0) {
        try {
          await entity.delete();
        } catch (_) {
          // Best effort; next run will retry.
        }
      }
    }
  }

  static void _openSinkForToday() {
    if (_logDir == null) return;
    final key = _dateKey(DateTime.now());
    if (_currentDateKey == key && _sink != null) return;
    _closeSink();
    final path =
        '${_logDir!.path}${Platform.pathSeparator}$_filePrefix$key$_fileSuffix';
    _sink = File(path).openWrite(mode: FileMode.writeOnlyAppend);
    _currentDateKey = key;
  }

  static void _closeSink() {
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    unawaited(sink.flush().then((_) => sink.close()).catchError((_) {}));
  }

  static String _dateKey(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static void _onRecord(LogRecord record) {
    final buf = StringBuffer()
      ..write(record.time.toIso8601String())
      ..write('  ')
      ..write(record.level.name.padRight(7))
      ..write('  [')
      ..write(record.loggerName)
      ..write(']  ')
      ..write(record.message);
    if (record.error != null) {
      buf.write('  | ');
      buf.write(record.error);
    }
    if (record.stackTrace != null) {
      buf.write('\n');
      buf.write(record.stackTrace);
    }
    final line = buf.toString();
    debugPrint(line);
    _writeToFile(line);
  }

  static void _writeToFile(String line) {
    if (_logDir == null) return;
    try {
      _openSinkForToday();
      final sink = _sink;
      if (sink == null) return;
      sink.writeln(line);
    } catch (e) {
      debugPrint('AppLogger: write failed: $e');
    }
  }
}
