// lib/main.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'utils/app_env.dart';
import 'utils/helpers.dart';
import 'utils/app_theme.dart';
import 'utils/app_router.dart';
import 'services/push_notification_service.dart';
import 'widgets/offline_banner.dart';

// Global Messenger Key to show Push Notifications across all screens
final GlobalKey<ScaffoldMessengerState> globalMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await loadAppEnv();

    await Firebase.initializeApp();

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      return true;
    };
    GoogleFonts.config.allowRuntimeFetching = false;

    final supabaseUrl = appEnv('SUPABASE_URL');
    final supabaseAnonKey = appEnv('SUPABASE_ANON_KEY');

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Missing backend config. Rebuild with --dart-define-from-file=.env',
      );
    }

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    await PushNotificationService.initialize();

    runApp(const ProviderScope(child: HotPotChefApp()));
  } catch (error, stack) {
    debugPrint('HotPotChef failed to start: $error\n$stack');
    runApp(_StartupFailedApp(message: error.toString()));
  }
}

/// Shown instead of a blank window when Firebase/Supabase init fails.
class _StartupFailedApp extends StatelessWidget {
  const _StartupFailedApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F3EE),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HotPotChef could not start',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF241F1C),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF5C564F)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HotPotChefApp extends StatefulWidget {
  const HotPotChefApp({super.key});

  @override
  State<HotPotChefApp> createState() => _HotPotChefAppState();
}

class _HotPotChefAppState extends State<HotPotChefApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.openPendingAlert();
    });
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        AppRouter.router.go('/reset-password');
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'HotPotChef',
          scaffoldMessengerKey: globalMessengerKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system, // Respect system light/dark mode settings
          routerConfig: AppRouter.router,
          builder: (context, child) {
            return OfflineBannerHost(child: child ?? const SizedBox.shrink());
          },
        );
      },
    );
  }
}