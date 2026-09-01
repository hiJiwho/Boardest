import 'package:flutter_test/flutter_test.dart';
import 'package:bst_canva/bst_canva.dart';

void main() {
  group('Canva Views Unit Tests', () {
    test('CanvaBoardView instantiation and properties', () {
      const boardView = CanvaBoardView(boardUrl: 'https://www.canva.com/design/DAG123');
      expect(boardView.boardUrl, 'https://www.canva.com/design/DAG123');
    });

    test('CanvaLibraryView instantiation and properties', () {
      const libraryView = CanvaLibraryView(url: 'https://www.canva.com/projects');
      expect(libraryView.url, 'https://www.canva.com/projects');
    });
  });
}
