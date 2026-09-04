import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_theme.dart';

CustomTransitionPage<T> appFadeSlidePage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: AppTheme.pageDuration,
    reverseTransitionDuration: AppTheme.pageReverseDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, page) {
      final curved = CurvedAnimation(parent: animation, curve: AppTheme.pageCurve);
      final outgoing = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic);
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.05, 0.012), end: Offset.zero).animate(curved),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.92).animate(outgoing),
            child: page,
          ),
        ),
      );
    },
  );
}

PageRoute<T> appMaterialRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: AppTheme.pageDuration,
    reverseTransitionDuration: AppTheme.pageReverseDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppTheme.pageCurve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.05, 0.012), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
