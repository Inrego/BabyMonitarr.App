import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'theme/app_colors.dart';
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

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/icon/icon_transparent.svg',
                  width: 140,
                  height: 140,
                ),
                const SizedBox(height: 24),
                Text(
                  'BabyMonitarr',
                  style: AppTheme.title.copyWith(
                    color: AppColors.primaryWarm,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.tealAccent.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
