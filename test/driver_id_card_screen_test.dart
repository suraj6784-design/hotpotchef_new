import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/screens/driver_id_card_screen.dart';
import 'package:hotpotchef_new/utils/app_theme.dart';

Widget _wrap(Brightness brightness) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: const DriverIdCardScreen(
      driverName: 'Test Driver',
      driverPhone: '9876543210',
      idCardNo: 'HPC-D100001',
      bloodGroup: 'O+',
      emergencyPhone: '9812121212',
    ),
  );
}

void main() {
  test('formats driver ID card fields', () {
    expect(displayDriverIdCardNo(null), 'Pending assignment');
    expect(displayDriverIdCardNo('  hpc-d100014  '), 'HPC-D100014');
    expect(displayDriverBloodGroup(''), 'Not on file');
    expect(displayDriverBloodGroup('b+'), 'B+');
    expect(displayDriverEmergencyContact(' 9812 '), '9812');
  });

  testWidgets('ID card chrome uses light background in light theme', (tester) async {
    await tester.pumpWidget(_wrap(Brightness.light));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.background);
    final title = tester.widget<Text>(find.text('Digital ID Card'));
    expect(title.style?.color, AppTheme.textMain);
    expect(find.text('TEST DRIVER'), findsOneWidget);
    expect(find.text('PH: 9876543210'), findsOneWidget);
    expect(find.text('ID HPC-D100001'), findsOneWidget);
    expect(find.text('O+'), findsOneWidget);
    expect(find.text('9812121212'), findsOneWidget);
  });

  testWidgets('ID card chrome uses dark background in dark theme', (tester) async {
    await tester.pumpWidget(_wrap(Brightness.dark));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.backgroundDark);
    final title = tester.widget<Text>(find.text('Digital ID Card'));
    expect(title.style?.color, AppTheme.textMainDark);
  });
}
