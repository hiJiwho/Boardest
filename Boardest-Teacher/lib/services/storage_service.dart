import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/school.dart';
import '../models/app_settings.dart';
import 'comcigan_service.dart';
import 'app_paths.dart';

class StorageService {
  static const String _keySchool = 'selected_school';
  static const String _keyGrade = 'selected_grade';
  static const String _keyClass = 'selected_class';
  static const String _keyAppSettings = 'app_settings';
  static const String _usbFileHistoryKey = 'usb_file_history';

  /// Saves the complete AppSettings object to local storage.
  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppSettings, json.encode(settings.toJson()));
    
    // Save special classroom startup file for native C++ window resizing before Flutter runs
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final file = File(p.join(exeDir, 'special_classroom.txt'));
      await file.writeAsString(settings.specialClassroomType.toString());
    } catch (_) {}

    // Save school_config.json back to AppData and others to ensure sync is maintained
    try {
      final configMap = {
        'region': settings.selectedSchool?.region ?? '서울',
        'schoolName': settings.selectedSchool?.name ?? '',
        'grade': settings.selectedGrade,
        'classNum': settings.selectedClass,
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

    // Maintain legacy fields for compatibility
    if (settings.selectedSchool != null) {
      await prefs.setString(_keySchool, json.encode(settings.selectedSchool!.toJson()));
    }
    await prefs.setInt(_keyGrade, settings.selectedGrade);
    await prefs.setInt(_keyClass, settings.selectedClass);
  }

  /// Retrieves the AppSettings object from local storage.
  Future<AppSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyAppSettings);
    if (jsonStr == null) {
      // Migrate from legacy fields if they exist
      final legacySchoolStr = prefs.getString(_keySchool);
      final legacyGrade = prefs.getInt(_keyGrade) ?? 1;
      final legacyClass = prefs.getInt(_keyClass) ?? 1;
      
      School? legacySchool;
      if (legacySchoolStr != null) {
        try {
          legacySchool = School.fromJson(json.decode(legacySchoolStr) as Map<String, dynamic>);
        } catch (_) {}
      }

      return AppSettings(
        selectedSchool: legacySchool,
        selectedGrade: legacyGrade,
        selectedClass: legacyClass,
        isSetupComplete: legacySchool != null, // If a school was selected, treat legacy as complete
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
        
        // If settings have changed or is not setup yet, perform background Comcigan search
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
          
          final updated = settings.copyWith(
            selectedSchool: matched,
            selectedGrade: grade,
            selectedClass: classNum,
            isSetupComplete: true,
          );
          
          await saveSettings(updated);
          settings = updated;
          
          debugPrint('[StorageService] school_config.json successfully loaded and synced for $schoolName.');
        }
      }
    } catch (e) {
      debugPrint('[StorageService] Error loading/syncing school_config.json: $e');
    }
    
    return settings;
  }

  /// Legacy methods preserved for compatibility
  Future<void> saveSelectedSchool(School school) async {
    final settings = await getSettings();
    await saveSettings(settings.copyWith(selectedSchool: school));
  }

  Future<School?> getSelectedSchool() async {
    final settings = await getSettings();
    return settings.selectedSchool;
  }

  Future<void> saveSelectedClass(int grade, int classNum) async {
    final settings = await getSettings();
    await saveSettings(settings.copyWith(selectedGrade: grade, selectedClass: classNum));
  }

  Future<Map<String, int>?> getSelectedClass() async {
    final settings = await getSettings();
    return {
      'grade': settings.selectedGrade,
      'class': settings.selectedClass,
    };
  }

  static const String _keyFolderSyncConfigs = 'folder_sync_configs_list';

  Future<void> saveSyncConfigs(List<Map<String, String>> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(configs);
    await prefs.setString(_keyFolderSyncConfigs, jsonStr);

    try {
      final configJson = const JsonEncoder.withIndent('  ').convert(configs);
      final appDataFile = File(p.join(AppPaths.dataRootSync, 'config', 'sync_configs.json'));
      await appDataFile.parent.create(recursive: true);
      await appDataFile.writeAsString(configJson);

      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final exeFile = File(p.join(exeDir, 'sync_configs.json'));
      await exeFile.writeAsString(configJson);
    } catch (_) {}
  }

  Future<List<Map<String, String>>> getSyncConfigs() async {
    // Try to load from json file first (ensures synchronization with external processes)
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final exeFile = File(p.join(exeDir, 'sync_configs.json'));
      if (await exeFile.exists()) {
        final content = await exeFile.readAsString();
        final decoded = json.decode(content) as List<dynamic>;
        return decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      }
      final appDataFile = File(p.join(AppPaths.dataRootSync, 'config', 'sync_configs.json'));
      if (await appDataFile.exists()) {
        final content = await appDataFile.readAsString();
        final decoded = json.decode(content) as List<dynamic>;
        return decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyFolderSyncConfigs);
    if (jsonStr == null) {
      // Fallback/Migrate from legacy fields if they exist
      final local = prefs.getString('local_sync_path');
      final usb = prefs.getString('usb_sync_folder');
      if (local != null && usb != null) {
        final list = [{'local': local, 'usb': usb}];
        await saveSyncConfigs(list);
        return list;
      }
      return [];
    }
    try {
      final decoded = json.decode(jsonStr) as List<dynamic>;
      return decoded.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Clears all stored settings (used for switching schools).
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySchool);
    await prefs.remove(_keyGrade);
    await prefs.remove(_keyClass);
    await prefs.remove(_keyAppSettings);
  }

  /// USB 파일 기록 저장 (최근 10개 파일 추적)
  Future<void> recordOpenedUsbFile(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList(_usbFileHistoryKey) ?? [];
      
      // 중복 제거
      history.removeWhere((item) => item.toLowerCase() == filePath.toLowerCase());
      
      // 맨 앞에 추가
      history.insert(0, filePath);
      
      // 최근 10개만 유지
      if (history.length > 10) {
        history = history.sublist(0, 10);
      }
      
      await prefs.setStringList(_usbFileHistoryKey, history);
      debugPrint('[StorageService] Recorded USB file: $filePath');
    } catch (e) {
      debugPrint('[StorageService] Error recording USB file: $e');
    }
  }

  /// USB 파일 열기 기록 조회 (최근순)
  Future<List<String>> getUsbFileHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_usbFileHistoryKey) ?? [];
    } catch (e) {
      debugPrint('[StorageService] Error retrieving USB file history: $e');
      return [];
    }
  }

  /// USB 파일 기록 초기화
  Future<void> clearUsbFileHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_usbFileHistoryKey);
      debugPrint('[StorageService] USB file history cleared');
    } catch (e) {
      debugPrint('[StorageService] Error clearing USB file history: $e');
    }
  }
}
