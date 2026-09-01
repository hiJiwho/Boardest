import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_ui/bst_ui.dart';

void main() {
  group('AppTheme Tests', () {
    test('darkTheme initializes with expected colors and dark brightness', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, const Color(0xFF7F5AF0));
      expect(theme.colorScheme.secondary, const Color(0xFF2EC4B6));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0F0E17));
    });
  });

  group('Widget Tests', () {
    testWidgets('PrimaryButton renders and triggers onPressed', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: PrimaryButton(
              text: 'Click Primary',
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Click Primary'), findsOneWidget);
      await tester.tap(find.text('Click Primary'));
      expect(pressed, isTrue);
    });

    testWidgets('SecondaryButton renders and triggers onPressed', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SecondaryButton(
              text: 'Click Secondary',
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Click Secondary'), findsOneWidget);
      await tester.tap(find.text('Click Secondary'));
      expect(pressed, isTrue);
    });

    testWidgets('AppCard renders child and padding', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: AppCard(
              child: Text('Card Content'),
            ),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('AppDialog renders title, content, and actions', (tester) async {
      bool confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: AppDialog(
              title: 'Confirm Action',
              content: const Text('Are you sure you want to proceed?'),
              actions: [
                TextButton(
                  onPressed: () {
                    confirmed = true;
                  },
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Confirm Action'), findsOneWidget);
      expect(find.text('Are you sure you want to proceed?'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      expect(confirmed, isTrue);
    });
  });
}
