# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the app code. Keep route-level UI in `lib/screens/`, reusable UI in `lib/widgets/`, state in `lib/providers/`, integrations in `lib/services/`, shared data types in `lib/models/`, helpers in `lib/utils/`, and colors/themes in `lib/theme/`. Put new tests under `test/` in the matching area (`test/services/`, `test/widgets/`, `test/utils/`, `test/models/`). Store app icons in `assets/icon/`, README or PR visuals in `screenshots/`, and only touch `android/`, `ios/`, `web/`, or `windows/` for real platform-specific changes.

## Build, Test, and Development Commands
Run `flutter pub get` after dependency changes in `pubspec.yaml`. Use `flutter run` to launch on a device or emulator. Run `flutter analyze` to enforce the analyzer rules from `analysis_options.yaml`, and `flutter test` to execute the unit and widget suite. Format before committing with `dart format lib test`. If icon assets or launcher icon settings change, regenerate them with `flutter pub run flutter_launcher_icons`.

## Coding Style & Naming Conventions
Follow `flutter_lints` and keep Dart indentation at 2 spaces. Use `snake_case.dart` filenames, `PascalCase` for classes and widgets, and `lowerCamelCase` for methods, fields, and locals. Match the existing suffix patterns such as `DashboardScreen`, `ConnectionProvider`, and `SignalRService`. Prefer small widgets with clear responsibilities, and keep UI, provider, and service logic separated.

## Testing Guidelines
Use `flutter_test` with `group`, `test`, and `testWidgets`. Name files `*_test.dart` and mirror source paths where practical, for example `lib/services/signalr_service.dart` with `test/services/signalr_service_test.dart`. There is no declared coverage gate, so add or update tests for every bug fix, parser change, and UI state change you touch.

## Commit & Pull Request Guidelines
Recent history uses short imperative subjects such as `Retry SignalR reconnect when idle on dashboard`. Keep commits focused on one logical change and avoid trailing punctuation. Pull requests should summarize user-visible impact, list verification steps like `flutter analyze` and `flutter test`, link the relevant issue when available, and include fresh screenshots for dashboard, monitoring, or settings UI changes.

## Security & Configuration Tips
Treat backend URLs, API keys, and device-specific settings as local secrets; never commit them. Avoid committing generated `build/` output, and keep platform runner edits minimal unless the change is required for Android, iOS, Web, or Windows behavior.

## Retrieving logs for debugging

BabyMonitarr is a Flutter app that runs overnight, so a debugger isn't usually attached. Runtime events are written to a persistent log file on the device. When investigating a bug that happened while the app was running, pull the log first — it will almost always tell you more than the code alone.

### What is logged

- SignalR connection state transitions and reconnect attempts.
- Start/stop listening per room, watchdog recoveries, foreground-service transitions.
- WebRTC peer-connection state changes, track-received events, ICE candidate drops.
- Every caught exception with its stack trace.
- Uncaught Flutter / platform / zone errors (via `FlutterError.onError`, `PlatformDispatcher.instance.onError`, `runZonedGuarded`).

Format: `<ISO8601>  <LEVEL>  [<loggerName>]  <message>  | <error>\n<stackTrace>`.

Default level is `INFO`. Files roll daily as `babymonitarr-YYYY-MM-DD.log` and the last 7 days are kept.

### Where the file lives

| Platform | Path |
|----------|------|
| Android  | `/sdcard/Android/data/com.babymonitarr.babymonitarr.opus/files/logs/` (release) |
| Android (dev build) | `/sdcard/Android/data/com.babymonitarr.babymonitarr.opus.dev/files/logs/` |
| iOS      | Application Documents directory (`<app sandbox>/Documents/logs/`) |
| Windows  | `getApplicationDocumentsDirectory()` → typically `%APPDATA%\com.babymonitarr\babymonitarr\logs\` |

The in-app **Settings → Diagnostics** section shows the absolute path and has a "Copy adb pull" button that produces the exact command for the current install.

### How to pull logs

**Android (preferred — no root required, app's external files dir is reachable via adb):**

```bash
# Release build
adb pull /sdcard/Android/data/com.babymonitarr.babymonitarr.opus/files/logs/ ./logs

# Dev build
adb pull /sdcard/Android/data/com.babymonitarr.babymonitarr.opus.dev/files/logs/ ./logs
```

If `adb pull` on the directory fails on a specific device, pull a single file:

```bash
adb shell ls /sdcard/Android/data/com.babymonitarr.babymonitarr.opus/files/logs/
adb pull /sdcard/Android/data/com.babymonitarr.babymonitarr.opus/files/logs/babymonitarr-YYYY-MM-DD.log
```

If you only have `adb logcat` access (device not permitting external-files-dir reads), filter for the app's log tags — `debugPrint` forwarding is still wired in `AppLogger._onRecord`, so every logged line also appears in logcat:

```bash
adb logcat -d -T "24 hours ago" | grep -E "flutter|babymonitarr"
```

**Windows:** the path is directly readable from the dev machine — just `Read` the file from the path shown in Settings → Diagnostics.

**iOS:** retrieve via Xcode → Devices and Simulators → Installed Apps → BabyMonitarr → ⚙ → Download Container, then inspect `Documents/logs/` inside the downloaded `.xcappdata`. (No adb-equivalent — this is the simplest path.)

### Triaging a log

1. Locate the approximate time the bug occurred. Logs use local time in the ISO8601 timestamp.
2. Scan backwards from that time for `SEVERE` or `WARNING` lines — these are the caught exceptions and uncaught errors.
3. Use the breadcrumbs (`SignalR state`, `PeerConnection state`, `Start listening to room N`, `Watchdog recovery for room N`, `Foreground service…`) to reconstruct what the app was doing in the minute leading up to the failure.
4. If the issue is audio/video-stream-related, look for matching peer-connection state transitions on the same `room N`.

### Adding new log lines

Use the module-scoped `Logger` pattern already established in every service and provider:

```dart
import 'package:logging/logging.dart';
final _log = Logger('MyComponent');

_log.info('Human-readable event');
_log.warning('Caught something recoverable', error, stackTrace);
_log.severe('Unrecoverable', error, stackTrace);
```

Always pass the caught `error` and `stackTrace` to `warning` / `severe` — `AppLogger` formats them into the file. Don't introduce `debugPrint` for anything worth persisting; it only goes to the attached debugger, which defeats the point of the file log.
