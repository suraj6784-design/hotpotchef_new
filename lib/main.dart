// lib/main.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'utils/helpers.dart';
import 'utils/app_theme.dart';
import 'utils/app_router.dart';
import 'services/push_notification_service.dart';

// Global Messenger Key to show Push Notifications across all screens
final GlobalKey<ScaffoldMessengerState> globalMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load environment variables first
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp();

  // Pass all uncaught asynchronous errors to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // 2. Validate environment credentials
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    throw Exception("FATAL: SUPABASE_URL is missing or empty in your .env file!");
  }
  if (supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
    throw Exception("FATAL: SUPABASE_ANON_KEY is missing or empty in your .env file!");
  }

  // 3. Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // 4. Initialize Push Notifications cleanly via centralized service
  await PushNotificationService.initialize();

  runApp(const ProviderScope(child: HotPotChefApp()));
}

class HotPotChefApp extends StatelessWidget {
  const HotPotChefApp({super.key});

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
        );
      },
    );
  }
}