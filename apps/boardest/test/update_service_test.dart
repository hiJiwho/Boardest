import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/services/update_service.dart';

void main() {
  group('UpdateService Version Constants and Normalization Tests', () {
    test('defaultVersion and metadata constants are aligned to v5.5.1+5510', () {
      expect(UpdateService.defaultVersion, equals('5.5.1'));
      expect(UpdateService.defaultBuildNumber, equals('5510'));
      expect(UpdateService.defaultFullVersion, equals('5.5.1+5510'));
    });

    test('normalizeVersion correctly strips prefix v and build metadata', () {
      expect(UpdateService.normalizeVersion('5.5.0'), equals('5.5.0'));
      expect(UpdateService.normalizeVersion('v5.5.0'), equals('5.5.0'));
      expect(UpdateService.normalizeVersion('5.5.0+5500'), equals('5.5.0'));
      expect(UpdateService.normalizeVersion('v5.5.0+5500'), equals('5.5.0'));
      expect(UpdateService.normalizeVersion('5.5.0.0'), equals('5.5.0'));
      expect(UpdateService.normalizeVersion('5.4.3+5430'), equals('5.4.3'));
      expect(UpdateService.normalizeVersion('v5.4.5'), equals('5.4.5'));
    });
  });

  group('UpdateService Windows Asset Scoring Tests', () {
    test('.msix is strictly prioritized over .appx for Class app', () {
      final msixScore = UpdateService.getWindowsAssetScore('boardest-class.msix', isCloud: false);
      final appxScore = UpdateService.getWindowsAssetScore('boardest-class.appx', isCloud: false);
      final genericMsixScore = UpdateService.getWindowsAssetScore('boardest.msix', isCloud: false);
      final genericAppxScore = UpdateService.getWindowsAssetScore('boardest.appx', isCloud: false);

      expect(msixScore, greaterThan(appxScore));
      expect(msixScore, greaterThan(genericMsixScore));
      expect(genericMsixScore, greaterThan(genericAppxScore));
      expect(genericMsixScore, greaterThan(appxScore));
      expect(appxScore, greaterThan(genericAppxScore));
    });

    test('Non-matching assets score 0', () {
      expect(UpdateService.getWindowsAssetScore('boardest-teacher.msix', isCloud: false), equals(0));
      expect(UpdateService.getWindowsAssetScore('boardest-class-lite.msix', isCloud: false), equals(0));
      expect(UpdateService.getWindowsAssetScore('boardest-overlay.msix', isCloud: false), equals(0));
      expect(UpdateService.getWindowsAssetScore('boardest-cloud.msix', isCloud: false), equals(0));
      expect(UpdateService.getWindowsAssetScore('boardest.apk', isCloud: false), equals(0));
    });

    test('Cloud mode prioritizes boardest-cloud.msix over .appx and non-cloud', () {
      final cloudMsix = UpdateService.getWindowsAssetScore('boardest-cloud.msix', isCloud: true);
      final cloudAppx = UpdateService.getWindowsAssetScore('boardest-cloud.appx', isCloud: true);
      final nonCloud = UpdateService.getWindowsAssetScore('boardest-class.msix', isCloud: true);

      expect(cloudMsix, greaterThan(cloudAppx));
      expect(cloudMsix, greaterThan(0));
      expect(nonCloud, equals(0));
    });
  });

  group('UpdateService Dynamic Extension Extraction Tests', () {
    test('extractExtensionFromUrl accurately extracts file extension from URL', () {
      expect(
        UpdateService.extractExtensionFromUrl('https://github.com/hiJiwho/Boardest/releases/download/v5.5.0/boardest-class.msix', isWindows: true),
        equals('msix'),
      );
      expect(
        UpdateService.extractExtensionFromUrl('https://github.com/hiJiwho/Boardest/releases/download/v5.5.0/boardest-class.appx', isWindows: true),
        equals('appx'),
      );
      expect(
        UpdateService.extractExtensionFromUrl('https://github.com/hiJiwho/Boardest/releases/download/v5.5.0/boardest.apk', isWindows: false),
        equals('apk'),
      );
      expect(
        UpdateService.extractExtensionFromUrl('https://github.com/hiJiwho/Boardest/releases/download/v5.5.0/boardest-installer.exe', isWindows: true),
        equals('exe'),
      );
      expect(
        UpdateService.extractExtensionFromUrl('https://example.com/download/unknown', isWindows: true),
        equals('msix'),
      );
      expect(
        UpdateService.extractExtensionFromUrl('https://example.com/download/unknown', isWindows: false),
        equals('apk'),
      );
    });
  });

  group('UpdateService Version Comparison (_isNewerVersion) Tests', () {
    bool _isNewerVersion(String target, String current) =>
        UpdateService.isNewerVersion(target, current);

    test('Identical version strings do not trigger update', () {
      expect(_isNewerVersion('v5.5.0', '5.5.0'), isFalse);
      expect(_isNewerVersion('5.5.0', '5.5.0+5500'), isFalse);
      expect(_isNewerVersion('v5.5.0+5500', '5.5.0+5500'), isFalse);
      expect(_isNewerVersion('v5.5.0', '5.5.0+5500'), isFalse);
      expect(_isNewerVersion('V5.5.0', '5.5.0'), isFalse);
      expect(_isNewerVersion('5.5.0', 'v5.5.0'), isFalse);
    });

    test('Newer versions trigger update', () {
      expect(_isNewerVersion('v5.5.1', '5.5.0+5500'), isTrue);
      expect(_isNewerVersion('v5.5.0+5501', '5.5.0+5500'), isTrue);
      expect(_isNewerVersion('v5.6.0', '5.5.0'), isTrue);
      expect(_isNewerVersion('v6.0.0', '5.5.0'), isTrue);
    });

    test('Older versions do not trigger update', () {
      expect(_isNewerVersion('v5.4.3', '5.5.0'), isFalse);
      expect(_isNewerVersion('v5.4.3+5430', '5.5.0+5500'), isFalse);
      expect(_isNewerVersion('5.4.3', '5.5.0'), isFalse);
      expect(_isNewerVersion('v5.5.0', '5.5.1'), isFalse);
    });
  });
}
