import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/connection_provider.dart';
import 'providers/audio_provider.dart';
import 'providers/room_provider.dart';
import 'providers/settings_provider.dart';
import 'services/audio_session_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioSession = AudioSessionService();
  await audioSession.configureForMediaPlayback();

  runApp(BabyMonitarrApp(audioSession: audioSession));
}

class BabyMonitarrApp extends StatelessWidget {
  const BabyMonitarrApp({super.key, required this.audioSession});

  final AudioSessionService audioSession;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AudioProvider()),
        ChangeNotifierProxyProvider<SettingsProvider, ConnectionProvider>(
          create: (_) => ConnectionProvider(audioSession: audioSession),
          update: (_, settings, connection) {
            connection!.updateSettings(settings);
            return connection;
          },
        ),
        ChangeNotifierProxyProvider<ConnectionProvider, RoomProvider>(
          create: (_) => RoomProvider(),
          update: (_, connection, rooms) {
            final provider = rooms ?? RoomProvider();
            provider.bindConnection(connection);
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'BabyMonitarr',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const _AppShell(),
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (settings.isLoading) return const _SplashScreen();
    if (!settings.isOnboardingComplete) return const WelcomeScreen();
    return const DashboardScreen();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
