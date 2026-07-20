import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:ffi' hide Size;
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lesson.dart';
import '../models/app_settings.dart';
import '../models/school.dart';
import '../services/comcigan_service.dart';
import '../services/storage_service.dart';
import '../services/usb_format_service.dart';
import '../services/usb_bridge_service.dart';
import '../services/usb_sync_service.dart';
import '../services/neis_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/bst_cloud_service.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'usb_format_dialog.dart';
import '../widgets/usb_explorer.dart';
import 'teacher_settings_dialog.dart';
import 'pdf_board_view.dart';
import 'boardest_pen_view.dart';
import 'ppt_overlay_view.dart';
import 'hwp_overlay_view.dart';
import 'browser_board_view.dart';
import 'youtube_board_view.dart';
import 'canva_board_view.dart';
import 'boardbook_editor.dart';
import 'meal_view.dart';
import 'message_view.dart';
import '../services/tray_service.dart';
import 'weather_view.dart';
import 'school_calendar_view.dart';
import 'website_board_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import '../services/bst_save_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;

/// Boardest Teacher View
/// - 좌측(flex 2): 오늘의 시간표 / 클릭 시 주간 시간표 격자 토글. 담임인 경우 하단에 담임 학급 상태 및 주간 시간표 전환 제공.
/// - 가운데(flex 6): USB 탐색기 + USB 형식 지정 (Plus, Pro 자동 반별 매핑)
/// - 우측(flex 2): 수업 도구 (기본판서, PDF판서, PPT판서, 타이머, 발표자 추첨) 활성화
class TeacherView extends StatefulWidget {
  const TeacherView({super.key});

  static VoidCallback? onWindowClosePressed;
  static VoidCallback? onSettingsChanged;

  @override
  State<TeacherView> createState() => _TeacherViewState();
}

class _TeacherViewState extends State<TeacherView> {
  final ComciganService _comciganService = ComciganService();
  final StorageService _storageService = StorageService();
  final UsbSyncService _usbSyncService = UsbSyncService();

  AppSettings _settings = AppSettings();
  TimetableResult? _timetableResult;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isMiniMode = false;

  // 실시간 시계/교시
  DateTime _now = DateTime.now();
  Timer? _timer;
  int? _currentPeriod;
  int? _nextPeriod;

  // USB 상태
  bool _isUsbConnected = false;
  String _usbDriveLetter = '';
  String _currentDrivePath = '';
  String _usbType = 'Plus'; // 'Plus', 'Pro', 'Cloud'

  // AOT (Always On Top) 상태
  bool _isAlwaysOnTop = false;
  Timer? _usbTimer;
  bool _usbHandling = false;
  Map<String, dynamic>? _boardStatus;
  String _bridgeStatus = 'Waiting for Board';

  // 시간표 뷰 토글 상태
  bool _showWeeklyGrid = false;
  bool _isViewingHomeroomWeekly = false; // 담임 학급 주간 시간표 보기 중 여부

  // 플로팅 타이머 상태
  bool _showMiniTimer = false;
  int _timerSecondsElapsed = 0;
  int _timerTargetSeconds = 0;
  bool _timerRunning = false;
  Timer? _miniTimerInstance;
  // 우측 상단 기본 위치 (build 시 화면 크기 기준으로 조정)
  Offset _timerWindowOffset = const Offset(-1, -1); // -1: unset, build 시 초기화
  bool _timerFullscreen = false;

  // 플로팅 계산기 상태
  bool _showMiniCalculator = false;
  Offset _calculatorWindowOffset = const Offset(-1, -1);
  String _calcExpression = '';
  String _calcResult = '';

  // 플로팅 발표자 상태
  bool _showMiniPicker = false;
  Offset _pickerWindowOffset = const Offset(-1, -1);
  int _pickerMaxStudents = 30;
  int? _pickerWinner;
  bool _pickerRolling = false;

  // 인라인 보드 뷰 상태
  String? _activeInlineView; // 'whiteboard', 'pdf', 'website', null
  String? _activeFilePath;
  String? _activeSubject;

  // USB Pro 및 매핑/동기화 상태
  Map<String, String> _classroomFolderMappings = {};
  List<String> _usbFolders = [];
  String? _selectedProClassroom;
  List<Map<String, String>> _syncConfigs = [];
  List<StreamSubscription<FileSystemEvent>> _syncWatchers = [];
  Timer? _debounceSyncTimer;
  bool _isSyncingInProgress = false;
  String _lastSyncSummary = 'No sync has run yet';
  String _themeMode = 'system';
  String _themeColor = 'system';
  Color _systemAccentColor = const Color(0xFF7F5AF0);

  bool get _isDark {
    if (_themeMode == 'dark') return true;
    if (_themeMode == 'light') return false;
    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark;
  }

  Color get _bgColor =>
      _isDark ? const Color(0xFF0F0E17) : const Color(0xFFF3F3F5);
  Color get _surfaceColor => _isDark ? const Color(0xFF16161A) : Colors.white;
  Color get _borderColor =>
      _isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.08);
  Color get _textColor => _isDark ? Colors.white : Colors.black87;
  Color get _textColor54 => _isDark ? Colors.white54 : Colors.black54;
  Color get _textColor38 => _isDark ? Colors.white30 : Colors.black38;
  Color get _textColor70 => _isDark ? Colors.white70 : Colors.black54;
  Color get _textColor24 => _isDark ? Colors.white24 : Colors.black26;
  Color get _cardColor =>
      _isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02);
  Color get _accentColor {
    if (_themeColor == 'purple') return const Color(0xFF7F5AF0);
    if (_themeColor == 'green') return const Color(0xFF2CB67D);
    if (_themeColor == 'blue') return const Color(0xFF007AFF);
    if (_themeColor == 'orange') return const Color(0xFFFF9F0A);
    return _systemAccentColor;
  }

  Color get _accentColorLight {
    final base = _accentColor;
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor();
  }

  Color get _accentColorDark {
    final base = _accentColor;
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }

  Future<void> _loadWindowsAccentColor() async {
    if (!Platform.isWindows) return;
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[Convert]::ToString((Get-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\DWM").ColorizationColor, 16)',
      ]);
      if (res.exitCode == 0) {
        final hex = res.stdout.toString().trim();
        if (hex.length >= 8) {
          final colorInt = int.tryParse(hex, radix: 16);
          if (colorInt != null) {
            if (mounted) {
              setState(() {
                _systemAccentColor = Color(colorInt).withOpacity(1.0);
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    TeacherView.onWindowClosePressed = null;
    _init();
  }

  @override
  void dispose() {
    _stopFolderWatchers();
    if (TeacherView.onWindowClosePressed != null) {
      TeacherView.onWindowClosePressed = null;
    }
    _timer?.cancel();
    _usbTimer?.cancel();
    _miniTimerInstance?.cancel();
    super.dispose();
  }

  void _applyWindowFrameStyle(String style) async {
    if (!Platform.isWindows) return;
    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await const MethodChannel('com.boardest/launch_args').invokeMethod('setWindowFrameStyle', style);
    } catch (e) {
      debugPrint('[TeacherView] setWindowFrameStyle error: $e');
    }
  }

  Future<void> _init() async {
    await CloudDriveService.instance.init();
    await _loadClassroomMappings();
    final syncConfigs = await _storageService.getSyncConfigs();
    if (mounted) {
      setState(() {
        _syncConfigs = syncConfigs;
      });
    }
    try {
      _settings = await _storageService.getSettings() ?? AppSettings();
      _applyWindowFrameStyle(_settings.windowFrameStyle);
      if (mounted) {
        setState(() {
          _themeMode = _settings.themeMode;
          _themeColor = _settings.themeColor;
        });
      }
      await _loadWindowsAccentColor();
      if (_settings.selectedSchool != null) {
        _fetchCalendarEvents();
        final rawData = await _comciganService.fetchTimetableRaw(
          _settings.selectedSchool!.code,
        );
        final result = _comciganService.parseTimetable(rawData);
        if (mounted) {
          setState(() {
            _timetableResult = result;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '시간표 데이터를 가져오지 못했습니다.';
          _isLoading = false;
        });
      }
    }

    // 1초 주기 타이머
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
      _updateCurrentPeriod();
    });

    // USB 감지 (Windows 전용)
    if (Platform.isWindows) {
      _checkUsb();
      _usbTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        _checkUsb();
      });
    }
  }

  void _updateCurrentPeriod() {
    final weekday = _now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    if (_timetableResult == null || isWeekend) {
      if (_currentPeriod != null || _nextPeriod != null) {
        setState(() {
          _currentPeriod = null;
          _nextPeriod = null;
        });
      }
      return;
    }
    final ts = _settings.timeSettings;
    final timeParts = ts.firstPeriodStart.split(':');
    int h = int.tryParse(timeParts[0]) ?? 8;
    int m = int.tryParse(timeParts[1]) ?? 40;
    int curMin = h * 60 + m;
    final nowMin = _now.hour * 60 + _now.minute;

    int? found;
    int? next;
    for (int p = 1; p <= 8; p++) {
      final start = curMin;
      final end = start + ts.lessonDuration;
      if (nowMin >= start && nowMin < end) {
        found = p;
        next = p + 1;
        break;
      }
      if (p == ts.lunchAfterPeriod) {
        curMin = end + ts.lunchDuration;
      } else {
        curMin = end + ts.breakDuration;
      }
    }
    if (_currentPeriod != found || _nextPeriod != next) {
      setState(() {
        _currentPeriod = found;
        _nextPeriod = found != null ? next : null;
      });
    }

    // 트레이 아이콘 및 툴팁 실시간 업데이트 연동
    if (Platform.isWindows) {
      final status = _getPeriodTimeStatus();
      final targetP = status?.targetPeriod ?? 1;
      final inProgress = status?.inProgress ?? false;
      final mins = status?.minutesLeft ?? 0;

      String periodLabel = '';
      if (status == null) {
        periodLabel = '일과 시간 외';
      } else {
        periodLabel = inProgress
            ? '$targetP교시 진행 중 ($mins분 남음)'
            : '$targetP교시 대기 중 ($mins분 남음)';
      }

      final classLabel =
          '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';

      TrayService.instance.updateStatus(
        periodLabel: periodLabel,
        classLabel: classLabel,
      );
    }
  }

  PeriodTimeStatus? _getPeriodTimeStatus() {
    final weekday = _now.weekday;
    if (_timetableResult == null || weekday == 6 || weekday == 7) return null;
    final ts = _settings.timeSettings;
    final timeParts = ts.firstPeriodStart.split(':');
    int h = int.tryParse(timeParts[0]) ?? 8;
    int m = int.tryParse(timeParts[1]) ?? 40;
    int curMin = h * 60 + m;
    final nowMin = _now.hour * 60 + _now.minute;

    // 1. Check if before 1st period starts
    if (nowMin < curMin) {
      return PeriodTimeStatus(
        targetPeriod: 1,
        inProgress: false,
        minutesLeft: curMin - nowMin,
      );
    }

    for (int p = 1; p <= 8; p++) {
      final start = curMin;
      final end = start + ts.lessonDuration;

      // In class?
      if (nowMin >= start && nowMin < end) {
        return PeriodTimeStatus(
          targetPeriod: p,
          inProgress: true,
          minutesLeft: end - nowMin,
        );
      }

      // Break/Lunch time?
      final breakDuration = (p == ts.lunchAfterPeriod)
          ? ts.lunchDuration
          : ts.breakDuration;
      final nextStart = end + breakDuration;

      if (nowMin >= end && nowMin < nextStart) {
        return PeriodTimeStatus(
          targetPeriod: p + 1,
          inProgress: false,
          minutesLeft: nextStart - nowMin,
        );
      }

      curMin = nextStart;
    }

    // After 8th period
    return null;
  }

  final NeisService _neisService = NeisService();
  List<Map<String, dynamic>> _apiScheduleEvents = [];

  void _fetchCalendarEvents() async {
    if (_settings.selectedSchool == null) return;
    try {
      final events = await _neisService.fetchSchoolSchedule(
        _settings.selectedSchool!.name,
        DateTime.now(),
      );
      if (mounted) {
        setState(() {
          _apiScheduleEvents = events;
        });
      }
    } catch (_) {}
  }

  void _checkUsb() async {
    if (!Platform.isWindows) return;
    if (_usbHandling) return;
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=2" | Select-Object -ExpandProperty DeviceID',
      ]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) {
          final drive = '${out.substring(0, 1)}:\\';
          if (!_isUsbConnected || _usbDriveLetter != drive) {
            setState(() {
              _isUsbConnected = true;
              _usbDriveLetter = drive;
              _currentDrivePath = drive;
            });
            _loadUsbType(drive);
          } else {
            _refreshBoardBridgeStatus();
          }
          return;
        }
      }
    } catch (_) {}

    if (_isUsbConnected) {
      _stopFolderWatchers();
      setState(() {
        _isUsbConnected = false;
        _usbDriveLetter = '';
        _currentDrivePath = '';
        _usbType = 'Plus';
        _boardStatus = null;
        _bridgeStatus = 'USB disconnected';
      });
    }

    if (CloudDriveService.instance.isLoggedIn) {
      _loadCloudDriveMappings();
    }
  }

  Future<void> _loadCloudDriveMappings() async {
    final mappings = await CloudDriveService.instance.fetchClassroomMappings();
    if (mounted && mappings.isNotEmpty) {
      setState(() {
        _classroomFolderMappings = mappings;
      });
    }
  }

  Future<void> _loadUsbType(String root) async {
    _usbHandling = true;
    try {
      // 일반 USB
      await UsbBridgeService.ensure(root);
      final t = await UsbFormatService.readCurrentType(root);
      if (mounted) {
        setState(() => _usbType = t);
        _scanUsbFolders();
      }
      await _runFolderSync();
      await _refreshBoardBridgeStatus();
      _startFolderWatchers();
    } finally {
      _usbHandling = false;
    }
  }

  Future<void> _refreshBoardBridgeStatus() async {
    if (!_isUsbConnected || _usbDriveLetter.isEmpty) return;
    final compatible = await UsbBridgeService.isCompatible(_usbDriveLetter);
    final status = compatible
        ? await UsbBridgeService.readBoardStatus(_usbDriveLetter)
        : null;
    if (mounted) {
      setState(() {
        _boardStatus = status;
        _bridgeStatus = !compatible
            ? 'USB protocol mismatch'
            : status == null
            ? 'Waiting for Board'
            : (status['locked'] == true ? 'Board locked' : 'Board online');
      });
    }
  }

  Future<void> _sendBoardCommand(
    String type, {
    Map<String, dynamic> payload = const {},
  }) async {
    if (!_isUsbConnected || _usbDriveLetter.isEmpty) return;
    final id = await UsbBridgeService.queueCommand(
      _usbDriveLetter,
      type,
      payload: payload,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Board command queued: $id')));
    await _refreshBoardBridgeStatus();
  }

  Future<void> _openBoardControlDialog() async {
    if (!_isUsbConnected || _usbDriveLetter.isEmpty) return;
    await _refreshBoardBridgeStatus();
    if (!mounted) return;
    final messageController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Board USB control'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_bridgeStatus),
              if (_boardStatus?['updatedAt'] != null)
                Text(
                  'Last response: ${_boardStatus!['updatedAt']}',
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: 'Full-screen message',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final selected = await FilePicker.pickFiles(allowMultiple: false);
              final path = selected?.files.single.path;
              if (path == null || !p.isWithin(_usbDriveLetter, path)) return;
              await _sendBoardCommand(
                'open_file',
                payload: {'path': p.relative(path, from: _usbDriveLetter)},
              );
            },
            child: const Text('Open material'),
          ),
          TextButton(
            onPressed: () => _sendBoardCommand('lock'),
            child: const Text('Lock'),
          ),
          TextButton(
            onPressed: () => _sendBoardCommand('unlock'),
            child: const Text('Unlock'),
          ),
          TextButton(
            onPressed: () => _sendBoardCommand('go_home'),
            child: const Text('Home'),
          ),
          TextButton(
            onPressed: () async {
              final message = messageController.text.trim();
              if (message.isNotEmpty)
                await _sendBoardCommand('alert', payload: {'message': message});
            },
            child: const Text('Send message'),
          ),
          TextButton(
            onPressed: () async {
              await UsbBridgeService.createDiagnosticReport(_usbDriveLetter, {
                'app': 'Teacher',
                'bridgeStatus': _bridgeStatus,
                'boardStatus': _boardStatus,
                'usbType': _usbType,
                'syncConfigs': _syncConfigs,
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Diagnostic report'),
          ),
        ],
      ),
    );
    messageController.dispose();
  }

  String _resolveProUsbPath(String root) {
    if (_usbType != 'Pro') return root;
    final status = _getPeriodTimeStatus();
    final targetP = status?.targetPeriod ?? 1;
    final combined = _getCombinedTodayLessons();
    _CombinedPeriod? activePeriod;
    if (combined.isNotEmpty) {
      activePeriod = combined.firstWhere(
        (cp) => cp.period == targetP,
        orElse: () => combined.first,
      );
    }

    final String gradeClass =
        (activePeriod != null && activePeriod.teacherClass.isNotEmpty)
        ? activePeriod.teacherClass
        : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';

    // 1. Try manual mapping first!
    String? mappedFolder = _classroomFolderMappings[gradeClass];
    if (mappedFolder == null) {
      final cleanGradeClass = gradeClass.replaceAll(' ', '');
      for (final entry in _classroomFolderMappings.entries) {
        if (entry.key.replaceAll(' ', '') == cleanGradeClass) {
          mappedFolder = entry.value;
          break;
        }
      }
    }

    if (mappedFolder != null) {
      final targetDir = Directory(p.join(root, mappedFolder));
      if (targetDir.existsSync()) {
        return targetDir.path;
      }
    }

    // 2. Fallback to automatic detection
    final gradeClassClean = gradeClass.replaceAll(' ', '');
    try {
      final dir = Directory(root);
      if (dir.existsSync()) {
        final List<FileSystemEntity> entities = dir.listSync();
        for (final entity in entities) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            final nameClean = name.replaceAll(' ', '');
            if (nameClean == gradeClassClean ||
                nameClean ==
                    '${_settings.selectedGrade}학년${_settings.selectedClass}반' ||
                nameClean ==
                    '${_settings.selectedGrade}-${_settings.selectedClass}') {
              return entity.path;
            }
          }
        }
      }
    } catch (_) {}

    final fallbackFolderName =
        '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';
    final fallbackDir = Directory(p.join(root, fallbackFolderName));
    if (fallbackDir.existsSync()) {
      return fallbackDir.path;
    }

    return root;
  }

  Future<void> _runFolderSync() async {
    if (!_isUsbConnected || _usbDriveLetter.isEmpty) return;

    try {
      final syncConfigs = await _storageService.getSyncConfigs();
      if (syncConfigs.isEmpty) return;

      int successCount = 0;
      for (final config in syncConfigs) {
        final localPath = config['local'] ?? '';
        final usbFolder = config['usb'] ?? '';

        if (localPath.isEmpty || usbFolder.isEmpty) continue;

        final localDir = Directory(localPath);
        if (!localDir.existsSync()) {
          debugPrint('[FolderSync] Local dir does not exist: $localPath');
          continue;
        }

        final usbSyncPath = p.join(_usbDriveLetter, usbFolder);
        final usbDir = Directory(usbSyncPath);
        if (!usbDir.existsSync()) {
          try {
            usbDir.createSync(recursive: true);
          } catch (e) {
            debugPrint('[FolderSync] Failed to create USB sync folder: $e');
            continue;
          }
        }

        debugPrint(
          '[FolderSync] Starting sync between $localPath and $usbSyncPath',
        );
        await _syncDirectories(localDir, usbDir);
        successCount++;
      }

      if (successCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount개 폴더 동기화 완료!'),
            backgroundColor: const Color(0xFF2CB67D),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('[FolderSync] Error during sync: $e');
    }
  }

  Future<void> _syncFolderPair(String localPath, String usbFolderPath) async {
    final localDir = Directory(localPath);
    if (!localDir.existsSync()) {
      debugPrint('[FolderSync] Local dir does not exist: $localPath');
      return;
    }
    final usbDir = Directory(usbFolderPath);
    if (!usbDir.existsSync()) {
      try {
        usbDir.createSync(recursive: true);
      } catch (e) {
        debugPrint('[FolderSync] Failed to create USB sync folder: $e');
        return;
      }
    }
    await _syncDirectories(localDir, usbDir);
  }

  Future<void> _syncDirectories(Directory dirA, Directory dirB) async {
    final preview = await _usbSyncService.preview(dirA, dirB);
    if (preview.conflicts.isNotEmpty) {
      final names = preview.conflicts.take(3).map((item) => item.relativePath).join(', ');
      final message = 'Sync blocked: ${preview.conflicts.length} conflict(s) ($names)';
      if (mounted) setState(() => _lastSyncSummary = message);
      debugPrint('[FolderSync] $message');
      return;
    }
    final freeBytes = await _usbSyncService.getUsbFreeBytes(_usbDriveLetter);
    if (freeBytes != null && preview.uploadBytes > freeBytes) {
      final message = 'Sync blocked: USB needs ${_formatBytes(preview.uploadBytes)} but only ${_formatBytes(freeBytes)} remains.';
      if (mounted) setState(() => _lastSyncSummary = message);
      return;
    }
    final result = await _usbSyncService.apply(dirA, dirB, preview);
    final message = result.failures.isEmpty
        ? '${result.copied} file(s) copied and ${result.verified} verified.'
        : '${result.copied} copied, ${result.failures.length} failed verification.';
    if (mounted) setState(() => _lastSyncSummary = message);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _openSyncPreviewDialog() async {
    if (!_isUsbConnected || _usbDriveLetter.isEmpty) return;
    final configs = await _storageService.getSyncConfigs();
    final previews = <_SyncPairPreview>[];
    for (final config in configs) {
      final localPath = config['local'] ?? '';
      final usbFolder = config['usb'] ?? '';
      if (localPath.isEmpty || usbFolder.isEmpty) continue;
      final local = Directory(localPath);
      final usb = Directory(p.join(_usbDriveLetter, usbFolder));
      if (await local.exists()) {
        previews.add(_SyncPairPreview(local, usb, await _usbSyncService.preview(local, usb)));
      }
    }
    final freeBytes = await _usbSyncService.getUsbFreeBytes(_usbDriveLetter);
    if (!mounted) return;
    final totalUpload = previews.fold<int>(0, (sum, item) => sum + (item.preview.uploadBytes as num).toInt());
    final conflicts = previews.fold<int>(0, (sum, item) => sum + (item.preview.conflicts.length as num).toInt());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sync preview'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${previews.fold<int>(0, (sum, item) => sum + (item.preview.changes.length as num).toInt())} file changes, $conflicts conflicts'),
            Text('USB upload: ${_formatBytes(totalUpload)}${freeBytes == null ? '' : ' / free ${_formatBytes(freeBytes)}'}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            Flexible(child: ListView(children: [
              for (final pair in previews) ...[
                Text('${p.basename(pair.local.path)} <-> ${p.basename(pair.usb.path)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final conflict in pair.preview.conflicts)
                  ListTile(dense: true, leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange), title: Text(conflict.relativePath), subtitle: const Text('Changed on both devices: choose a version manually.')),
                for (final change in pair.preview.changes.take(30))
                  ListTile(dense: true, leading: Icon(change.direction == SyncDirection.localToUsb ? Icons.upload_rounded : Icons.download_rounded), title: Text(change.relativePath), trailing: Text(_formatBytes(change.bytes))),
              ],
            ])),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          FilledButton(
            onPressed: conflicts > 0 || (freeBytes != null && totalUpload > freeBytes) ? null : () async {
              Navigator.pop(dialogContext);
              for (final pair in previews) {
                await _syncDirectories(pair.local, pair.usb);
              }
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lastSyncSummary)));
            },
            child: const Text('Sync verified changes'),
          ),
        ],
      ),
    );
  }

  void _showSafeRemoveDialog() {
    final message = _isSyncingInProgress
        ? 'A sync is still running. Keep the USB connected until it finishes.'
        : 'No sync is running. It is safe to remove the USB after closing files opened from it.';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Safe USB removal'),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  void _openFolderSyncDialog({String? prefilledUsbFolder}) async {
    final s = _settings.scaleFactor;
    List<Map<String, String>> configs = await _storageService.getSyncConfigs();

    final newLocalController = TextEditingController();
    final newUsbController = TextEditingController(text: prefilledUsbFolder);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF16161A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16 * s),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.sync_rounded,
                    color: const Color(0xFF2CB67D),
                    size: 20 * s,
                  ),
                  SizedBox(width: 8 * s),
                  Text(
                    '노트북 ↔ USB 폴더 동기화 설정',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 14 * s,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480 * s,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'USB 연결 시 지정한 노트북 폴더와 USB 내부 폴더를 양방향 실시간 동기화합니다. (여러 개 등록 가능)',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white60,
                          fontSize: 11 * s,
                        ),
                      ),
                      SizedBox(height: 14 * s),

                      // ── 기존 설정 목록 ──
                      if (configs.isNotEmpty) ...[
                        Text(
                          '현재 등록된 동기화 목록',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontSize: 11 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6 * s),
                        Container(
                          constraints: BoxConstraints(maxHeight: 180 * s),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(8 * s),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: configs.length,
                            separatorBuilder: (context, index) => Divider(
                              color: Colors.white.withOpacity(0.05),
                              height: 1,
                            ),
                            itemBuilder: (context, index) {
                              final c = configs[index];
                              return Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10 * s,
                                  vertical: 8 * s,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.laptop_windows_rounded,
                                                color: const Color(0xFF7F5AF0),
                                                size: 12 * s,
                                              ),
                                              SizedBox(width: 4 * s),
                                              Expanded(
                                                child: Text(
                                                  c['local'] ?? '',
                                                  style: GoogleFonts.notoSansKr(
                                                    color: Colors.white,
                                                    fontSize: 11 * s,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 3 * s),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.usb_rounded,
                                                color: const Color(0xFF2CB67D),
                                                size: 12 * s,
                                              ),
                                              SizedBox(width: 4 * s),
                                              Expanded(
                                                child: Text(
                                                  c['usb'] ?? '',
                                                  style: GoogleFonts.notoSansKr(
                                                    color: Colors.white70,
                                                    fontSize: 11 * s,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.redAccent,
                                        size: 16 * s,
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          configs.removeAt(index);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(height: 16 * s),
                      ],

                      // ── 새 동기화 규칙 추가 ──
                      Text(
                        '새 동기화 설정 추가',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF2CB67D),
                          fontSize: 11 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8 * s),

                      // 로컬 폴더
                      Text(
                        '노트북 로컬 폴더 경로',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white70,
                          fontSize: 10 * s,
                        ),
                      ),
                      SizedBox(height: 4 * s),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: newLocalController,
                              decoration: InputDecoration(
                                hintText: 'C:\\Users\\...',
                                hintStyle: GoogleFonts.notoSansKr(
                                  color: Colors.white24,
                                  fontSize: 10 * s,
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.03),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8 * s),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.1),
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10 * s,
                                  vertical: 8 * s,
                                ),
                              ),
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontSize: 11 * s,
                              ),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          ElevatedButton(
                            onPressed: () async {
                              final path = await FilePicker.getDirectoryPath();
                              if (path != null) {
                                setDialogState(() {
                                  newLocalController.text = path;
                                  if (newUsbController.text.isEmpty) {
                                    newUsbController.text = p.basename(path);
                                  }
                                });
                              }
                            },
                            child: Text('선택'),
                          ),
                        ],
                      ),
                      SizedBox(height: 10 * s),

                      // USB 폴더
                      Text(
                        'USB 내 동기화 폴더명',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white70,
                          fontSize: 10 * s,
                        ),
                      ),
                      SizedBox(height: 4 * s),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: newUsbController,
                              decoration: InputDecoration(
                                hintText: '예: MyClass',
                                hintStyle: GoogleFonts.notoSansKr(
                                  color: Colors.white24,
                                  fontSize: 10 * s,
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.03),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8 * s),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.1),
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10 * s,
                                  vertical: 8 * s,
                                ),
                              ),
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontSize: 11 * s,
                              ),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          ElevatedButton(
                            onPressed: () {
                              final local = newLocalController.text.trim();
                              final usb = newUsbController.text.trim();
                              if (local.isNotEmpty && usb.isNotEmpty) {
                                setDialogState(() {
                                  configs.add({'local': local, 'usb': usb});
                                  newLocalController.clear();
                                  newUsbController.clear();
                                });
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '경로와 폴더명을 모두 기입 후 추가를 눌러주세요.',
                                    ),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7F5AF0),
                            ),
                            child: Text('추가'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '취소',
                    style: GoogleFonts.notoSansKr(color: Colors.white38),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final remLocal = newLocalController.text.trim();
                    final remUsb = newUsbController.text.trim();
                    if (remLocal.isNotEmpty && remUsb.isNotEmpty) {
                      configs.add({'local': remLocal, 'usb': remUsb});
                    }

                    await _storageService.saveSyncConfigs(configs);
                    if (mounted) {
                      setState(() {
                        _syncConfigs = configs;
                      });
                    }
                    _startFolderWatchers();
                    if (context.mounted) Navigator.pop(context);
                    _runFolderSync();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2CB67D),
                  ),
                  child: Text(
                    '저장 및 동기화',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Pro USB 전용: 동기화 설정 / 반 매핑 / 파일 정렬 통합 옵션 다이얼로그
  void _openFolderOptionsDialog({int initialTab = 0}) async {
    final s = _settings.scaleFactor;
    // 탭 인덱스: 0=동기화, 1=반 매핑, 2=파일 정렬
    int _tabIndex = initialTab;

    // 클래스룸 목록 (매핑용)
    final teacherName = _settings.selectedTeacher
        .replaceAll('*', '')
        .trim()
        .toUpperCase();
    final classroomSet = <String>{};
    if (_timetableResult != null && teacherName.isNotEmpty) {
      for (final l in _timetableResult!.lessons) {
        if (l.teacher.replaceAll('*', '').trim().toUpperCase() == teacherName) {
          classroomSet.add('${l.grade}학년 ${l.classNum}반');
        }
      }
    }
    final homeroomClass =
        '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';
    if (!classroomSet.contains(homeroomClass)) classroomSet.add(homeroomClass);
    final classrooms = classroomSet.toList();

    // 현재 매핑 로컬 복사
    final localMappings = Map<String, String>.from(_classroomFolderMappings);

    // 동기화 설정 로드
    List<Map<String, String>> syncConfigs = await _storageService
        .getSyncConfigs();
    final newLocalCtrl = TextEditingController();
    final newUsbCtrl = TextEditingController();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (ctx, setDS) {
            final tabs = ['동기화 설정', '반 매핑', '파일 정렬'];
            return AlertDialog(
              backgroundColor: _isDark ? const Color(0xFF16161A) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16 * s),
              ),
              title: Row(
                children: [
                  Icon(Icons.tune_rounded, color: _accentColor, size: 20 * s),
                  SizedBox(width: 8 * s),
                  Text(
                    'USB Pro 폴더 옵션',
                    style: GoogleFonts.notoSansKr(
                      color: _textColor,
                      fontSize: 14 * s,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500 * s,
                height: 400 * s,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 탭 바
                    Row(
                      children: List.generate(tabs.length, (i) {
                        final active = _tabIndex == i;
                        return GestureDetector(
                          onTap: () => setDS(() => _tabIndex = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: EdgeInsets.only(right: 8 * s),
                            padding: EdgeInsets.symmetric(
                              horizontal: 14 * s,
                              vertical: 7 * s,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? _accentColor.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8 * s),
                              border: Border.all(
                                color: active
                                    ? _accentColor.withOpacity(0.4)
                                    : _borderColor,
                              ),
                            ),
                            child: Text(
                              tabs[i],
                              style: GoogleFonts.notoSansKr(
                                color: active ? _accentColor : _textColor54,
                                fontSize: 12 * s,
                                fontWeight: active
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: 14 * s),
                    Expanded(
                      child: _tabIndex == 0
                          // ── 동기화 설정 탭 ──
                          ? SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'USB ↔ 노트북 양방향 실시간 동기화',
                                    style: GoogleFonts.notoSansKr(
                                      color: _textColor54,
                                      fontSize: 11 * s,
                                    ),
                                  ),
                                  SizedBox(height: 10 * s),
                                  if (syncConfigs.isNotEmpty) ...[
                                    ...syncConfigs.asMap().entries.map((e) {
                                      final idx = e.key;
                                      final c = e.value;
                                      return Container(
                                        margin: EdgeInsets.only(bottom: 6 * s),
                                        padding: EdgeInsets.all(10 * s),
                                        decoration: BoxDecoration(
                                          color: _cardColor,
                                          borderRadius: BorderRadius.circular(
                                            8 * s,
                                          ),
                                          border: Border.all(
                                            color: _borderColor,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .laptop_windows_rounded,
                                                        color: const Color(
                                                          0xFF7F5AF0,
                                                        ),
                                                        size: 12 * s,
                                                      ),
                                                      SizedBox(width: 4 * s),
                                                      Expanded(
                                                        child: Text(
                                                          c['local'] ?? '',
                                                          style:
                                                              GoogleFonts.notoSansKr(
                                                                color:
                                                                    _textColor,
                                                                fontSize:
                                                                    11 * s,
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 3 * s),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.usb_rounded,
                                                        color: const Color(
                                                          0xFF2CB67D,
                                                        ),
                                                        size: 12 * s,
                                                      ),
                                                      SizedBox(width: 4 * s),
                                                      Expanded(
                                                        child: Text(
                                                          c['usb'] ?? '',
                                                          style:
                                                              GoogleFonts.notoSansKr(
                                                                color:
                                                                    _textColor54,
                                                                fontSize:
                                                                    11 * s,
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.redAccent,
                                                size: 16 * s,
                                              ),
                                              onPressed: () => setDS(
                                                () => syncConfigs.removeAt(idx),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    SizedBox(height: 6 * s),
                                  ],
                                  Text(
                                    '새 동기화 추가',
                                    style: GoogleFonts.notoSansKr(
                                      color: const Color(0xFF2CB67D),
                                      fontSize: 11 * s,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 6 * s),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: newLocalCtrl,
                                          decoration: InputDecoration(
                                            hintText: '노트북 폴더 경로',
                                            hintStyle: GoogleFonts.notoSansKr(
                                              color: _textColor24,
                                              fontSize: 10 * s,
                                            ),
                                            filled: true,
                                            fillColor: _cardColor,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8 * s),
                                              borderSide: BorderSide(
                                                color: _borderColor,
                                              ),
                                            ),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 10 * s,
                                                  vertical: 8 * s,
                                                ),
                                          ),
                                          style: GoogleFonts.notoSansKr(
                                            color: _textColor,
                                            fontSize: 11 * s,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 6 * s),
                                      ElevatedButton(
                                        onPressed: () async {
                                          final path =
                                              await FilePicker.getDirectoryPath();
                                          if (path != null)
                                            setDS(() {
                                              newLocalCtrl.text = path;
                                              if (newUsbCtrl.text.isEmpty)
                                                newUsbCtrl.text = p.basename(
                                                  path,
                                                );
                                            });
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _accentColor,
                                        ),
                                        child: Text(
                                          '선택',
                                          style: GoogleFonts.notoSansKr(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 6 * s),
                                  TextField(
                                    controller: newUsbCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'USB 폴더명 (예: MyClass)',
                                      hintStyle: GoogleFonts.notoSansKr(
                                        color: _textColor24,
                                        fontSize: 10 * s,
                                      ),
                                      filled: true,
                                      fillColor: _cardColor,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          8 * s,
                                        ),
                                        borderSide: BorderSide(
                                          color: _borderColor,
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10 * s,
                                        vertical: 8 * s,
                                      ),
                                    ),
                                    style: GoogleFonts.notoSansKr(
                                      color: _textColor,
                                      fontSize: 11 * s,
                                    ),
                                  ),
                                  SizedBox(height: 8 * s),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        final local = newLocalCtrl.text.trim();
                                        final usb = newUsbCtrl.text.trim();
                                        if (local.isNotEmpty &&
                                            usb.isNotEmpty) {
                                          setDS(() {
                                            syncConfigs.add({
                                              'local': local,
                                              'usb': usb,
                                            });
                                            newLocalCtrl.clear();
                                            newUsbCtrl.clear();
                                          });
                                        }
                                      },
                                      icon: Icon(
                                        Icons.add_rounded,
                                        size: 16 * s,
                                      ),
                                      label: Text(
                                        '추가',
                                        style: GoogleFonts.notoSansKr(),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF2CB67D,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _tabIndex == 1
                          // ── 반 매핑 탭 ──
                          ? ListView.builder(
                              itemCount: classrooms.length,
                              itemBuilder: (_, idx) {
                                final cls = classrooms[idx];
                                final mapped = localMappings[cls];
                                return Container(
                                  margin: EdgeInsets.only(bottom: 8 * s),
                                  padding: EdgeInsets.all(10 * s),
                                  decoration: BoxDecoration(
                                    color: _cardColor,
                                    borderRadius: BorderRadius.circular(10 * s),
                                    border: Border.all(color: _borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              cls,
                                              style: GoogleFonts.notoSansKr(
                                                color: _textColor,
                                                fontSize: 12 * s,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            SizedBox(height: 3 * s),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8 * s,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _surfaceColor,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      6 * s,
                                                    ),
                                                border: Border.all(
                                                  color: _borderColor,
                                                ),
                                              ),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value:
                                                      _usbFolders.contains(
                                                        mapped,
                                                      )
                                                      ? mapped
                                                      : null,
                                                  hint: Text(
                                                    'USB 폴더 선택',
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          color: _textColor38,
                                                          fontSize: 11 * s,
                                                        ),
                                                  ),
                                                  dropdownColor: _isDark
                                                      ? const Color(0xFF16161A)
                                                      : Colors.white,
                                                  isExpanded: true,
                                                  items: [
                                                    DropdownMenuItem<String>(
                                                      value: null,
                                                      child: Text(
                                                        '매핑 없음',
                                                        style:
                                                            GoogleFonts.notoSansKr(
                                                              color:
                                                                  _textColor38,
                                                              fontSize: 11 * s,
                                                            ),
                                                      ),
                                                    ),
                                                    ..._usbFolders.map(
                                                      (
                                                        f,
                                                      ) => DropdownMenuItem<String>(
                                                        value: f,
                                                        child: Text(
                                                          f,
                                                          style:
                                                              GoogleFonts.notoSansKr(
                                                                color:
                                                                    _textColor,
                                                                fontSize:
                                                                    11 * s,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  onChanged: (val) {
                                                    setDS(() {
                                                      if (val == null)
                                                        localMappings.remove(
                                                          cls,
                                                        );
                                                      else
                                                        localMappings[cls] =
                                                            val;
                                                    });
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )
                          // ── 파일 정렬 탭 ──
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.sort_rounded,
                                    color: _accentColor,
                                    size: 40 * s,
                                  ),
                                  SizedBox(height: 12 * s),
                                  Text(
                                    '파일 탐색기에서 파일을 길게 눌러\n드래그로 순서를 조정할 수 있습니다.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.notoSansKr(
                                      color: _textColor54,
                                      fontSize: 12 * s,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '취소',
                    style: GoogleFonts.notoSansKr(color: _textColor38),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // 동기화 저장
                    await _storageService.saveSyncConfigs(syncConfigs);
                    // 반 매핑 저장
                    if (mounted) {
                      setState(() {
                        _syncConfigs = syncConfigs;
                        _classroomFolderMappings = localMappings;
                      });
                      _saveClassroomMappings();
                    }
                    _startFolderWatchers();
                    if (context.mounted) Navigator.pop(context);
                    _runFolderSync();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                  ),
                  child: Text(
                    '저장',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 로그인된 교사가 담임인지 여부 역추적
  bool _isHomeroomTeacher() {
    if (_timetableResult == null) return false;
    final homeroomMap =
        _timetableResult!.homeroomTeachers[_settings.selectedGrade];
    if (homeroomMap == null) return false;
    final homeroomTeacher = homeroomMap[_settings.selectedClass];
    if (homeroomTeacher == null) return false;

    final selectedTeacherSanitized = _settings.selectedTeacher
        .replaceAll('*', '')
        .trim()
        .toUpperCase();
    final homeroomTeacherSanitized = homeroomTeacher
        .replaceAll('*', '')
        .trim()
        .toUpperCase();
    return selectedTeacherSanitized.isNotEmpty &&
        selectedTeacherSanitized == homeroomTeacherSanitized;
  }

  List<String> _getTeacherTaughtClasses() {
    final Set<String> classes = {'전체 반 공용 (통합)'};
    if (_timetableResult != null) {
      final teacherName = _settings.selectedTeacher
          .replaceAll('*', '')
          .trim()
          .toUpperCase();
      final lessons = _timetableResult!.lessons.where((l) {
        if (teacherName.isEmpty) return true;
        return l.teacher.replaceAll('*', '').trim().toUpperCase() == teacherName;
      });
      for (final l in lessons) {
        if (l.grade > 0 && l.classNum > 0) {
          classes.add('${l.grade}학년 ${l.classNum}반');
        }
      }
    }
    if (classes.length == 1) {
      classes.addAll([
        '1학년 1반',
        '1학년 2반',
        '2학년 1반',
        '2학년 2반',
        '3학년 1반',
        '3학년 2반',
      ]);
    }
    final list = classes.toList();
    list.sort((a, b) {
      if (a.contains('전체')) return -1;
      if (b.contains('전체')) return 1;
      return a.compareTo(b);
    });
    return list;
  }

  List<Lesson> _getTodayLessons() {
    if (_timetableResult == null) return [];
    final weekday = _now.weekday;
    final displayDay = (weekday >= 1 && weekday <= 5) ? weekday : 1;

    // 교과 교사 모드일 때
    if (_settings.specialClassroomMode && _settings.specialClassroomType == 1) {
      final teacherName = _settings.selectedTeacher
          .replaceAll('*', '')
          .trim()
          .toUpperCase();
      if (teacherName.isEmpty) return [];
      return _timetableResult!.lessons
          .where(
            (l) =>
                l.weekday == displayDay &&
                l.teacher.replaceAll('*', '').trim().toUpperCase() ==
                    teacherName,
          )
          .map(
            (l) => Lesson(
              grade: l.grade,
              classNum: l.classNum,
              weekday: l.weekday,
              classTime: l.classTime,
              subject: l.subject,
              teacher: '${l.grade}-${l.classNum}',
              classroom: l.classroom,
              isChanged: l.isChanged,
            ),
          )
          .toList()
        ..sort((a, b) => a.classTime.compareTo(b.classTime));
    }

    // 일반 학급 모드일 때
    return _timetableResult!.lessons
        .where(
          (l) =>
              l.weekday == displayDay &&
              l.grade == _settings.selectedGrade &&
              l.classNum == _settings.selectedClass,
        )
        .map(
          (l) => Lesson(
            grade: l.grade,
            classNum: l.classNum,
            weekday: l.weekday,
            classTime: l.classTime,
            subject: l.subject,
            teacher: AppSettings.formatTeacherDisplayName(l.teacher),
            classroom: l.classroom,
            isChanged: l.isChanged,
          ),
        )
        .toList()
      ..sort((a, b) => a.classTime.compareTo(b.classTime));
  }

  // ── 통합 시간표 (교사 + 교실) ────────────────────────────

  /// 교사 본인 시간표 + 교실(담임 학급 or 설정 학급) 시간표를 합쳐 CombinedPeriod 목록으로 반환.
  List<_CombinedPeriod> _getCombinedTodayLessons() {
    if (_timetableResult == null) return [];
    final weekday = _now.weekday;
    final displayDay = (weekday >= 1 && weekday <= 5) ? weekday : 1;

    // 교사 본인 시간표 (교과 교사 모드 or 담임 모드 모두)
    final teacherName = _settings.selectedTeacher
        .replaceAll('*', '')
        .trim()
        .toUpperCase();
    final teacherLessons =
        teacherName.isEmpty
              ? <Lesson>[]
              : _timetableResult!.lessons
                    .where(
                      (l) =>
                          l.weekday == displayDay &&
                          l.teacher.replaceAll('*', '').trim().toUpperCase() ==
                              teacherName,
                    )
                    .toList()
          ..sort((a, b) => a.classTime.compareTo(b.classTime));

    // 교실(담임 학급) 시간표
    final classroomLessons =
        _timetableResult!.lessons
            .where(
              (l) =>
                  l.weekday == displayDay &&
                  l.grade == _settings.selectedGrade &&
                  l.classNum == _settings.selectedClass,
            )
            .toList()
          ..sort((a, b) => a.classTime.compareTo(b.classTime));

    // 교시 범위 통합
    final periods = <int>{};
    for (final l in teacherLessons) periods.add(l.classTime);
    for (final l in classroomLessons) periods.add(l.classTime);
    final sortedPeriods = periods.toList()..sort();

    return sortedPeriods.map((p) {
      final tLesson = teacherLessons.cast<Lesson?>().firstWhere(
        (l) => l?.classTime == p,
        orElse: () => null,
      );
      final cLesson = classroomLessons.cast<Lesson?>().firstWhere(
        (l) => l?.classTime == p,
        orElse: () => null,
      );
      return _CombinedPeriod(
        period: p,
        teacherSubject: tLesson?.subject ?? '',
        teacherClass: tLesson != null
            ? '${tLesson.grade}-${tLesson.classNum}반'
            : '',
        classroomSubject: cLesson?.subject ?? '',
        classroomTeacher: cLesson != null
            ? AppSettings.formatTeacherDisplayName(cLesson.teacher)
            : '',
        teacherIsChanged: tLesson?.isChanged ?? false,
        classroomIsChanged: cLesson?.isChanged ?? false,
      );
    }).toList();
  }

  // 본인 교실(담임 반)의 오늘 지금/다음 과목 추출
  Map<String, String> _getHomeroomCurrentNextSubjects() {
    final result = {'current': '없음', 'next': '없음'};
    if (_timetableResult == null) return result;

    final weekday = _now.weekday;
    final displayDay = (weekday >= 1 && weekday <= 5) ? weekday : 1;
    final homeroomLessons = _timetableResult!.lessons
        .where(
          (l) =>
              l.weekday == displayDay &&
              l.grade == _settings.selectedGrade &&
              l.classNum == _settings.selectedClass,
        )
        .toList();

    if (_currentPeriod != null) {
      final curL = homeroomLessons.firstWhere(
        (l) => l.classTime == _currentPeriod,
        orElse: () => _emptyLesson(),
      );
      if (curL.subject.isNotEmpty)
        result['current'] = curL.subject.replaceAll('*', '');
    }
    if (_nextPeriod != null) {
      final nextL = homeroomLessons.firstWhere(
        (l) => l.classTime == _nextPeriod,
        orElse: () => _emptyLesson(),
      );
      if (nextL.subject.isNotEmpty)
        result['next'] = nextL.subject.replaceAll('*', '');
    }
    return result;
  }

  String _periodTimeStr(int period) {
    final ts = _settings.timeSettings;
    final parts = ts.firstPeriodStart.split(':');
    int h = int.tryParse(parts[0]) ?? 8;
    int m = int.tryParse(parts[1]) ?? 40;
    int cur = h * 60 + m;
    for (int p = 1; p <= period; p++) {
      if (p == period) {
        final eH = ((cur + ts.lessonDuration) ~/ 60).toString().padLeft(2, '0');
        final eM = ((cur + ts.lessonDuration) % 60).toString().padLeft(2, '0');
        final sH = (cur ~/ 60).toString().padLeft(2, '0');
        final sM = (cur % 60).toString().padLeft(2, '0');
        return '$sH:$sM–$eH:$eM';
      }
      final end = cur + ts.lessonDuration;
      cur = (p == ts.lunchAfterPeriod)
          ? end + ts.lunchDuration
          : end + ts.breakDuration;
    }
    return '';
  }

  void _openSettings() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TeacherSettingsDialog(scaleFactor: _settings.scaleFactor),
    );
    if (result == true && mounted) {
      _init();
      TeacherView.onSettingsChanged?.call();
    }
  }

  void _openUsbFormat() async {
    if (!_isUsbConnected) return;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => UsbFormatDialog(
        usbRoot: _usbDriveLetter,
        scaleFactor: _settings.scaleFactor,
      ),
    );
    if (result != null && mounted) {
      setState(() => _usbType = result);
    }
  }

  void _openFile(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) {
      setState(() {
        _activeInlineView = 'pdf';
        _activeFilePath = path;
      });
    } else if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PptOverlayView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
          ),
        ),
      );
    } else if (lower.endsWith('.hwp') || lower.endsWith('.hwpx')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HwpOverlayView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
          ),
        ),
      );
    } else if (lower.endsWith('.iwb')) {
      setState(() {
        _activeInlineView = 'whiteboard';
        _activeFilePath = path;
        _activeSubject = null;
      });
    } else if (lower.endsWith('.yt')) {
      _openYoutubeBoard(filePath: path);
    } else if (lower.endsWith('.canva')) {
      _openCanvaBoard(filePath: path);
    }
  }

  // ── 수업 도구 실행 ────────────────────────────────────

  void _openWhiteboard() async {
    try {
      await BstSaveService.instance.ensureStructure();
      final boardDir = await BstSaveService.instance.directoryFor(
        BstSaveService.subBoard,
      );
      final targetPath = p.join(
        boardDir.path,
        'quick_board_${DateTime.now().millisecondsSinceEpoch}.iwb',
      );

      final lesson = _currentPeriod != null
          ? _getTodayLessons().firstWhere(
              (l) => l.classTime == _currentPeriod,
              orElse: () => _emptyLesson(),
            )
          : _emptyLesson();

      setState(() {
        _activeInlineView = 'whiteboard';
        _activeFilePath = targetPath;
        _activeSubject = lesson.subject.isNotEmpty ? lesson.subject : null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('전자칠판을 실행할 수 없습니다: $e')));
      }
    }
  }

  void _openPdfBoard() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'pptx', 'ppt', 'hwp', 'hwpx', 'doc', 'docx'],
    );
    if (result != null && result.files.single.path != null) {
      _openFile(result.files.single.path!);
    }
  }

  void _openBoardBookEditor() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BoardBookEditor(
          scaleFactor: _settings.scaleFactor,
          onOpenUrl: (url, title) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WebsiteBoardView(
                  initialUrl: url,
                  scaleFactor: _settings.scaleFactor,
                ),
              ),
            );
          },
        ),
      ),
    );
  }


  void _openPptBoard() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ppt', 'pptx'],
    );
    if (result != null && result.files.single.path != null) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PptOverlayView(
              initialFilePath: result.files.single.path!,
              scaleFactor: _settings.scaleFactor,
            ),
          ),
        );
      }
    }
  }

  void _openRandomPicker() {
    setState(() {
      _showMiniPicker = !_showMiniPicker;
      if (_showMiniPicker) {
        _pickerWinner = null;
        _pickerRolling = false;
        _pickerWindowOffset = const Offset(450, 150);
      }
    });
  }

  // ── 미니 플로팅 타이머 제어 로직 ────────────────────────

  void _toggleMiniTimer() {
    setState(() {
      _showMiniTimer = !_showMiniTimer;
      if (_showMiniTimer) {
        _timerSecondsElapsed = 0;
        _timerTargetSeconds = 0;
        _timerRunning = false;
        _miniTimerInstance?.cancel();
        _timerWindowOffset = const Offset(300, 200);
        _timerFullscreen = false;
      } else {
        _miniTimerInstance?.cancel();
      }
    });
  }

  void _startMiniTimer() {
    if (_timerRunning) return;
    setState(() {
      _timerRunning = true;
    });
    _miniTimerInstance = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_timerTargetSeconds > 0) {
          // 카운트다운
          if (_timerSecondsElapsed > 0) {
            _timerSecondsElapsed--;
          } else {
            _timerRunning = false;
            timer.cancel();
            // 알람 시각 시각 효과
          }
        } else {
          // 스톱워치
          _timerSecondsElapsed++;
        }
      });
    });
  }

  void _pauseMiniTimer() {
    setState(() {
      _timerRunning = false;
    });
    _miniTimerInstance?.cancel();
  }

  void _resetMiniTimer() {
    setState(() {
      _timerSecondsElapsed = _timerTargetSeconds;
      _timerRunning = false;
    });
    _miniTimerInstance?.cancel();
  }

  void _adjustMiniTimer(int amount) {
    setState(() {
      _timerTargetSeconds += amount;
      if (_timerTargetSeconds < 0) _timerTargetSeconds = 0;
      _timerSecondsElapsed = _timerTargetSeconds;
    });
  }

  // ── 헬퍼 메서드 ──────────────────────────────────────

  Lesson _emptyLesson() => Lesson(
    grade: _settings.selectedGrade,
    classNum: _settings.selectedClass,
    weekday: _now.weekday.clamp(1, 5),
    classTime: 1,
    subject: '',
    teacher: '',
    classroom: '',
    isChanged: false,
  );

  void _showComingSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title 기능은 전자칠판 연결 후 사용 가능합니다.'),
        backgroundColor: const Color(0xFF7F5AF0),
      ),
    );
  }

  void _enterMiniMode() async {
    setState(() {
      _isMiniMode = true;
    });

    try {
      // 1. On-the-fly C# WPF compile for Popup.exe
      final cscPath =
          r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe';

      final exeDir = File(Platform.resolvedExecutable).parent.path;
      String csPath = p.join(exeDir, 'Popup.cs');
      String exePath = p.join(exeDir, 'Popup.exe');
      if (!await File(csPath).exists()) {
        csPath = p.join(Directory.current.path, 'Popup.cs');
      }
      if (!await File(exePath).exists()) {
        exePath = p.join(Directory.current.path, 'Popup.exe');
      }

      final csFile = File(csPath);
      final exeFile = File(exePath);

      if (await csFile.exists()) {
        if (!await exeFile.exists() ||
            (await csFile.lastModified()).isAfter(
              await exeFile.lastModified(),
            )) {
          debugPrint('[TeacherView] Compiling C# WPF Popup widget...');
          await Process.run(cscPath, [
            '/target:winexe',
            '/out:$exePath',
            '/lib:C:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319,C:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\WPF',
            '/r:System.dll,System.Core.dll,WindowsBase.dll,PresentationCore.dll,PresentationFramework.dll,System.Xaml.dll',
            csPath,
          ]);
        }
      }

      // 2. 시간표 정보 캡처
      final status = _getPeriodTimeStatus();
      final targetP = status?.targetPeriod ?? 1;
      final inProgress = status?.inProgress ?? false;
      final mins = status?.minutesLeft ?? 0;

      String periodLabel = '';
      if (status == null) {
        periodLabel = '일과 시간 외';
      } else {
        if (inProgress) {
          periodLabel = '$targetP교시 진행 중 ($mins분 남음)';
        } else {
          periodLabel = '$targetP교시 대기 중 ($mins분 남음)';
        }
      }

      final combined = _getCombinedTodayLessons();
      _CombinedPeriod? activePeriod;
      if (combined.isNotEmpty) {
        activePeriod = combined.firstWhere(
          (cp) => cp.period == targetP,
          orElse: () => combined.first,
        );
      }

      final teacherSubject =
          activePeriod?.teacherSubject.replaceAll('*', '') ?? '수업 없음';
      final teacherClass = activePeriod?.teacherClass ?? '';
      final classroomSubject =
          activePeriod?.classroomSubject.replaceAll('*', '') ?? '수업 없음';
      final classroomTeacher = activePeriod?.classroomTeacher ?? '';

      // 3. WPF 독립 팝업 프로세스 실행
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final args = [
        '--theme',
        isDark ? 'dark' : 'light',
        '--period',
        periodLabel,
        '--teacher-class',
        teacherClass.isNotEmpty ? teacherClass : '수업 없음',
        '--teacher-subject',
        teacherClass.isNotEmpty ? teacherSubject : '',
        '--classroom-subject',
        classroomSubject.isNotEmpty ? classroomSubject : '수업 없음',
        '--classroom-teacher',
        classroomSubject.isNotEmpty ? classroomTeacher : '',
      ];

      if (await exeFile.exists()) {
        await Process.start(exePath, args, mode: ProcessStartMode.detached);
        await TrayService.instance.dispose();
        exit(0);
      } else {
        throw Exception('Popup.exe executable not found at $exePath');
      }
    } catch (e) {
      debugPrint('[TeacherView] Failed to launch C# WPF mini mode: $e');
      try {
        await windowManager.setMinimumSize(const Size(0, 0));
        await windowManager.setMaximumSize(const Size(9999, 9999));
        await windowManager.setSize(const Size(320, 130));
        await windowManager.show();
      } catch (_) {}
    }
  }

  void _exitMiniMode() async {
    setState(() {
      _isMiniMode = false;
    });

    try {
      await windowManager.setMinimumSize(const Size(960, 640));
      await windowManager.setMaximumSize(const Size(9999, 9999));
      await windowManager.setBackgroundColor(_bgColor);
      if (Platform.isWindows) {
        await acrylic.Window.setEffect(effect: acrylic.WindowEffect.disabled);
      }
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setResizable(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[TeacherView] Failed to exit mini mode: $e');
    }
  }

  Widget _buildMiniWidget(double s) {
    final status = _getPeriodTimeStatus();
    final targetP = status?.targetPeriod ?? 1;
    final inProgress = status?.inProgress ?? false;
    final mins = status?.minutesLeft ?? 0;

    String periodLabel = '';
    if (status == null) {
      periodLabel = '일과 시간 외';
    } else {
      if (inProgress) {
        periodLabel = '$targetP교시 진행 중 ($mins분 남음)';
      } else {
        periodLabel = '$targetP교시 대기 중 ($mins분 남음)';
      }
    }

    final combined = _getCombinedTodayLessons();
    _CombinedPeriod? activePeriod;
    if (combined.isNotEmpty) {
      activePeriod = combined.firstWhere(
        (cp) => cp.period == targetP,
        orElse: () => combined.first,
      );
    }

    final teacherSubject =
        activePeriod?.teacherSubject.replaceAll('*', '') ?? '수업 없음';
    final teacherClass = activePeriod?.teacherClass ?? '';
    final classroomSubject =
        activePeriod?.classroomSubject.replaceAll('*', '') ?? '수업 없음';
    final classroomTeacher = activePeriod?.classroomTeacher ?? '';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF16161A).withOpacity(0.50)
        : Colors.white.withOpacity(0.50);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.12)
        : Colors.black.withOpacity(0.12);
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final secondaryTextColor = isDark
        ? Colors.white70
        : const Color(0xFF1A1A1A).withOpacity(0.7);
    final tertiaryTextColor = isDark
        ? Colors.white30
        : const Color(0xFF1A1A1A).withOpacity(0.35);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          width: 320,
          height: 130,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 빨간색 원 (닫기 - 프로그램 완전 종료)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      TrayService.instance.dispose().then((_) => exit(0));
                    },
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFF5F56),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 파란색 원 (앱 열기 - 원래 화면 복원)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _exitMiniMode,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 현교시 상태 텍스트
                  Text(
                    periodLabel,
                    style: GoogleFonts.notoSansKr(
                      color: isDark
                          ? const Color(0xFF00F5D4)
                          : const Color(0xFF00BFA6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Teacher Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2EC4B6).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '교사',
                      style: GoogleFonts.notoSansKr(
                        color: isDark
                            ? const Color(0xFF2EC4B6)
                            : const Color(0xFF0F9B8E),
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status == null
                        ? '일과 시간 외'
                        : '$targetP교시 (${inProgress ? '남음' : '후'} ${mins}분)',
                    style: GoogleFonts.notoSansKr(
                      color: secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 학년반 번호 크게
                  Text(
                    teacherClass.isNotEmpty ? teacherClass : '수업 없음',
                    style: GoogleFonts.notoSansKr(
                      color: primaryTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (teacherClass.isNotEmpty && teacherSubject.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '[$teacherSubject]',
                      style: GoogleFonts.notoSansKr(
                        color: tertiaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              // Classroom Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F5AF0).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '교실',
                      style: GoogleFonts.notoSansKr(
                        color: isDark
                            ? const Color(0xFF9B7CFA)
                            : const Color(0xFF623AD6),
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status == null
                        ? '일과 시간 외'
                        : '$targetP교시 (${inProgress ? '남음' : '후'} ${mins}분)',
                    style: GoogleFonts.notoSansKr(
                      color: secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 과목명 크게
                  Text(
                    classroomSubject,
                    style: GoogleFonts.notoSansKr(
                      color: primaryTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (classroomTeacher.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '($classroomTeacher)',
                      style: GoogleFonts.notoSansKr(
                        color: tertiaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scale = _settings.scaleFactor;

    // 플로팅 팝업 최초 위치: 우측 상단 (화면 크기 기반, 한 번만 초기화)
    if (_timerWindowOffset.dx < 0) {
      final sz = MediaQuery.of(context).size;
      _timerWindowOffset = Offset(sz.width - 280 * scale, 60 * scale);
      _calculatorWindowOffset = Offset(sz.width - 320 * scale, 60 * scale);
      _pickerWindowOffset = Offset(sz.width - 300 * scale, 60 * scale);
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF2EC4B6)),
        ),
      );
    }

    if (_isMiniMode) {

      return _buildMiniWidget(scale);
    }

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Scaffold(
          backgroundColor: _bgColor,
          body: Column(
            children: [
              _buildTitleBar(scale),
            Expanded(
              child: Stack(
                children: [
                  // Aurora background
                  Positioned(
                    top: -100,
                    left: -100,
                    child: Container(
                      width: 360,
                      height: 360,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF7F5AF0).withOpacity(0.10),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -120,
                    right: -80,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2EC4B6).withOpacity(0.08),
                      ),
                    ),
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                    child: Container(color: Colors.transparent),
                  ),

                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _activeInlineView != null
                          // ── 인라인 보드 뷰 활성 시: 전체 영역 채움 ──
                          ? _buildInlineBoardView(scale)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: _buildWeeklyGridTable(
                                    scale,
                                    isHomeroom: false,
                                    inline: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: _buildWeeklyGridTable(
                                    scale,
                                    isHomeroom: true,
                                    inline: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: _buildToolsPanel(scale),
                                ),
                              ],
                            ),
                    ),
                  ),

                  // 플로팅 미니 타이머 오버레이
                  if (_showMiniTimer) _buildFloatingTimer(scale),
                  if (_showMiniCalculator) _buildMiniCalculatorWindow(scale),
                  if (_showMiniPicker) _buildMiniPickerWindow(scale),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  // ── 좌측: 시간표 패널 (주간 격자 전환 대응) ────────────────

  Widget _buildTimetablePanel(double s) {
    if (_showWeeklyGrid) {
      return _buildWeeklyGridTable(s, isHomeroom: false);
    }

    final combined = _getCombinedTodayLessons();
    final weekday = _now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    final teacherName = _settings.selectedTeacher.replaceAll('*', '').trim();
    final hasTeacher = teacherName.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openWeeklyTimetablePopup(false),
      child: Container(
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(color: _borderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20 * s),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Padding(
              padding: EdgeInsets.all(14 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 헤더 ──────────────────────────────────────────
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        color: const Color(0xFF7F5AF0),
                        size: 16 * s,
                      ),
                      SizedBox(width: 6 * s),
                      Expanded(
                        child: Text(
                          isWeekend
                              ? '시간표 월'
                              : '시간표 ${_getKoreanWeekday(_now.weekday)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                            color: _textColor,
                            fontSize: 12 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _openWeeklyTimetablePopup(false),
                        icon: const Icon(
                          Icons.grid_on_rounded,
                          size: 12,
                          color: Color(0xFF7F5AF0),
                        ),
                        label: Text(
                          '주간 보기',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10 * s,
                            color: const Color(0xFF7F5AF0),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * s,
                            vertical: 4 * s,
                          ),
                          backgroundColor: const Color(
                            0xFF7F5AF0,
                          ).withOpacity(0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * s),

                  // ── 범례 컬럼 제목 (이중 헤더) ─────────────────────
                  Row(
                    children: [
                      SizedBox(width: 26 * s), // 교시 원 너비 맞춤
                      SizedBox(width: 8 * s),
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 4 * s,
                              height: 4 * s,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2EC4B6),
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 3 * s),
                            Expanded(
                              child: Text(
                                '교사 시간표',
                                style: GoogleFonts.notoSansKr(
                                  color: const Color(0xFF2EC4B6),
                                  fontSize: 9 * s,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 4 * s,
                              height: 4 * s,
                              decoration: const BoxDecoration(
                                color: Color(0xFF7F5AF0),
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 3 * s),
                            Expanded(
                              child: InkWell(
                                onTap: () => _openWeeklyTimetablePopup(true),
                                child: Text(
                                  '${_settings.selectedGrade}-${_settings.selectedClass}반 시간표',
                                  style: GoogleFonts.notoSansKr(
                                    color: const Color(0xFF7F5AF0),
                                    fontSize: 9 * s,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6 * s),

                  // ── 에러/빈 상태 ──────────────────────────────────
                  if (_errorMessage != null)
                    Expanded(
                      child: Center(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFFEF4565),
                            fontSize: 12 * s,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else if (combined.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              color: _textColor24,
                              size: 32 * s,
                            ),
                            SizedBox(height: 8 * s),
                            Text(
                              _settings.selectedSchool == null
                                  ? '학교를 먼저 설정해주세요'
                                  : '시간표 없음',
                              style: GoogleFonts.notoSansKr(
                                color: _textColor38,
                                fontSize: 12 * s,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    // ── 이중 시간표 목록 ─────────────────────────────
                    Expanded(
                      child: ListView.builder(
                        itemCount: combined.length,
                        itemBuilder: (_, i) {
                          final cp = combined[i];
                          final isCurrent = _currentPeriod == cp.period;
                          final teacherHasClass = cp.teacherSubject.isNotEmpty;
                          final classroomHasClass =
                              cp.classroomSubject.isNotEmpty;

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: EdgeInsets.only(bottom: 5 * s),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF2EC4B6).withOpacity(0.10)
                                  : _cardColor,
                              borderRadius: BorderRadius.circular(12 * s),
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFF2EC4B6).withOpacity(0.5)
                                    : _borderColor,
                                width: isCurrent ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // 교시 원
                                Padding(
                                  padding: EdgeInsets.all(7 * s),
                                  child: Container(
                                    width: 22 * s,
                                    height: 22 * s,
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? const Color(0xFF2EC4B6)
                                          : _borderColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${cp.period}',
                                        style: GoogleFonts.outfit(
                                          color: isCurrent
                                              ? Colors.black
                                              : _textColor54,
                                          fontSize: 11 * s,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // 교사 셀
                                Expanded(
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 6 * s,
                                      horizontal: 4 * s,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: const Color(0xFF2EC4B6)
                                              .withOpacity(
                                                teacherHasClass ? 0.5 : 0.15,
                                              ),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          teacherHasClass
                                              ? cp.teacherSubject.replaceAll(
                                                  '*',
                                                  '',
                                                )
                                              : '—',
                                          style: GoogleFonts.notoSansKr(
                                            color: teacherHasClass
                                                ? (isCurrent
                                                      ? _textColor
                                                      : _textColor70)
                                                : _textColor24,
                                            fontSize: 11 * s,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (teacherHasClass)
                                          Text(
                                            cp.teacherClass,
                                            style: GoogleFonts.notoSansKr(
                                              color: const Color(
                                                0xFF2EC4B6,
                                              ).withOpacity(0.8),
                                              fontSize: 9 * s,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        else
                                          Text(
                                            _periodTimeStr(cp.period),
                                            style: GoogleFonts.outfit(
                                              color: _textColor24,
                                              fontSize: 9 * s,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6 * s),
                                // 교실 셀
                                Expanded(
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 6 * s,
                                      horizontal: 4 * s,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: const Color(0xFF7F5AF0)
                                              .withOpacity(
                                                classroomHasClass ? 0.5 : 0.15,
                                              ),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                classroomHasClass
                                                    ? cp.classroomSubject
                                                          .replaceAll('*', '')
                                                    : '—',
                                                style: GoogleFonts.notoSansKr(
                                                  color: classroomHasClass
                                                      ? (isCurrent
                                                            ? _textColor
                                                            : _textColor70)
                                                      : _textColor24,
                                                  fontSize: 11 * s,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (cp.teacherIsChanged ||
                                                cp.classroomIsChanged)
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 4 * s,
                                                  vertical: 1 * s,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        3 * s,
                                                      ),
                                                ),
                                                child: Text(
                                                  '변경',
                                                  style: GoogleFonts.notoSansKr(
                                                    color: Colors.amber,
                                                    fontSize: 8 * s,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (classroomHasClass)
                                          Text(
                                            cp.classroomTeacher,
                                            style: GoogleFonts.notoSansKr(
                                              color: const Color(
                                                0xFF7F5AF0,
                                              ).withOpacity(0.8),
                                              fontSize: 9 * s,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        else
                                          Text(
                                            _periodTimeStr(cp.period),
                                            style: GoogleFonts.outfit(
                                              color: _textColor24,
                                              fontSize: 9 * s,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(width: 4 * s),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                  // ── 교사 이름이 없으면 안내 배너 ─────────────────────
                  if (!hasTeacher) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(8 * s),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8 * s),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.amber,
                            size: 13 * s,
                          ),
                          SizedBox(width: 6 * s),
                          Expanded(
                            child: Text(
                              '설정에서 교사명을 선택하면 교사 시간표가 표시됩니다.',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.amber,
                                fontSize: 10 * s,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openWeeklyTimetablePopup(bool isHomeroom) {
    final s = _settings.scaleFactor;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Center(
          child: SizedBox(
            width: 800 * s,
            height: 520 * s,
            child: Material(
              color: Colors.transparent,
              child: _buildWeeklyGridTable(
                s,
                isHomeroom: isHomeroom,
                inline: false,
                onClose: () {
                  Navigator.pop(dialogContext);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // 주간 시간표 격자 뷰 테이블 (주간 보기)
  Widget _buildWeeklyGridTable(
    double s, {
    required bool isHomeroom,
    bool inline = false,
    VoidCallback? onClose,
  }) {
    final title = isHomeroom
        ? '${_settings.selectedGrade}학년 ${_settings.selectedClass}반 주간 시간표'
        : '교사 개인 주간 시간표';

    final weekdays = ['월', '화', '수', '목', '금'];
    final lessons = isHomeroom
        ? (_timetableResult?.lessons
                  .where(
                    (l) =>
                        l.grade == _settings.selectedGrade &&
                        l.classNum == _settings.selectedClass,
                  )
                  .toList() ??
              [])
        : (_timetableResult?.lessons.where((l) {
                final tName = _settings.selectedTeacher
                    .replaceAll('*', '')
                    .trim()
                    .toUpperCase();
                return l.teacher.replaceAll('*', '').trim().toUpperCase() ==
                    tName;
              }).toList() ??
              []);

    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1 = Mon, ..., 5 = Fri, 6 = Sat, 7 = Sun
    final activePeriod = _currentPeriod ?? _nextPeriod;

    final tableWidget = Container(
      decoration: BoxDecoration(
        color: inline
            ? _cardColor
            : (_isDark ? const Color(0xFF1E1E24) : Colors.white),
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(color: _borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 * s),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: inline ? 10.0 : 0.0,
            sigmaY: inline ? 10.0 : 0.0,
          ),
          child: Padding(
            padding: EdgeInsets.all(12 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    Icon(
                      Icons.grid_on_rounded,
                      color: _accentColor,
                      size: 16 * s,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.notoSansKr(
                          color: _textColor,
                          fontSize: 12 * s,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!inline)
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: _textColor54,
                          size: 18 * s,
                        ),
                        onPressed:
                            onClose ??
                            () {
                              if (Navigator.canPop(context)) {
                                Navigator.pop(context);
                              }
                            },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '돌아가기',
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // 시간표 격자 테이블
                Expanded(
                  child: SingleChildScrollView(
                    child: Table(
                      border: TableBorder.all(
                        color: _borderColor,
                        width: 1,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      columnWidths: const {
                        0: FixedColumnWidth(26), // 교시 열
                        1: FlexColumnWidth(),
                        2: FlexColumnWidth(),
                        3: FlexColumnWidth(),
                        4: FlexColumnWidth(),
                        5: FlexColumnWidth(),
                      },
                      children: [
                        // 요일 헤더 행
                        TableRow(
                          decoration: BoxDecoration(
                            color: _isDark
                                ? Colors.white.withOpacity(0.04)
                                : Colors.black.withOpacity(0.03),
                          ),
                          children: [
                            const TableCell(
                              child: SizedBox(
                                height: 28,
                                child: Center(child: Text('')),
                              ),
                            ),
                            ...weekdays.asMap().entries.map((entry) {
                              final dayIdx = entry.key;
                              final day = entry.value;
                              final isToday = (todayWeekday == dayIdx + 1);
                              return TableCell(
                                child: Container(
                                  height: 28,
                                  decoration: BoxDecoration(
                                    border: isToday
                                        ? Border.all(
                                            color: _accentColor,
                                            width: 2.0,
                                          )
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      day,
                                      style: GoogleFonts.notoSansKr(
                                        color: isToday
                                            ? _accentColor
                                            : _textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11 * s,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        // 1교시 ~ 7교시 행 구성
                        ...List.generate(7, (periodIdx) {
                          final period = periodIdx + 1;
                          return TableRow(
                            children: [
                              // 교시 라벨
                              TableCell(
                                verticalAlignment:
                                    TableCellVerticalAlignment.middle,
                                child: Container(
                                  height: 52 * s,
                                  color: _isDark
                                      ? Colors.white.withOpacity(0.02)
                                      : Colors.black.withOpacity(0.015),
                                  child: Center(
                                    child: Text(
                                      '$period',
                                      style: GoogleFonts.outfit(
                                        color: _accentColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13 * s,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // 월 ~ 금 셀 채우기
                              ...List.generate(5, (dayIdx) {
                                final day = dayIdx + 1;
                                final lesson = lessons.firstWhere(
                                  (l) =>
                                      l.weekday == day && l.classTime == period,
                                  orElse: () => Lesson(
                                    grade: _settings.selectedGrade,
                                    classNum: _settings.selectedClass,
                                    weekday: day,
                                    classTime: period,
                                    subject: '',
                                    teacher: '',
                                    classroom: '',
                                    isChanged: false,
                                  ),
                                );

                                final isEmpty = lesson.subject.isEmpty;
                                final displayLabel = isHomeroom
                                    ? lesson.subject.replaceAll('*', '')
                                    : '${lesson.grade}-${lesson.classNum}';

                                final isTodayAndCurrentPeriod =
                                    (day == todayWeekday &&
                                    period == activePeriod);

                                return TableCell(
                                  child: Container(
                                    height: 52 * s,
                                    decoration: BoxDecoration(
                                      color: lesson.isChanged
                                          ? const Color(
                                              0xFFEF4565,
                                            ).withOpacity(0.08)
                                          : Colors.transparent,
                                      border: isTodayAndCurrentPeriod
                                          ? Border.all(
                                              color: _accentColor,
                                              width: 2.0,
                                            )
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.all(2),
                                    child: isEmpty
                                        ? Text(
                                            '-',
                                            style: GoogleFonts.notoSansKr(
                                              color: _textColor24,
                                              fontSize: 10 * s,
                                            ),
                                          )
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                displayLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.notoSansKr(
                                                  color: lesson.isChanged
                                                      ? const Color(0xFFEF4565)
                                                      : (isTodayAndCurrentPeriod
                                                            ? _accentColor
                                                            : _textColor),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10 * s,
                                                ),
                                              ),
                                              if (!isHomeroom &&
                                                  lesson
                                                      .subject
                                                      .isNotEmpty) ...[
                                                const SizedBox(height: 1),
                                                Text(
                                                  lesson.subject.replaceAll(
                                                    '*',
                                                    '',
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.notoSansKr(
                                                    color:
                                                        isTodayAndCurrentPeriod
                                                        ? _accentColor
                                                              .withOpacity(0.7)
                                                        : _textColor38,
                                                    fontSize: 8 * s,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                  ),
                                );
                              }),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (inline) {
      return tableWidget;
    }

    return tableWidget;
  }

  // ── 인라인 보드 뷰 ────────────────────────────────────
  Widget _buildInlineBoardView(double s) {
    Widget boardWidget;

    final onBack = () {
      setState(() {
        _activeInlineView = null;
        _activeFilePath = null;
        _activeSubject = null;
      });
    };

    switch (_activeInlineView) {
      case 'pdf':
        boardWidget = _activeFilePath != null
            ? PdfBoardView(
                key: ValueKey(_activeFilePath),
                initialFilePath: _activeFilePath!,
                scaleFactor: s,
                usbSessionId: null,
                onBack: onBack,
                classList: _getTeacherTaughtClasses(),
              )
            : const Center(child: Text('파일 없음'));
        break;
      case 'whiteboard':
        boardWidget = BoardestPenView(
          key: ValueKey('whiteboard_${_activeFilePath ?? 'blank'}'),
          filePath: _activeFilePath ?? '',
          scaleFactor: s,
          subject: _activeSubject,
          teacher: _settings.selectedTeacher,
          onBack: onBack,
        );
        break;
      case 'website':
        boardWidget = WebsiteBoardView(
          key: const ValueKey('website'),
          scaleFactor: s,
          onBack: onBack,
        );
        break;
      default:
        boardWidget = const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20 * s),
      child: boardWidget,
    );
  }

  // ── USB 연결 시 반 매핑 패널 (flex 2) ─────────────────
  Widget _buildMappingPanel(double s) {
    // 이 교사가 담당하는 클래스 목록
    final teacherName = _settings.selectedTeacher
        .replaceAll('*', '')
        .trim()
        .toUpperCase();
    final classroomSet = <String>{};
    if (_timetableResult != null && teacherName.isNotEmpty) {
      for (final l in _timetableResult!.lessons) {
        if (l.teacher.replaceAll('*', '').trim().toUpperCase() == teacherName) {
          classroomSet.add('${l.grade}-${l.classNum}반');
        }
      }
    }
    final classrooms = classroomSet.toList();

    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(color: _borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 * s),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(14 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.class_rounded,
                      color: _accentColor,
                      size: 16 * s,
                    ),
                    SizedBox(width: 6 * s),
                    Expanded(
                      child: Text(
                        '반 매핑',
                        style: GoogleFonts.notoSansKr(
                          color: _textColor,
                          fontSize: 12 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _openFolderOptionsDialog(initialTab: 1),
                      child: Icon(
                        Icons.tune_rounded,
                        color: _textColor54,
                        size: 14 * s,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10 * s),
                if (classrooms.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        '시간표를 먼저 불러오세요',
                        style: GoogleFonts.notoSansKr(
                          color: _textColor38,
                          fontSize: 11 * s,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: classrooms.length,
                      itemBuilder: (_, idx) {
                        final cls = classrooms[idx];
                        final longKey = cls.replaceAll('-', '학년 ');
                        final mapped = _classroomFolderMappings[longKey];
                        final isActive = mapped != null;
                        return GestureDetector(
                          onTap: () => _openFolderOptionsDialog(initialTab: 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: EdgeInsets.only(bottom: 6 * s),
                            padding: EdgeInsets.all(10 * s),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _accentColor.withOpacity(0.10)
                                  : _cardColor,
                              borderRadius: BorderRadius.circular(10 * s),
                              border: Border.all(
                                color: isActive
                                    ? _accentColor.withOpacity(0.4)
                                    : _borderColor,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_rounded,
                                  color: isActive ? _accentColor : _textColor38,
                                  size: 14 * s,
                                ),
                                SizedBox(width: 8 * s),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cls,
                                        style: GoogleFonts.notoSansKr(
                                          color: _textColor,
                                          fontSize: 11 * s,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (isActive) ...[
                                        SizedBox(height: 2 * s),
                                        Text(
                                          mapped!,
                                          style: GoogleFonts.notoSansKr(
                                            color: _textColor54,
                                            fontSize: 9 * s,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── USB 미연결 시 교실 시간표 패널 (flex 4) ────────────
  Widget _buildClassroomTimetablePanel(double s) {
    final grade = _settings.selectedGrade;
    final cls = _settings.selectedClass;

    final lessons =
        _timetableResult?.lessons
            .where((l) => l.grade == grade && l.classNum == cls)
            .toList() ??
        [];

    final weekday = _now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    final displayDay = isWeekend ? 1 : weekday;

    final todayLessons = lessons.where((l) => l.weekday == displayDay).toList()
      ..sort((a, b) => a.classTime.compareTo(b.classTime));

    return GestureDetector(
      onTap: () => _openWeeklyTimetablePopup(true),
      child: Container(
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(color: _borderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20 * s),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Padding(
              padding: EdgeInsets.all(14 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.school_rounded,
                        color: const Color(0xFF7F5AF0),
                        size: 16 * s,
                      ),
                      SizedBox(width: 6 * s),
                      Expanded(
                        child: Text(
                          '$grade학년 $cls반 ${isWeekend ? '월' : _getKoreanWeekday(weekday)} 시간표',
                          style: GoogleFonts.notoSansKr(
                            color: _textColor,
                            fontSize: 12 * s,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _openWeeklyTimetablePopup(true),
                        icon: Icon(
                          Icons.grid_on_rounded,
                          size: 12,
                          color: const Color(0xFF7F5AF0),
                        ),
                        label: Text(
                          '주간',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10 * s,
                            color: const Color(0xFF7F5AF0),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * s,
                            vertical: 4 * s,
                          ),
                          backgroundColor: const Color(
                            0xFF7F5AF0,
                          ).withOpacity(0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * s),
                  if (todayLessons.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              color: _textColor24,
                              size: 28 * s,
                            ),
                            SizedBox(height: 8 * s),
                            Text(
                              '시간표 없음',
                              style: GoogleFonts.notoSansKr(
                                color: _textColor38,
                                fontSize: 11 * s,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: todayLessons.length,
                        itemBuilder: (_, i) {
                          final l = todayLessons[i];
                          final isCurrent = _currentPeriod == l.classTime;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: EdgeInsets.only(bottom: 5 * s),
                            padding: EdgeInsets.symmetric(
                              horizontal: 10 * s,
                              vertical: 7 * s,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF7F5AF0).withOpacity(0.10)
                                  : _cardColor,
                              borderRadius: BorderRadius.circular(12 * s),
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFF7F5AF0).withOpacity(0.5)
                                    : _borderColor,
                                width: isCurrent ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 22 * s,
                                  height: 22 * s,
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFF7F5AF0)
                                        : _borderColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${l.classTime}',
                                      style: GoogleFonts.outfit(
                                        color: isCurrent
                                            ? Colors.white
                                            : _textColor54,
                                        fontSize: 11 * s,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10 * s),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          l.subject.replaceAll('*', ''),
                                          style: GoogleFonts.notoSansKr(
                                            color: isCurrent
                                                ? _textColor
                                                : _textColor70,
                                            fontSize: 12 * s,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (l.isChanged)
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 4 * s,
                                            vertical: 1 * s,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(
                                              0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              3 * s,
                                            ),
                                          ),
                                          child: Text(
                                            '변경',
                                            style: GoogleFonts.notoSansKr(
                                              color: Colors.amber,
                                              fontSize: 8 * s,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 6 * s),
                                Text(
                                  l.teacher.replaceAll('*', ''),
                                  style: GoogleFonts.notoSansKr(
                                    color: const Color(
                                      0xFF7F5AF0,
                                    ).withOpacity(0.7),
                                    fontSize: 9 * s,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 가운데: USB 탐색기 패널 ─────────────────────────

  Widget _buildUsbPanel(double s) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(color: _borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 * s),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(14 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.usb_rounded,
                      color: _isUsbConnected
                          ? const Color(0xFF2CB67D)
                          : _textColor38,
                      size: 16 * s,
                    ),
                    SizedBox(width: 8 * s),
                    Expanded(
                      child: Text(
                        _isUsbConnected
                            ? 'USB 탐색기 — $_usbDriveLetter (Boardest-$_usbType)'
                            : 'USB를 연결해주세요',
                        style: GoogleFonts.notoSansKr(
                          color: _isUsbConnected ? _textColor : _textColor38,
                          fontSize: 13 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_isUsbConnected) ...[
                      if (_usbType == 'Pro') ...[
                        TextButton.icon(
                          onPressed: _openFolderOptionsDialog,
                          icon: Icon(
                            Icons.tune_rounded,
                            color: _accentColor,
                            size: 14 * s,
                          ),
                          label: Text(
                            '폴더 옵션',
                            style: GoogleFonts.notoSansKr(
                              color: _accentColor,
                              fontSize: 11 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10 * s,
                              vertical: 5 * s,
                            ),
                            backgroundColor: _accentColor.withOpacity(0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8 * s),
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        SizedBox(width: 8 * s),
                      ],
                      TextButton.icon(
                        onPressed: _openUsbFormat,
                        icon: Icon(
                          Icons.tune_rounded,
                          color: _accentColor,
                          size: 14 * s,
                        ),
                        label: Text(
                          'USB 형식 변경',
                          style: GoogleFonts.notoSansKr(
                            color: _accentColor,
                            fontSize: 11 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10 * s,
                            vertical: 5 * s,
                          ),
                          backgroundColor: _accentColor.withOpacity(0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8 * s),
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 10 * s),

                Expanded(
                  child: _isUsbConnected
                      ? Container(
                          decoration: BoxDecoration(
                            color: _cardColor,
                            borderRadius: BorderRadius.circular(14 * s),
                            border: Border.all(color: _borderColor),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14 * s),
                            child: UsbExplorer(
                              drivePath:
                                  _classroomFolderMappings[_selectedProClassroom] !=
                                      null
                                  ? p.join(
                                      _usbDriveLetter,
                                      _classroomFolderMappings[_selectedProClassroom]!,
                                    )
                                  : _currentDrivePath.isNotEmpty
                                  ? _currentDrivePath
                                  : _usbDriveLetter,
                              scaleFactor: s,
                              isPro: _usbType == 'Pro',
                              onFileOpen: (path) => _openFile(path),
                              onSyncNow: (folderPath) async {
                                final folderName = p.basename(folderPath);
                                final matchedRule = _syncConfigs.firstWhere(
                                  (c) =>
                                      (c['usb'] ?? '').toLowerCase() ==
                                      folderName.toLowerCase(),
                                  orElse: () => {},
                                );
                                if (matchedRule.isNotEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '[$folderName] 동기화를 실행합니다...',
                                      ),
                                    ),
                                  );
                                  await _syncFolderPair(
                                    matchedRule['local']!,
                                    folderPath,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('동기화 완료!')),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '[$folderName]에 대한 동기화 규칙이 등록되어 있지 않습니다. 폴더 옵션에서 등록해주세요.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              onRegisterSync: (folderPath) {
                                _openFolderOptionsDialog();
                              },
                            ),
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.usb_off_rounded,
                                color: _textColor24,
                                size: 48 * s,
                              ),
                              SizedBox(height: 12 * s),
                              Text(
                                'USB 연결 대기 중...',
                                style: GoogleFonts.notoSansKr(
                                  color: _textColor24,
                                  fontSize: 14 * s,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsbTypeBadgeRow(double s) {
    Color badgeColor = const Color(0xFF2EC4B6);
    String desc = '';
    bool isPro = _usbType == 'Pro';
    if (isPro) {
      badgeColor = _accentColorDark;
      final isMapped = _currentDrivePath != _usbDriveLetter;
      desc = isMapped
          ? '교실 맵핑 완료 (클릭 시 USB 루트로 복귀)'
          : 'Boardest-Pro 모드 (클릭 시 현재 교실 폴더로 맵핑)';
    } else {
      badgeColor = const Color(0xFF2EC4B6);
      desc = '포맷되지 않은 일반 상태입니다. USB 내부 전체를 자유롭게 탐색합니다.';
    }

    return InkWell(
      onTap: isPro
          ? () {
              setState(() {
                if (_currentDrivePath == _usbDriveLetter) {
                  _currentDrivePath = _resolveProUsbPath(_usbDriveLetter);
                } else {
                  _currentDrivePath = _usbDriveLetter;
                }
              });
            }
          : null,
      borderRadius: BorderRadius.circular(12 * s),
      child: Container(
        padding: EdgeInsets.all(10 * s),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12 * s),
          border: Border.all(color: badgeColor.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6 * s),
              ),
              child: Text(
                'Boardest-$_usbType',
                style: GoogleFonts.outfit(
                  color: badgeColor,
                  fontSize: 10 * s,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 10 * s),
            Expanded(
              child: Text(
                desc,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white70,
                  fontSize: 10 * s,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 우측: 수업 도구 패널 ─────────────────────────────

  IconData _getToolIcon(String id) {
    switch (id) {
      case 'timer':
        return Icons.timer_rounded;
      case 'calculator':
        return Icons.calculate_rounded;
      case 'picker':
        return Icons.person_search_rounded;
      case 'weather':
        return Icons.wb_sunny_rounded;
      case 'school_calendar':
        return Icons.calendar_month_rounded;
      case 'notepad':
        return Icons.note_alt_rounded;
      case 'whiteboard':
        return Icons.draw_rounded;
      case 'document_board':
        return Icons.description_rounded;
      case 'website_board':
        return Icons.language_rounded;
      case 'browser_board':
        return Icons.security_rounded;
      case 'youtube_board':
        return Icons.play_circle_fill_rounded;
      case 'canva_board':
        return Icons.palette_rounded;
      case 'student_connect':
        return Icons.wifi_tethering_rounded;
      case 'boardbook':
        return Icons.auto_stories_rounded;
      case 'usb_explorer':
        return Icons.usb_rounded;
      case 'bst_cloud':
        return Icons.cloud_sync_rounded;
      case 'meal_call':
        return Icons.rice_bowl_rounded;
      case 'message_box':
        return Icons.mark_email_unread_rounded;
      case 'settings':
        return Icons.tune_rounded;
      case 'file_explorer':
        return Icons.folder_open_rounded;
      case 'timetable':
        return Icons.calendar_view_week_rounded;
      case 'app_drawer':
        return Icons.apps_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  VoidCallback _getToolOnTap(String id) {
    switch (id) {
      case 'timer':
        return _toggleMiniTimer;
      case 'calculator':
        return _openCalculator;
      case 'picker':
        return _openRandomPicker;
      case 'weather':
        return _openWeatherDialog;
      case 'school_calendar':
        return _openSchoolCalendarDialog;
      case 'whiteboard':
        return _openWhiteboard;
      case 'document_board':
        return _openPdfBoard;
      case 'website_board':
        return _openWebsiteBoard;
      case 'browser_board':
        return _openBrowserBoard;
      case 'youtube_board':
        return _openYoutubeBoard;
      case 'canva_board':
        return _openCanvaBoard;
      case 'boardbook':
        return _openBoardBookEditor;
      case 'usb_explorer':
        return _openUsbExplorerDialog;
      case 'bst_cloud':
        return _openBstCloud;
      case 'meal_call':
        return _openMealCall;
      case 'message_box':
        return _openMessageBox;
      case 'app_drawer':
        return _openAppDrawer;
      case 'settings':
        return _openSettings;
      default:
        return () {};
    }
  }

  void _openUsbExplorerDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 820 * _settings.scaleFactor,
          height: 620 * _settings.scaleFactor,
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(24 * _settings.scaleFactor),
            border: Border.all(color: _borderColor),
          ),
          child: _buildUsbPanel(_settings.scaleFactor),
        ),
      ),
    );
  }

  void _openBstCloud() {
    showDialog(
      context: context,
      builder: (context) => _BstCloudDialog(
        scaleFactor: _settings.scaleFactor,
        onFileDownloaded: (file) => _openFile(file.path),
        onStatusChanged: () {
          _checkUsb();
        },
      ),
    );
  }

  void _openAppDrawer() {
    final s = _settings.scaleFactor;
    final apps = [
      {'name': '메모장 (Notepad)', 'icon': Icons.edit_note_rounded, 'color': const Color(0xFFFF8906), 'action': () => Process.run('notepad.exe', [])},
      {'name': '계산기 (Calculator)', 'icon': Icons.calculate_rounded, 'color': const Color(0xFF2EC4B6), 'action': () => Process.run('calc.exe', [])},
      {'name': '그림판 (Paint)', 'icon': Icons.brush_rounded, 'color': const Color(0xFFEF4565), 'action': () => Process.run('mspaint.exe', [])},
      {'name': '파일 탐색기', 'icon': Icons.folder_rounded, 'color': const Color(0xFFFF8E3C), 'action': () => Process.run('explorer.exe', [])},
      {'name': '작업 관리자', 'icon': Icons.assessment_rounded, 'color': const Color(0xFF00F5D4), 'action': () => Process.run('taskmgr.exe', [])},
      {'name': '웹 브라우저', 'icon': Icons.language_rounded, 'color': const Color(0xFF3B82F6), 'action': () => launchUrl(Uri.parse('https://www.google.com'))},
      {'name': '기본 판서', 'icon': Icons.draw_rounded, 'color': const Color(0xFF2EC4B6), 'action': _openWhiteboard},
      {'name': '문서 판서', 'icon': Icons.picture_as_pdf_rounded, 'color': const Color(0xFFEF4565), 'action': _openPdfBoard},
      {'name': 'Canva 슬라이드', 'icon': Icons.palette_rounded, 'color': const Color(0xFF8B5CF6), 'action': () => _openCanvaBoard()},
      {'name': '수업 유튜브', 'icon': Icons.video_library_rounded, 'color': Colors.redAccent, 'action': () => _openYoutubeBoard()},
      {'name': '급식 지도 & 문자', 'icon': Icons.restaurant_menu_rounded, 'color': const Color(0xFF2EC4B6), 'action': () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MealView(scaleFactor: s)))},
      {'name': '학급 쪽지', 'icon': Icons.mail_rounded, 'color': const Color(0xFFFF8906), 'action': () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageView(scaleFactor: s)))},
      {'name': '날씨 정보', 'icon': Icons.wb_sunny_rounded, 'color': const Color(0xFFFF8906), 'action': () => showDialog(context: context, builder: (_) => WeatherDialog(scaleFactor: s))},
      {'name': '학사 일정', 'icon': Icons.calendar_month_rounded, 'color': const Color(0xFF00F5D4), 'action': () => showDialog(context: context, builder: (_) => SchoolCalendarDialog(scaleFactor: s, apiScheduleEvents: const []))},
      {'name': '보드북 편집기', 'icon': Icons.menu_book_rounded, 'color': const Color(0xFF7F5AF0), 'action': _openBoardBookEditor},
      {'name': '설정', 'icon': Icons.settings_rounded, 'color': Colors.white70, 'action': _openSettings},
    ];

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24 * s),
          side: BorderSide(color: _borderColor, width: 1.2),
        ),
        child: Container(
          width: 720 * s,
          height: 540 * s,
          padding: EdgeInsets.all(24 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.grid_view_rounded, color: const Color(0xFF00F5D4), size: 24 * s),
                      SizedBox(width: 10 * s),
                      Text(
                        'BST 전체 앱 서랍 (App Drawer)',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 18 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Divider(color: Colors.white.withOpacity(0.08), height: 20 * s),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: 12 * s,
                    mainAxisSpacing: 12 * s,
                  ),
                  itemCount: apps.length,
                  itemBuilder: (context, idx) {
                    final app = apps[idx];
                    final IconData icon = app['icon'] as IconData;
                    final Color color = app['color'] as Color;
                    final VoidCallback action = app['action'] as VoidCallback;
                    final String name = app['name'] as String;

                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        action();
                      },
                      borderRadius: BorderRadius.circular(16 * s),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16 * s),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.all(12 * s),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, color: color, size: 26 * s),
                            ),
                            SizedBox(height: 8 * s),
                            Text(
                              name,
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontSize: 12 * s,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCalculator() {
    setState(() {
      _showMiniCalculator = !_showMiniCalculator;
      if (_showMiniCalculator) {
        _calculatorWindowOffset = const Offset(500, 200);
      }
    });
  }

  void _openWeatherDialog() {
    showDialog(
      context: context,
      builder: (context) => WeatherDialog(scaleFactor: _settings.scaleFactor),
    );
  }

  void _openSchoolCalendarDialog() {
    showDialog(
      context: context,
      builder: (context) => SchoolCalendarDialog(
        scaleFactor: _settings.scaleFactor,
        apiScheduleEvents: _apiScheduleEvents,
      ),
    );
  }

  String _getKoreanWeekday(int weekday) {
    switch (weekday) {
      case 1:
        return '월';
      case 2:
        return '화';
      case 3:
        return '수';
      case 4:
        return '목';
      case 5:
        return '금';
      case 6:
        return '토';
      case 7:
        return '일';
      default:
        return '';
    }
  }

  void _openWebsiteBoard() {
    setState(() {
      _activeInlineView = 'website';
    });
  }

  void _launchSystemApp(SystemApp app) async {
    final path = app.appId;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      final uri = Uri.parse(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } else {
      if (Platform.isWindows) {
        Process.run(path, []);
      }
    }
  }

  void _openAppSelectorForSlot(int slotIndex) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe', 'lnk'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = p.basenameWithoutExtension(path);

      final updatedSlots = List<LauncherSlot>.from(_settings.launcherSlots);
      updatedSlots[slotIndex] = LauncherSlot(
        type: LauncherSlotType.systemApp,
        name: name,
        id: path,
      );
      final newSettings = _settings.copyWith(launcherSlots: updatedSlots);
      await _storageService.saveSettings(newSettings);
      setState(() {
        _settings = newSettings;
      });
    }
  }

  void _removeAppFromSlot(int slotIndex) async {
    final updatedSlots = List<LauncherSlot>.from(_settings.launcherSlots);
    updatedSlots[slotIndex] = LauncherSlot(
      type: LauncherSlotType.empty,
      name: '',
      id: '',
    );
    final newSettings = _settings.copyWith(launcherSlots: updatedSlots);
    await _storageService.saveSettings(newSettings);
    setState(() {
      _settings = newSettings;
    });
  }

  void _openBrowserBoard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserBoardView(scaleFactor: _settings.scaleFactor),
      ),
    );
  }

  void _openYoutubeBoard({String? url, String? filePath}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => YoutubeBoardView(
          scaleFactor: _settings.scaleFactor,
          initialUrl: url,
          filePath: filePath,
        ),
      ),
    );
  }

  void _openCanvaBoard({String? url, String? filePath}) {
    _showCanvaUrlInputDialog(initialUrl: url, filePath: filePath);
  }

  Future<void> _showCanvaUrlInputDialog({String? initialUrl, String? filePath}) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedUrls = prefs.getStringList('saved_canva_urls') ?? [];
    final lastUrl = prefs.getString('last_canva_url') ?? '';

    final urlCtrl = TextEditingController(text: initialUrl ?? (lastUrl.isNotEmpty ? lastUrl : ''));

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          title: Row(
            children: [
              const Icon(Icons.palette_rounded, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              Text('🎨 Canva 슬라이드 URL 입력', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('수업에 사용할 Canva 프레젠테이션 URL 주소를 입력하면 자동 저장됩니다.', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'https://www.canva.com/design/...',
                  hintStyle: TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Color(0xFF242629),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('💾 저장된 Canva URL:', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      label: const Text('기본 Canva', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11)),
                      backgroundColor: const Color(0xFF242629),
                      onPressed: () => urlCtrl.text = 'https://www.canva.com',
                    ),
                    const SizedBox(width: 6),
                    ...savedUrls.map((u) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(u, style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 11), overflow: TextOverflow.ellipsis),
                        backgroundColor: const Color(0xFF242629),
                        onPressed: () => urlCtrl.text = u,
                      ),
                    )),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () async {
                final val = urlCtrl.text.trim();
                if (val.isNotEmpty) {
                  final list = prefs.getStringList('saved_canva_urls') ?? [];
                  if (!list.contains(val)) list.add(val);
                  await prefs.setStringList('saved_canva_urls', list);
                  await prefs.setString('last_canva_url', val);
                }
                Navigator.pop(ctx);
                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CanvaBoardView(
                        scaleFactor: _settings.scaleFactor,
                        initialUrl: val.isNotEmpty ? val : null,
                        filePath: filePath,
                      ),
                    ),
                  );
                }
              },
              child: const Text('💾 저장 및 Canva 판서 시작', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _openMealCall() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealView(scaleFactor: _settings.scaleFactor),
      ),
    );
  }

  void _openMessageBox() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessageView(scaleFactor: _settings.scaleFactor),
      ),
    );
  }

  // ── 수업 도구 패널 (3열 × 6행 그리드 = 총 18개 슬롯) ───────────────────────
  Widget _buildToolsPanel(double s) {
    // 3열 × 6행 = 18 슬롯 (가로 3, 세로 6)
    final List<Map<String, String>> col1Tools = [
      {'id': 'timer',           'name': '타이머'},
      {'id': 'calculator',      'name': '계산기'},
      {'id': 'picker',          'name': '발표자'},
      {'id': 'weather',         'name': '날씨'},
      {'id': 'school_calendar', 'name': '학사달력'},
      {'id': 'boardbook',       'name': 'BoardBook'},
    ];
    final List<Map<String, String>> col2Tools = [
      {'id': 'whiteboard',      'name': '기본판서'},
      {'id': 'document_board',  'name': '문서판서'},
      {'id': 'website_board',   'name': '사이트판서'},
      {'id': 'browser_board',   'name': '웹브라우저'},
      {'id': 'youtube_board',   'name': '유튜브'},
      {'id': 'canva_board',     'name': '캔바'},
    ];
    final List<Map<String, String>> col3Tools = [
      {'id': 'usb_explorer',    'name': 'USB 탐색기'},
      {'id': 'bst_cloud',       'name': 'BST Cloud'},
      {'id': 'meal_call',       'name': '급식문자'},
      {'id': 'message_box',     'name': '학급쪽지'},
      {'id': 'app_drawer',      'name': '앱 서랍'},
      {'id': 'settings',        'name': '설정'},
    ];

    return Container(
      padding: EdgeInsets.all(8 * s),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4 * s,
                height: 12 * s,
                decoration: BoxDecoration(
                  color: _accentColorLight,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColorLight.withOpacity(0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 6 * s),
              Text(
                'BST 수업 도구',
                style: GoogleFonts.notoSansKr(
                  color: _textColor,
                  fontSize: 12 * s,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(width: 4 * s),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00F5D4).withOpacity(0.3),
                        const Color(0xFF00F5D4).withOpacity(0.01),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6 * s),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1열 (6행)
                Expanded(
                  child: Column(
                    children: List.generate(6, (index) {
                      final item = col1Tools[index];
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(2 * s),
                          child: _buildGridSlot(item['id']!, item['name']!, s),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(width: 4 * s),
                // 2열 (6행)
                Expanded(
                  child: Column(
                    children: List.generate(6, (index) {
                      final item = col2Tools[index];
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(2 * s),
                          child: _buildGridSlot(item['id']!, item['name']!, s),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(width: 4 * s),
                // 3열 (6행)
                Expanded(
                  child: Column(
                    children: List.generate(6, (index) {
                      final item = col3Tools[index];
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(2 * s),
                          child: _buildGridSlot(item['id']!, item['name']!, s),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildGridSlot(String id, String name, double scale) {
    final colors = [
      const Color(0xFF2EC4B6),
      const Color(0xFF00F5D4),
      const Color(0xFF2CB67D),
    ];

    final Color accentColor = colors[id.hashCode.abs() % colors.length];
    final IconData icon = _getToolIcon(id);
    final VoidCallback onTap = _getToolOnTap(id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10 * scale),
        child: Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(10 * scale),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: Container(
                  width: 22 * scale,
                  height: 22 * scale,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6 * scale),
                    border: Border.all(
                      color: accentColor.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, color: accentColor, size: 12 * scale),
                  ),
                ),
              ),
              SizedBox(height: 3 * scale),
              Text(
                name,
                style: GoogleFonts.notoSansKr(
                  fontSize: 8.5 * scale,
                  fontWeight: FontWeight.w600,
                  color: _textColor54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 플로팅 미니 타이머 오버레이 UI ─────────────────────────

  Widget _buildFloatingTimer(double scale) {
    final String timeText =
        '${(_timerSecondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_timerSecondsElapsed % 60).toString().padLeft(2, '0')}';
    final accentColor = const Color(0xFFFF8906);

    return Positioned(
      left: _timerWindowOffset.dx,
      top: _timerWindowOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _timerWindowOffset += details.delta;
          });
        },
        child: Material(
          elevation: 16,
          color: Colors.transparent,
          child: Container(
            width: 250 * scale,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 타이머 헤더 바
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.timer_rounded,
                          color: accentColor,
                          size: 16 * scale,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '타이머',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12 * scale,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white38,
                        size: 16,
                      ),
                      onPressed: _toggleMiniTimer,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 시간 텍스트
                Text(
                  timeText,
                  style: GoogleFonts.outfit(
                    fontSize: 48 * scale,
                    fontWeight: FontWeight.w900,
                    color: accentColor,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),

                // 제어 버튼들
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        _timerRunning
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24 * scale,
                      ),
                      onPressed: _timerRunning
                          ? _pauseMiniTimer
                          : _startMiniTimer,
                      style: IconButton.styleFrom(
                        backgroundColor: _timerRunning
                            ? Colors.orangeAccent
                            : const Color(0xFF2CB67D),
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.replay_rounded,
                        color: Colors.white,
                        size: 20 * scale,
                      ),
                      onPressed: _resetMiniTimer,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4565),
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 시간 조절 프리셋 버튼
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTimerPresetButton('+1분', 60, scale),
                    _buildTimerPresetButton('+3분', 180, scale),
                    _buildTimerPresetButton('+5분', 300, scale),
                    _buildTimerPresetButton('CLR', -1, scale),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimerPresetButton(String label, int seconds, double scale) {
    return SizedBox(
      height: 24 * scale,
      child: TextButton(
        onPressed: () {
          if (seconds == -1) {
            setState(() {
              _timerTargetSeconds = 0;
              _timerSecondsElapsed = 0;
              _timerRunning = false;
              _miniTimerInstance?.cancel();
            });
          } else {
            _adjustMiniTimer(seconds);
          }
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          backgroundColor: Colors.white.withOpacity(0.04),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          minimumSize: Size.zero,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white70,
            fontSize: 10 * scale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── 플로팅 계산기 오버레이 UI ─────────────────────────
  Widget _buildMiniCalculatorWindow(double scale) {
    final accentColor = const Color(0xFF2EC4B6);

    return Positioned(
      left: _calculatorWindowOffset.dx,
      top: _calculatorWindowOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _calculatorWindowOffset += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 230 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withOpacity(0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accentColor.withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: accentColor.withOpacity(0.08),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14 * scale,
                        vertical: 8 * scale,
                      ),
                      color: Colors.white.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calculate_rounded,
                            color: accentColor,
                            size: 14 * scale,
                          ),
                          SizedBox(width: 8 * scale),
                          Text(
                            '계산기',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.bold,
                              fontSize: 11 * scale,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close_rounded,
                              color: const Color(0xFFEF4565),
                              size: 14 * scale,
                            ),
                            onPressed: () {
                              setState(() {
                                _showMiniCalculator = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16 * scale,
                        vertical: 12 * scale,
                      ),
                      alignment: Alignment.centerRight,
                      color: Colors.black.withOpacity(0.2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _calcExpression.isEmpty ? '0' : _calcExpression,
                            style: GoogleFonts.outfit(
                              fontSize: 18 * scale,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4 * scale),
                          Text(
                            _calcResult.isEmpty ? '0' : _calcResult,
                            style: GoogleFonts.outfit(
                              fontSize: 26 * scale,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF00F5D4),
                              shadows: [
                                Shadow(
                                  color: const Color(
                                    0xFF00F5D4,
                                  ).withOpacity(0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.all(8.0 * scale),
                      child: Column(
                        children: [
                          _buildCalcRow(['C', '⌫', '%', '/'], scale),
                          _buildCalcRow(['7', '8', '9', '*'], scale),
                          _buildCalcRow(['4', '5', '6', '-'], scale),
                          _buildCalcRow(['1', '2', '3', '+'], scale),
                          _buildCalcRow(['0', '.', '='], scale),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalcRow(List<String> keys, double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.0 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: keys.map((k) {
          final isOperator = ['/', '*', '-', '+', '='].contains(k);
          final isClear = ['C', '⌫', '%'].contains(k);

          Color btnColor = Colors.white.withOpacity(0.04);
          Color textColor = Colors.white.withOpacity(0.85);
          if (isOperator) {
            btnColor = const Color(0xFF2EC4B6).withOpacity(0.15);
            textColor = const Color(0xFF00F5D4);
          } else if (isClear) {
            btnColor = const Color(0xFFEF4565).withOpacity(0.12);
            textColor = const Color(0xFFEF4565);
          }

          if (k == '=') {
            btnColor = const Color(0xFF2EC4B6);
            textColor = Colors.white;
          }

          return Expanded(
            flex: k == '0' ? 2 : 1,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 3.0 * scale),
              child: SizedBox(
                height: 34 * scale,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: textColor,
                    padding: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isOperator && k != '='
                            ? const Color(0xFF2EC4B6).withOpacity(0.35)
                            : (isClear
                                  ? const Color(0xFFEF4565).withOpacity(0.3)
                                  : Colors.white.withOpacity(0.06)),
                        width: 1,
                      ),
                    ),
                  ),
                  onPressed: () => _onCalcKeyPress(k),
                  child: Text(
                    k,
                    style: GoogleFonts.outfit(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _onCalcKeyPress(String val) {
    setState(() {
      if (val == 'C' || val == 'AC') {
        _calcExpression = '';
        _calcResult = '';
      } else if (val == '⌫') {
        if (_calcExpression.isNotEmpty) {
          _calcExpression = _calcExpression.substring(
            0,
            _calcExpression.length - 1,
          );
        }
      } else if (val == '=') {
        _evaluateCalcExpression();
      } else {
        final operators = ['+', '-', '*', '/'];
        if (_calcExpression.isNotEmpty) {
          final lastChar = _calcExpression[_calcExpression.length - 1];
          if (operators.contains(lastChar) && operators.contains(val)) {
            _calcExpression =
                _calcExpression.substring(0, _calcExpression.length - 1) + val;
            return;
          }
        }
        _calcExpression += val;
      }
    });
  }

  void _evaluateCalcExpression() {
    if (_calcExpression.isEmpty) return;
    try {
      String expr = _calcExpression
          .replaceAll('*', ' * ')
          .replaceAll('/', ' / ')
          .replaceAll('+', ' + ')
          .replaceAll('-', ' - ');
      List<String> tokens = expr.split(' ').where((t) => t.isNotEmpty).toList();

      if (tokens.isEmpty) return;

      List<String> pass1 = [];
      int i = 0;
      while (i < tokens.length) {
        if (tokens[i] == '*' || tokens[i] == '/') {
          final op = tokens[i];
          if (pass1.isEmpty || i + 1 >= tokens.length) {
            _calcResult = '오류';
            return;
          }
          final double left = double.tryParse(pass1.removeLast()) ?? 0.0;
          final double right = double.tryParse(tokens[i + 1]) ?? 0.0;
          double res = 0.0;
          if (op == '*') {
            res = left * right;
          } else {
            if (right == 0.0) {
              _calcResult = '0으로 나눌 수 없음';
              return;
            }
            res = left / right;
          }
          pass1.add(res.toString());
          i += 2;
        } else {
          pass1.add(tokens[i]);
          i++;
        }
      }

      if (pass1.isEmpty) return;
      double result = double.tryParse(pass1[0]) ?? 0.0;
      int j = 1;
      while (j < pass1.length) {
        final op = pass1[j];
        if (j + 1 >= pass1.length) {
          _calcResult = '오류';
          return;
        }
        final double right = double.tryParse(pass1[j + 1]) ?? 0.0;
        if (op == '+') {
          result += right;
        } else if (op == '-') {
          result -= right;
        }
        j += 2;
      }

      if (result % 1 == 0) {
        _calcResult = result.toInt().toString();
      } else {
        _calcResult = result.toStringAsFixed(4);
        while (_calcResult.endsWith('0')) {
          _calcResult = _calcResult.substring(0, _calcResult.length - 1);
        }
        if (_calcResult.endsWith('.')) {
          _calcResult = _calcResult.substring(0, _calcResult.length - 1);
        }
      }
    } catch (e) {
      _calcResult = '오류';
    }
  }

  // ── 플로팅 무작위 발표자 오버레이 UI ─────────────────────────
  Widget _buildMiniPickerWindow(double scale) {
    final accentColor = const Color(0xFF00F5D4);

    return Positioned(
      left: _pickerWindowOffset.dx,
      top: _pickerWindowOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _pickerWindowOffset += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withOpacity(0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accentColor.withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: accentColor.withOpacity(0.08),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Bar
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14 * scale,
                        vertical: 8 * scale,
                      ),
                      color: Colors.white.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(
                            Icons.emoji_people_rounded,
                            color: accentColor,
                            size: 14 * scale,
                          ),
                          SizedBox(width: 8 * scale),
                          Text(
                            '무작위 발표자',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.bold,
                              fontSize: 11 * scale,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close_rounded,
                              color: const Color(0xFFEF4565),
                              size: 14 * scale,
                            ),
                            onPressed: () {
                              setState(() {
                                _showMiniPicker = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    // Main Area
                    Padding(
                      padding: EdgeInsets.all(16.0 * scale),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Student Count Selector
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '학생 수:',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white70,
                                  fontSize: 11 * scale,
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4 * scale,
                                    ),
                                    icon: Icon(
                                      Icons.remove_circle_outline,
                                      color: const Color(0xFF2EC4B6),
                                      size: 16 * scale,
                                    ),
                                    onPressed: _pickerRolling
                                        ? null
                                        : () {
                                            if (_pickerMaxStudents > 2) {
                                              setState(() {
                                                _pickerMaxStudents--;
                                              });
                                            }
                                          },
                                  ),
                                  Text(
                                    '$_pickerMaxStudents명',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 13 * scale,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4 * scale,
                                    ),
                                    icon: Icon(
                                      Icons.add_circle_outline,
                                      color: const Color(0xFF2EC4B6),
                                      size: 16 * scale,
                                    ),
                                    onPressed: _pickerRolling
                                        ? null
                                        : () {
                                            if (_pickerMaxStudents < 99) {
                                              setState(() {
                                                _pickerMaxStudents++;
                                              });
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 12 * scale),

                          // Winner display area
                          Container(
                            height: 100 * scale,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF16161A).withOpacity(0.8),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _pickerWinner != null && !_pickerRolling
                                    ? accentColor.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.05),
                              ),
                            ),
                            child: _pickerRolling
                                ? SizedBox(
                                    width: 24 * scale,
                                    height: 24 * scale,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5 * scale,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        accentColor,
                                      ),
                                    ),
                                  )
                                : _pickerWinner == null
                                ? Text(
                                    '?',
                                    style: GoogleFonts.outfit(
                                      fontSize: 48 * scale,
                                      color: Colors.white24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '당첨자 🎉',
                                        style: GoogleFonts.notoSansKr(
                                          color: Colors.white60,
                                          fontSize: 9 * scale,
                                        ),
                                      ),
                                      SizedBox(height: 2 * scale),
                                      Text(
                                        '$_pickerWinner번',
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 32 * scale,
                                          color: accentColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          SizedBox(height: 12 * scale),

                          // Trigger Button
                          SizedBox(
                            width: double.infinity,
                            height: 36 * scale,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2EC4B6),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFF2EC4B6,
                                ).withOpacity(0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: _pickerRolling
                                  ? null
                                  : () async {
                                      setState(() {
                                        _pickerRolling = true;
                                        _pickerWinner = null;
                                      });
                                      final random =
                                          DateTime.now().millisecondsSinceEpoch;
                                      int rollCount = 15;
                                      for (int i = 0; i < rollCount; i++) {
                                        await Future.delayed(
                                          Duration(milliseconds: 50 + (i * 15)),
                                        );
                                        if (!mounted) return;
                                        final candidate =
                                            ((random + i) %
                                                _pickerMaxStudents) +
                                            1;
                                        setState(() {
                                          _pickerWinner = candidate;
                                        });
                                      }
                                      if (mounted) {
                                        setState(() {
                                          _pickerRolling = false;
                                        });
                                      }
                                    },
                              child: Text(
                                _pickerRolling ? '추첨 중...' : '추첨 시작 🎲',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadClassroomMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('classroom_folder_mappings');
    if (jsonStr != null) {
      try {
        setState(() {
          _classroomFolderMappings = Map<String, String>.from(
            jsonDecode(jsonStr),
          );
        });
      } catch (_) {}
    }
  }

  Future<void> _saveClassroomMappings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'classroom_folder_mappings',
      jsonEncode(_classroomFolderMappings),
    );
  }

  void _scanUsbFolders() {
    if (!_isUsbConnected || _usbDriveLetter.isEmpty) {
      setState(() {
        _usbFolders = [];
      });
      return;
    }
    try {
      final usbDir = Directory(_usbDriveLetter);
      if (usbDir.existsSync()) {
        final List<String> list = [];
        final entities = usbDir.listSync();
        for (final entity in entities) {
          if (entity is Directory) {
            list.add(p.basename(entity.path));
          }
        }
        setState(() {
          _usbFolders = list;
        });
      }
    } catch (e) {
      debugPrint('[TeacherView] Failed to scan USB folders: $e');
    }
  }

  void _stopFolderWatchers() {
    for (final sub in _syncWatchers) {
      sub.cancel();
    }
    _syncWatchers.clear();
    _debounceSyncTimer?.cancel();
  }

  void _startFolderWatchers() {
    _stopFolderWatchers();
    if (!_isUsbConnected || _usbDriveLetter.isEmpty) return;

    for (final rule in _syncConfigs) {
      final localPath = rule['local'] ?? '';
      final usbFolder = rule['usb'] ?? '';
      if (localPath.isEmpty || usbFolder.isEmpty) continue;

      // Watch Local folder
      try {
        final localDir = Directory(localPath);
        if (localDir.existsSync()) {
          final sub = localDir.watch(recursive: true).listen((event) {
            debugPrint(
              '[FolderSyncWatcher] Change detected in local: ${event.path}',
            );
            _onFolderChanged(rule);
          });
          _syncWatchers.add(sub);
        }
      } catch (e) {
        debugPrint(
          '[FolderSyncWatcher] Failed to watch local path ($localPath): $e',
        );
      }

      // Watch USB folder
      try {
        final usbSyncPath = p.join(_usbDriveLetter, usbFolder);
        final usbDir = Directory(usbSyncPath);
        if (!usbDir.existsSync()) {
          usbDir.createSync(recursive: true);
        }
        final sub = usbDir.watch(recursive: true).listen((event) {
          debugPrint(
            '[FolderSyncWatcher] Change detected in USB: ${event.path}',
          );
          _onFolderChanged(rule);
        });
        _syncWatchers.add(sub);
      } catch (e) {
        debugPrint(
          '[FolderSyncWatcher] Failed to watch USB path ($usbFolder): $e',
        );
      }
    }
    debugPrint(
      '[FolderSyncWatcher] Started ${_syncWatchers.length} folder watchers.',
    );
  }

  void _onFolderChanged(Map<String, String> rule) {
    if (_isSyncingInProgress) return;
    _debounceSyncTimer?.cancel();
    _debounceSyncTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (_isSyncingInProgress) return;
      _isSyncingInProgress = true;
      try {
        final localPath = rule['local'] ?? '';
        final usbFolder = rule['usb'] ?? '';
        if (localPath.isNotEmpty &&
            usbFolder.isNotEmpty &&
            _isUsbConnected &&
            _usbDriveLetter.isNotEmpty) {
          final usbSyncPath = p.join(_usbDriveLetter, usbFolder);
          debugPrint(
            '[FolderSyncWatcher] Triggering auto-sync for $localPath <-> $usbSyncPath',
          );
          await _syncFolderPair(localPath, usbSyncPath);
        }
      } catch (e) {
        debugPrint('[FolderSyncWatcher] Error during auto-sync: $e');
      } finally {
        await Future.delayed(const Duration(milliseconds: 500));
        _isSyncingInProgress = false;
      }
    });
  }

  Widget _buildTitleBar(double s) {
    final List<Map<String, String>> titleBarTools = [
      {'id': 'timer', 'name': '타이머'},
      {'id': 'calculator', 'name': '계산기'},
      {'id': 'whiteboard', 'name': '기본판서'},
      {'id': 'picker', 'name': '발표자'},
      {'id': 'document_board', 'name': '문서판서'},
      {'id': 'weather', 'name': '날씨'},
      {'id': 'website_board', 'name': '사이트 판서'},
      {'id': 'school_calendar', 'name': '학사달력'},
      {'id': 'settings', 'name': '설정'},
    ];

    return Container(
      height: 44 * s,
      decoration: BoxDecoration(color: _surfaceColor),
      child: Row(
        children: [
          SizedBox(width: 16 * s),
          _MacTrafficLights(
            scale: s,
            onClose: () => exit(0),
            onMinimize: () => windowManager.minimize(),
            onMaximize: () async {
              bool isMax = await windowManager.isMaximized();
              if (isMax) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            onPopup: () => _enterMiniMode(),
          ),
          SizedBox(width: 20 * s),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                bool isMax = await windowManager.isMaximized();
                if (isMax) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: Row(
                children: [
                  Icon(Icons.school_rounded, color: _accentColor, size: 18 * s),
                  SizedBox(width: 8 * s),
                  Text(
                    'Bst Teacher',
                    style: GoogleFonts.outfit(
                      color: _textColor,
                      fontSize: 16 * s,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  // USB Status Badge (Only when physical USB is connected)
                  if (_isUsbConnected) ...[
                    InkWell(
                      onTap: _openUsbExplorerDialog,
                      borderRadius: BorderRadius.circular(10 * s),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF006a60).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10 * s),
                          border: Border.all(color: const Color(0xFF74f8e5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.usb_rounded,
                              size: 13 * s,
                              color: const Color(0xFF74f8e5),
                            ),
                            SizedBox(width: 4 * s),
                            Text(
                              'USB (${_usbDriveLetter})',
                              style: TextStyle(
                                color: const Color(0xFF74f8e5),
                                fontSize: 11 * s,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 6 * s),
                  ],
                  // Google Login Status Badge
                  InkWell(
                    onTap: _openBstCloud,
                    borderRadius: BorderRadius.circular(10 * s),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
                      decoration: BoxDecoration(
                        color: CloudDriveService.instance.isLoggedIn ? const Color(0xFF2EC4B6).withOpacity(0.2) : const Color(0xFFFF8906).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10 * s),
                        border: Border.all(color: CloudDriveService.instance.isLoggedIn ? const Color(0xFF2EC4B6) : const Color(0xFFFF8906)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CloudDriveService.instance.isLoggedIn ? Icons.cloud_done_rounded : Icons.account_circle_rounded,
                            size: 13 * s,
                            color: CloudDriveService.instance.isLoggedIn ? const Color(0xFF2EC4B6) : const Color(0xFFFF8906),
                          ),
                          SizedBox(width: 4 * s),
                          Text(
                            CloudDriveService.instance.isLoggedIn ? (CloudDriveService.instance.userName ?? 'Google 연결됨') : '로그인 필요',
                            style: TextStyle(
                              color: CloudDriveService.instance.isLoggedIn ? const Color(0xFF2EC4B6) : const Color(0xFFFF8906),
                              fontSize: 11 * s,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),

                  // Render the 10 BST tools in the title bar (aligned right, only when USB is connected)
                  if (_isUsbConnected) ...[
                    Tooltip(
                      message: _bridgeStatus,
                      child: IconButton(
                        onPressed: _openBoardControlDialog,
                        icon: Icon(
                          _boardStatus == null
                              ? Icons.usb_rounded
                              : Icons.cast_connected_rounded,
                          color: _boardStatus == null
                              ? Colors.amber
                              : const Color(0xFF2CB67D),
                          size: 18 * s,
                        ),
                      ),
                    ),
                    ...titleBarTools.map((t) {
                      final id = t['id']!;
                      final name = t['name']!;
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2 * s),
                        child: Tooltip(
                          message: name,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _getToolOnTap(id),
                              borderRadius: BorderRadius.circular(8 * s),
                              child: Container(
                                width: 32 * s,
                                height: 32 * s,
                                alignment: Alignment.center,
                                child: Icon(
                                  _getToolIcon(id),
                                  color: _accentColor,
                                  size: 18 * s,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    SizedBox(width: 16 * s),
                  ],

                   // AOT (Always On Top) 토글 버튼 — 항상 표시
                  Tooltip(
                    message: _isAlwaysOnTop ? '항상 위 해제' : '항상 위 (AOT)',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          final next = !_isAlwaysOnTop;
                          await windowManager.setAlwaysOnTop(next);
                          setState(() => _isAlwaysOnTop = next);
                        },
                        borderRadius: BorderRadius.circular(8 * s),
                        child: Container(
                          width: 32 * s,
                          height: 32 * s,
                          alignment: Alignment.center,
                          decoration: _isAlwaysOnTop
                              ? BoxDecoration(
                                  color: const Color(0xFF7F5AF0).withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(8 * s),
                                  border: Border.all(
                                    color: const Color(0xFF7F5AF0).withOpacity(0.5),
                                  ),
                                )
                              : null,
                          child: Icon(
                            Icons.push_pin_rounded,
                            color: _isAlwaysOnTop
                                ? const Color(0xFF7F5AF0)
                                : _textColor54,
                            size: 16 * s,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * s),

                  if (!_isUsbConnected) ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8 * s,
                        vertical: 3 * s,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6 * s),
                        border: Border.all(
                          color: Colors.redAccent.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        'USB 연결 없음.',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.redAccent,
                          fontSize: 11 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 16 * s),
                  ] else if (_usbType == 'Cloud') ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8 * s,
                        vertical: 3 * s,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF006a60).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6 * s),
                        border: Border.all(
                          color: const Color(0xFF74f8e5).withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done_rounded,
                              color: const Color(0xFF74f8e5), size: 12 * s),
                          SizedBox(width: 4 * s),
                          Text(
                            'Cloud',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF74f8e5),
                              fontSize: 11 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 16 * s),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Win7TrafficLights extends StatefulWidget {
  final double scale;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onPopup;

  const _Win7TrafficLights({
    required this.scale,
    required this.onClose,
    required this.onMinimize,
    required this.onMaximize,
    required this.onPopup,
  });

  @override
  State<_Win7TrafficLights> createState() => _Win7TrafficLightsState();
}

class _Win7TrafficLightsState extends State<_Win7TrafficLights> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return Container(
      height: 28 * s,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2E40).withOpacity(0.4),
        borderRadius: BorderRadius.circular(6 * s),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildWin7Btn(
            index: 0,
            icon: Icons.picture_in_picture_alt_rounded,
            tooltip: '미니 팝업 모드',
            hoverColor: const Color(0xFF0084FF),
            onTap: widget.onPopup,
            scale: s,
          ),
          _buildWin7Btn(
            index: 1,
            icon: Icons.remove_rounded,
            tooltip: '최소화',
            hoverColor: Colors.white.withOpacity(0.2),
            onTap: widget.onMinimize,
            scale: s,
          ),
          _buildWin7Btn(
            index: 2,
            icon: Icons.crop_square_rounded,
            tooltip: '최대화',
            hoverColor: Colors.white.withOpacity(0.2),
            onTap: widget.onMaximize,
            scale: s,
          ),
          _buildWin7Btn(
            index: 3,
            icon: Icons.close_rounded,
            tooltip: '닫기',
            hoverColor: const Color(0xFFE81123),
            isClose: true,
            onTap: widget.onClose,
            scale: s,
          ),
        ],
      ),
    );
  }

  Widget _buildWin7Btn({
    required int index,
    required IconData icon,
    required String tooltip,
    required Color hoverColor,
    required VoidCallback onTap,
    required double scale,
    bool isClose = false,
  }) {
    final isHovered = _hoveredIndex == index;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredIndex = index),
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: (isClose ? 36 : 30) * scale,
            height: 28 * scale,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isHovered ? hoverColor : Colors.transparent,
              borderRadius: isClose
                  ? BorderRadius.only(
                      topRight: Radius.circular(5 * scale),
                      bottomRight: Radius.circular(5 * scale),
                    )
                  : (index == 0
                      ? BorderRadius.only(
                          topLeft: Radius.circular(5 * scale),
                          bottomLeft: Radius.circular(5 * scale),
                        )
                      : null),
            ),
            child: Icon(
              icon,
              color: isHovered ? Colors.white : Colors.white70,
              size: (isClose ? 14 : 12) * scale,
            ),
          ),
        ),
      ),
    );
  }
}

class _MacTrafficLights extends StatefulWidget {
  final double scale;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onPopup;

  const _MacTrafficLights({
    required this.scale,
    required this.onClose,
    required this.onMinimize,
    required this.onMaximize,
    required this.onPopup,
  });

  @override
  State<_MacTrafficLights> createState() => _MacTrafficLightsState();
}

class _MacTrafficLightsState extends State<_MacTrafficLights> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Red (Close)
          _buildDot(
            color: const Color(0xFFFC5753),
            icon: Icons.close_rounded,
            tooltip: '닫기',
            onTap: widget.onClose,
            scale: s,
          ),
          SizedBox(width: 8 * s),
          // Yellow (Minimize)
          _buildDot(
            color: const Color(0xFFFDBC40),
            icon: Icons.remove_rounded,
            tooltip: '최소화',
            onTap: widget.onMinimize,
            scale: s,
          ),
          SizedBox(width: 8 * s),
          // Green (Maximize)
          _buildDot(
            color: const Color(0xFF33C748),
            icon: Icons.add_rounded,
            tooltip: '최대화',
            onTap: widget.onMaximize,
            scale: s,
          ),
          SizedBox(width: 8 * s),
          // Blue (Popup)
          _buildDot(
            color: const Color(0xFF0084FF),
            icon: Icons.picture_in_picture_alt_rounded,
            tooltip: '미니 팝업 모드',
            onTap: widget.onPopup,
            scale: s,
          ),
        ],
      ),
    );
  }

  Widget _buildDot({
    required Color color,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required double scale,
  }) {
    return Tooltip(
      message: tooltip,
      textStyle: GoogleFonts.notoSansKr(
        fontSize: 10 * scale,
        color: Colors.black,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4 * scale),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12 * scale,
          height: 12 * scale,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
            child: AnimatedOpacity(
              opacity: _isHovered ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 100),
              child: Icon(icon, color: Colors.black87, size: 7.5 * scale),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  _ToolItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.enabled,
  });
}

/// 교사 본인 교시 + 교실 교시를 합쳐 표현하는 데이터 클래스
class _CombinedPeriod {
  final int period;
  final String teacherSubject; // 교사 본인이 가르치는 과목
  final String teacherClass; // 교사 본인이 가르치는 학급 (예: '3-2반')
  final String classroomSubject; // 담임/설정 학급의 해당 교시 과목
  final String classroomTeacher; // 담임/설정 학급의 해당 교시 선생님
  final bool teacherIsChanged;
  final bool classroomIsChanged;

  const _CombinedPeriod({
    required this.period,
    required this.teacherSubject,
    required this.teacherClass,
    required this.classroomSubject,
    required this.classroomTeacher,
    required this.teacherIsChanged,
    required this.classroomIsChanged,
  });
}

class PeriodTimeStatus {
  final int targetPeriod;
  final bool inProgress;
  final int minutesLeft;

  const PeriodTimeStatus({
    required this.targetPeriod,
    required this.inProgress,
    required this.minutesLeft,
  });
}

class _SyncPairPreview {
  final Directory local;
  final Directory usb;
  final dynamic preview;

  _SyncPairPreview(this.local, this.usb, this.preview);
}

// ─── BST CLOUD GOOGLE DRIVE API DIALOG ───────────────────────────

class _BstCloudDialog extends StatefulWidget {
  final double scaleFactor;
  final void Function(File file) onFileDownloaded;
  final VoidCallback onStatusChanged;

  const _BstCloudDialog({
    required this.scaleFactor,
    required this.onFileDownloaded,
    required this.onStatusChanged,
  });

  @override
  State<_BstCloudDialog> createState() => _BstCloudDialogState();
}

class _BstCloudDialogState extends State<_BstCloudDialog> {
  List<CloudDriveFile> _files = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    if (!CloudDriveService.instance.isLoggedIn) return;
    setState(() => _loading = true);
    final list = await CloudDriveService.instance.fetchDriveFiles();
    if (mounted) {
      setState(() {
        _files = list;
        _loading = false;
      });
    }
  }

  void _showTokenInputDialog() {
    final tokenCtrl = TextEditingController(text: CloudDriveService.instance.accessToken ?? '');
    final emailCtrl = TextEditingController(text: CloudDriveService.instance.userEmail ?? '');
    final nameCtrl = TextEditingController(text: CloudDriveService.instance.userName ?? '');
    final schoolCtrl = TextEditingController(text: CloudDriveService.instance.schoolName ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Google Drive Access Token / 세션 연동',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'https://bst-cloud.web.app 에서 로그인 후 발급받은 Google Access Token 또는 세션을 직접 입력합니다.',
                style: GoogleFonts.notoSansKr(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Google OAuth Access Token',
                  labelStyle: TextStyle(color: Colors.white60),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Google 계정 이메일',
                  labelStyle: TextStyle(color: Colors.white60),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '교사 성명',
                  labelStyle: TextStyle(color: Colors.white60),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              final tok = tokenCtrl.text.trim();
              if (tok.isNotEmpty) {
                await CloudDriveService.instance.setSession(
                  accessToken: tok,
                  email: emailCtrl.text.trim(),
                  name: nameCtrl.text.trim(),
                  school: schoolCtrl.text.trim(),
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  widget.onStatusChanged();
                  _loadFiles();
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006a60)),
            child: Text('연동 저장', style: GoogleFonts.notoSansKr(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final isLoggedIn = CloudDriveService.instance.isLoggedIn;

    return Dialog(
      backgroundColor: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24 * s)),
      child: Container(
        width: 600 * s,
        height: 520 * s,
        padding: EdgeInsets.all(24 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF006a60).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF74f8e5), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Boardest Cloud (Google Drive API)',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isLoggedIn
                            ? '${CloudDriveService.instance.userEmail ?? "구글 로그인 완료"} · Drive API 실시간 연동'
                            : '구글 계정 로그인 및 Drive API 직접 연동',
                        style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 11 * s),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Main View
            Expanded(
              child: !isLoggedIn
                  ? _buildLoggedOutView(s)
                  : _buildLoggedInView(s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedOutView(double s) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: EdgeInsets.all(20 * s),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 56),
          const SizedBox(height: 16),
          Text(
            'Google 계정 및 Drive API가 연동되어 있지 않습니다.',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * s),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF242629),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.3)),
            ),
            child: Text(
              '📌 교사용 앱 로그인 가이드:\nBoardest.web.app 접속 ➔ 학교명 기입 ➔ 구글 로그인 ➔ 교사용 앱 로그인 눌러주세요',
              style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontWeight: FontWeight.bold, fontSize: 11 * s, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                label: Text('🌐 Chrome에서 구글 로그인 (Drive API)', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F5AF0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Chrome 브라우저에서 구글 로그인을 진행해 주세요...', style: GoogleFonts.notoSansKr()),
                      backgroundColor: const Color(0xFF7F5AF0),
                    ),
                  );
                  final ok = await CloudDriveService.instance.loginWithBrowserOAuth();
                  if (ok && mounted) {
                    widget.onStatusChanged();
                    _loadFiles();
                  }
                },
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.vpn_key_rounded, size: 18),
                label: Text('토큰/세션 수동 입력', style: GoogleFonts.notoSansKr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF74f8e5),
                  side: const BorderSide(color: Color(0xFF006a60)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _showTokenInputDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    setState(() => _loading = true);
    int success = 0;
    for (final file in result.files) {
      if (file.path != null) {
        final ok = await CloudDriveService.instance.uploadFileToDrive(File(file.path!));
        if (ok) success++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success > 0
                ? '$success개 파일이 Google Drive에 성공적으로 업로드되었습니다! ☁️'
                : '파일 업로드에 실패했습니다.',
            style: GoogleFonts.notoSansKr(),
          ),
          backgroundColor: success > 0 ? const Color(0xFF2CB67D) : Colors.redAccent,
        ),
      );
      _loadFiles();
    }
  }

  final Map<String, String> _classMappings = {};
  final List<String> _targetClasses = [
    '전체 반 공용',
    '1학년 1반',
    '1학년 2반',
    '2학년 1반',
    '2학년 2반',
    '3학년 1반',
    '3학년 2반',
  ];

  void _showCreateFolderDialog() {
    final folderCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('📁 새 폴더 만들기', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: folderCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: '폴더 이름 입력',
            labelStyle: TextStyle(color: Colors.white70),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2CB67D)),
            onPressed: () async {
              final name = folderCtrl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                setState(() => _loading = true);
                final folderId = await CloudDriveService.instance.createFolderInDrive(name);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(folderId != null ? '📁 [ $name ] 폴더가 생성되었습니다!' : '폴더 생성 실패'),
                      backgroundColor: folderId != null ? const Color(0xFF2CB67D) : Colors.redAccent,
                    ),
                  );
                  _loadFiles();
                }
              }
            },
            child: const Text('생성', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggedInView(double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Action Bar
        Row(
          children: [
            Text('수업 자료 파일 (${_files.length}개)',
                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12 * s)),
            const Spacer(),
            ElevatedButton.icon(
              icon: const Icon(Icons.create_new_folder_rounded, size: 14),
              label: Text('폴더 생성', style: GoogleFonts.notoSansKr(fontSize: 11 * s, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
              ),
              onPressed: _showCreateFolderDialog,
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file_rounded, size: 14),
              label: Text('파일 업로드', style: GoogleFonts.notoSansKr(fontSize: 11 * s, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2CB67D),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
              ),
              onPressed: _uploadFile,
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF74f8e5), size: 18),
              tooltip: 'Drive 새로고침',
              onPressed: _loadFiles,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
              tooltip: '구글 로그아웃',
              onPressed: () async {
                await CloudDriveService.instance.logout();
                widget.onStatusChanged();
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // File List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF2CB67D)))
              : _files.isEmpty
                  ? Center(
                      child: Text('Google Drive에 저장된 수업 파일이 없습니다.',
                          style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 12 * s)),
                    )
                  : ListView.builder(
                      itemCount: _files.length,
                      itemBuilder: (ctx, idx) {
                        final f = _files[idx];
                        final isFolder = f.mimeType == 'application/vnd.google-apps.folder';
                        IconData iconData = isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded;
                        Color iconColor = isFolder ? const Color(0xFFFF8E3C) : const Color(0xFF2EC4B6);

                        if (!isFolder) {
                          if (f.name.endsWith('.pdf')) {
                            iconData = Icons.picture_as_pdf_rounded;
                            iconColor = const Color(0xFFFF8906);
                          } else if (f.name.endsWith('.bb')) {
                            iconData = Icons.auto_stories_rounded;
                            iconColor = const Color(0xFF7F5AF0);
                          } else if (f.name.endsWith('.pptx') || f.name.endsWith('.ppt')) {
                            iconData = Icons.slideshow_rounded;
                            iconColor = const Color(0xFFEF4565);
                          }
                        }

                        final currentMappedClass = _classMappings[f.id] ?? '전체 반 공용';

                        return Card(
                          color: Colors.white.withOpacity(0.04),
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: Icon(iconData, color: iconColor),
                            title: Text(f.name,
                                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12 * s)),
                            subtitle: Row(
                              children: [
                                Text(
                                  isFolder ? '폴더' : '${f.size > 0 ? (f.size / 1024).round() : 0} KB',
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2EC4B6).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: DropdownButton<String>(
                                    dropdownColor: const Color(0xFF242629),
                                    value: currentMappedClass,
                                    isDense: true,
                                    underline: const SizedBox(),
                                    style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontSize: 10, fontWeight: FontWeight.bold),
                                    items: _targetClasses.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _classMappings[f.id] = val);
                                        BstCloudService.instance.saveSyncState('folder_mapping', {
                                          'fileId': f.id,
                                          'fileName': f.name,
                                          'mappedClass': val,
                                          'isFolder': isFolder,
                                          'mappedAt': DateTime.now().toIso8601String(),
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('🔗 [${f.name}] ▶ [$val] 매핑 설정이 적용되었습니다!'),
                                            backgroundColor: const Color(0xFF2EC4B6),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            trailing: isFolder
                                ? null
                                : ElevatedButton.icon(
                                    icon: const Icon(Icons.download_rounded, size: 14),
                                    label: Text('열기', style: GoogleFonts.notoSansKr(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF006a60),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                    onPressed: () async {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Drive API에서 \'${f.name}\' 다운로드 중...'),
                                          backgroundColor: const Color(0xFF006a60),
                                        ),
                                      );
                                      final downloaded = await CloudDriveService.instance.downloadDriveFileToTemp(f);
                                      if (downloaded != null && mounted) {
                                        Navigator.pop(context);
                                        widget.onFileDownloaded(downloaded);
                                      }
                                    },
                                  ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
