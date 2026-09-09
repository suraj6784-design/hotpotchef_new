import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/app_theme.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final light = l1 > l2 ? l1 : l2;
  final dark = l1 > l2 ? l2 : l1;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  test('muted and link text meet WCAG AA on brand surfaces', () {
    expect(_contrast(AppTheme.textMuted, AppTheme.snow), greaterThanOrEqualTo(4.5));
    expect(_contrast(AppTheme.textMuted, AppTheme.surfaceLight), greaterThanOrEqualTo(4.5));
    expect(_contrast(AppTheme.textMutedOnDark, AppTheme.backgroundDark), greaterThanOrEqualTo(4.5));
    expect(AppTheme.link, AppTheme.primaryDark);
    expect(_contrast(AppTheme.link, AppTheme.snow), greaterThanOrEqualTo(4.5));
  });

  test('list entrance stays snappy', () {
    expect(AppTheme.entranceDuration, const Duration(milliseconds: 250));
    expect(AppTheme.entranceStaggerMaxIndex, 4);
    expect(AppTheme.entranceStaggerMs * AppTheme.entranceStaggerMaxIndex, 240);
  });
}
