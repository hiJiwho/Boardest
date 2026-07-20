import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'bst_save_service.dart';

// ────────────────────────────────────────────────
// 공개 데이터 클래스
// ────────────────────────────────────────────────

class UsbFileState {
  final int lastPage;
  final int totalPages;
  final String type; // 'ppt', 'pdf', 'video'

  const UsbFileState({required this.lastPage, required this.totalPages, required this.type});

  Map<String, dynamic> toJson() => {'lastPage': lastPage, 'totalPages': totalPages, 'type': type};
  factory UsbFileState.fromJson(Map<String, dynamic> json) => UsbFileState(
    lastPage: json['lastPage'] as int? ?? 0,
    totalPages: json['totalPages'] as int? ?? 1,
    type: json['type'] as String? ?? 'ppt',
  );
}

class UsbSession {
  final String rootPath;
  List<String> sortedFiles;
  final Map<String, UsbFileState> fileStates;
  bool autoOpenEnabled;
  String? lastOpenedFile;

  UsbSession({
    required this.rootPath,
    required this.sortedFiles,
    required this.fileStates,
    required this.autoOpenEnabled,
    this.lastOpenedFile,
  });

  Map<String, dynamic> toJson() => {
    'rootPath': rootPath,
    'sortedFiles': sortedFiles,
    'fileStates': fileStates.map((k, v) => MapEntry(k, v.toJson())),
    'autoOpenEnabled': autoOpenEnabled,
    'lastOpenedFile': lastOpenedFile,
  };

  factory UsbSession.fromJson(Map<String, dynamic> json) => UsbSession(
    rootPath: json['rootPath'] as String? ?? '',
    sortedFiles: (json['sortedFiles'] as List?)?.map((e) => e.toString()).toList() ?? [],
    fileStates: (json['fileStates'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, UsbFileState.fromJson(v as Map<String, dynamic>))) ?? {},
    autoOpenEnabled: json['autoOpenEnabled'] as bool? ?? true,
    lastOpenedFile: json['lastOpenedFile'] as String?,
  );
}

// ────────────────────────────────────────────────
// 서비스
// ────────────────────────────────────────────────

/// USB별 수업 자료 세션을 관리하는 싱글턴 서비스
class UsbSessionService {
  static final UsbSessionService instance = UsbSessionService._();
  UsbSessionService._();

  static const _kFileName = 'usb_sessions.json';
  final Map<String, UsbSession> _sessions = {};
  bool _loaded = false;

  // 지원 확장자
  static const _pptExts = {'.pptx', '.ppt'};
  static const _pdfExts = {'.pdf'};
  static const _iwbExts = {'.iwb'};
  static const _hwpExts = {'.hwp'};
  static const _videoExts = {'.mp4', '.mkv', '.avi'};
  static final _allExts = {..._pptExts, ..._pdfExts, ..._iwbExts, ..._hwpExts, ..._videoExts};

  static Set<String> get _allowedExtensions {
    if (Platform.isAndroid) {
      return _pdfExts;
    }
    return _allExts;
  }

  static bool _isEligibleForReorder(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.hwp', '.ppt', '.pptx', '.pdf'].contains(ext);
  }

  // ── Storage ─────────────────────────────────

  Future<File> _getFile() async {
    if (!Platform.isWindows) {
      final supportDir = await getApplicationSupportDirectory();
      final targetDir = Directory(p.join(supportDir.path, 'BstSave', 'USB'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      return File(p.join(targetDir.path, _kFileName));
    }
    final targetDir = await BstSaveService.instance.directoryFor(BstSaveService.subUsb);
    return File(p.join(targetDir.path, _kFileName));
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final sessionsJson = json['usb_sessions'] as Map<String, dynamic>? ?? {};
        for (final entry in sessionsJson.entries) {
          _sessions[entry.key] = UsbSession.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[UsbSession] load error: $e');
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode({
        'usb_sessions': _sessions.map((k, v) => MapEntry(k, v.toJson())),
      }));
    } catch (e) {
      debugPrint('[UsbSession] save error: $e');
    }
  }

  // ── USB Serial ID ────────────────────────────

  /// Windows: VolumeSerialNumber으로 USB 고유 ID 획득
  /// Windows: VolumeSerialNumber으로 USB 고유 ID 획득 (Win32 API GetVolumeInformationW를 통한 FFI 호출로 0ms 초고속 감지)
  static Future<String?> getUsbSerialId(String driveLetter) async {
    if (!Platform.isWindows) return null;
    try {
      final letter = driveLetter.replaceAll(RegExp(r'[:\\\/]'), '').trim();
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID=\'${letter}:\'" | Select-Object -ExpandProperty VolumeSerialNumber'
      ]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) return out;
      }
    } catch (e) {
      debugPrint('[UsbSession] getUsbSerialId error: $e');
    }
    
    // fallback: drive letter itself
    final letter = driveLetter.replaceAll(RegExp(r'[:\\\/]'), '').trim();
    return letter;
  }

  // ── 파일 스캔 + 숫자 정렬 ───────────────────

  /// USB 폴더 탐색 경로 목록 (설정 기반)
  static List<String> getCandidatePaths(String usbRoot, {
    String? schoolName,
    int? grade,
    String? year,
  }) {
    final yearStr = year ?? DateTime.now().year.toString();
    final paths = <String>[];
    // /Bst/
    paths.add(p.join(usbRoot, 'Bst'));
    // /N학년/
    if (grade != null) {
      paths.add(p.join(usbRoot, '${grade}학년'));
    }
    // 학교명 폴더
    if (schoolName != null && schoolName.isNotEmpty) {
      paths.add(p.join(usbRoot, schoolName));
      paths.add(p.join(usbRoot, yearStr, schoolName));
    }
    // 연도 폴더
    paths.add(p.join(usbRoot, yearStr));
    // USB 루트
    paths.add(usbRoot);
    return paths;
  }

  /// 폴더들을 지능적으로 탐색해 수업 자료 파일 목록 반환 (중복 제거, 숫자 정렬)
  /// 학교명(양동중학교, 양동중 등) 및 연도(2026 등) 폴더가 있는 경우 재귀 탐색하여 내부 PPT, PDF를 들고옵니다.
  static Future<List<String>> scanAndSortFiles(
    String usbRoot, {
    String? schoolName,
    String? year,
    int? grade,
    String? classNickname,
  }) async {
    final seen = <String>{};
    final allFiles = <String>[];

    // Check BoardestUSB.json config for Boardest-Pro and Boardest-Ultra configurations
    final jsonFile = File(p.join(usbRoot, 'BoardestUSB.json'));
    if (jsonFile.existsSync()) {
      try {
        final content = jsonFile.readAsStringSync();
        final config = jsonDecode(content);
        final String? type = config['type'];
        
        if (type == 'Bst' && classNickname != null && classNickname.isNotEmpty) {
          final classes = config['classes'] as Map<String, dynamic>? ?? {};
          final classData = classes[classNickname] as Map<String, dynamic>?;
          final visibleFiles = (classData?['visible_files'] as List?)?.map((e) => e.toString()).toList() ?? [];
          
          final list = <String>[];
          for (final file in visibleFiles) {
            final ext = p.extension(file).toLowerCase();
            final subDir = (ext.contains('ppt') || ext.contains('pptx')) ? 'PPT' : 'PDF';
            final fullPath = p.join(usbRoot, 'bst', subDir, file);
            if (File(fullPath).existsSync()) {
              list.add(fullPath);
            }
          }
          return list;
        } else if (type == 'Lite' && classNickname != null && classNickname.isNotEmpty) {
          final liteSettings = config['lite_settings'] as Map<String, dynamic>? ?? {};
          final relativePath = liteSettings[classNickname] as String?;
          if (relativePath != null && relativePath.isNotEmpty) {
            final dirPath = p.join(usbRoot, relativePath);
            final dir = Directory(dirPath);
            if (dir.existsSync()) {
              final files = await dir.list().toList();
              final localAllowedExtensions = {..._pptExts, ..._pdfExts, ..._iwbExts, ..._hwpExts};
              final list = <String>[];
              for (final e in files) {
                if (e is File) {
                  final ext = p.extension(e.path).toLowerCase();
                  if (localAllowedExtensions.contains(ext)) {
                    list.add(e.path);
                  }
                }
              }
              list.sort((a, b) {
                final isEligA = _isEligibleForReorder(a);
                final isEligB = _isEligibleForReorder(b);
                if (isEligA != isEligB) {
                  return isEligA ? -1 : 1;
                }
                final numA = _leadingNumber(p.basename(a));
                final numB = _leadingNumber(p.basename(b));
                if (numA != numB) return numA.compareTo(numB);
                return p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
              });
              return list;
            }
          }
          return [];
        }
      } catch (e) {
        debugPrint('[UsbSession] BoardestUSB.json parse failed: $e');
      }
    }

    final yearStr = year ?? DateTime.now().year.toString();
    final tokens = <String>{'bst', ...buildSchoolFolderTokens(schoolName, year: yearStr)};
    if (grade != null) tokens.add('${grade}학년');

    // 2. USB 루트 디렉토리 스캔을 통해 조건에 부합하는 폴더들 식별
    final rootDir = Directory(usbRoot);
    final matchedFolders = <Directory>[];

    if (await rootDir.exists()) {
      try {
        final rootEntities = await rootDir.list().toList();
        for (final entity in rootEntities) {
          if (entity is Directory) {
            final folderName = p.basename(entity.path);
            if (folderNameMatchesTokens(folderName, tokens.toList())) {
              matchedFolders.add(entity);
            }
          }
        }
      } catch (e) {
        debugPrint('[UsbSession] Root scan list error: $e');
      }
    }

    // 3. 지능형 탐색:
    // 폴더 내부가 바로 파일들로 구성되어 있으면 직접 들고오고,
    // 서브폴더가 존재한다면 그 안의 PPT, PDF 파일들도 함께 수집합니다.
    const maxFiles = 800;
    final localAllowedExtensions = {..._pptExts, ..._pdfExts, ..._iwbExts};
    for (final dir in matchedFolders) {
      if (allFiles.length >= maxFiles) break;
      if (!await dir.exists()) continue;
      try {
        final entities = await dir.list().toList();
        
        // 3-1. 폴더 직속 파일 스캔
        for (final e in entities) {
          if (e is File) {
            final ext = p.extension(e.path).toLowerCase();
            if (localAllowedExtensions.contains(ext) && seen.add(e.path)) {
              allFiles.add(e.path);
              if (allFiles.length >= maxFiles) break;
            }
          }
        }
        
        // 3-2. 폴더 내부 서브디렉토리 재귀 탐색
        if (allFiles.length < maxFiles) {
        for (final e in entities) {
          if (allFiles.length >= maxFiles) break;
          if (e is Directory) {
            try {
              final subEntities = await e.list().toList();
              for (final subE in subEntities) {
                if (allFiles.length >= maxFiles) break;
                if (subE is File) {
                  final ext = p.extension(subE.path).toLowerCase();
                  if (localAllowedExtensions.contains(ext) && seen.add(subE.path)) {
                    allFiles.add(subE.path);
                  }
                }
              }
            } catch (_) {}
          }
        }
        }
      } catch (_) {}
    }

    // 정렬: HWP, PPT, PDF가 최우선 위로 오고, 그 후 숫자 오름차순, 같은 숫자면 PPT > PDF > video, 이후 파일명 알파벳
    allFiles.sort((a, b) {
      final isEligA = _isEligibleForReorder(a);
      final isEligB = _isEligibleForReorder(b);
      if (isEligA != isEligB) {
        return isEligA ? -1 : 1;
      }
      final numA = _leadingNumber(p.basename(a));
      final numB = _leadingNumber(p.basename(b));
      if (numA != numB) return numA.compareTo(numB);
      final priA = _extPriority(p.extension(a).toLowerCase());
      final priB = _extPriority(p.extension(b).toLowerCase());
      if (priA != priB) return priA.compareTo(priB);
      return p.basename(a).compareTo(p.basename(b));
    });

    return allFiles;
  }

  static int _leadingNumber(String filename) {
    final m = RegExp(r'^(\d+)').firstMatch(filename);
    return m != null ? (int.tryParse(m.group(1)!) ?? 9999) : 9999;
  }

  static int _extPriority(String ext) {
    if (_pptExts.contains(ext)) return 0;
    if (_pdfExts.contains(ext)) return 1;
    if (_iwbExts.contains(ext)) return 2;
    return 3;
  }

  static String getFileType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    if (_pptExts.contains(ext)) return 'ppt';
    if (_pdfExts.contains(ext)) return 'pdf';
    if (_iwbExts.contains(ext)) return 'iwb';
    return 'video';
  }

  // ── 세션 API ────────────────────────────────

  Future<bool> hasSession(String usbId) async {
    await _load();
    return _sessions.containsKey(usbId);
  }

  Future<UsbSession?> getSession(String usbId) async {
    await _load();
    return _sessions[usbId];
  }

  Future<void> initSession(String usbId, String usbRoot, List<String> sortedFiles) async {
    await _load();
    _sessions[usbId] = UsbSession(
      rootPath: usbRoot,
      sortedFiles: sortedFiles,
      fileStates: {},
      autoOpenEnabled: true,
    );
    await _save();
  }

  Future<void> updateSortedFiles(String usbId, List<String> sortedFiles) async {
    await _load();
    final session = _sessions[usbId];
    if (session == null) return;
    session.sortedFiles = sortedFiles;
    await _save();
  }

  Future<void> updateFileState(
    String usbId,
    String filePath,
    int page,
    int totalPages,
  ) async {
    await _load();
    final session = _sessions[usbId];
    if (session == null) return;
    session.fileStates[filePath] = UsbFileState(
      lastPage: page,
      totalPages: totalPages,
      type: getFileType(filePath),
    );
    session.lastOpenedFile = filePath;
    await _save();
  }

  Future<void> setLastOpenedFile(String usbId, String filePath) async {
    await _load();
    final session = _sessions[usbId];
    if (session == null) return;
    session.lastOpenedFile = filePath;
    if (!session.fileStates.containsKey(filePath)) {
      session.fileStates[filePath] = UsbFileState(
        lastPage: 0,
        totalPages: 1,
        type: getFileType(filePath),
      );
    }
    await _save();
  }

  Future<void> setAutoOpen(String usbId, bool value) async {
    await _load();
    final session = _sessions[usbId];
    if (session == null) return;
    session.autoOpenEnabled = value;
    await _save();
  }

  Future<UsbFileState?> getFileState(String usbId, String filePath) async {
    await _load();
    return _sessions[usbId]?.fileStates[filePath];
  }

  /// sortedFiles에서 마지막으로 기록된 파일 (lastOpenedFile 우선, 없으면 fileStates 역순)
  Future<String?> getLastOpenedFile(String usbId) async {
    await _load();
    final session = _sessions[usbId];
    if (session == null) return null;
    
    if (session.lastOpenedFile != null && session.sortedFiles.contains(session.lastOpenedFile)) {
      return session.lastOpenedFile;
    }
    
    for (final f in session.sortedFiles.reversed) {
      if (session.fileStates.containsKey(f)) return f;
    }
    return session.sortedFiles.isNotEmpty ? session.sortedFiles.last : null;
  }

  /// 현재 파일 다음 파일 경로 반환
  Future<String?> findNextFile(String usbId, String currentFilePath) async {
    await _load();
    final session = _sessions[usbId];
    if (session == null) return null;
    final idx = session.sortedFiles.indexOf(currentFilePath);
    if (idx < 0 || idx >= session.sortedFiles.length - 1) return null;
    return session.sortedFiles[idx + 1];
  }

  /// 현재 파일 이전 파일 경로 반환
  Future<String?> findPrevFile(String usbId, String currentFilePath) async {
    await _load();
    final session = _sessions[usbId];
    if (session == null) return null;
    final idx = session.sortedFiles.indexOf(currentFilePath);
    if (idx <= 0) return null;
    return session.sortedFiles[idx - 1];
  }

  /// 다음 USB 파일을 열어야 할 때: 현재 페이지가 총 페이지를 넘었을 때만 (0-based).
  bool shouldOpenNextUsbFile(int currentPage, int totalPages) {
    return totalPages > 0 && currentPage >= totalPages - 1;
  }

  /// 학교명·연도로 USB 루트 폴더명 매칭 토큰 생성 (예: 2021, 길동중, 길동, 길동중학교).
  static List<String> buildSchoolFolderTokens(String? schoolName, {String? year}) {
    final tokens = <String>{};
    final yearStr = year ?? DateTime.now().year.toString();
    tokens.add(yearStr);

    var name = (schoolName ?? '').trim();
    if (name.isEmpty) return tokens.toList();

    final yearInName = RegExp(r'^(\d{4})').firstMatch(name);
    if (yearInName != null) tokens.add(yearInName.group(1)!);

    tokens.add(name);

    final withoutSchool = name
        .replaceAll('초등학교', '')
        .replaceAll('중학교', '')
        .replaceAll('고등학교', '')
        .replaceAll('학교', '')
        .trim();
    if (withoutSchool.isNotEmpty) {
      var stem = withoutSchool;
      while (stem.length >= 2) {
        tokens.add(stem);
        if (stem.length <= 2) break;
        stem = stem.substring(0, stem.length - 1);
      }
    }
    return tokens.toList();
  }

  static bool folderNameMatchesTokens(String folderName, List<String> tokens) {
    final fn = folderName.toLowerCase();
    for (final raw in tokens) {
      final t = raw.toLowerCase().trim();
      if (t.isEmpty) continue;
      if (fn == t) return true;
      if (t.length >= 2 && fn.contains(t)) return true;
      if (fn.length >= 2 && t.contains(fn)) return true;
    }
    return false;
  }
}
