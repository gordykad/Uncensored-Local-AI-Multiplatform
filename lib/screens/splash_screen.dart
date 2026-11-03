import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../widgets/faithful/textfx.dart';
import '../widgets/faithful/shared.dart';
import '../services/llm_service.dart';
import '../services/model_manager.dart';
import '../services/chat_storage_service.dart';
import '../services/local_api_server_service.dart';
import '../services/wakelock_service.dart';
import '../services/log_service.dart';
import '../services/telemetry_service.dart';
import '../services/background_optimizer_service.dart';
import '../routes/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      // Initialize logging first
      final log = Get.find<LogService>()..init();

      setState(() => _status = 'Setting up storage...');
      log.info('Initializing storage...', source: 'Splash');
      await Get.find<ChatStorageService>().init();

      setState(() => _status = 'Loading model catalog...');
      log.info('Loading model catalog...', source: 'Splash');
      await Get.find<ModelManager>().init();

      setState(() => _status = 'Preparing AI engine...');
      log.info('Preparing AI engine...', source: 'Splash');
      await Get.find<LlmService>().init();

      setState(() => _status = 'Preparing local API...');
      log.info('Preparing local API...', source: 'Splash');
      await Get.find<LocalApiServerService>().init();

      setState(() => _status = 'Starting telemetry...');
      log.info('Starting telemetry...', source: 'Splash');
      Get.find<TelemetryService>().init();

      setState(() => _status = 'Setting up background services...');
      log.info('Setting up background services...', source: 'Splash');
      await Get.find<WakelockService>().init();

      setState(() => _status = 'Ready!');
      log.info('All services initialized successfully', source: 'Splash');
      await Future.delayed(const Duration(milliseconds: 500));

      // Prompt for battery optimization on Android (first launch only)
      if (mounted) {
        await BackgroundOptimizerService.checkAndPrompt(context);
      }

      Get.offAllNamed(AppRoutes.home);
    } catch (e) {
      setState(() => _status = 'Error: $e');
      try {
        Get.find<LogService>().error('Init failed: $e', source: 'Splash');
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo
            Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/icon/minix-icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                )
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 24),
            SignalReveal(
              text: 'ASTRO MINIX',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w700,
                color: context.text,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing leaves this phone.',
              style: TextStyle(fontSize: 13, color: context.textM),
            ).animate().fadeIn(delay: 400.ms, duration: 600.ms),
            const SizedBox(height: 26),
            const RedactionBars(widths: [120, 84, 142], barHeight: 9),
            const SizedBox(height: 34),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(AppColors.accent),
              ),
            ).animate().fadeIn(delay: 600.ms),
            const SizedBox(height: 16),
            ScrambleText(
              text: _status,
              style: TextStyle(fontSize: 12, color: context.textD),
            ).animate().fadeIn(delay: 600.ms),
          ],
        ),
      ),
    );
  }
}
