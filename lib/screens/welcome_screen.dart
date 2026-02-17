import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/feature_pill.dart';
import 'onboarding_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text(
                'BabyMonitarr',
                style: AppTheme.subtitle.copyWith(
                  color: AppColors.primaryWarm,
                  fontSize: 20,
                ),
              ),
              const Spacer(flex: 1),
              SvgPicture.asset(
                'assets/icon/icon.svg',
                width: 200,
                height: 200,
              ),
              const SizedBox(height: 32),
              Text(
                'Watch Over Your\nLittle One',
                textAlign: TextAlign.center,
                style: AppTheme.title,
              ),
              const SizedBox(height: 16),
              Text(
                'Keep your baby safe and sound with gentle monitoring, '
                'soft alerts, and real-time audio streaming right to your device.',
                textAlign: TextAlign.center,
                style: AppTheme.body,
              ),
              const SizedBox(height: 24),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FeaturePill(
                    label: 'Gentle Alerts',
                    icon: Icons.notifications_none,
                  ),
                  FeaturePill(label: 'Soft Visuals', icon: Icons.visibility),
                  FeaturePill(label: 'Always Secure', icon: Icons.lock_outline),
                ],
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OnboardingScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryWarm,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    textStyle: AppTheme.subtitle,
                  ),
                  child: const Text('Get Started'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {},
                child: Text(
                  'Why BabyMonitarr?',
                  style: AppTheme.caption.copyWith(color: AppColors.tealAccent),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('From our family to yours ', style: AppTheme.caption),
                  Icon(
                    Icons.favorite,
                    size: 14,
                    color: AppColors.secondaryWarm,
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
