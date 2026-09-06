import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/school.dart';
import '../models/app_settings.dart';
import 'comcigan_service.dart';
import 'auth_service.dart';
import 'app_paths.dart';

class StorageService {
  static const String _keySchool = 'selected_school';
  static const String _keyGrade = 'selected_grade';
  static const String _keyClass = 'selected_class';
  static const String _keyAppSettings = 'app_settings';
  static const String _usbFileHistoryKey = 'usb_file_history';

  static Future<void> syncLocalSchoolConfigFile(AppSettings settings) async {
    if (kIsWeb) return;
    try {
      final configMap = {
        'region': settings.selectedSchool?.region ?? '',
        'schoolName': settings.selectedSchool?.name ?? '',
        'schoolId': settings.schoolId,
        'grade': settings.selectedGrade,
        'classNum': settings.selectedClass,
        'isSetupComplete': settings.isSetupComplete,
      };
      final configJson = const JsonEncoder.withIndent('  ').convert(configMap);
      
      final appDataFile = File(AppPaths.schoolConfigPath);
      await appDataFile.parent.create(recursive: true);
      await appDataFile.writeAsString(configJson);

      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final exeFile = File(p.join(exeDir, 'school_config.json'));
      if (await exeFile.exists()) {
        await exeFile.writeAsString(configJson);
      }

      final devFile = File('school_config.json');
      if (await devFile.exists()) {
        await devFile.writeAsString(configJson);
      }
    } catch (_) {}
  }

  /// Saves the complete AppSettings object to local storage.
  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppSettings, json.encode(settings.toJson()));
    
    if (!kIsWeb) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final file = File(p.join(exeDir, 'special_classroom.txt'));
        await file.writeAsString(settings.specialClassroomType.toString());
      } catch (_) {}

      try {
        final configMap = {
          'region': settings.selectedSchool?.region ?? '',
          'schoolName': settings.selectedSchool?.name ?? '',
          'schoolId': settings.schoolId,
          'grade': settings.selectedGrade,
          'classNum': settings.selectedClass,
          'isSetupComplete': settings.isSetupComplete,
        };
        final configJson = const JsonEncoder.withIndent('  ').convert(configMap);
        
        final appDataFile = File(AppPaths.schoolConfigPath);
        await appDataFile.parent.create(recursive: true);
        await appDataFile.writeAsString(configJson);

        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final exeFile = File(p.join(exeDir, 'school_config.json'));
        if (await exeFile.exists()) {
          await exeFile.writeAsString(configJson);
        }

        final devFile = File('school_config.json');
        if (await devFile.exists()) {
          await devFile.writeAsString(configJson);
        }
      } catch (_) {}
    }

    if (settings.selectedSchool != null) {
      await prefs.setString(_keySchool, json.encode(settings.toJson()));
    }
    await prefs.setInt(_keyGrade, settings.selectedGrade);
    await prefs.setInt(_keyClass, settings.selectedClass);

    // 클라우드 계정(Firestore users/{email})에도 환경설정 자동 백업 동기화
    AuthService().getCurrentUser().then((user) {
      if (user != null && user.email.isNotEmpty) {
        AuthService().saveUserSettings(user.email, settings);
      }
    }).catchError((_) {});
  }

  Future<void> saveSelectedSchool(School school) async {
    final current = await getSettings();
    await saveSettings(current.copyWith(selectedSchool: school));
  }

  /// Retrieves the AppSettings object from local storage.
  Future<AppSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyAppSettings);
    
    if (jsonStr == null) {
      final schoolStr = prefs.getString(_keySchool);
      School? legacySchool;
      if (schoolStr != null) {
        try {
          legacySchool = School.fromJson(json.decode(schoolStr) as Map<String, dynamic>);
        } catch (_) {}
      }
      final legacyGrade = prefs.getInt(_keyGrade) ?? 1;
      final legacyClass = prefs.getInt(_keyClass) ?? 1;

      return AppSettings(
        selectedSchool: legacySchool,
        selectedGrade: legacyGrade,
        selectedClass: legacyClass,
        isSetupComplete: false,
      );
    }

    try {
      return AppSettings.fromJson(json.decode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  /// Automatically checks for a local school_config.json file and syncs it.
  Future<AppSettings> loadConfigAndSync() async {
    AppSettings settings = await getSettings();
    if (kIsWeb) return settings;
    
    try {
      await AppPaths.init();
      File configFile = File(AppPaths.schoolConfigPath);
      if (!await configFile.exists()) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        configFile = File(p.join(exeDir, 'school_config.json'));
      }
      if (!await configFile.exists()) {
        configFile = File('school_config.json');
      }
      
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        
        final String region = jsonMap['region'] as String? ?? '서울';
        final String schoolName = jsonMap['schoolName'] as String? ?? '길동중학교';
        final int grade = (jsonMap['grade'] as num? ?? 1).toInt();
        final int classNum = (jsonMap['classNum'] as num? ?? 1).toInt();
        
        if (settings.selectedSchool == null ||
            settings.selectedSchool!.region != region ||
            settings.selectedSchool!.name != schoolName ||
            settings.selectedGrade != grade ||
            settings.selectedClass != classNum) {
          
          final comcigan = ComciganService();
          final schools = await comcigan.searchSchool(schoolName);
          final matched = schools.firstWhere(
            (s) => s.region == region && s.name.contains(schoolName),
            orElse: () => schools.isNotEmpty ? schools.first : School(id: 0, region: region, name: schoolName, code: 31828),
          );
          
          final String resolvedSchoolId = (jsonMap['schoolId'] as String?) ?? settings.schoolId;
          final bool configIsComplete = (jsonMap['isSetupComplete'] as bool?) ?? settings.isSetupComplete;
          
          final updated = settings.copyWith(
            selectedSchool: matched,
            schoolId: resolvedSchoolId,
            selectedGrade: grade,
            selectedClass: classNum,
            isSetupComplete: configIsComplete,
          );
          
          await saveSettings(updated);
          settings = updated;
          
          final authService = AuthService();
          await authService.loginOrSignupClass(
            region: region,
            school: schoolName,
            grade: grade,
            classNum: classNum,
          );
          
          debugPrint('[StorageService] school_config.json successfully loaded and synced for $schoolName.');
        }
      }
    } catch (e) {
      debugPrint('[StorageService] Error loading/syncing school_config.json: $e');
    }
    
    return settings;
  }

  Future<void> recordOpenedUsbFile(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList(_usbFileHistoryKey) ?? [];
      history.remove(filePath);
      history.insert(0, filePath);
      if (history.length > 50) {
        history = history.sublist(0, 50);
      }
      await prefs.setStringList(_usbFileHistoryKey, history);
    } catch (_) {}
  }

  Future<List<String>> getOpenedUsbFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_usbFileHistoryKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> clearUsbFileHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_usbFileHistoryKey);
    } catch (_) {}
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
