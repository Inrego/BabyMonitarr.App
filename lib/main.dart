import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/connection_provider.dart';
import 'providers/audio_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/welcome_screen.dart';
import 'screens/monitoring_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BabyMonitarrApp());
}

class BabyMonitarrApp extends StatelessWidget {
  const BabyMonitarrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AudioProvider()),
        ChangeNotifierProxyProvider<SettingsProvider, ConnectionProvider>(
          create: (_) => ConnectionProvider(),
          update: (_, settings, connection) {
            connection!.updateSettings(settings);
            return connection;
          },
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'BabyMonitarr',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            home: settings.isLoading
                ? const _SplashScreen()
                : settings.isOnboardingComplete
                ? const MonitoringScreen()
                : const WelcomeScreen(),
          );
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
