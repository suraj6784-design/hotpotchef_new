// lib/utils/app_router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/app_role.dart';
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
import '../screens/referral_screen.dart';
import '../screens/customer_order_history_screen.dart';
import '../screens/customer_bulk_request_screen.dart';
import '../services/auth_session.dart';
import '../widgets/not_found_page.dart';

class AppRouter {
  static final AuthRefreshNotifier _authRefresh = AuthRefreshNotifier();

  static final GoRouter router = GoRouter(
    initialLocation: '/customer-hub',
    refreshListenable: _authRefresh,
    errorBuilder: (context, state) {
      final user = Supabase.instance.client.auth.currentUser;
      final role = AppRole.parse(user?.userMetadata?['role']?.toString());

      return NotFoundPage(onHome: () => context.go(role.hubPath));
    },
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuthenticated = session != null;
      final path = state.uri.path;
      final role = AppRole.parse(session?.user.userMetadata?['role']?.toString());

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
          return role.hubPath;
        }

        // Chefs and drivers should not land on the guest customer feed
        if (path == '/customer-hub' && role != AppRole.customer) {
          return role.hubPath;
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
            final mapExtra = extra is Map ? Map<String, dynamic>.from(extra) : <String, dynamic>{};

            final order = mapExtra['order'] is Map
                ? Map<String, dynamic>.from(mapExtra['order'] as Map)
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
      GoRoute(
        path: '/referral',
        builder: (context, state) => const ReferralScreen(),
      ),
      GoRoute(
        path: '/order-history',
        builder: (context, state) => const CustomerOrderHistoryScreen(),
      ),
      GoRoute(
        path: '/bulk-request',
        builder: (context, state) => const CustomerBulkRequestScreen(),
      ),
    ],
  );
}