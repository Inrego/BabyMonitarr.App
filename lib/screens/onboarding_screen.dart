import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:validators/validators.dart' as validators;
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/monitor_address_field.dart';
import '../providers/settings_provider.dart';
import '../providers/connection_provider.dart';
import '../models/connection_state.dart';
import 'monitoring_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _urlController = TextEditingController();
  String? _errorText;
  _ConnectionStatus _status = _ConnectionStatus.idle;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String url) {
    if (url.isEmpty) return false;
    // Accept URLs with or without scheme
    final withScheme =
        url.startsWith('http://') || url.startsWith('https://') ? url : 'http://$url';
    return validators.isURL(withScheme, requireProtocol: false);
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (!_isValidUrl(url)) {
      setState(() {
        _errorText = 'Please enter a valid URL';
      });
      return;
    }

    // Ensure URL has a scheme
    final normalizedUrl =
        url.startsWith('http://') || url.startsWith('https://') ? url : 'http://$url';

    setState(() {
      _status = _ConnectionStatus.connecting;
      _errorText = null;
    });

    try {
      final settings = context.read<SettingsProvider>();
      final connection = context.read<ConnectionProvider>();

      await settings.setServerUrl(normalizedUrl);
      await connection.connect(normalizedUrl);

      // Give WebRTC a moment to establish
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      if (connection.isConnected ||
          connection.connectionInfo.state ==
              MonitorConnectionState.connected) {
        setState(() {
          _status = _ConnectionStatus.connected;
        });

        await settings.completeOnboarding();

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MonitoringScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _status = _ConnectionStatus.error;
          _errorText = 'Could not connect. Check the address and try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _ConnectionStatus.error;
        _errorText = 'Could not connect. Check the address and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Connect Your Monitor', style: AppTheme.subtitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.dns_outlined,
                    size: 36,
                    color: AppColors.tealAccent,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  "Where's Your Monitor?",
                  style: AppTheme.title.copyWith(fontSize: 24),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Enter the address of your BabyMonitarr server to start monitoring.',
                  textAlign: TextAlign.center,
                  style: AppTheme.body,
                ),
              ),
              const SizedBox(height: 32),
              MonitorAddressField(
                controller: _urlController,
                errorText: _errorText,
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() => _errorText = null);
                  }
                },
                onSubmitted: _connect,
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    side: const BorderSide(color: AppColors.tealAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  ),
                  child: Text(
                    'Need Help?',
                    style:
                        AppTheme.caption.copyWith(color: AppColors.tealAccent),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildStatusIndicator(),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _urlController.text.trim().isEmpty ||
                          _status == _ConnectionStatus.connecting
                      ? null
                      : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryWarm,
                    foregroundColor: AppColors.background,
                    disabledBackgroundColor:
                        AppColors.primaryWarm.withValues(alpha: 0.3),
                    disabledForegroundColor:
                        AppColors.background.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    textStyle: AppTheme.subtitle,
                  ),
                  child: _status == _ConnectionStatus.connecting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.background,
                          ),
                        )
                      : const Text('Connect to Monitor'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Make sure your device is on the same WiFi network',
                        style: AppTheme.caption,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    IconData icon;
    Color color;
    String text;

    switch (_status) {
      case _ConnectionStatus.idle:
        icon = Icons.circle;
        color = AppColors.textSecondary;
        text = 'Not connected yet';
        break;
      case _ConnectionStatus.connecting:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryWarm,
              ),
            ),
            const SizedBox(width: 8),
            Text('Connecting...',
                style: AppTheme.caption
                    .copyWith(color: AppColors.primaryWarm)),
          ],
        );
      case _ConnectionStatus.connected:
        icon = Icons.check_circle;
        color = AppColors.successGreen;
        text = 'Connected';
        break;
      case _ConnectionStatus.error:
        icon = Icons.error;
        color = AppColors.liveRed;
        text = 'Connection failed';
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Text(text, style: AppTheme.caption.copyWith(color: color)),
      ],
    );
  }
}

enum _ConnectionStatus { idle, connecting, connected, error }
