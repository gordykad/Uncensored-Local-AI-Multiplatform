import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'models/chat_model.dart';
import 'models/message_model.dart';
import 'theme/app_theme.dart';
import 'bindings/app_bindings.dart';
import 'controllers/theme_controller.dart';
import 'services/log_service.dart';
import 'services/chatgpt_service.dart';
// ignore: unused_import
import 'screens/splash_screen.dart'; // needed in routes/app_routes.dart
import 'routes/app_routes.dart';

Future<void> main() async {
  // Wrap entire app in error zone to catch native/async crashes
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Catch Flutter framework errors (rendering, layout, etc.)
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exception}');
      _captureToLog('FlutterError', details.exception, details.stack);
    };

    // Catch unhandled platform errors (native crashes, isolate errors)
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformError: $error\n$stack');
      _captureToLog('PlatformError', error, stack);
      return true; // Prevent app from crashing
    };

    // Init Hive
    final appDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDir.path);

    // Register Hive adapters
    Hive.registerAdapter(ChatModelAdapter());
    Hive.registerAdapter(MessageModelAdapter());
    Hive.registerAdapter(MessageRoleAdapter());

    // Open Hive boxes
    await Hive.openBox<ChatModel>('chats');
    await Hive.openBox('settings');
    await Hive.openBox('models_meta');
    await Hive.openBox('imagegen'); // ticket 28 entries + lane keys (device-local)
    await Hive.openBox('mesh'); // ticket 31 catalog cache (no keys, ever)
    await Hive.openBox('connections'); // ticket 31 custom connections + Kai's pasted keys (device-local)
    await Hive.openBox('chatgpt'); // ticket 33 ChatGPT lane prefs + session flag (tokens live in the Keychain, 1.20.3)
    await ChatGptService.migrateLegacy(); // move any pre-1.20.3 plaintext Hive tokens into the Keychain

    // Load theme preference
    final themeController = Get.put(ThemeController());

    runApp(PortableAIApp(themeController: themeController));
  }, (error, stack) {
    // Last-resort error handler — prevents silent force-close
    debugPrint('Unhandled error: $error\n$stack');
    _captureToLog('Unhandled', error, stack);
  });
}

/// Build 18 diagnostics: framework errors land in the LogService ring
/// buffer (readable via /admin/logs) instead of dying in the console.
void _captureToLog(String kind, Object error, StackTrace? stack) {
  try {
    Get.find<LogService>()
        .error('$kind: $error', source: 'Framework');
  } catch (_) {}
}

class PortableAIApp extends StatelessWidget {
  final ThemeController themeController;
  
  const PortableAIApp({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Uncensored Local AI',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // ticket 08: dark-only — a light theme cannot be a black box
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      initialBinding: AppBindings(),
      initialRoute: AppRoutes.splash,
      getPages: AppRoutes.pages,
      // UI audit 2026-11-06 P1-1: clamp the system text scaler ONCE
      // here; TS styles return base sizes and Text scales a single
      // time against this clamped scaler.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.of(
            context,
          ).textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.35),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
