// lib/utils/app_router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/app_role.dart';
import '../screens/auth_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/customer_hub.dart';
import '../screens/chef_hub.dart';
import '../screens/driver_hub.dart';
import '../screens/in_app_chat_screen.dart';
import '../screens/chat_inbox_screen.dart';
import '../screens/meal_link_screen.dart';
import '../screens/live_tracking_screen.dart';
import '../screens/chef_profile_screen.dart';
import '../screens/driver_profile_screen.dart';
import '../screens/customer_profile_screen.dart';
import '../screens/chef_analytics_screen.dart';
import '../screens/chef_publish_meal_screen.dart';
import '../screens/referral_screen.dart';
import '../screens/customer_order_history_screen.dart';
import '../screens/customer_bulk_request_screen.dart';
import '../screens/driver_id_card_screen.dart';
import '../services/auth_session.dart';
import '../widgets/not_found_page.dart';
import 'app_page.dart';
import 'helpers.dart';

GoRoute _fadeRoute(
  String path,
  Widget Function(BuildContext context, GoRouterState state) builder,
) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => appFadeSlidePage(
      key: state.pageKey,
      child: builder(context, state),
    ),
  );
}

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
        '/driver-id-card',
        '/chef-publish-meal',
        '/chats',
      ];
      if (!isAuthenticated && (protectedChefDriverRoutes.contains(path) || path.startsWith('/chat/'))) {
        return '/auth';
      }

      // Recovery session is authenticated — stay on the new-password screen.
      if (isPasswordRecoveryPath(path)) {
        return path == '/reset-callback' ? '/reset-password' : null;
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
      _fadeRoute('/auth', (context, state) => const AuthScreen()),
      _fadeRoute('/reset-password', (context, state) => const ResetPasswordScreen()),
      _fadeRoute('/reset-callback', (context, state) => const ResetPasswordScreen()),
      _fadeRoute(
        '/customer-hub',
        (context, state) => CustomerHubScreen(
          key: ValueKey('customer-${state.uri.query}'),
          initialTab: customerHubTabIndex(state.uri.queryParameters['tab']),
        ),
      ),
      _fadeRoute(
        '/chef-hub',
        (context, state) => ChefDashboardScreen(
          key: ValueKey('chef-${state.uri.query}'),
          initialTab: chefHubTabIndex(state.uri.queryParameters['tab']),
        ),
      ),
      _fadeRoute('/driver-hub', (context, state) => const DriverHubScreen()),
      _fadeRoute('/chef-publish-meal', (context, state) {
        final extra = state.extra;
        final meal = extra is Map<String, dynamic>
            ? extra
            : extra is Map
                ? Map<String, dynamic>.from(extra)
                : null;
        return ChefPublishMealScreen(existingMeal: meal);
      }),
      _fadeRoute(
        '/meal/:mealId',
        (context, state) => MealLinkScreen(mealId: state.pathParameters['mealId'] ?? ''),
      ),
      _fadeRoute('/chats', (context, state) => const ChatInboxScreen()),
      _fadeRoute('/chat/:mealId', (context, state) {
        final mealId = state.pathParameters['mealId'] ?? '';
        return InAppChatScreen(
          mealId: mealId,
          roomName: state.uri.queryParameters['roomName'] ?? 'Chat',
          otherUserId: state.uri.queryParameters['otherUserId'],
          memberIds: parseChatMemberIds(state.uri.queryParameters['memberIds']),
          isGroup: state.uri.queryParameters['group'] == '1',
        );
      }),
      _fadeRoute('/tracking', (context, state) {
        try {
          final extra = state.extra;
          final mapExtra = extra is Map ? Map<String, dynamic>.from(extra) : <String, dynamic>{};
          final orderId = state.uri.queryParameters['orderId'];
          final order = mapExtra['order'] is Map
              ? Map<String, dynamic>.from(mapExtra['order'] as Map)
              : (orderId != null && orderId.isNotEmpty)
                  ? <String, dynamic>{'id': orderId, 'order_id': orderId}
                  : <String, dynamic>{};
          return LiveTrackingScreen(
            order: order,
            isDriver: mapExtra['isDriver'] == true,
            isDineInNavigation: mapExtra['isDineInNavigation'] == true,
          );
        } catch (e, stack) {
          FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Tracking route parameter parsing failure');
          return const Scaffold(body: Center(child: Text('Invalid tracking parameters')));
        }
      }),
      _fadeRoute('/customer-profile', (context, state) => const CustomerProfileScreen()),
      _fadeRoute('/chef-profile', (context, state) => const ChefProfileScreen()),
      _fadeRoute('/driver-profile', (context, state) => const DriverProfileScreen()),
      _fadeRoute('/driver-id-card', (context, state) {
        final extra = state.extra is Map ? Map<String, dynamic>.from(state.extra as Map) : <String, dynamic>{};
        return DriverIdCardScreen(
          driverName: extra['name']?.toString() ?? 'Delivery Partner',
          driverPhone: extra['phone']?.toString() ?? '',
          avatarUrl: extra['avatarUrl']?.toString(),
        );
      }),
      _fadeRoute('/chef-analytics', (context, state) => const ChefAnalyticsScreen()),
      _fadeRoute('/referral', (context, state) => const ReferralScreen()),
      _fadeRoute('/order-history', (context, state) => const CustomerOrderHistoryScreen()),
      _fadeRoute('/bulk-request', (context, state) => const CustomerBulkRequestScreen()),
    ],
  );
}