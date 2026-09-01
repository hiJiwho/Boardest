import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_ad/bst_ad.dart';

void main() {
  group('AdBanner Model Tests', () {
    test('AdBanner toJson and fromJson round-trip', () {
      final banner = AdBanner(
        id: 'ad_101',
        imageUrl: 'https://example.com/banner.png',
        clickUrl: 'https://example.com/promotion',
        remainingSeconds: 3600,
      );

      final json = banner.toJson();
      expect(json['id'], 'ad_101');
      expect(json['imageUrl'], 'https://example.com/banner.png');
      expect(json['clickUrl'], 'https://example.com/promotion');
      expect(json['remainingSeconds'], 3600);

      final restored = AdBanner.fromJson(json);
      expect(restored.id, 'ad_101');
      expect(restored.imageUrl, 'https://example.com/banner.png');
      expect(restored.clickUrl, 'https://example.com/promotion');
      expect(restored.remainingSeconds, 3600);
      expect(restored.toString(), contains('ad_101'));
    });

    test('AdBanner.fromJson handles nulls gracefully', () {
      final restored = AdBanner.fromJson({});
      expect(restored.id, '');
      expect(restored.imageUrl, '');
      expect(restored.clickUrl, '');
      expect(restored.remainingSeconds, 0);
    });
  });

  group('AdService Tests', () {
    test('getSortedBanners sorts by remainingSeconds ascending', () {
      final service = AdService();
      final b1 = AdBanner(id: '1', imageUrl: '', clickUrl: '', remainingSeconds: 500);
      final b2 = AdBanner(id: '2', imageUrl: '', clickUrl: '', remainingSeconds: 100);
      final b3 = AdBanner(id: '3', imageUrl: '', clickUrl: '', remainingSeconds: 300);

      final sorted = service.getSortedBanners([b1, b2, b3]);
      expect(sorted.map((b) => b.id).toList(), ['2', '3', '1']);
    });
  });

  group('AdRollingBanner Widget Tests', () {
    testWidgets('AdRollingBanner renders empty view when list is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdRollingBanner(banners: []),
          ),
        ),
      );

      expect(find.byType(PageView), findsNothing);
    });
  });
}
