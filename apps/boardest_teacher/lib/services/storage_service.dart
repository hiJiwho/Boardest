import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/school.dart';
import '../models/app_settings.dart';
import '../config/app_config.dart';
import 'comcigan_service.dart';
import 'app_paths.dart';
import 'cloud_drive_service.dart';

class StorageService {
  static const String _keySchool = 'selected_school';
  static const String _keyGrade = 'selected_grade';
  static const String _keyClass = 'selected_class';
  static const String _keyAppSettings = 'app_settings';
  static const String _usbFileHistoryKey = 'usb_file_history';

  /// Saves the complete AppSettings object to local storage and hardened disk backup.
  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppSettings, json.encode(settings.toJson()));
    
    if (!kIsWeb) {
      // Save special classroom startup file for native C++ window resizing before Flutter runs
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final file = File(p.join(exeDir, 'special_classroom.txt'));
        await file.writeAsString(settings.specialClassroomType.toString());
      } catch (_) {}

      // Hardened disk backup for school_config.json
      try {
        final configMap = {
          'region': settings.selectedSchool?.region ?? '서울',
          'schoolName': settings.selectedSchool?.name ?? '',
          'schoolId': settings.schoolId.isNotEmpty ? settings.schoolId : 'ydm',
          'schoolCode': settings.selectedSchool?.code ?? 44134,
          'grade': settings.selectedGrade,
          'classNum': settings.selectedClass,
          'selectedTeacher': settings.selectedTeacher,
          'selectedTeacherId': settings.selectedTeacherId,
          'selectedTeacherName': settings.selectedTeacherName,
          'cafeteriaNum': settings.cafeteriaNum,
          'isHomeroom': settings.isHomeroom,
          'isSetupComplete': settings.isSetupComplete,
          'appSettings': settings.toJson(),
        };
        final configJson = const JsonEncoder.withIndent('  ').convert(configMap);
        
        final appDataFile = File(AppPaths.schoolConfigPath);
        await appDataFile.parent.create(recursive: true);
        await appDataFile.writeAsString(configJson);

        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final exeFile = File(p.join(exeDir, 'school_config.json'));
        await exeFile.writeAsString(configJson);

        final devFile = File('school_config.json');
        if (await devFile.exists()) {
          await devFile.writeAsString(configJson);
        }
      } catch (_) {}
    }

    // Maintain legacy fields for compatibility
    if (settings.selectedSchool != null) {
      await prefs.setString(_keySchool, json.encode(settings.selectedSchool!.toJson()));
    }
    await prefs.setInt(_keyGrade, settings.selectedGrade);
    await prefs.setInt(_keyClass, settings.selectedClass);
  }

  /// Retrieves the AppSettings object from local storage (with automatic disk backup recovery).
  Future<AppSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyAppSettings);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final decoded = json.decode(jsonStr) as Map<String, dynamic>;
        final parsed = AppSettings.fromJson(decoded);
        if (parsed.isSetupComplete || parsed.selectedSchool != null) {
          return parsed;
        }
      } catch (_) {}
    }

    // Disk fallback: check school_config.json
    if (!kIsWeb) {
      try {
        File? candidateFile;
        final f1 = File(AppPaths.schoolConfigPath);
        if (await f1.exists()) {
          candidateFile = f1;
        } else {
          final exeDir = File(Platform.resolvedExecutable).parent.path;
          final f2 = File(p.join(exeDir, 'school_config.json'));
          if (await f2.exists()) {
            candidateFile = f2;
          } else {
            final f3 = File('school_config.json');
            if (await f3.exists()) {
              candidateFile = f3;
            }
          }
        }

        if (candidateFile != null) {
          final content = await candidateFile.readAsString();
          final data = json.decode(content) as Map<String, dynamic>;
          if (data.containsKey('appSettings') && data['appSettings'] is Map) {
            final recovered = AppSettings.fromJson(Map<String, dynamic>.from(data['appSettings'] as Map));
            await prefs.setString(_keyAppSettings, json.encode(recovered.toJson()));
            return recovered;
          }

          final schoolName = data['schoolName']?.toString() ?? '양동중학교';
          final schoolId = data['schoolId']?.toString() ?? 'ydm';
          final schoolCode = int.tryParse(data['schoolCode']?.toString() ?? '') ?? 44134;
          final grade = int.tryParse(data['grade']?.toString() ?? '') ?? 1;
          final classNum = int.tryParse(data['classNum']?.toString() ?? '') ?? 1;
          final teacher = data['selectedTeacher']?.toString() ?? data['selectedTeacherName']?.toString() ?? '';
          final teacherId = data['selectedTeacherId']?.toString() ?? teacher;
          final isSetupComplete = data['isSetupComplete'] == true || (data['isSetupComplete']?.toString() == 'true');

          final recovered = AppSettings(
            selectedSchool: School(id: schoolCode, code: schoolCode, name: schoolName, region: data['region']?.toString() ?? '서울'),
            schoolId: schoolId,
            selectedGrade: grade,
            selectedClass: classNum,
            selectedTeacher: teacher,
            selectedTeacherId: teacherId,
            selectedTeacherName: teacher,
            cafeteriaNum: data['cafeteriaNum']?.toString() ?? '1',
            isHomeroom: data['isHomeroom'] == true,
            isSetupComplete: isSetupComplete || schoolName.isNotEmpty,
          );
          await prefs.setString(_keyAppSettings, json.encode(recovered.toJson()));
          return recovered;
        }
      } catch (_) {}
    }

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
      isSetupComplete: false,
    );
  }

  /// Clears all local and cloud session data (Logout)
  Future<void> clearAllSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAppSettings);
    await prefs.remove(_keySchool);
    await prefs.remove(_keyGrade);
    await prefs.remove(_keyClass);
    await prefs.remove('bst_google_access_token');
    await prefs.remove('bst_token');
    await prefs.remove('bst_cld_token');
    await prefs.remove('bst_google_user_email');
    await prefs.remove('bst_user_email');
    await prefs.remove('bst_google_email');
    await prefs.remove('bst_google_user_name');
    await prefs.remove('bst_user_name');
    await prefs.remove('bst_school_name');
    await prefs.remove('boardest_auth_callback_search');

    if (!kIsWeb) {
      try {
        final f1 = File(AppPaths.schoolConfigPath);
        if (await f1.exists()) await f1.delete();
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final f2 = File(p.join(exeDir, 'school_config.json'));
        if (await f2.exists()) await f2.delete();
      } catch (_) {}
    }

    await CloudDriveService.instance.clearSession();
  }

  /// Automatically syncs with Firestore teacher_profiles in real-time.
  Future<AppSettings> loadConfigAndSync() async {
    AppSettings settings = await getSettings();
    final prefs = await SharedPreferences.getInstance();
    String email = prefs.getString('bst_google_user_email') ?? '';
    if (email.isEmpty) {
      email = prefs.getString('bst_user_email') ?? prefs.getString('bst_google_email') ?? '';
    }
    if (email.isEmpty) {
      email = CloudDriveService.instance.userEmail ?? '';
    }
    
    if (email.isNotEmpty) {
      try {
        final docId = email.replaceAll('.', '_').replaceAll('@', '_').replaceAll('+', '_');
        final url = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_profiles/$docId?key=${AppConfig.firebaseApiKey}',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 404) {
          debugPrint('[StorageService] ℹ️ Teacher profile not found in remote Firestore (404). Retaining local cached settings.');
          return settings;
        } else if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final fields = data['fields'] as Map<String, dynamic>?;
          if (fields != null) {
            final Map<String, dynamic> map = {};
            fields.forEach((k, v) {
              if (v is Map) {
                map[k] = v['stringValue'] ?? v['integerValue'] ?? v['booleanValue'] ?? v['doubleValue'];
              }
            });
            
            final schoolName = map['schoolName']?.toString() ?? settings.selectedSchool?.name ?? '학교';
            final schoolId = map['schoolId']?.toString() ?? settings.schoolId;
            final schoolCodeStr = map['schoolCode']?.toString() ?? map['schoolId']?.toString() ?? '';
            final teacherName = map['teacherName']?.toString() ?? settings.selectedTeacherName;
            final teacherId = map['teacherId']?.toString() ?? settings.selectedTeacherId;
            final grade = int.tryParse(map['grade']?.toString() ?? '') ?? settings.selectedGrade;
            final classNum = int.tryParse(map['classNum']?.toString() ?? '') ?? settings.selectedClass;
            final cafeteria = map['cafeteriaNum']?.toString() ?? settings.cafeteriaNum;

            int parsedCode = int.tryParse(schoolCodeStr) ?? int.tryParse(schoolId) ?? settings.selectedSchool?.code ?? 44134;
            if (schoolId.toLowerCase() == 'ydm' || schoolName.contains('양동')) {
              parsedCode = 44134;
            }

            final updated = settings.copyWith(
              selectedSchool: School(
                id: parsedCode,
                code: parsedCode,
                name: schoolName,
                region: '서울',
              ),
              schoolId: schoolId,
              selectedTeacher: teacherId.isNotEmpty ? teacherId : teacherName,
              selectedTeacherId: teacherId.isNotEmpty ? teacherId : teacherName,
              selectedTeacherName: teacherName,
              selectedGrade: grade,
              selectedClass: classNum,
              cafeteriaNum: cafeteria,
              isSetupComplete: true,
            );
            await saveSettings(updated);
            settings = updated;
          }
        }
      } catch (_) {}
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
        return decoded.map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))).toList();
      }
      final appDataFile = File(p.join(AppPaths.dataRootSync, 'config', 'sync_configs.json'));
      if (await appDataFile.exists()) {
        final content = await appDataFile.readAsString();
        final decoded = json.decode(content) as List<dynamic>;
        return decoded.map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))).toList();
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
      return decoded.map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))).toList();
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

    if (!kIsWeb) {
      try {
        final f1 = File(AppPaths.schoolConfigPath);
        if (await f1.exists()) await f1.delete();
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final f2 = File(p.join(exeDir, 'school_config.json'));
        if (await f2.exists()) await f2.delete();
      } catch (_) {}
    }
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
