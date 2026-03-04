import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/connection_state.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/qr_payload_parser.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

class QrScanScreen extends StatefulWidget {
  final bool isReconfigure;

  const QrScanScreen({super.key, this.isReconfigure = false});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  MobileScannerController? _scannerController;
  _ScanState _state = _ScanState.checkingPermission;
  String? _errorMessage;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }

    if (!mounted) return;

    if (status.isGranted || status.isLimited) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
      setState(() => _state = _ScanState.scanning);
    } else if (status.isPermanentlyDenied) {
      setState(() => _state = _ScanState.permanentlyDenied);
    } else {
      setState(() => _state = _ScanState.denied);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;

    final raw = barcode.rawValue;
    final result = QrPayloadParser.parse(raw);

    if (result.isValid) {
      _processing = true;
      _scannerController?.stop();
      _connectWithResult(result);
    } else {
      setState(() {
        _errorMessage = result.errorMessage;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _errorMessage = null);
      });
    }
  }

  Future<void> _connectWithResult(QrScanResult result) async {
    setState(() => _state = _ScanState.connecting);

    try {
      final settings = context.read<SettingsProvider>();
      final connection = context.read<ConnectionProvider>();

      await settings.setServerUrl(result.serverUrl!);
      await settings.setApiKey(result.apiKey!);
      await connection.connect(result.serverUrl!);

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      if (connection.isConnected ||
          connection.connectionInfo.state == MonitorConnectionState.connected) {
        if (widget.isReconfigure) {
          Navigator.of(context).pop();
        } else {
          await settings.completeOnboarding();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
            (route) => false,
          );
        }
      } else {
        setState(() {
          _state = _ScanState.scanning;
          _processing = false;
          _errorMessage = 'Could not connect. Check the server and try again.';
        });
        _scannerController?.start();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _errorMessage = null);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.scanning;
        _processing = false;
        _errorMessage = 'Could not connect. Check the server and try again.';
      });
      _scannerController?.start();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _errorMessage = null);
      });
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_state) {
        _ScanState.checkingPermission => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryWarm),
        ),
        _ScanState.denied => _buildPermissionDeniedView(permanent: false),
        _ScanState.permanentlyDenied => _buildPermissionDeniedView(permanent: true),
        _ScanState.scanning => _buildScannerView(),
        _ScanState.connecting => _buildConnectingView(),
      },
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController!,
          onDetect: _onDetect,
        ),
        // Dark overlay with viewfinder cutout
        CustomPaint(
          size: Size.infinite,
          painter: _ViewfinderPainter(),
        ),
        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _circleButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Text('Scan QR Code', style: AppTheme.subtitle),
                const Spacer(),
                _circleButton(
                  icon: Icons.flash_on,
                  onPressed: () => _scannerController?.toggleTorch(),
                ),
              ],
            ),
          ),
        ),
        // Bottom panel
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.qr_code,
                  size: 32,
                  color: AppColors.primaryWarm,
                ),
                const SizedBox(height: 12),
                Text(
                  'Point your camera at the QR code\nin your web interface',
                  textAlign: TextAlign.center,
                  style: AppTheme.body,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.liveRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: AppTheme.caption.copyWith(color: AppColors.liveRed),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primaryWarm,
            ),
          ),
          const SizedBox(height: 24),
          Text('Connecting...', style: AppTheme.subtitle),
          const SizedBox(height: 8),
          Text(
            'Setting up your monitor',
            style: AppTheme.body,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedView({required bool permanent}) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 24),
            Text(
              'Camera Access Needed',
              style: AppTheme.title.copyWith(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'To scan the QR code, BabyMonitarr needs camera access.',
              textAlign: TextAlign.center,
              style: AppTheme.body,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: permanent ? openAppSettings : _checkPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryWarm,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  textStyle: AppTheme.subtitle,
                ),
                child: Text(permanent ? 'Open Settings' : 'Allow Camera'),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const OnboardingScreen(),
                  ),
                );
              },
              child: Text(
                'Enter Manually Instead',
                style: AppTheme.caption.copyWith(color: AppColors.tealAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.8),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

enum _ScanState {
  checkingPermission,
  denied,
  permanentlyDenied,
  scanning,
  connecting,
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 40);
    const boxSize = 260.0;
    final rect = Rect.fromCenter(center: center, width: boxSize, height: boxSize);

    // Dark scrim with cutout
    final scrimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    // Corner brackets
    const armLength = 28.0;
    const strokeWidth = 3.0;
    const radius = 16.0;
    final bracketPaint = Paint()
      ..color = AppColors.primaryWarm
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + armLength)
        ..lineTo(rect.left, rect.top + radius)
        ..quadraticBezierTo(rect.left, rect.top, rect.left + radius, rect.top)
        ..lineTo(rect.left + armLength, rect.top),
      bracketPaint,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - armLength, rect.top)
        ..lineTo(rect.right - radius, rect.top)
        ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + radius)
        ..lineTo(rect.right, rect.top + armLength),
      bracketPaint,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - armLength)
        ..lineTo(rect.left, rect.bottom - radius)
        ..quadraticBezierTo(rect.left, rect.bottom, rect.left + radius, rect.bottom)
        ..lineTo(rect.left + armLength, rect.bottom),
      bracketPaint,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - armLength, rect.bottom)
        ..lineTo(rect.right - radius, rect.bottom)
        ..quadraticBezierTo(rect.right, rect.bottom, rect.right, rect.bottom - radius)
        ..lineTo(rect.right, rect.bottom - armLength),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
