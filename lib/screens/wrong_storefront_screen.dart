import 'package:flutter/material.dart';

import '../services/auth_session.dart';
import '../utils/app_flavor.dart';
import '../utils/app_theme.dart';

class WrongStorefrontScreen extends StatelessWidget {
  const WrongStorefrontScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = AuthSession.roleFromSession();
    return Scaffold(
              backgroundColor: AppTheme.snow,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(kAppStorefront.isPartner ? Icons.restaurant_menu_rounded : Icons.soup_kitchen_outlined,
                  size: 48, color: AppTheme.primary),
              const SizedBox(height: 20),
              Text(
                kAppStorefront.appName,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                kAppStorefront.wrongAccountMessage(role),
                style: TextStyle(fontSize: 15, height: 1.4, color: AppTheme.onSurfaceOf(context).withValues(alpha: 0.75)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => AuthSession.logout(context),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
