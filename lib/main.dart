// lib/main.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'utils/app_env.dart';
import 'utils/app_flavor.dart';
import 'utils/helpers.dart';
import 'utils/app_theme.dart';
import 'utils/app_router.dart';
import 'utils/diner_locale.dart';
import 'services/auth_session.dart';
import 'services/push_notification_service.dart';
import 'widgets/offline_banner.dart';

// Global Messenger Key to show Push Notifications across all screens
final GlobalKey<ScaffoldMessengerState> globalMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _HotPotBootApp());
}

/// Paints a cream splash immediately so Firebase/Supabase/FCM cannot leave a
/// white native window. Heavy init runs after the first frame.
class _HotPotBootApp extends StatefulWidget {
  const _HotPotBootApp();

  @override
  State<_HotPotBootApp> createState() => _HotPotBootAppState();
}

class _HotPotBootAppState extends State<_HotPotBootApp> {
  Widget? _app;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    try {
      await loadAppEnv();
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));

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
      ).timeout(const Duration(seconds: 10));
      unawaited(PushNotificationService.initialize());
      unawaited(AuthSession.discardStaleSession());

      if (!mounted) return;
      setState(() {
        _app = const ProviderScope(child: HotPotChefApp());
      });
    } catch (error, stack) {
      debugPrint('HotPotChef failed to start: $error\n$stack');
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _StartupFailedApp(message: _error!);
    }
    return _app ?? const _LaunchPlaceholder();
  }
}

class _LaunchPlaceholder extends StatelessWidget {
  const _LaunchPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFF6EEE6),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFE85A24)),
              SizedBox(height: 20),
              Text(
                'HotPotChef',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF241F1C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    // Notification permission dialog can zero the Android surface if it
    // opens on the first diner frame — wait until Home has painted.
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(PushNotificationService.requestPermissionAndSync());
    });
    unawaited(DinerLocaleController.instance.load());
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
    return MaterialApp.router(
      title: kAppStorefront.appName,
      scaffoldMessengerKey: globalMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
      builder: (context, child) {
        return OfflineBannerHost(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
