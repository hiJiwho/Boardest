import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/main.dart';
import 'package:boardest/models/app_settings.dart';

void main() {
  testWidgets('Setup Wizard smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(settings: AppSettings(), isLoggedIn: false));

    // Verify that the onboarding setup wizard is displayed
    expect(find.text('학교 검색'), findsWidgets);
  });
}
