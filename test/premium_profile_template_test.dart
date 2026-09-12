import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/widgets/premium_profile_template.dart';

void main() {
  test('profile workspaces share exclusive titles and trust copy', () {
    expect(profileWorkspaceTitle(ProfileWorkspace.diner), 'Your table');
    expect(profileWorkspaceTitle(ProfileWorkspace.chef), 'Your kitchen');
    expect(profileWorkspaceTitle(ProfileWorkspace.driver), 'Your run');
    expect(profileWorkspaceRoleLabel(ProfileWorkspace.diner), 'Diner');
    expect(profileWorkspaceTrustLine(ProfileWorkspace.diner), isNot(contains('FSSAI')));
    expect(profileWorkspaceTrustLine(ProfileWorkspace.chef), contains('FSSAI'));
    expect(profileWorkspaceTrustLine(ProfileWorkspace.driver), contains('Verified'));
  });

  testWidgets('form section uses the shared cream card chrome', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PremiumProfileFormSection(
            title: 'Kitchen credentials',
            caption: 'FSSAI first',
            children: [Text('Licence field')],
          ),
        ),
      ),
    );
    expect(find.text('Kitchen credentials'), findsOneWidget);
    expect(find.text('Licence field'), findsOneWidget);
  });
}
