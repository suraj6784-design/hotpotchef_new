// lib/utils/app_router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../screens/auth_screen.dart';
import '../screens/customer_hub.dart';
import '../screens/chef_hub.dart';
import '../screens/driver_hub.dart';
import '../screens/in_app_chat_screen.dart';
import '../screens/live_tracking_screen.dart';
import '../screens/chef_profile_screen.dart';
import '../screens/driver_profile_screen.dart';
import '../screens/customer_profile_screen.dart';
import '../screens/chef_analytics_screen.dart';
import '../screens/chef_publish_meal_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/customer-hub',
    errorBuilder: (context, state) {
      final user = Supabase.instance.client.auth.currentUser;
      final role = (user?.userMetadata?['role'] ?? 'customer').toString().toLowerCase();

      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.deepOrange),
                const SizedBox(height: 16),
                const Text('Page not found', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('The page you are looking for does not exist or has been moved.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                  onPressed: () {
                    if (role == 'chef') {
                      context.go('/chef-hub');
                    } else if (role == 'driver') {
                      context.go('/driver-hub');
                    } else {
                      context.go('/customer-hub');
                    }
                  },
                  child: const Text('Return Home'),
                ),
              ],
            ),
          ),
        ),
      );
    },
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuthenticated = session != null;
      final path = state.uri.path;
      final role = session?.user.userMetadata?['role']?.toString().toLowerCase() ?? 'customer';

      // 1. Protect Chef and Driver routes against unauthenticated access
      const protectedChefDriverRoutes = [
        '/chef-hub',
        '/driver-hub',
        '/chef-analytics',
        '/chef-profile',
        '/driver-profile',
        '/chef-publish-meal',
      ];
      if (!isAuthenticated && protectedChefDriverRoutes.contains(path)) {
        return '/auth';
      }

      // 2. Enforce correct role-based landing on app startup or auth navigation
      if (isAuthenticated) {
        if (path == '/auth') {
          if (role == 'chef') return '/chef-hub';
          if (role == 'driver') return '/driver-hub';
          return '/customer-hub';
        }

        // Intercept if a Chef or Driver lands on the customer hub by default on app launch
        if (path == '/customer-hub') {
          if (role == 'chef') return '/chef-hub';
          if (role == 'driver') return '/driver-hub';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/customer-hub',
        builder: (context, state) => const CustomerHubScreen(),
      ),
      GoRoute(
        path: '/chef-hub',
        builder: (context, state) => const ChefDashboardScreen(),
      ),
      GoRoute(
        path: '/driver-hub',
        builder: (context, state) => const DriverHubScreen(),
      ),
      GoRoute(
        path: '/chef-publish-meal',
        builder: (context, state) => const ChefPublishMealScreen(),
      ),
      GoRoute(
        path: '/chat/:mealId',
        builder: (context, state) {
          final mealId = state.pathParameters['mealId'] ?? '';
          final roomName = state.uri.queryParameters['roomName'] ?? 'Chat';
          return InAppChatScreen(mealId: mealId, roomName: roomName);
        },
      ),
      GoRoute(
        path: '/tracking',
        builder: (context, state) {
          try {
            final extra = state.extra;
            final mapExtra = extra is Map<String, dynamic> ? extra : <String, dynamic>{};

            final order = mapExtra['order'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(mapExtra['order'])
                : <String, dynamic>{};
            final isDriver = mapExtra['isDriver'] == true;
            final isDineInNavigation = mapExtra['isDineInNavigation'] == true;

            return LiveTrackingScreen(order: order, isDriver: isDriver, isDineInNavigation: isDineInNavigation);
          } catch (e, stack) {
            FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Tracking route parameter parsing failure');
            return const Scaffold(body: Center(child: Text('Invalid tracking parameters')));
          }
        },
      ),
      GoRoute(
        path: '/customer-profile',
        builder: (context, state) => const CustomerProfileScreen(),
      ),
      GoRoute(
        path: '/chef-profile',
        builder: (context, state) => const ChefProfileScreen(),
      ),
      GoRoute(
        path: '/driver-profile',
        builder: (context, state) => const DriverProfileScreen(),
      ),
      GoRoute(
        path: '/chef-analytics',
        builder: (context, state) => const ChefAnalyticsScreen(),
      ),
    ],
  );
}