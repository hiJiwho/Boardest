import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/main.dart';
import 'package:boardest/models/app_settings.dart';
import 'package:boardest/views/setup_wizard_view.dart';

void main() {
  testWidgets('Setup Wizard smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(settings: AppSettings(), isLoggedIn: false));
    await tester.pump();

    // Verify that the onboarding setup wizard is displayed
    expect(find.byType(SetupWizardView), findsOneWidget);
  });
}
