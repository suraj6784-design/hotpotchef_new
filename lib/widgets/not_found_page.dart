import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade400 : AppTheme.textMuted;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                'Page not found',
                style: TextStyle(color: titleColor, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'The page you are looking for does not exist or has been moved.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: onHome,
                child: const Text('Return Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
