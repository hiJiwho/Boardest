import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_pdf/bst_pdf.dart';

void main() {
  group('PdfBoardView Unit Tests', () {
    test('PdfBoardView parameters and default initialization', () {
      const pdfView = PdfBoardView(
        filePath: 'test.pdf',
        initialPage: 2,
      );

      expect(pdfView.filePath, 'test.pdf');
      expect(pdfView.initialPage, 2);
      expect(pdfView.onPageChanged, isNull);
    });

    testWidgets('PdfBoardView renders initial state in test tree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PdfBoardView(
              filePath: 'non_existent.pdf',
            ),
          ),
        ),
      );

      expect(find.byType(PdfBoardView), findsOneWidget);
    });
  });
}
