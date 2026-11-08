// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:boardest_student/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await initializeDateFormatting('ko_KR', null);
    } catch (_) {}
  });

  testWidgets('BoardestStudentApp smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BoardestStudentApp());
    await tester.pump();

    expect(find.byType(BoardestStudentApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(StudentMainShell), findsOneWidget);
  });
}
