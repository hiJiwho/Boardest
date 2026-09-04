import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:bst_core/bst_core.dart' show PanserPluginService;

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
import '../services/totp_service.dart';
import '../services/folder_picker_helper.dart';
import '../services/web_pip_helper.dart';
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
import 'canva_library_view.dart';
import 'tbp/tbp_creator_dialog.dart';
import 'tbp/tbp_viewer_route.dart';
import 'meal_view.dart';
import 'message_view.dart';
import '../services/tray_service.dart';
import '../services/update_service.dart';
import 'weather_view.dart';
import 'saved_ink_view.dart';
import 'video_board_view.dart';
import 'web_hwp_ppt_view.dart';
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
// ── 교내 등록된 전자칠판 중 최근 5분 이내 온라인 기기 조회 ──
Future<List<Map<String, dynamic>>> _fetchOnlineClassrooms([String? schoolCode]) async {
  try {
    final code = (schoolCode != null && schoolCode.trim().isNotEmpty) ? schoolCode.trim() : 'ydm';
    final res = await http.get(
      Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/classrooms?schoolCode=' + code),
    ).timeout(const Duration(seconds: 4));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final list = (data['classrooms'] as List<dynamic>?) ?? [];
      final now = DateTime.now().toUtc();

      final Map<String, Map<String, dynamic>> dedup = {};

      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final lastActiveStr = m['lastActive']?.toString();
        if (lastActiveStr == null || lastActiveStr.isEmpty) continue;

        try {
          final dt = DateTime.parse(lastActiveStr);
          final diffMinutes = now.difference(dt).inMinutes.abs();
          if (diffMinutes <= 5) {
            final key = (m['nickname'] ?? m['docId'] ?? '').toString();
            if (!dedup.containsKey(key) ||
                DateTime.parse(dedup[key]!['lastActive']).isBefore(dt)) {
              dedup[key] = m;
            }
          }
        } catch (_) {}
      }
      return dedup.values.toList();
    }
  } catch (e) {
    debugPrint('[TeacherView] Error fetching online classrooms: ' + e.toString());
  }
  return [];
}

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
  int _miniWidgetTab = 0; // 0: OTP, 1: 교사 시간표, 2: 교실 시간표
  int _bottomAuthSubTab = 0; // 0: 온라인 전자칠판 OTP 주기, 1: 인증 기기 & 로그

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
  int _mobileTabIndex = 0; // 0: 시간표, 1: Cloud, 2: 수업도구, 3: 급식/쪽지, 4: 설정

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
  Color _systemAccentColor = const Color(0xFF00F5D4);

  String _currentOtp = '------';
  int _remainingSeconds = 60;
  bool _autoPtEnabled = false;
  Timer? _otpTimer;

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
      _isDark ? const Color(0xFF00F5D4).withValues(alpha: 0.15) : Colors.black.withOpacity(0.08);
  Color get _textColor => _isDark ? Colors.white : Colors.black87;
  Color get _textColor54 => _isDark ? Colors.white54 : Colors.black54;
  Color get _textColor38 => _isDark ? Colors.white30 : Colors.black38;
  Color get _textColor70 => _isDark ? Colors.white70 : Colors.black54;
  Color get _textColor24 => _isDark ? Colors.white24 : Colors.black26;
  Color get _cardColor =>
      _isDark ? const Color(0xFF16161A) : Colors.black.withOpacity(0.02);
  Color get _accentColor {
    if (_themeColor == 'mint' || _themeColor == 'system') return const Color(0xFF00F5D4);
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
    if (kIsWeb || !Platform.isWindows) return;
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
    _otpTimer?.cancel();
    super.dispose();
  }

  void _startOtpTimer() {
    _updateOtp();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final rem = TotpService.getRemainingSeconds(step: 60);
      if (rem != _remainingSeconds && mounted) {
        setState(() {
          _remainingSeconds = rem;
        });
      }
      if (rem == 60 || rem == 1) {
        _updateOtp();
      }
    });
  }

  void _updateOtp() {
    try {
      final cloud = CloudDriveService.instance;
      final otp = cloud.currentStegano6DigitOtp;
      if (mounted) {
        setState(() {
          _currentOtp = otp.isNotEmpty ? otp : '------';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _currentOtp = '------';
        });
      }
    }
  }

  void _applyWindowFrameStyle(String style) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await const MethodChannel('com.boardest/launch_args').invokeMethod('setWindowFrameStyle', style);
    } catch (e) {
      debugPrint('[TeacherView] setWindowFrameStyle error: $e');
    }
  }

  Future<void> _init() async {
    _startOtpTimer();
    _checkForAppUpdates(silent: true);
    if (!kIsWeb && Platform.isWindows) {
      PanserPluginService.checkAndAutoInstallOnStartup();
    }
    await CloudDriveService.instance.init();
    _updateOtp();
    _refreshDriveFiles();
    CloudDriveService.instance.registerLoginCallback(() async {
      _updateOtp();
      final s = await _storageService.loadConfigAndSync();
      if (mounted) {
        setState(() {
          _settings = s;
        });
        _loadClassroomMappings();
        _refreshDriveFiles();
        if (_settings.schoolId.isNotEmpty || _settings.selectedSchool != null) {
          try {
            final sId = _settings.schoolId.isNotEmpty ? _settings.schoolId : 'ydm';
            final schoolCfg = await ComciganService.fetchSchoolConfig(sId);
            final int resolvedCode = schoolCfg['schoolCode'] as int? ?? 44134;
            final String resolvedName = schoolCfg['schoolName'] as String? ?? '양동중학교';
            _settings = _settings.copyWith(
              selectedSchool: School(id: resolvedCode, code: resolvedCode, name: resolvedName, region: '서울'),
              schoolId: sId,
              isSetupComplete: true,
            );
            await _storageService.saveSettings(_settings);

            final rawData = await _comciganService.fetchTimetableRaw(resolvedCode);
            final result = _comciganService.parseTimetable(rawData);
            if (mounted) {
              setState(() {
                _timetableResult = result;
                _isLoading = false;
              });
            }
          } catch (_) {}
        }
      }
    });
    await _loadClassroomMappings();
    final syncConfigs = await _storageService.getSyncConfigs();
    if (mounted) {
      setState(() {
        _syncConfigs = syncConfigs;
      });
    }
    try {
      _settings = await _storageService.loadConfigAndSync();
      _applyWindowFrameStyle(_settings.windowFrameStyle);
      if (mounted) {
        setState(() {
          _themeMode = _settings.themeMode;
          _themeColor = _settings.themeColor;
        });
      }
      await _loadWindowsAccentColor();

      // Boardest Control에 등록된 control_configs 학교 설정 상시 동기화
      final sId = _settings.schoolId.isNotEmpty ? _settings.schoolId : 'ydm';
      final schoolCfg = await ComciganService.fetchSchoolConfig(sId);
      final int resolvedCode = schoolCfg['schoolCode'] as int? ?? 44134;
      final String resolvedName = schoolCfg['schoolName'] as String? ?? '양동중학교';

      if (_settings.selectedSchool == null || _settings.selectedSchool!.code != resolvedCode || _settings.selectedSchool!.code <= 0) {
        _settings = _settings.copyWith(
          selectedSchool: School(id: resolvedCode, code: resolvedCode, name: resolvedName, region: '서울'),
          schoolId: sId,
          isSetupComplete: true,
        );
        await _storageService.saveSettings(_settings);
      }

      if (_settings.selectedSchool != null) {
        _fetchCalendarEvents();
        final rawData = await _comciganService.fetchTimetableRaw(
          resolvedCode,
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
    if (!kIsWeb && Platform.isWindows) {
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
    if (!kIsWeb && Platform.isWindows) {
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
    if (kIsWeb || !Platform.isWindows) return;
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
    void _openFolderOptionsDialog({int initialTab = 0}) async {}

    void _openBoardBookEditor() {}
  void _showGithubAuthDialog() {}
  void _checkForAppUpdates({bool silent = false}) async {
    if (kIsWeb) return;
    try {
      final updateInfo = await UpdateService.instance.checkForUpdate();
      if (updateInfo != null && updateInfo.hasUpdate && mounted) {
        UpdateService.instance.showUpdateDialog(context, updateInfo);
      }
    } catch (e) {
      debugPrint('[TeacherView] Update check error: $e');
    }
  }
  void _openSettings() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => TeacherSettingsDialog(scaleFactor: _settings.scaleFactor),
    );
    if (updated == true) {
      final s = await _storageService.getSettings();
      if (s != null && mounted) {
        setState(() {
          _settings = s;
        });
        _init();
      }
    }
  }
  void _showCloudRequiredDialog(String type) {}
  void _toggleMiniTimer() {}
  void _pauseMiniTimer() {}
  void _startMiniTimer() {}
  void _resetMiniTimer() {}
  void _adjustMiniTimer(int seconds) {}
  void _enterMiniMode() {}

  void _openFile(String path) {
    if (path.isEmpty) return;
    final lower = path.toLowerCase();

    // 1. PDF 문서: Boardest PDF 판서 뷰어로 열기
    if (lower.endsWith('.pdf')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfBoardView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
          ),
        ),
      );
      return;
    }

    // 2. 판서 파일 (.pen, .bstpen, .iwb): Boardest 전자칠판 판서 뷰어로 열기
    if (lower.endsWith('.pen') || lower.endsWith('.bstpen') || lower.endsWith('.iwb')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BoardestPenView(
            filePath: path,
            scaleFactor: _settings.scaleFactor,
          ),
        ),
      );
      return;
    }

    // 3. 교과서 (.tbp, .bsttbp): Boardest TBP 뷰어로 열기
    if (lower.endsWith('.tbp') || lower.endsWith('.bsttbp')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TbpViewerRoute(
            tbpFilePath: path,
            scaleFactor: _settings.scaleFactor,
          ),
        ),
      );
      return;
    }

    // 4. Canva 디자인 (.canva, .bstcanva, .canva.bst, .canvaboard): Boardest Canva 뷰어로 열기
    if (lower.endsWith('.canva') || lower.endsWith('.bstcanva') || lower.endsWith('.canva.bst') || lower.endsWith('.canvaboard')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CanvaBoardView(
            filePath: path,
            scaleFactor: _settings.scaleFactor,
          ),
        ),
      );
      return;
    }

    // 5. 파워포인트 (.pptx, .ppt): Windows만 직접 오버레이 지원, Web/Android는 다운로드 또는 기본앱 실행
    if (lower.endsWith('.pptx') || lower.endsWith('.ppt')) {
      if (!kIsWeb && Platform.isWindows) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PptOverlayView(
              initialFilePath: path,
              scaleFactor: _settings.scaleFactor,
            ),
          ),
        );
      } else {
        try {
          if (kIsWeb) {
            launchUrl(Uri.parse(path), mode: LaunchMode.externalApplication);
          } else {
            launchUrl(Uri.file(path));
          }
        } catch (e) {
          debugPrint('[TeacherView] open external PPT error: $e');
        }
      }
      return;
    }

    // 6. 한글 문서 (.hwpx, .hwp): Windows만 직접 오버레이 지원, Web/Android는 다운로드 또는 기본앱 실행
    if (lower.endsWith('.hwpx') || lower.endsWith('.hwp')) {
      if (!kIsWeb && Platform.isWindows) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HwpOverlayView(
              initialFilePath: path,
              scaleFactor: _settings.scaleFactor,
            ),
          ),
        );
      } else {
        try {
          if (kIsWeb) {
            launchUrl(Uri.parse(path), mode: LaunchMode.externalApplication);
          } else {
            launchUrl(Uri.file(path));
          }
        } catch (e) {
          debugPrint('[TeacherView] open external HWP error: $e');
        }
      }
      return;
    }

    // 7. 동영상 파일 (.mp4, .mkv, .avi, .mov): Boardest 비디오 뷰어
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi') || lower.endsWith('.mov')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoBoardView(
            initialVidPath: path,
            scaleFactor: _settings.scaleFactor,
          ),
        ),
      );
      return;
    }

    // 8. 미지원 형식: 기본 시스템 앱으로 연결하여 열기
    try {
      if (!kIsWeb && Platform.isWindows) {
        Process.run('explorer.exe', [path]);
      } else {
        launchUrl(Uri.file(path));
      }
    } catch (e) {
      debugPrint('[TeacherView] open unsupported file error: $e');
    }
  }
  void _openUsbFormat() {}
  void _openRandomPicker() {}
  void _openWhiteboard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardestPenView(
          filePath: '',
          scaleFactor: _settings.scaleFactor,
        ),
      ),
    );
  }
  void _openPdfBoard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfBoardView(
          initialFilePath: '',
          scaleFactor: _settings.scaleFactor,
        ),
      ),
    );
  }

  List<dynamic> _getCombinedTodayLessons() { return []; }
  Widget _buildMiniWidget(double s) { return Container(); }
  void _openAuthAndDeviceManager() {
    showDialog(
      context: context,
      builder: (ctx) => _BstCloudDialog(
        scaleFactor: _settings.scaleFactor,
        onFileDownloaded: (file) {
          _openFile(file.path);
        },
        onStatusChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }
  List<String>? _getTeacherTaughtClasses() { return []; }

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
                          ? _buildInlineBoardView(scale)
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final isHomeroom = _settings.isHomeroom;
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 9,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          // 상단: 교사 주간 시간표 / 교실 주간시간표 (flex: 5)
                                          Expanded(
                                            flex: 5,
                                            child: isHomeroom
                                                ? Row(
                                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                                    children: [
                                                      Expanded(
                                                        child: _buildTeacherTimetablePanel(scale),
                                                      ),
                                                      SizedBox(width: 12 * scale),
                                                      Expanded(
                                                        child: _buildClassroomTimetablePanel(scale),
                                                      ),
                                                    ],
                                                  )
                                                : _buildTeacherTimetablePanel(scale),
                                          ),
                                          SizedBox(height: 12 * scale),
                                          // 하단 3단 패널: 좌측(OTP, 인증 관리) / 중간(파일) / 우측(파일 업로드, 폴더 맵핑) (flex: 5)
                                          Expanded(
                                            flex: 5,
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                // 좌측: OTP 및 인증/기기 관리 (flex: 33)
                                                Expanded(
                                                  flex: 33,
                                                  child: _isUsbConnected
                                                      ? _buildUsbPanel(scale)
                                                      : _buildBottomOtpAndAuthPanel(scale),
                                                ),
                                                SizedBox(width: 12 * scale),
                                                // 중간: 파일 탐색기 (bst-save) (flex: 37)
                                                Expanded(
                                                  flex: 37,
                                                  child: _buildDriveFilesPanel(scale),
                                                ),
                                                SizedBox(width: 12 * scale),
                                                // 우측: 파일 업로드 및 폴더 맵핑 (flex: 30)
                                                Expanded(
                                                  flex: 30,
                                                  child: _buildBottomUploadAndMappingPanel(scale),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 12 * scale),
                                    Expanded(
                                      flex: 3,
                                      child: _buildToolsPanel(scale),
                                    ),
                                  ],
                                );
                              },
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

  // ── 모바일 세로 모드 차단 뷰 및 리다이렉션 ────────────────
  bool _isMobilePortrait(BuildContext context) {
    if (!kIsWeb) return false;
    final size = MediaQuery.of(context).size;
    if (size.height <= size.width) return false;
    final aspect = size.height / (size.width > 0 ? size.width : 1);
    if (aspect < 1.2) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  int _mobileRedirectSeconds = 10;
  Timer? _mobileRedirectTimer;

  void _startMobileRedirectCountdown() {
    if (_mobileRedirectTimer != null) return;
    _mobileRedirectSeconds = 10;
    _mobileRedirectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_mobileRedirectSeconds > 1) {
          _mobileRedirectSeconds--;
        } else {
          timer.cancel();
          _redirectToLite();
        }
      });
    });
  }

  void _redirectToLite() {
    launchUrl(
      Uri.parse('https://boardest-teacher-lite.web.app'),
      webOnlyWindowName: '_self',
    );
  }

  Widget _buildMobileBlockedView(double s) {
    _startMobileRedirectCountdown();
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7F5AF0).withOpacity(0.12),
                  blurRadius: 30,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F5AF0).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.devices_other_rounded,
                    color: Color(0xFF7F5AF0),
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '모바일 접속 안내',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '모바일에서는 Boardest Teacher가 사용 불가능합니다.\n태블릿 또는 컴퓨터에서 접속하시거나 간단한 기능은 Boardest Teacher Lite를 이용해주세요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    color: const Color(0xFF94A1B2),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242629),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, color: Color(0xFF00F5D4), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '$_mobileRedirectSeconds초 뒤 Lite로 자동 이동합니다',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF00F5D4),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _redirectToLite,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: Text(
                    '🚀 Boardest Teacher Lite 바로가기',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F5AF0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 교사 ID 매칭 헬퍼 (교사 실명 완전 배제, 오직 컴시간 교사 ID만 매칭) ──
  bool _isTeacherMatch(String lessonTeacher) {
    final lt = lessonTeacher.replaceAll('*', '').replaceAll('선생님', '').trim().toUpperCase();
    if (lt.isEmpty) return false;
    final targetId = (_settings.selectedTeacherId.isNotEmpty 
        ? _settings.selectedTeacherId 
        : _settings.selectedTeacher).replaceAll('*', '').replaceAll('선생님', '').trim().toUpperCase();
    if (targetId.isEmpty) return false;

    // 1. 완전 일치 (예: '임채' == '임채')
    if (lt == targetId) return true;

    // 2. 부분 일치 (예: '임채' 포함 여부)
    if (lt.contains(targetId) || targetId.contains(lt)) return true;

    // 3. 2글자 이상 접두사 일치
    if (lt.length >= 2 && targetId.length >= 2 && lt.substring(0, 2) == targetId.substring(0, 2)) {
      return true;
    }
    return false;
  }

  // ── 좌측 상단: 선생님 시간표 패널 ─────────────────────────
  Widget _buildTeacherTimetablePanel(double s) {
    final weekday = _now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    final displayDay = isWeekend ? 1 : weekday;
    final teacherDisplayName = _settings.selectedTeacherName.isNotEmpty
        ? _settings.selectedTeacherName
        : (_settings.selectedTeacher.isNotEmpty
            ? _settings.selectedTeacher
            : '교사');

    final teacherLessons = (_timetableResult?.lessons ?? [])
        .where((l) => l.weekday == displayDay && _isTeacherMatch(l.teacher))
        .toList()
      ..sort((a, b) => a.classTime.compareTo(b.classTime));

    const totalPeriods = 7;

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
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(4 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2EC4B6).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_rounded,
                          color: const Color(0xFF2EC4B6),
                          size: 14 * s,
                        ),
                      ),
                      SizedBox(width: 6 * s),
                      Expanded(
                        child: Text(
                          '$teacherDisplayName 선생님 (${isWeekend ? '월' : _getKoreanWeekday(weekday)})',
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
                          color: Color(0xFF2EC4B6),
                        ),
                        label: Text(
                          '주간',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10 * s,
                            color: Color(0xFF2EC4B6),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * s,
                            vertical: 4 * s,
                          ),
                          backgroundColor: const Color(0xFF2EC4B6).withOpacity(0.08),
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
                  if (_errorMessage != null)
                    Expanded(
                      child: Center(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFFEF4565),
                            fontSize: 11 * s,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: totalPeriods,
                        itemBuilder: (_, i) {
                          final period = i + 1;
                          final lesson = teacherLessons.firstWhere(
                            (l) => l.classTime == period,
                            orElse: () => Lesson(
                              grade: 0,
                              classNum: 0,
                              weekday: displayDay,
                              classTime: period,
                              teacher: '',
                              subject: '',
                              classroom: '',
                              isChanged: false,
                            ),
                          );
                          final hasClass = lesson.subject.isNotEmpty;
                          final isCurrent = _currentPeriod == period;

                          return Container(
                            margin: EdgeInsets.only(bottom: 4 * s),
                            padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF2EC4B6).withOpacity(0.12)
                                  : _cardColor,
                              borderRadius: BorderRadius.circular(10 * s),
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFF2EC4B6).withOpacity(0.5)
                                    : _borderColor,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20 * s,
                                  height: 20 * s,
                                  decoration: BoxDecoration(
                                    color: isCurrent ? const Color(0xFF2EC4B6) : _borderColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$period',
                                      style: GoogleFonts.outfit(
                                        color: isCurrent ? Colors.black : _textColor54,
                                        fontSize: 10 * s,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8 * s),
                                Expanded(
                                  child: Text(
                                    hasClass ? lesson.subject.replaceAll('*', '') : '— (공강)',
                                    style: GoogleFonts.notoSansKr(
                                      color: hasClass ? _textColor : _textColor24,
                                      fontSize: 11 * s,
                                      fontWeight: hasClass ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (hasClass)
                                  Text(
                                    '${lesson.grade}-${lesson.classNum}반',
                                    style: GoogleFonts.notoSansKr(
                                      color: const Color(0xFF2EC4B6),
                                      fontSize: 10 * s,
                                      fontWeight: FontWeight.w600,
                                    ),
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

  // ── Drive Files State ────────────────────────────────
  List<Map<String, dynamic>> _driveFiles = [];
  bool _isLoadingDriveFiles = false;
  String? _currentDriveFolderId;
  String _currentDriveFolderName = 'bst-save';
  final List<Map<String, String>> _driveFolderNavStack = [];
  String _cloudCategoryFilter = '전체';
  String _cloudSearchQuery = '';

  List<Map<String, dynamic>> get _filteredDriveFiles {
    return _driveFiles.where((f) {
      final name = (f['name'] ?? '').toString().toLowerCase();
      if (_cloudSearchQuery.isNotEmpty && !name.contains(_cloudSearchQuery.toLowerCase())) {
        return false;
      }
      if (_cloudCategoryFilter == 'PDF' && !name.endsWith('.pdf')) return false;
      if (_cloudCategoryFilter == 'Canva' && !name.endsWith('.canva.bst') && !name.endsWith('.canva')) return false;
      if (_cloudCategoryFilter == 'PPT' && !name.endsWith('.ppt') && !name.endsWith('.pptx')) return false;
      if (_cloudCategoryFilter == '판서' && !name.endsWith('.pen') && !name.endsWith('.iwb')) return false;
      return true;
    }).toList();
  }

  Future<void> _refreshDriveFiles({String? folderId, String? folderName}) async {
    if (!CloudDriveService.instance.isLoggedIn) return;
    if (mounted) {
      setState(() {
        _isLoadingDriveFiles = true;
        if (folderId != null) _currentDriveFolderId = folderId;
        if (folderName != null) _currentDriveFolderName = folderName;
      });
    }
    try {
      final mergedList = await CloudDriveService.instance.fetchMergedMaterials(targetFolderId: _currentDriveFolderId);
      final list = mergedList.map((item) {
        final f = item['file'] as CloudDriveFile;
        return {
          'id': f.id,
          'name': f.name,
          'mimeType': f.mimeType,
          'size': f.size,
          'webViewLink': f.webViewLink,
          'webContentLink': f.webContentLink,
          'source': item['source'],
          'sourceLabel': item['sourceLabel'],
          'folderId': item['folderId'],
        };
      }).toList();
      if (mounted) {
        setState(() {
          _driveFiles = list;
          _isLoadingDriveFiles = false;
        });
      }
      return;
    } catch (_) {}
    if (mounted) setState(() => _isLoadingDriveFiles = false);
  }

  /// Google Drive로 로컬 파일 즉시 업로드
  Future<void> _uploadLocalFileToDrive() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        if (mounted) setState(() => _isLoadingDriveFiles = true);
        int successCount = 0;
        for (final f in result.files) {
          if (f.bytes != null) {
            final ok = await CloudDriveService.instance.uploadBytesToDrive(f.bytes!, f.name);
            if (ok) successCount++;
          } else if (f.path != null) {
            final ok = await CloudDriveService.instance.uploadFileToDrive(File(f.path!));
            if (ok) successCount++;
          }
        }
        await _refreshDriveFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('총 $successCount개 파일이 Google Drive에 업로드되었습니다! 🎉')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 실패: $e')),
        );
      }
    }
  }

  /// Canva 디자인 등록 다이얼로그
  void _showRegisterCanvaDialog() {
    final titleController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2028),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.palette_rounded, color: Color(0xFF00C4CC), size: 22),
            const SizedBox(width: 8),
            Text('Canva 디자인 등록', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('교안으로 사용할 Canva 디자인의 공유/보기 URL을 입력하세요.\n(디자인 ID를 자동 추출하여 .canva.bst 파일로 클라우드에 보관합니다.)',
                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 14),
            TextField(
              controller: titleController,
              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: '수업/디자인 제목',
                labelStyle: GoogleFonts.notoSansKr(color: Colors.white60),
                hintText: '예: 2단원 1차시 과학 탐구',
                hintStyle: GoogleFonts.notoSansKr(color: Colors.white24),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlController,
              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Canva URL 전체 주소',
                labelStyle: GoogleFonts.notoSansKr(color: Colors.white60),
                hintText: 'https://www.canva.com/design/DAG...',
                hintStyle: GoogleFonts.notoSansKr(color: Colors.white24),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C4CC),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final title = titleController.text.trim();
              final url = urlController.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(ctx);
              final ok = await CloudDriveService.instance.registerCanvaDesign(title: title, canvaUrl: url);
              if (mounted) {
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🎨 Canva 디자인이 클라우드에 성공적으로 등록되었습니다!')),
                  );
                  _refreshDriveFiles();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('⚠️ Canva URL 형식이 올바르지 않거나 등록에 실패했습니다.')),
                  );
                }
              }
            },
            child: Text('등록하기', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Google Drive 파일 이름 변경 다이얼로그
  Future<void> _renameDriveFile(Map<String, dynamic> file) async {
    final fileId = file['id']?.toString() ?? '';
    final oldName = file['name']?.toString() ?? '';
    if (fileId.isEmpty) return;

    final lowerOld = oldName.toLowerCase();
    final isPen = lowerOld.endsWith('.pen') || lowerOld.endsWith('.iwb');
    
    // 확장자 뺀 기본 이름을 기본 텍스트필드 값으로 제공
    String defaultInput = oldName;
    if (lowerOld.endsWith('.pen')) {
      defaultInput = oldName.substring(0, oldName.length - 4);
    } else if (lowerOld.endsWith('.iwb')) {
      defaultInput = oldName.substring(0, oldName.length - 4);
    }

    final controller = TextEditingController(text: defaultInput);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isPen ? Icons.draw_rounded : Icons.edit_note_rounded, color: isPen ? const Color(0xFF00F5D4) : const Color(0xFF4285F4), size: 20),
            const SizedBox(width: 8),
            Text(isPen ? '자유판서 이름 변경' : 'Drive 파일 이름 변경', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPen)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '기존: ${CloudDriveService.formatBoardDisplayName(oldName)}',
                  style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 12),
                ),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.notoSansKr(color: Colors.white),
              decoration: InputDecoration(
                hintText: isPen ? '새 판서명을 입력하세요 (예: 2단원 수학 정리)' : '새 파일명을 입력하세요',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isPen ? const Color(0xFF00F5D4) : const Color(0xFF4285F4),
              foregroundColor: isPen ? Colors.black : Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('변경', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != defaultInput && newName != oldName) {
      String finalTargetName = newName.trim();
      if (lowerOld.endsWith('.pen') && !finalTargetName.toLowerCase().endsWith('.pen')) {
        finalTargetName = '$finalTargetName.pen';
      } else if (lowerOld.endsWith('.iwb') && !finalTargetName.toLowerCase().endsWith('.iwb')) {
        finalTargetName = '$finalTargetName.iwb';
      }

      final ok = await CloudDriveService.instance.renameDriveFile(fileId, finalTargetName);
      if (ok) {
        await _refreshDriveFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isPen ? '자유판서 이름이 "$finalTargetName"(으)로 변경되었습니다.' : '파일명이 변경되었습니다.'),
              backgroundColor: const Color(0xFF00F5D4),
            ),
          );
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('파일명 변경 실패')));
      }
    }
  }

  /// Google Drive 파일 삭제 다이얼로그
  Future<void> _deleteDriveFile(Map<String, dynamic> file) async {
    final fileId = file['id']?.toString() ?? '';
    final name = file['name']?.toString() ?? '';
    if (fileId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text('Drive 파일 삭제', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Google Drive에서 "$name" 파일을 삭제하시겠습니까?', style: GoogleFonts.notoSansKr(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await CloudDriveService.instance.deleteDriveFile(fileId);
      if (ok) {
        await _refreshDriveFiles();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('파일이 삭제되었습니다.')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('파일 삭제 실패')));
      }
    }
  }

  /// Drive 파일 열기 / 다운로드
  Future<void> _openDriveFile(Map<String, dynamic> file) async {
    final fileId = file['id']?.toString() ?? '';
    final name = file['name']?.toString() ?? 'downloaded_file';
    if (fileId.isEmpty) return;

    try {
      final lower = name.toLowerCase();

      // Boardest 지원 포맷 확인:
      // PDF, 판서(.pen, .bstpen, .iwb), 교과서(.tbp, .bsttbp), Canva(.canva, .canva.bst)
      final isBoardestNativeFormat = lower.endsWith('.pdf') ||
          lower.endsWith('.pen') ||
          lower.endsWith('.bstpen') ||
          lower.endsWith('.iwb') ||
          lower.endsWith('.tbp') ||
          lower.endsWith('.bsttbp') ||
          lower.endsWith('.canva') ||
          lower.endsWith('.canva.bst');

      final isWindowsOffice = (lower.endsWith('.pptx') || lower.endsWith('.ppt') || lower.endsWith('.hwpx') || lower.endsWith('.hwp')) &&
          (!kIsWeb && Platform.isWindows);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name 준비 중...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      final driveFile = CloudDriveFile(
        id: fileId,
        name: name,
        mimeType: file['mimeType']?.toString() ?? '',
        modifiedTime: DateTime.tryParse(file['modifiedTime']?.toString() ?? '') ?? DateTime.now(),
        size: int.tryParse(file['size']?.toString() ?? '0') ?? 0,
        webViewLink: file['webViewLink']?.toString(),
        webContentLink: file['webContentLink']?.toString(),
      );

      final localF = await CloudDriveService.instance.downloadDriveFileToTemp(driveFile);

      if (isBoardestNativeFormat || isWindowsOffice) {
        if (localF != null && localF.existsSync()) {
          _openFile(localF.path);
        }
      } else {
        // 미지원 외부 파일 (안드로이드 / Web 등): 다운로드 또는 기본 앱 실행
        if (kIsWeb) {
          final url = driveFile.webContentLink ?? 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else if (localF != null && localF.existsSync()) {
          launchUrl(Uri.file(localF.path));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('파일 열기 실패: $e')));
    }
  }

  /// 로컬 폴더 ↔ Google Drive 폴더 맵핑 및 동기화 다이얼로그
  /// 로컬 폴더 ↔ Google Drive 폴더 맵핑 및 동기화 다이얼로그 (Web 폴더 API 및 Native EXE 지원)
  Future<void> _openDriveFolderSyncDialog() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('웹 폴더 선택기를 실행합니다. 업로드할 폴더를 선택해주세요...')),
        );
      }
      final webFiles = await pickFolderFilesWeb();
      if (webFiles.isEmpty) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${webFiles.length}개 파일 업로드를 진행 중입니다...')),
        );
      }
      final count = await CloudDriveService.instance.uploadWebFolderFilesToSync(webFiles);
      await _refreshDriveFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('동기화 완료: $count개 파일이 Cloud Drive (bst-sync)에 성공적으로 업로드되었습니다! 🚀')),
        );
      }
      return;
    }

    // Windows EXE / Desktop Native
    String? selectedDir = await FilePicker.getDirectoryPath();
    if (selectedDir == null || selectedDir.isEmpty) return;

    final dirName = p.basename(selectedDir);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Row(
          children: [
            const Icon(Icons.sync_alt_rounded, color: Color(0xFF00F5D4)),
            const SizedBox(width: 8),
            Text('폴더 동기화 / 맵핑', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('선택한 로컬 폴더("$dirName")를 Cloud Drive의 bst-sync 폴더와 맵핑하여 지금 동기화하시겠습니까?', style: GoogleFonts.notoSansKr(color: Colors.white70)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(selectedDir!, style: GoogleFonts.firaCode(color: const Color(0xFF00F5D4), fontSize: 11)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('동기화 시작', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('동기화를 진행 중입니다...')));
      }
      final count = await CloudDriveService.instance.syncLocalFolderToDrive(selectedDir);
      await _refreshDriveFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('폴더 동기화 완료: $count개 파일이 성공적으로 동기화되었습니다! 🚀')),
        );
      }
    }
  }

  // ── 우측 상단: 학급 시간표 패널 ─────────────────────────
  Widget _buildClassroomTimetablePanel(double s) {
    final weekday = _now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    final displayDay = isWeekend ? 1 : weekday;

    final classLessons = (_timetableResult?.lessons ?? [])
        .where((l) =>
            l.weekday == displayDay &&
            l.grade == _settings.selectedGrade &&
            l.classNum == _settings.selectedClass)
        .toList()
      ..sort((a, b) => a.classTime.compareTo(b.classTime));

    const totalPeriods = 7;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
                      Container(
                        padding: EdgeInsets.all(4 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7F5AF0).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          color: const Color(0xFF7F5AF0),
                          size: 14 * s,
                        ),
                      ),
                      SizedBox(width: 6 * s),
                      Expanded(
                        child: Text(
                          '${_settings.selectedGrade}학년 ${_settings.selectedClass}반 (${isWeekend ? '월' : _getKoreanWeekday(weekday)})',
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
                        onPressed: () => _openWeeklyTimetablePopup(true),
                        icon: const Icon(
                          Icons.grid_on_rounded,
                          size: 12,
                          color: Color(0xFF7F5AF0),
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
                          backgroundColor: const Color(0xFF7F5AF0).withOpacity(0.08),
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
                  Expanded(
                    child: ListView.builder(
                      itemCount: totalPeriods,
                      itemBuilder: (_, i) {
                        final period = i + 1;
                        final lesson = classLessons.firstWhere(
                          (l) => l.classTime == period,
                          orElse: () => Lesson(
                            grade: _settings.selectedGrade,
                            classNum: _settings.selectedClass,
                            weekday: displayDay,
                            classTime: period,
                            teacher: '',
                            subject: '',
                            classroom: '',
                            isChanged: false,
                          ),
                        );
                        final hasClass = lesson.subject.isNotEmpty;
                        final isCurrent = _currentPeriod == period;

                        return Container(
                          margin: EdgeInsets.only(bottom: 4 * s),
                          padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? const Color(0xFF7F5AF0).withOpacity(0.12)
                                : _cardColor,
                            borderRadius: BorderRadius.circular(10 * s),
                            border: Border.all(
                              color: isCurrent
                                  ? const Color(0xFF7F5AF0).withOpacity(0.5)
                                  : _borderColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20 * s,
                                height: 20 * s,
                                decoration: BoxDecoration(
                                  color: isCurrent ? const Color(0xFF7F5AF0) : _borderColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$period',
                                    style: GoogleFonts.outfit(
                                      color: isCurrent ? Colors.white : _textColor54,
                                      fontSize: 10 * s,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 8 * s),
                              Expanded(
                                child: Text(
                                  hasClass ? lesson.subject.replaceAll('*', '') : '—',
                                  style: GoogleFonts.notoSansKr(
                                    color: hasClass ? _textColor : _textColor24,
                                    fontSize: 11 * s,
                                    fontWeight: hasClass ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (hasClass)
                                Text(
                                  lesson.teacher.replaceAll('*', ''),
                                  style: GoogleFonts.notoSansKr(
                                    color: const Color(0xFF7F5AF0),
                                    fontSize: 10 * s,
                                    fontWeight: FontWeight.w600,
                                  ),
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

  // ── 좌측 하단 (Web): 1분 OTP 패널 ─────────────────────────
  Widget _buildOtpPanel(double s) {
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
                    Container(
                      padding: EdgeInsets.all(4 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7F5AF0).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.vpn_key_rounded,
                        color: const Color(0xFF7F5AF0),
                        size: 14 * s,
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    Text(
                      '전자칠판 6자리 동적 보안 접속 코드',
                      style: GoogleFonts.notoSansKr(
                        color: _textColor,
                        fontSize: 12 * s,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    final full6 = CloudDriveService.instance.currentStegano6DigitOtp;
                    Clipboard.setData(ClipboardData(text: full6));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('📋 6자리 접속 코드 [$full6] 가 복사되었습니다.'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: const Color(0xFF2EC4B6),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Column(
                      children: [
                        Builder(
                          builder: (context) {
                            final full6 = CloudDriveService.instance.currentStegano6DigitOtp;
                            final display6 = '${full6.substring(0, 3)} ${full6.substring(3, 6)}';
                            return Text(
                              display6,
                              style: GoogleFonts.sourceCodePro(
                                color: const Color(0xFF00F5D4),
                                fontSize: 24 * s,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 6 * s,
                              ),
                            );
                          },
                        ),
                        SizedBox(height: 4 * s),
                        Text(
                          'Cloud ID: ${CloudDriveService.instance.cloudId} (자동로그인 칠판용)',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFFFFD166),
                            fontSize: 10 * s,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8 * s),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _remainingSeconds / 60.0,
                            minHeight: 4 * s,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(Color(0xFF00F5D4)),
                          ),
                        ),
                        SizedBox(height: 6 * s),
                        Text(
                          '$_remainingSeconds초 뒤 갱신 (클릭 시 6자리 복사)',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFFFF8906),
                            fontSize: 10 * s,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Auto-PT 자동 실행',
                      style: GoogleFonts.notoSansKr(
                        color: _textColor70,
                        fontSize: 10 * s,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Switch(
                      value: _autoPtEnabled,
                      activeColor: const Color(0xFF2EC4B6),
                      onChanged: (val) async {
                        setState(() => _autoPtEnabled = val);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('bst_auto_pt', val);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 우측 하단 (Web/EXE): Google Drive 속 파일 목록 패널 (Boardest Cloud Explorer 스타일) ────
  Widget _buildDriveFilesPanel(double s) {
    final isLogged = CloudDriveService.instance.isLoggedIn;
    final displayFiles = _filteredDriveFiles;

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
            padding: EdgeInsets.all(12 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 헤더: 경로 표시 & 도구 버튼
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(4 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_done_rounded,
                        color: const Color(0xFF00F5D4),
                        size: 14 * s,
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    if (_driveFolderNavStack.isNotEmpty) ...[
                      InkWell(
                        onTap: () {
                          _driveFolderNavStack.removeLast();
                          final parent = _driveFolderNavStack.isNotEmpty ? _driveFolderNavStack.last : null;
                          _refreshDriveFiles(
                            folderId: parent?['id'],
                            folderName: parent?['name'] ?? 'bst-save',
                          );
                        },
                        borderRadius: BorderRadius.circular(4 * s),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 2 * s),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back_rounded, size: 14 * s, color: const Color(0xFF00F5D4)),
                              SizedBox(width: 2 * s),
                              Text('상위', style: TextStyle(color: const Color(0xFF00F5D4), fontSize: 9 * s, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 4 * s),
                    ],
                    Expanded(
                      child: Text(
                        '내 드라이브 > $_currentDriveFolderName',
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFF00F5D4),
                          fontSize: 11 * s,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.security_rounded, size: 16 * s, color: const Color(0xFF00F5D4)),
                      tooltip: '인증 & 기기 관리 (8자리 자동 OTP)',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _openAuthAndDeviceManager,
                    ),
                    SizedBox(width: 6 * s),
                    IconButton(
                      icon: Icon(Icons.create_new_folder_rounded, size: 16 * s, color: const Color(0xFFFFB703)),
                      tooltip: '새 폴더 만들기',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _showCreateFolderDialog,
                    ),
                    SizedBox(width: 6 * s),
                    IconButton(
                      icon: Icon(Icons.upload_file_rounded, size: 16 * s, color: const Color(0xFF4285F4)),
                      tooltip: '파일 올리기',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _uploadLocalFileToDrive,
                    ),
                    SizedBox(width: 6 * s),
                    IconButton(
                      icon: Icon(Icons.palette_rounded, size: 16 * s, color: const Color(0xFF00C4CC)),
                      tooltip: 'Canva 디자인 등록',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _showRegisterCanvaDialog,
                    ),
                    SizedBox(width: 6 * s),
                    IconButton(
                      icon: Icon(Icons.sync_alt_rounded, size: 16 * s, color: const Color(0xFF2EC4B6)),
                      tooltip: '폴더 동기화 / 맵핑',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _openDriveFolderSyncDialog,
                    ),
                    SizedBox(width: 6 * s),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, size: 16 * s, color: _textColor54),
                      tooltip: '새로고침',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _refreshDriveFiles,
                    ),
                  ],
                ),
                SizedBox(height: 6 * s),
                // 2. 검색창 & 카테고리 필터 칩
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 26 * s,
                        child: TextField(
                          style: TextStyle(color: Colors.white, fontSize: 10 * s),
                          onChanged: (v) => setState(() => _cloudSearchQuery = v),
                          decoration: InputDecoration(
                            hintText: '자료 검색...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 10 * s),
                            prefixIcon: Icon(Icons.search, size: 13 * s, color: Colors.white54),
                            prefixIconConstraints: BoxConstraints(minWidth: 24 * s),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4 * s),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6 * s),
                              borderSide: BorderSide(color: Colors.white12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ['전체', 'PDF', 'Canva', 'PPT', '판서'].map((cat) {
                            final isSel = _cloudCategoryFilter == cat;
                            return Padding(
                              padding: EdgeInsets.only(right: 4 * s),
                              child: InkWell(
                                onTap: () => setState(() => _cloudCategoryFilter = cat),
                                borderRadius: BorderRadius.circular(12 * s),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFF00F5D4) : Colors.white10,
                                    borderRadius: BorderRadius.circular(12 * s),
                                  ),
                                  child: Text(
                                    cat,
                                    style: GoogleFonts.notoSansKr(
                                      color: isSel ? Colors.black : Colors.white70,
                                      fontSize: 9 * s,
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8 * s),
                // 3. 파일 목록 (카드형 탐색기 뷰)
                Expanded(
                  child: !isLogged
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_off_rounded, size: 28 * s, color: _textColor24),
                              SizedBox(height: 6 * s),
                              Text(
                                '클라우드 드라이브가 연동되지 않았습니다.',
                                style: GoogleFonts.notoSansKr(color: _textColor54, fontSize: 10 * s),
                              ),
                            ],
                          ),
                        )
                      : _isLoadingDriveFiles
                          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                          : displayFiles.isEmpty
                              ? Center(
                                  child: Text(
                                    _cloudSearchQuery.isNotEmpty || _cloudCategoryFilter != '전체'
                                        ? '조건에 맞는 자료가 없습니다.'
                                        : '드라이브에 저장된 파일이 없습니다.',
                                    style: GoogleFonts.notoSansKr(color: _textColor54, fontSize: 10 * s),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: displayFiles.length,
                                  itemBuilder: (_, i) {
                                    final file = displayFiles[i];
                                    final name = file['name']?.toString() ?? '자료';
                                    final lower = name.toLowerCase();
                                    final isFolder = file['mimeType'] == 'application/vnd.google-apps.folder';

                                    Color iconColor = const Color(0xFF4285F4);
                                    IconData iconData = Icons.insert_drive_file_outlined;
                                    String tag = 'FILE';

                                    if (isFolder) {
                                      iconColor = const Color(0xFFFFB703);
                                      iconData = Icons.folder_rounded;
                                      tag = '폴더';
                                    } else if (lower.endsWith('.canva.bst') || lower.endsWith('.canva')) {
                                      iconColor = const Color(0xFF00C4CC);
                                      iconData = Icons.palette_rounded;
                                      tag = 'CANVA';
                                    } else if (lower.endsWith('.pdf')) {
                                      iconColor = const Color(0xFFEF4565);
                                      iconData = Icons.picture_as_pdf_rounded;
                                      tag = 'PDF';
                                    } else if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
                                      iconColor = const Color(0xFFFF8906);
                                      iconData = Icons.slideshow_rounded;
                                      tag = 'PPT';
                                    } else if (lower.endsWith('.pen') || lower.endsWith('.iwb')) {
                                      iconColor = const Color(0xFF00F5D4);
                                      iconData = Icons.draw_rounded;
                                      tag = '판서';
                                    }

                                    return InkWell(
                                      onTap: () {
                                        if (isFolder) {
                                          _driveFolderNavStack.add({'id': file['id']?.toString() ?? '', 'name': name});
                                          _refreshDriveFiles(folderId: file['id']?.toString(), folderName: name);
                                        } else {
                                          _openDriveFile(file);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(8 * s),
                                      child: Container(
                                        margin: EdgeInsets.only(bottom: 4 * s),
                                        padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 5 * s),
                                        decoration: BoxDecoration(
                                          color: _cardColor,
                                          borderRadius: BorderRadius.circular(8 * s),
                                          border: Border.all(color: _borderColor),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.all(4 * s),
                                              decoration: BoxDecoration(
                                                color: iconColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6 * s),
                                              ),
                                              child: Icon(iconData, size: 14 * s, color: iconColor),
                                            ),
                                            SizedBox(width: 6 * s),
                                            Container(
                                              padding: EdgeInsets.symmetric(horizontal: 3.5 * s, vertical: 1 * s),
                                              decoration: BoxDecoration(
                                                color: iconColor.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(3 * s),
                                              ),
                                              child: Text(
                                                tag,
                                                style: TextStyle(
                                                  color: iconColor,
                                                  fontSize: 7.5 * s,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 5 * s),
                                            Expanded(
                                              child: Text(
                                                (lower.endsWith('.pen') || lower.endsWith('.iwb'))
                                                    ? CloudDriveService.formatBoardDisplayName(name)
                                                    : name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.notoSansKr(
                                                  color: _textColor,
                                                  fontSize: 10.5 * s,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            if (lower.endsWith('.pen') || lower.endsWith('.iwb')) ...[
                                              IconButton(
                                                icon: Icon(Icons.drive_file_rename_outline_rounded, size: 14 * s, color: const Color(0xFF00F5D4)),
                                                tooltip: '자유판서 이름 변경',
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: () => _renameDriveFile(file),
                                              ),
                                              SizedBox(width: 4 * s),
                                            ],
                                            PopupMenuButton<String>(
                                              icon: Icon(Icons.more_vert_rounded, size: 14 * s, color: _textColor54),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              color: const Color(0xFF16161A),
                                              onSelected: (val) {
                                                if (val == 'open') {
                                                  _openDriveFile(file);
                                                } else if (val == 'rename') {
                                                  _renameDriveFile(file);
                                                } else if (val == 'delete') {
                                                  _deleteDriveFile(file);
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                PopupMenuItem(
                                                  value: 'open',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.file_download_outlined, size: 14, color: Colors.white70),
                                                      const SizedBox(width: 6),
                                                      Text('열기 / 다운로드', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 11)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'rename',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.edit_outlined, size: 14, color: Colors.white70),
                                                      const SizedBox(width: 6),
                                                      Text('이름 변경', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 11)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.pinkAccent),
                                                      const SizedBox(width: 6),
                                                      Text('삭제', style: GoogleFonts.notoSansKr(color: Colors.pinkAccent, fontSize: 11)),
                                                    ],
                                                  ),
                                                ),
                                              ],
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
        ? '${_settings.selectedGrade}학년 ${_settings.selectedClass}반 주간'
        : '교사 개인 주간';
    final accentColor = isHomeroom ? const Color(0xFF7F5AF0) : const Color(0xFF00F5D4);

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
        : (_timetableResult?.lessons.where((l) => _isTeacherMatch(l.teacher)).toList() ??
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
        border: Border.all(color: inline ? _borderColor : accentColor.withOpacity(0.4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 * s),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: inline ? 10.0 : 0.0,
            sigmaY: inline ? 10.0 : 0.0,
          ),
          child: Padding(
            padding: EdgeInsets.all(10 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(4 * s),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isHomeroom ? Icons.school_rounded : Icons.person_rounded,
                        color: accentColor,
                        size: 13 * s,
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.notoSansKr(
                          color: _textColor,
                          fontSize: 11.5 * s,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (inline) ...[
                      TextButton.icon(
                        onPressed: () => _openWeeklyTimetablePopup(isHomeroom),
                        icon: Icon(Icons.open_in_full_rounded, size: 10 * s, color: accentColor),
                        label: Text('확대', style: TextStyle(color: accentColor, fontSize: 9.5 * s)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                          backgroundColor: accentColor.withOpacity(0.08),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6 * s)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
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
                SizedBox(height: 8 * s),

                // 시간표 격자 테이블
                Expanded(
                  child: SingleChildScrollView(
                    child: Table(
                      border: TableBorder.all(
                        color: _borderColor,
                        width: 0.8,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      columnWidths: const {
                        0: FixedColumnWidth(22), // 교시 열
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
                                height: 24,
                                child: Center(child: Text('')),
                              ),
                            ),
                            ...weekdays.asMap().entries.map((entry) {
                              final dayIdx = entry.key;
                              final day = entry.value;
                              final isToday = (todayWeekday == dayIdx + 1);
                              return TableCell(
                                child: Container(
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isToday ? accentColor.withOpacity(0.18) : Colors.transparent,
                                    border: isToday
                                        ? Border.all(
                                            color: accentColor,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      day,
                                      style: GoogleFonts.notoSansKr(
                                        color: isToday
                                            ? accentColor
                                            : _textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10.5 * s,
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
                                verticalAlignment: TableCellVerticalAlignment.middle,
                                child: Container(
                                  height: 44 * s,
                                  color: _isDark
                                      ? Colors.white.withOpacity(0.02)
                                      : Colors.black.withOpacity(0.015),
                                  child: Center(
                                    child: Text(
                                      '$period',
                                      style: GoogleFonts.outfit(
                                        color: accentColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11 * s,
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
                                final topLabel = isHomeroom
                                    ? lesson.subject.replaceAll('*', '')
                                    : (lesson.grade > 0 ? '${lesson.grade}-${lesson.classNum}' : '');
                                final subLabel = isHomeroom
                                    ? lesson.teacher.replaceAll('*', '')
                                    : lesson.subject.replaceAll('*', '');

                                final isTodayAndCurrentPeriod =
                                    (day == todayWeekday &&
                                    period == activePeriod);

                                  return TableCell(
                                    child: Container(
                                      height: 48 * s,
                                      decoration: BoxDecoration(
                                        color: isTodayAndCurrentPeriod
                                            ? accentColor.withOpacity(0.24)
                                            : (day == todayWeekday
                                                ? accentColor.withOpacity(0.06)
                                                : (lesson.isChanged
                                                    ? const Color(0xFFEF4565).withOpacity(0.08)
                                                    : Colors.transparent)),
                                        border: isTodayAndCurrentPeriod
                                            ? Border.all(
                                                color: accentColor,
                                                width: 1.8,
                                              )
                                            : (day == todayWeekday
                                                ? Border(
                                                    left: BorderSide(color: accentColor.withOpacity(0.3), width: 0.8),
                                                    right: BorderSide(color: accentColor.withOpacity(0.3), width: 0.8),
                                                  )
                                                : null),
                                      ),
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(1),
                                      child: isEmpty
                                          ? Text(
                                              '-',
                                              style: GoogleFonts.notoSansKr(
                                                color: _textColor24,
                                                fontSize: 9 * s,
                                              ),
                                            )
                                          : Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  topLabel.isNotEmpty ? topLabel : '-',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: GoogleFonts.notoSansKr(
                                                    color: lesson.isChanged
                                                        ? const Color(0xFFEF4565)
                                                        : (isTodayAndCurrentPeriod
                                                            ? accentColor
                                                            : _textColor),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 9.5 * s,
                                                  ),
                                                ),
                                                if (subLabel.isNotEmpty) ...[
                                                  Text(
                                                    subLabel,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.notoSansKr(
                                                      color: isTodayAndCurrentPeriod
                                                          ? accentColor.withOpacity(0.85)
                                                          : (isHomeroom ? const Color(0xFF7F5AF0) : _textColor54),
                                                      fontSize: 8 * s,
                                                      fontWeight: isTodayAndCurrentPeriod ? FontWeight.w600 : FontWeight.normal,
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

  // ── 모바일 전용 반응형 레이아웃 ────────────────────────
  Widget _buildMobileLayout(double scale) {
    Widget content;
    switch (_mobileTabIndex) {
      case 0:
        content = SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
          child: Column(
            children: [
              SizedBox(height: 380 * scale, child: _buildTeacherTimetablePanel(scale)),
              SizedBox(height: 12 * scale),
              SizedBox(height: 380 * scale, child: _buildClassroomTimetablePanel(scale)),
            ],
          ),
        );
        break;
      case 1:
        content = Padding(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
          child: _buildCloudDrivePanel(scale),
        );
        break;
      case 2:
        content = Padding(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
          child: _buildToolsPanel(scale),
        );
        break;
      case 3:
        content = _buildMobileMealAndMessages(scale);
        break;
      case 4:
        content = _buildToolsPanel(scale);
        break;
      default:
        content = const SizedBox();
    }

    return Column(
      children: [
        Expanded(child: content),
        Container(
          height: 60 * scale,
          decoration: BoxDecoration(
            color: _surfaceColor,
            border: Border(top: BorderSide(color: _borderColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMobileNavItem(0, Icons.calendar_today_rounded, '시간표', scale),
              _buildMobileNavItem(1, Icons.cloud_rounded, 'Cloud', scale),
              _buildMobileNavItem(2, Icons.apps_rounded, '수업도구', scale),
              _buildMobileNavItem(3, Icons.restaurant_menu_rounded, '급식/쪽지', scale),
              _buildMobileNavItem(4, Icons.settings_rounded, '설정', scale),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileNavItem(int index, IconData icon, String label, double s) {
    final isSelected = _mobileTabIndex == index;
    final color = isSelected ? const Color(0xFF2EC4B6) : _textColor54;
    return InkWell(
      onTap: () {
        setState(() {
          _mobileTabIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(12 * s),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20 * s),
            SizedBox(height: 2 * s),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11 * s,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _mealOrMessageSubTab = 0; // 0: 급식지도, 1: 학급쪽지

  Widget _buildMobileMealAndMessages(double s) {
    return Column(
      children: [
        // Sub-tabs switch (급식 지도 vs 학급 쪽지)
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
          padding: EdgeInsets.all(4 * s),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(12 * s),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _mealOrMessageSubTab = 0),
                  borderRadius: BorderRadius.circular(10 * s),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8 * s),
                    decoration: BoxDecoration(
                      color: _mealOrMessageSubTab == 0 ? const Color(0xFF2EC4B6).withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10 * s),
                      border: Border.all(
                        color: _mealOrMessageSubTab == 0 ? const Color(0xFF2EC4B6) : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.restaurant_menu_rounded, size: 14 * s, color: _mealOrMessageSubTab == 0 ? const Color(0xFF2EC4B6) : _textColor54),
                          SizedBox(width: 6 * s),
                          Text('급식 지도 & 호출', style: TextStyle(color: _mealOrMessageSubTab == 0 ? const Color(0xFF2EC4B6) : _textColor54, fontWeight: FontWeight.bold, fontSize: 11 * s)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _mealOrMessageSubTab = 1),
                  borderRadius: BorderRadius.circular(10 * s),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8 * s),
                    decoration: BoxDecoration(
                      color: _mealOrMessageSubTab == 1 ? const Color(0xFFFF8906).withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10 * s),
                      border: Border.all(
                        color: _mealOrMessageSubTab == 1 ? const Color(0xFFFF8906) : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mark_email_unread_rounded, size: 14 * s, color: _mealOrMessageSubTab == 1 ? const Color(0xFFFF8906) : _textColor54),
                          SizedBox(width: 6 * s),
                          Text('학급 쪽지 발송', style: TextStyle(color: _mealOrMessageSubTab == 1 ? const Color(0xFFFF8906) : _textColor54, fontWeight: FontWeight.bold, fontSize: 11 * s)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Sub-tab view body
        Expanded(
          child: _mealOrMessageSubTab == 0
              ? MealView(scaleFactor: s)
              : MessageView(scaleFactor: s),
        ),
      ],
    );
  }

  // ── Boardest Cloud (Google Drive & 1분 OTP & 수업자료 파일 관리) 패널 ───────
  Widget _buildCloudDrivePanel(double s) {
    final isLoggedIn = CloudDriveService.instance.isLoggedIn;
    final userEmail = CloudDriveService.instance.userEmail ?? '';
    final userName = CloudDriveService.instance.userName ?? '선생님';
    final otp = CloudDriveService.instance.currentStegano6DigitOtp;
    final remaining = TotpService.getRemainingSeconds();
    final autoPt = CloudDriveService.instance.autoLessonFlowEnabled;

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
            padding: EdgeInsets.all(12 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header Row
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(5 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2EC4B6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8 * s),
                      ),
                      child: Icon(
                        Icons.cloud_done_rounded,
                        color: const Color(0xFF2EC4B6),
                        size: 16 * s,
                      ),
                    ),
                    SizedBox(width: 8 * s),
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            'Boardest Cloud',
                            style: GoogleFonts.notoSansKr(
                              color: _textColor,
                              fontSize: 13 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 6 * s),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                            decoration: BoxDecoration(
                              color: isLoggedIn ? const Color(0xFF2EC4B6).withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6 * s),
                              border: Border.all(color: isLoggedIn ? const Color(0xFF2EC4B6) : Colors.amber),
                            ),
                            child: Text(
                              isLoggedIn ? '연동됨' : '미연동',
                              style: TextStyle(
                                color: isLoggedIn ? const Color(0xFF2EC4B6) : Colors.amber,
                                fontSize: 9.5 * s,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isLoggedIn && userEmail.isNotEmpty) ...[
                            SizedBox(width: 8 * s),
                            Text(
                              '$userName ($userEmail)',
                              style: TextStyle(color: _textColor54, fontSize: 10.5 * s),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isLoggedIn) ...[
                      ElevatedButton.icon(
                        icon: const Icon(Icons.create_new_folder_rounded, size: 12),
                        label: Text('새 폴더', style: TextStyle(fontSize: 10.5 * s, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F5D4),
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6 * s)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => _BstCloudDialog(
                              scaleFactor: _settings.scaleFactor,
                              onFileDownloaded: (file) => _openFile(file.path),
                              onStatusChanged: () => setState(() {}),
                            ),
                          );
                        },
                      ),
                      SizedBox(width: 6 * s),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.upload_file_rounded, size: 12),
                        label: Text('파일 올리기', style: TextStyle(fontSize: 10.5 * s, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2CB67D),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6 * s)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => _BstCloudDialog(
                              scaleFactor: _settings.scaleFactor,
                              onFileDownloaded: (file) => _openFile(file.path),
                              onStatusChanged: () => setState(() {}),
                            ),
                          );
                        },
                      ),
                      SizedBox(width: 6 * s),
                      TextButton.icon(
                        icon: Icon(Icons.security_rounded, size: 13 * s, color: const Color(0xFF7F5AF0)),
                        label: Text('인증 허브', style: TextStyle(fontSize: 10.5 * s, color: const Color(0xFF7F5AF0), fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _openAuthManagement,
                      ),
                      SizedBox(width: 4 * s),
                    ],
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: _textColor54, size: 15 * s),
                      onPressed: () => setState(() {}),
                      tooltip: '새로고침',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                SizedBox(height: 8 * s),

                // 2. Body Row: Left (OTP & Auto-PT) + Right (Inline Drive File List)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left: OTP & Auto PT Controls (flex: 4)
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            // OTP Box
                            Expanded(
                              flex: 6,
                              child: Container(
                                padding: EdgeInsets.all(10 * s),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF7F5AF0).withOpacity(0.18),
                                      const Color(0xFF2EC4B6).withOpacity(0.12),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14 * s),
                                  border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.35)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.pin_rounded, color: const Color(0xFF7F5AF0), size: 13 * s),
                                        SizedBox(width: 4 * s),
                                        Text(
                                          '전자칠판 OTP',
                                          style: GoogleFonts.notoSansKr(
                                            color: _textColor,
                                            fontSize: 11 * s,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 5 * s, vertical: 1.5 * s),
                                          decoration: BoxDecoration(
                                            color: Colors.black45,
                                            borderRadius: BorderRadius.circular(5 * s),
                                          ),
                                          child: Text(
                                            '${remaining}초',
                                            style: TextStyle(
                                              color: const Color(0xFFFF8906),
                                              fontSize: 9.5 * s,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 4 * s),
                                    Text(
                                      otp.split('').join(' '),
                                      style: GoogleFonts.sourceCodePro(
                                        color: const Color(0xFF00F5D4),
                                        fontSize: 20 * s,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 4 * s,
                                      ),
                                    ),
                                    SizedBox(height: 4 * s),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3 * s),
                                      child: LinearProgressIndicator(
                                        value: remaining / 60.0,
                                        minHeight: 3 * s,
                                        backgroundColor: Colors.white10,
                                        valueColor: const AlwaysStoppedAnimation(Color(0xFF2EC4B6)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 6 * s),

                            // Auto PT Box
                            Expanded(
                              flex: 4,
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                                decoration: BoxDecoration(
                                  color: _cardColor,
                                  borderRadius: BorderRadius.circular(12 * s),
                                  border: Border.all(color: _borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.auto_awesome_rounded, color: const Color(0xFFFF8906), size: 14 * s),
                                    SizedBox(width: 6 * s),
                                    Expanded(
                                      child: Text(
                                        '자동 수업 PT',
                                        style: GoogleFonts.notoSansKr(
                                          color: _textColor,
                                          fontSize: 11 * s,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Transform.scale(
                                      scale: 0.75,
                                      child: Switch(
                                        value: autoPt,
                                        activeColor: const Color(0xFF2EC4B6),
                                        onChanged: (val) async {
                                          await CloudDriveService.instance.setAutoLessonFlowEnabled(val);
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10 * s),

                      // Right: Real-time Drive File Explorer & Sync Board (flex: 6)
                      Expanded(
                        flex: 6,
                        child: Container(
                          padding: EdgeInsets.all(10 * s),
                          decoration: BoxDecoration(
                            color: _cardColor,
                            borderRadius: BorderRadius.circular(14 * s),
                            border: Border.all(color: _borderColor),
                          ),
                          child: !isLoggedIn
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 24 * s),
                                      SizedBox(height: 6 * s),
                                      Text('Google Drive 미연동 상태입니다', style: TextStyle(color: _textColor54, fontSize: 11 * s)),
                                      SizedBox(height: 6 * s),
                                      ElevatedButton(
                                        onPressed: () => CloudDriveService.instance.loginWithBrowserOAuth(),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF7F5AF0),
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
                                        ),
                                        child: Text('Google 로그인', style: TextStyle(fontSize: 11 * s, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                )
                              : FutureBuilder<List<CloudDriveFile>>(
                                  future: CloudDriveService.instance.fetchDriveFiles(),
                                  builder: (ctx, snap) {
                                    if (snap.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2EC4B6)));
                                    }
                                    final files = (snap.data ?? []).where((f) {
                                      final n = f.name.toLowerCase();
                                      return !n.endsWith('.annot.json') && !n.contains('_annot') && !n.endsWith('.sync.json');
                                    }).toList();

                                    if (files.isEmpty) {
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.folder_open_rounded, color: Colors.white24, size: 28 * s),
                                            SizedBox(height: 4 * s),
                                            Text('수업 자료 폴더에 파일이 없습니다', style: TextStyle(color: _textColor38, fontSize: 10.5 * s)),
                                            SizedBox(height: 4 * s),
                                            TextButton.icon(
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) => _BstCloudDialog(
                                                    scaleFactor: _settings.scaleFactor,
                                                    onFileDownloaded: (file) => _openFile(file.path),
                                                    onStatusChanged: () => setState(() {}),
                                                  ),
                                                );
                                              },
                                              icon: Icon(Icons.add_circle_outline_rounded, size: 13 * s, color: const Color(0xFF2EC4B6)),
                                              label: Text('파일 추가하기', style: TextStyle(color: const Color(0xFF2EC4B6), fontSize: 11 * s)),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    return ListView.separated(
                                      itemCount: files.length,
                                      separatorBuilder: (_, __) => SizedBox(height: 4 * s),
                                      itemBuilder: (ctx, idx) {
                                        final f = files[idx];
                                        final isFolder = f.mimeType == 'application/vnd.google-apps.folder';
                                        final isPdf = f.name.toLowerCase().endsWith('.pdf');
                                        final isPpt = f.name.toLowerCase().endsWith('.ppt') || f.name.toLowerCase().endsWith('.pptx');

                                        return InkWell(
                                          onTap: () async {
                                            if (isFolder) {
                                              showDialog(
                                                context: context,
                                                builder: (context) => _BstCloudDialog(
                                                  scaleFactor: _settings.scaleFactor,
                                                  onFileDownloaded: (file) => _openFile(file.path),
                                                  onStatusChanged: () => setState(() {}),
                                                ),
                                              );
                                              return;
                                            }
                                            // 일반 파일 직접 열기
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('${f.name} 여는 중...', style: GoogleFonts.notoSansKr()),
                                                duration: const Duration(seconds: 1),
                                                backgroundColor: const Color(0xFF1E293B),
                                              ),
                                            );
                                            try {
                                              final tempFile = await CloudDriveService.instance.downloadDriveFileToTemp(f);
                                              if (tempFile != null) {
                                                _openFile(tempFile.path);
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('파일 다운로드에 실패했습니다.')),
                                                );
                                              }
                                            } catch (e) {
                                              debugPrint('[CloudDrive] File open error: $e');
                                            }
                                          },
                                          borderRadius: BorderRadius.circular(8 * s),
                                          child: Container(
                                            padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 5 * s),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.04),
                                              borderRadius: BorderRadius.circular(8 * s),
                                              border: Border.all(color: Colors.white10),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isFolder ? Icons.folder_rounded : isPdf ? Icons.picture_as_pdf_rounded : isPpt ? Icons.slideshow_rounded : Icons.insert_drive_file_rounded,
                                                  color: isFolder ? const Color(0xFFFF8E3C) : isPdf ? Colors.redAccent : isPpt ? Colors.orangeAccent : const Color(0xFF2EC4B6),
                                                  size: 14 * s,
                                                ),
                                                SizedBox(width: 6 * s),
                                                Expanded(
                                                  child: Text(
                                                    f.name,
                                                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 10.5 * s, fontWeight: FontWeight.w500),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 9 * s),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
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
    );
  }

  // ── USB 연결 시 반 매핑 패널 (flex 2) ─────────────────
  // ── 중앙: USB 연결 시 USB 탐색기 / 평상시 및 Web: OTP & Cloud 패널 ───────
  Widget _buildMappingPanel(double s) {
    if (_isUsbConnected && !kIsWeb) {
      return _buildUsbPanel(s);
    }
    return _buildCloudDrivePanel(s);
  }

  // ── (레거시) USB 연결 시 반 매핑 패널 ─────────────────
  Widget _buildLegacyMappingPanel(double s) {
    if (kIsWeb) {
      return _buildCloudDrivePanel(s);
    }
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
      case 'timetable_full':
        return Icons.calendar_view_week_rounded;
      case 'cloud_settings':
        return Icons.cloud_circle_rounded;
      case 'otp_settings':
        return Icons.pin_rounded;
      case 'usb_explorer':
        return Icons.folder_open_rounded;
      case 'bst_cloud':
        return Icons.cloud_sync_rounded;
      case 'auth_management':
        return Icons.security_rounded;
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
      case 'saved_ink':
        return Icons.border_color_rounded;
      case 'app_drawer':
        return Icons.apps_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  VoidCallback _getToolOnTap(String id) {
    switch (id) {
      case 'cloud_settings':
        return _openAuthManagement;
      case 'bst_cloud':
        return _openBstCloud;
      case 'saved_ink':
        return () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SavedInkView(scaleFactor: _settings.scaleFactor)),
          );
        };
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
        return _openBstCloud;
      case 'auth_management':
        return _openAuthManagement;
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

  void _showLoginRequiredDialog(String featureTitle) {
    final s = _settings.scaleFactor;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20 * s),
          side: BorderSide(color: const Color(0xFFFF8906).withOpacity(0.4), width: 1.2),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8 * s),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8906).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10 * s),
              ),
              child: Icon(Icons.lock_rounded, color: const Color(0xFFFF8906), size: 22 * s),
            ),
            SizedBox(width: 10 * s),
            Expanded(
              child: Text(
                'Google 로그인 필요',
                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15 * s),
              ),
            ),
          ],
        ),
        content: Text(
          '[$featureTitle] 기능을 사용하려면 Google 계정 및 Drive API 로그인이 필요합니다.\n\n설정 또는 브라우저에서 구글 로그인을 먼저 진행해주세요.',
          style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * s, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('닫기', style: GoogleFonts.notoSansKr(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.open_in_browser_rounded, size: 16),
            label: Text('Google 로그인 진행', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 12 * s)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await CloudDriveService.instance.loginWithBrowserOAuth();
            },
          ),
        ],
      ),
    );
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
    if (!CloudDriveService.instance.isLoggedIn) {
      _showLoginRequiredDialog('BST Cloud (수업자료 드라이브)');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _BstCloudDialog(
        scaleFactor: _settings.scaleFactor,
        onFileDownloaded: (file) {
          _openFile(file.path);
        },
        onStatusChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _openAuthManagement() {
    if (!CloudDriveService.instance.isLoggedIn) {
      _showLoginRequiredDialog('인증 관리 (Google OTP / 기기 신뢰)');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _AuthManagementDialog(
        scaleFactor: _settings.scaleFactor,
      ),
    );
  }

  void _openAppDrawer() {
    final s = _settings.scaleFactor;
    final apps = [
      {'name': '기본 판서 (칠판)', 'icon': Icons.draw_rounded, 'color': const Color(0xFF2EC4B6), 'action': () { Navigator.of(context).pop(); _openWhiteboard(); }},
      {'name': '미니 계산기', 'icon': Icons.calculate_rounded, 'color': const Color(0xFF2EC4B6), 'action': () { Navigator.of(context).pop(); _openCalculator(); }},
      {'name': '타이머 / 스톱워치', 'icon': Icons.timer_rounded, 'color': const Color(0xFFFF8906), 'action': () { Navigator.of(context).pop(); _toggleMiniTimer(); }},
      {'name': '랜덤 발표자 뽑기', 'icon': Icons.casino_rounded, 'color': const Color(0xFF7F5AF0), 'action': () { Navigator.of(context).pop(); _openRandomPicker(); }},
      {'name': 'BST Cloud 자료', 'icon': Icons.cloud_rounded, 'color': const Color(0xFF2EC4B6), 'action': () { Navigator.of(context).pop(); _openBstCloud(); }},
      {'name': '인증 관리 (OTP)', 'icon': Icons.security_rounded, 'color': const Color(0xFF00F5D4), 'action': () { Navigator.of(context).pop(); _openAuthManagement(); }},
      {'name': '문서 판서', 'icon': Icons.picture_as_pdf_rounded, 'color': const Color(0xFFEF4565), 'action': () { Navigator.of(context).pop(); _openPdfBoard(); }},
      {'name': 'Canva 슬라이드', 'icon': Icons.palette_rounded, 'color': const Color(0xFF8B5CF6), 'action': () { Navigator.of(context).pop(); _openCanvaBoard(); }},
      {'name': '급식 지도 & 문자', 'icon': Icons.restaurant_menu_rounded, 'color': const Color(0xFF2EC4B6), 'action': () { Navigator.of(context).pop(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => MealView(scaleFactor: s))); }},
      {'name': '학급 쪽지', 'icon': Icons.mail_rounded, 'color': const Color(0xFFFF8906), 'action': () { Navigator.of(context).pop(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageView(scaleFactor: s))); }},
      {'name': '날씨 정보', 'icon': Icons.wb_sunny_rounded, 'color': const Color(0xFFFF8906), 'action': () { Navigator.of(context).pop(); showDialog(context: context, builder: (_) => WeatherDialog(scaleFactor: s)); }},
      {'name': '학사 일정', 'icon': Icons.calendar_month_rounded, 'color': const Color(0xFF00F5D4), 'action': () { Navigator.of(context).pop(); showDialog(context: context, builder: (_) => SchoolCalendarDialog(scaleFactor: s, apiScheduleEvents: const [])); }},
      {'name': '웹 브라우저', 'icon': Icons.language_rounded, 'color': const Color(0xFF3B82F6), 'action': () { Navigator.of(context).pop(); launchUrl(Uri.parse('https://www.google.com')); }},
      {'name': '보드북 편집기', 'icon': Icons.menu_book_rounded, 'color': const Color(0xFF7F5AF0), 'action': () { Navigator.of(context).pop(); _openBoardBookEditor(); }},
      {'name': 'GitHub 계정/릴리즈 설정', 'icon': Icons.account_circle_rounded, 'color': const Color(0xFF00F5D4), 'action': () { Navigator.of(context).pop(); _showGithubAuthDialog(); }},
      {'name': '시스템 업데이트 확인', 'icon': Icons.system_update_rounded, 'color': const Color(0xFF2EC4B6), 'action': () { Navigator.of(context).pop(); _checkForAppUpdates(silent: false); }},
      {'name': '판서 저장 보기', 'icon': Icons.border_color_rounded, 'color': const Color(0xFF00F5D4), 'action': () { Navigator.of(context).pop(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => SavedInkView(scaleFactor: s))); }},
      {'name': '설정', 'icon': Icons.settings_rounded, 'color': Colors.white70, 'action': () { Navigator.of(context).pop(); _openSettings(); }},
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
      if (!kIsWeb && Platform.isWindows) {
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
    if (!CloudDriveService.instance.isLoggedIn) {
      _showCloudRequiredDialog('Canva');
      return;
    }
    _showCanvaActionDialog(initialUrl: url, filePath: filePath);
  }

  void _showCanvaActionDialog({String? initialUrl, String? filePath}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.palette_rounded, color: Color(0xFF8B5CF6), size: 28),
            const SizedBox(width: 10),
            Text(
              '🎨 Canva 슬라이드',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '진행할 Canva 수업 방식을 선택해 주세요.',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(ctx);
                _showCanvaUrlInputDialog(initialUrl: initialUrl, filePath: filePath);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add_link_rounded, color: Colors.white, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '✨ 새 Canva URL로 시작',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Canva 공유/임베드 웹 링크를 입력하여 즉시 수업 판서 시작',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(ctx);
                _showSavedCanvaListDialog(filePath: filePath);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF242629),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open_rounded, color: Color(0xFF00F5D4), size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📂 최근 / 저장된 Canva 열기',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '이전에 진행했던 Canva 프로젝트 및 URL 목록에서 열기',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Future<void> _showSavedCanvaListDialog({String? filePath}) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedUrls = prefs.getStringList('saved_canva_urls') ?? [];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.folder_open_rounded, color: Color(0xFF00F5D4)),
            const SizedBox(width: 8),
            Text(
              '📂 최근 Canva 프로젝트',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: savedUrls.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      '저장된 최근 Canva URL이 없습니다.\n[✨ 새 Canva URL로 시작]을 이용해 주세요.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: savedUrls.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                  itemBuilder: (context, idx) {
                    final u = savedUrls[idx];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.palette_rounded, color: Color(0xFF8B5CF6), size: 20),
                      ),
                      title: Text(
                        u,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                        onPressed: () async {
                          savedUrls.remove(u);
                          await prefs.setStringList('saved_canva_urls', savedUrls);
                          Navigator.pop(ctx);
                          _showSavedCanvaListDialog(filePath: filePath);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CanvaBoardView(
                              scaleFactor: _settings.scaleFactor,
                              initialUrl: u,
                              filePath: filePath,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
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
              Text('💾 추천 바로가기:', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
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
                    ActionChip(
                      label: const Text('교육용 프레젠테이션', style: TextStyle(color: Color(0xFF00C4CC), fontSize: 11)),
                      backgroundColor: const Color(0xFF242629),
                      onPressed: () => urlCtrl.text = 'https://www.canva.com/education',
                    ),
                    const SizedBox(width: 6),
                    ...savedUrls.take(3).map((u) => Padding(
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
                  if (!list.contains(val)) list.insert(0, val);
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
              child: const Text('🚀 Canva 판서 시작', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      {'id': 'cloud_settings',  'name': 'Cloud 설정'},
      {'id': 'timer',           'name': '타이머'},
      {'id': 'calculator',      'name': '계산기'},
      {'id': 'picker',          'name': '발표자'},
      {'id': 'saved_ink',       'name': '판서보관함'},
      {'id': 'app_drawer',      'name': '앱서랍'},
    ];
    final List<Map<String, String>> col2Tools = [
      {'id': 'whiteboard',      'name': '기본판서'},
      {'id': 'document_board',  'name': '문서판서'},
      {'id': 'boardbook',       'name': 'BoardBook'},
      {'id': 'canva_board',     'name': 'Canva 슬라이드'},
      {'id': 'website_board',   'name': '사이트판서'},
      {'id': 'browser_board',   'name': '웹브라우저'},
    ];
    final List<Map<String, String>> col3Tools = [
      {'id': 'bst_cloud',       'name': 'BST Cloud'},
      {'id': 'meal_call',       'name': '급식문자'},
      {'id': 'school_calendar', 'name': '학사달력'},
      {'id': 'message_box',     'name': '학급쪽지'},
      {'id': 'weather',         'name': '날씨'},
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
                      if (index >= col1Tools.length) return const Expanded(child: SizedBox.shrink());
                      final item = col1Tools[index];
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(2 * s),
                          child: _buildGridSlot(item['id'] ?? '', item['name'] ?? '', s),
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
                      if (index >= col2Tools.length) return const Expanded(child: SizedBox.shrink());
                      final item = col2Tools[index];
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(2 * s),
                          child: _buildGridSlot(item['id'] ?? '', item['name'] ?? '', s),
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
                      if (index >= col3Tools.length) return const Expanded(child: SizedBox.shrink());
                      final item = col3Tools[index];
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(2 * s),
                          child: _buildGridSlot(item['id'] ?? '', item['name'] ?? '', s),
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
    if (kIsWeb) {
      return const SizedBox.shrink();
    }
    return _buildWindowsTitleBar(s);
  }

  Widget _buildWindowsTitleBar(double s) {
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
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          SizedBox(width: 16 * s),
          if (!kIsWeb && Platform.isWindows) ...[
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
            SizedBox(width: 16 * s),
          ],
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) {
                if (!kIsWeb && Platform.isWindows) {
                  windowManager.startDragging();
                }
              },
              onDoubleTap: () async {
                if (!kIsWeb && Platform.isWindows) {
                  bool isMax = await windowManager.isMaximized();
                  if (isMax) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                }
              },
              child: Row(
                children: [
                  Icon(Icons.school_rounded, color: _accentColor, size: 18 * s),
                  SizedBox(width: 8 * s),
                  Text(
                    'Boardest Teacher',
                    style: GoogleFonts.outfit(
                      color: _textColor,
                      fontSize: 15 * s,
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

  // ── 하단 좌측: OTP 및 보안 인증/기기 관리 패널 ──
  Widget _buildBottomOtpAndAuthPanel(double s) {
    final cloud = CloudDriveService.instance;
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
            padding: EdgeInsets.all(12 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(4 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7F5AF0).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.vpn_key_rounded,
                        color: const Color(0xFF7F5AF0),
                        size: 14 * s,
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    Text(
                      'OTP & 보안 인증 관리',
                      style: GoogleFonts.notoSansKr(
                        color: _textColor,
                        fontSize: 12 * s,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD166).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6 * s),
                        border: Border.all(color: const Color(0xFFFFD166).withOpacity(0.3)),
                      ),
                      child: Text(
                        'Cloud ID: ' + cloud.cloudId,
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFFFFD166),
                          fontSize: 9.5 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8 * s),

                // 6자리 Stegano OTP 대형 카드
                InkWell(
                  onTap: () {
                    final full6 = _currentOtp;
                    Clipboard.setData(ClipboardData(text: full6));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('📋 6자리 접속 코드 [' + full6 + '] 가 복사되었습니다.'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: const Color(0xFF2EC4B6),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12 * s),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8 * s, horizontal: 10 * s),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.025),
                      borderRadius: BorderRadius.circular(12 * s),
                      border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Builder(
                          builder: (context) {
                            final full6 = _currentOtp;
                            final display6 = full6.length == 6
                                ? (full6.substring(0, 3) + ' ' + full6.substring(3, 6))
                                : full6;
                            return Text(
                              display6,
                              style: GoogleFonts.sourceCodePro(
                                color: const Color(0xFF00F5D4),
                                fontSize: 22 * s,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4 * s,
                              ),
                            );
                          },
                        ),
                        SizedBox(height: 4 * s),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4 * s),
                          child: LinearProgressIndicator(
                            value: _remainingSeconds / 60.0,
                            minHeight: 3.5 * s,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation(Color(0xFF00F5D4)),
                          ),
                        ),
                        SizedBox(height: 4 * s),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _remainingSeconds.toString() + '초 뒤 갱신 (클릭 시 복사)',
                              style: TextStyle(color: const Color(0xFFFF8906), fontSize: 9 * s),
                            ),
                            Row(
                              children: [
                                Text('Auto-PT', style: TextStyle(color: _textColor70, fontSize: 9 * s)),
                                SizedBox(width: 4 * s),
                                SizedBox(
                                  height: 20 * s,
                                  child: Switch(
                                    value: _autoPtEnabled,
                                    activeColor: const Color(0xFF2EC4B6),
                                    onChanged: (val) async {
                                      setState(() => _autoPtEnabled = val);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('bst_auto_pt', val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8 * s),

                // 서브 탭 스위처: [📡 다른 기기 OTP 주기 (온라인)] / [🔐 인증 기기 & 로그]
                Container(
                  padding: EdgeInsets.all(2 * s),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8 * s),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _bottomAuthSubTab = 0),
                          borderRadius: BorderRadius.circular(6 * s),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 4 * s),
                            decoration: BoxDecoration(
                              color: _bottomAuthSubTab == 0 ? const Color(0xFF00F5D4) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6 * s),
                            ),
                            child: Center(
                              child: Text(
                                '📡 다른 기기 OTP 주기',
                                style: GoogleFonts.notoSansKr(
                                  color: _bottomAuthSubTab == 0 ? Colors.black : Colors.white70,
                                  fontSize: 10 * s,
                                  fontWeight: _bottomAuthSubTab == 0 ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _bottomAuthSubTab = 1),
                          borderRadius: BorderRadius.circular(6 * s),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 4 * s),
                            decoration: BoxDecoration(
                              color: _bottomAuthSubTab == 1 ? const Color(0xFF00F5D4) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6 * s),
                            ),
                            child: Center(
                              child: Text(
                                '🔐 인증 기기 목록',
                                style: GoogleFonts.notoSansKr(
                                  color: _bottomAuthSubTab == 1 ? Colors.black : Colors.white70,
                                  fontSize: 10 * s,
                                  fontWeight: _bottomAuthSubTab == 1 ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 6 * s),

                // Sub-tab content (Expanded)
                Expanded(
                  child: _bottomAuthSubTab == 0
                      ? _buildOnlineOtpDevicesList(s, cloud)
                      : _buildRegisteredDevicesList(s, cloud),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 실시간 온라인 전자칠판 목록 및 8자리 직통 전송
  Widget _buildOnlineOtpDevicesList(double s, CloudDriveService cloud) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchOnlineClassrooms(_settings.schoolId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(color: Color(0xFF00F5D4), strokeWidth: 2),
            ),
          );
        }
        final onlineRooms = snapshot.data ?? [];
        if (onlineRooms.isEmpty) {
          return Container(
            alignment: Alignment.center,
            padding: EdgeInsets.all(8 * s),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, size: 24 * s, color: Colors.white24),
                SizedBox(height: 4 * s),
                Text(
                  '현재 온라인인 전자칠판이 없습니다.',
                  style: GoogleFonts.notoSansKr(color: _textColor70, fontSize: 10.5 * s, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2 * s),
                Text(
                  '칠판 앱(Boardest)이 켜지면 5분 이내 자동 감지됩니다.',
                  style: TextStyle(color: _textColor38, fontSize: 8.5 * s),
                ),
                SizedBox(height: 4 * s),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4), size: 18),
                  onPressed: () => setState(() {}),
                  tooltip: '온라인 기기 다시 검색',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: onlineRooms.length,
          separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.04), height: 4 * s),
          itemBuilder: (ctx, idx) {
            final r = onlineRooms[idx];
            final name = (r['nickname'] ?? r['docId'] ?? '전자칠판').toString();
            final docId = (r['docId'] ?? '').toString();
            return Container(
              padding: EdgeInsets.symmetric(vertical: 4 * s, horizontal: 4 * s),
              child: Row(
                children: [
                  Stack(
                    children: [
                      Icon(Icons.tv_rounded, color: const Color(0xFF00F5D4), size: 18 * s),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 6 * s,
                          height: 6 * s,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00F5D4),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 6 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.notoSansKr(color: _textColor, fontWeight: FontWeight.bold, fontSize: 11 * s),
                        ),
                        Text(
                          '🟢 온라인 · ID: ' + docId,
                          style: TextStyle(color: const Color(0xFF00F5D4), fontSize: 8.5 * s),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('📡 [' + name + '] 으로 8자리 자동 OTP 발송 중...')),
                      );
                      bool ok = false;
                      try {
                        final res = await http.post(
                          Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/auto-otp'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'email': cloud.userEmail ?? 'teacher@boardest.bst',
                            'teacherName': cloud.userName ?? '선생님',
                            'fcmToken': docId,
                            'classId': docId,
                            'display': name,
                          }),
                        );
                        ok = (res.statusCode == 200);
                      } catch (_) {
                        ok = false;
                      }
                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('✅ [' + name + '] 에 8자리 자동 OTP Secret 등록 완료!'), backgroundColor: const Color(0xFF00F5D4)),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('❌ 발송 실패. 네트워크를 확인해주세요.'), backgroundColor: Colors.redAccent),
                        );
                      }
                    },
                    icon: Icon(Icons.send_rounded, size: 11 * s, color: Colors.black),
                    label: Text('8자리 전송', style: TextStyle(fontSize: 9.5 * s, color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F5D4),
                      padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                      minimumSize: Size(50 * s, 26 * s),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 등록된 인증 기기 목록
  Widget _buildRegisteredDevicesList(double s, CloudDriveService cloud) {
    return FutureBuilder<List<dynamic>>(
      future: cloud.fetchDeviceListAndLogs().then((res) => (res['devices'] as List<dynamic>?) ?? <dynamic>[]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(color: Color(0xFF00F5D4), strokeWidth: 2),
            ),
          );
        }
        final devices = snapshot.data ?? [];
        if (devices.isEmpty) {
          return Container(
            alignment: Alignment.center,
            padding: EdgeInsets.all(8 * s),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices_other_rounded, size: 24 * s, color: Colors.white24),
                SizedBox(height: 4 * s),
                Text('등록된 신뢰 기기가 없습니다.', style: TextStyle(color: Colors.white38, fontSize: 10 * s)),
              ],
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: devices.length,
          separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.04), height: 4 * s),
          itemBuilder: (context, idx) {
            final dev = devices[idx] as Map<String, dynamic>;
            final keyId = (dev['keyId'] ?? dev['id'] ?? '').toString();
            final display = (dev['display'] ?? dev['classroomName'] ?? dev['deviceLabel'] ?? '전자칠판').toString();
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 2 * s),
              child: Row(
                children: [
                  Icon(Icons.devices_rounded, color: const Color(0xFF2EC4B6), size: 16 * s),
                  SizedBox(width: 6 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(display, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5 * s)),
                        Text('ID: ' + keyId, style: TextStyle(color: Colors.white38, fontSize: 8.5 * s)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      await cloud.removeDevice(keyId);
                      if (mounted) setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('🗑️ [' + display + '] 연결이 취소되었습니다.')),
                      );
                    },
                    borderRadius: BorderRadius.circular(4 * s),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4 * s),
                      ),
                      child: Text('해제', style: TextStyle(color: Colors.redAccent, fontSize: 9 * s, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── 하단 우측: 파일 업로드 및 폴더 맵핑 패널 ──
  Widget _buildBottomUploadAndMappingPanel(double s) {
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
            padding: EdgeInsets.all(12 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(4 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2EC4B6).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.drive_file_move_rounded,
                        color: const Color(0xFF2EC4B6),
                        size: 14 * s,
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    Text(
                      '업로드 & 폴더 맵핑',
                      style: GoogleFonts.notoSansKr(
                        color: _textColor,
                        fontSize: 12 * s,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, size: 15 * s, color: _textColor54),
                      tooltip: '새로고침',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        await _loadCloudDriveMappings();
                        setState(() {});
                      },
                    ),
                  ],
                ),
                SizedBox(height: 10 * s),

                // 4 Action Buttons in 2x2 grid
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildActionTile(
                                icon: Icons.upload_file_rounded,
                                iconColor: const Color(0xFF4285F4),
                                title: '파일 올리기',
                                subtitle: 'PDF / PPT / 교안',
                                onTap: _uploadLocalFileToDrive,
                                s: s,
                              ),
                            ),
                            SizedBox(width: 6 * s),
                            Expanded(
                              child: _buildActionTile(
                                icon: Icons.palette_rounded,
                                iconColor: const Color(0xFF00C4CC),
                                title: 'Canva 등록',
                                subtitle: '디자인 링크 연동',
                                onTap: _showRegisterCanvaDialog,
                                s: s,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 6 * s),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildActionTile(
                                icon: Icons.create_new_folder_rounded,
                                iconColor: const Color(0xFFFF8906),
                                title: '새 폴더',
                                subtitle: 'bst-save에 생성',
                                onTap: _showCreateFolderDialog,
                                s: s,
                              ),
                            ),
                            SizedBox(width: 6 * s),
                            Expanded(
                              child: _buildActionTile(
                                icon: Icons.sync_alt_rounded,
                                iconColor: const Color(0xFF00F5D4),
                                title: '폴더 맵핑',
                                subtitle: '교과/반별 동기화',
                                onTap: _openDriveFolderSyncDialog,
                                s: s,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10 * s),

                // Folder Mappings Summary
                Row(
                  children: [
                    Icon(Icons.folder_shared_outlined, size: 12 * s, color: _textColor54),
                    SizedBox(width: 4 * s),
                    Text(
                      '현재 교과 / 반별 매핑 (' + _classroomFolderMappings.length.toString() + ')',
                      style: GoogleFonts.notoSansKr(
                        color: _textColor70,
                        fontSize: 10 * s,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4 * s),
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: EdgeInsets.all(6 * s),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8 * s),
                      border: Border.all(color: Colors.white.withOpacity(0.04)),
                    ),
                    child: _classroomFolderMappings.isEmpty
                        ? Center(
                            child: Text(
                              '매핑된 교과 폴더가 없습니다.\n[폴더 맵핑] 버튼을 눌러 설정하세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white30, fontSize: 9 * s, height: 1.3),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _classroomFolderMappings.length,
                            separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.04), height: 4 * s),
                            itemBuilder: (ctx, idx) {
                              final entry = _classroomFolderMappings.entries.elementAt(idx);
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _cloudSearchQuery = entry.value;
                                  });
                                },
                                borderRadius: BorderRadius.circular(4 * s),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 2 * s, horizontal: 4 * s),
                                  child: Row(
                                    children: [
                                      Icon(Icons.folder_rounded, size: 11 * s, color: const Color(0xFF00F5D4)),
                                      SizedBox(width: 4 * s),
                                      Expanded(
                                        child: Text(
                                          entry.key + ' → ' + entry.value,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.sourceCodePro(color: Colors.white70, fontSize: 9.5 * s),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required double s,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10 * s),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 6 * s),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(10 * s),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6 * s),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8 * s),
                ),
                child: Icon(icon, size: 16 * s, color: iconColor),
              ),
              SizedBox(width: 8 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                        color: _textColor,
                        fontSize: 10.5 * s,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textColor54,
                        fontSize: 8.5 * s,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateFolderDialog() {
    final s = _settings.scaleFactor;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * s)),
        title: Text('📂 새 교안 폴더 생성', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14 * s)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: Colors.white, fontSize: 12 * s),
          decoration: InputDecoration(
            hintText: '폴더 이름 입력 (예: 1학기_수학)',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * s)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                await CloudDriveService.instance.createFolderPairInDrive(name);
                await _refreshDriveFiles();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✅ 폴더 [' + name + '] 가 생성되었습니다.'), backgroundColor: const Color(0xFF00F5D4)),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4)),
            child: const Text('생성', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
  Timer? _totpTimer;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    super.dispose();
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
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _loading = true);
    int success = 0;
    for (final file in result.files) {
      if (file.bytes != null) {
        final ok = await CloudDriveService.instance.uploadBytesToDrive(file.bytes!, file.name);
        if (ok) success++;
      } else if (file.path != null) {
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
                final folderId = await CloudDriveService.instance.createFolderPairInDrive(name);
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

// ─── AUTH MANAGEMENT DIALOG (GOOGLE OTP / TRUSTED DEVICE / AUTO LESSON FLOW) ──────

class _AuthManagementDialog extends StatefulWidget {
  final double scaleFactor;
  const _AuthManagementDialog({required this.scaleFactor});

  @override
  State<_AuthManagementDialog> createState() => _AuthManagementDialogState();
}

class _AuthManagementDialogState extends State<_AuthManagementDialog> {
  Timer? _ticker;
  int _currentSubTab = 0; // 0: 계정 & OTP, 1: 등록된 기기, 2: 다른 기기 OTP 주기

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _showGoogleOtpRegistrationDialog(double s) {
    final cloud = CloudDriveService.instance;
    final secret = cloud.totpSecret ?? '';
    final email = cloud.userEmail ?? 'teacher@boardest.bst';
    final otpAuthUri = TotpService.getOtpAuthUri(secret: secret, email: email);
    final qrUrl = TotpService.getQrCodeImageUrl(otpAuthUri, size: 280);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13171F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20 * s),
          side: BorderSide(color: const Color(0xFF00F5D4).withOpacity(0.3)),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8 * s),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10 * s),
              ),
              child: Icon(Icons.qr_code_scanner_rounded, color: const Color(0xFF00F5D4), size: 22 * s),
            ),
            SizedBox(width: 10 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Google OTP 앱 등록',
                      style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.bold)),
                  Text('Google Authenticator / Microsoft Authenticator 지원',
                      style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 11 * s)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 340 * s,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '스마트폰의 Google OTP 앱에서 [+] ➔ [QR 코드 스캔]을 눌러 아래 QR을 스캔하세요.',
                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * s, height: 1.4),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 14 * s),
              Container(
                padding: EdgeInsets.all(12 * s),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16 * s),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F5D4).withOpacity(0.25),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Image.network(
                  qrUrl,
                  width: 180 * s,
                  height: 180 * s,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: 180 * s,
                    height: 180 * s,
                    alignment: Alignment.center,
                    child: const Text('QR 로드 실패', style: TextStyle(color: Colors.black54)),
                  ),
                ),
              ),
              SizedBox(height: 14 * s),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 8 * s),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10 * s),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('수동 직접 입력 키:', style: TextStyle(color: Colors.white38, fontSize: 10 * s)),
                          Text(
                            secret,
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF74f8e5),
                              fontSize: 11 * s,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Color(0xFF00F5D4), size: 18),
                      tooltip: '키 복사',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: secret));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('📋 OTP 시크릿 키가 복사되었습니다!'), backgroundColor: Color(0xFF2EC4B6)),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('닫기', style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final cloud = CloudDriveService.instance;
    final otp = cloud.currentStegano6DigitOtp;
    final remaining = cloud.remainingSeconds;
    final formattedOtp = otp.length == 6 ? '${otp.substring(0, 3)} ${otp.substring(3)}' : otp;

    return Dialog(
      backgroundColor: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24 * s)),
      child: Container(
        width: 600 * s,
        padding: EdgeInsets.all(22 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12 * s),
                  ),
                  child: Icon(Icons.cloud_circle_rounded, color: const Color(0xFF00F5D4), size: 24 * s),
                ),
                SizedBox(width: 14 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '☁️ Boardest Cloud 통합 설정',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 16.5 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${cloud.userEmail ?? "Google 계정 연동됨"} · 로그인 & 기기 관리 & 자동 OTP',
                        style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 11.5 * s),
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
            SizedBox(height: 16 * s),

            // 3-Tab Switcher
            Container(
              padding: EdgeInsets.all(4 * s),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Row(
                children: [
                  _buildSubTabButton(0, '🔐 내 계정 & OTP', s),
                  _buildSubTabButton(1, '📱 등록된 전자칠판', s),
                  _buildSubTabButton(2, '📡 다른 기기 OTP 주기', s),
                ],
              ),
            ),
            SizedBox(height: 16 * s),

            // Tab Content
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 460 * s),
              child: SingleChildScrollView(
                child: _currentSubTab == 0
                    ? _buildTab0AccountAndOtp(s, cloud, formattedOtp, remaining)
                    : _currentSubTab == 1
                        ? _buildTab1RegisteredDevices(s, cloud)
                        : _buildTab2AutoOtpToDevices(s, cloud),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabButton(int index, String label, double s) {
    final isSelected = _currentSubTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentSubTab = index),
        borderRadius: BorderRadius.circular(10 * s),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8 * s),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.transparent,
            borderRadius: BorderRadius.circular(10 * s),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.notoSansKr(
                color: isSelected ? Colors.black : Colors.white70,
                fontSize: 11.5 * s,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 탭 0: 계정 및 OTP 관리
  Widget _buildTab0AccountAndOtp(double s, CloudDriveService cloud, String formattedOtp, int remaining) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // OTP 대형 카드
        Container(
          padding: EdgeInsets.all(16 * s),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF003830).withOpacity(0.6),
                const Color(0xFF0D141C).withOpacity(0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18 * s),
            border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4), width: 1.2),
          ),
          child: Column(
            children: [
              Text('전자칠판 6자리 동적 보안 접속 코드', style: TextStyle(color: Colors.white70, fontSize: 11.5 * s)),
              SizedBox(height: 8 * s),
              Text(
                formattedOtp,
                style: GoogleFonts.outfit(
                  color: const Color(0xFF00F5D4),
                  fontSize: 36 * s,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4 * s,
                ),
              ),
              SizedBox(height: 8 * s),
              ClipRRect(
                borderRadius: BorderRadius.circular(4 * s),
                child: LinearProgressIndicator(
                  value: remaining / 60.0,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF00F5D4),
                  minHeight: 4 * s,
                ),
              ),
              SizedBox(height: 6 * s),
              Text('남은 시간: ${remaining}초 (매 분 위치 무작위 갱신)', style: TextStyle(color: Colors.white38, fontSize: 10 * s)),
            ],
          ),
        ),
        SizedBox(height: 14 * s),

        // 액션 버튼들 (재로그인, OTP 만료 및 새로 받기, QR 등록)
        Wrap(
          spacing: 8 * s,
          runSpacing: 8 * s,
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await CloudDriveService.instance.loginWithBrowserOAuth();
                if (mounted) setState(() {});
              },
              icon: Icon(Icons.refresh_rounded, size: 14 * s, color: Colors.black),
              label: Text('Google 계정 다시 로그인', style: TextStyle(fontSize: 11.5 * s, color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4)),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await CloudDriveService.instance.regenerateTotpSecret();
                if (mounted) setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔄 현재 기기 OTP 시크릿이 만료되고 새 키가 발급되었습니다!'), backgroundColor: Color(0xFF2EC4B6)),
                );
              },
              icon: Icon(Icons.lock_reset_rounded, size: 14 * s, color: Colors.orangeAccent),
              label: Text('현재 기기 OTP 만료 & 새로 받기', style: TextStyle(fontSize: 11.5 * s, color: Colors.orangeAccent)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orangeAccent)),
            ),
            OutlinedButton.icon(
              onPressed: () => _showGoogleOtpRegistrationDialog(s),
              icon: Icon(Icons.qr_code_scanner_rounded, size: 14 * s, color: Colors.white70),
              label: Text('Google OTP 앱 QR 등록', style: TextStyle(fontSize: 11.5 * s, color: Colors.white70)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
            ),
          ],
        ),
      ],
    );
  }

  // 탭 1: 등록된 기기 관리 & 취소
  Widget _buildTab1RegisteredDevices(double s, CloudDriveService cloud) {
    return FutureBuilder<List<dynamic>>(
      future: cloud.fetchDeviceListAndLogs().then((res) => (res['devices'] as List<dynamic>?) ?? <dynamic>[]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF00F5D4))));
        }
        final devices = snapshot.data ?? [];
        if (devices.isEmpty) {
          return Container(
            padding: EdgeInsets.all(24 * s),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.devices_other_rounded, size: 36 * s, color: Colors.white24),
                SizedBox(height: 8 * s),
                Text('등록된 신뢰 기기가 없습니다.', style: TextStyle(color: Colors.white38, fontSize: 12 * s)),
              ],
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: devices.length,
          separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 12 * s),
          itemBuilder: (context, idx) {
            final dev = devices[idx] as Map<String, dynamic>;
            final keyId = dev['keyId'] ?? dev['id'] ?? '';
            final display = dev['display'] ?? dev['classroomName'] ?? '전자칠판';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.tv_rounded, color: const Color(0xFF00F5D4), size: 22 * s),
              title: Text(display, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * s)),
              subtitle: Text('ID: $keyId', style: TextStyle(color: Colors.white38, fontSize: 10.5 * s)),
              trailing: ElevatedButton(
                onPressed: () async {
                  await cloud.removeDevice(keyId);
                  if (mounted) setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('🗑️ [$display] 기기 OTP 연결이 취소되었습니다.')),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.8)),
                child: Text('OTP 취소', style: TextStyle(color: Colors.white, fontSize: 11 * s)),
              ),
            );
          },
        );
      },
    );
  }

  // 탭 2: 다른 기기 OTP 주기 (실시간 온라인 기기만 표시)
  Widget _buildTab2AutoOtpToDevices(double s, CloudDriveService cloud) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '온라인 전자칠판을 선택하면 8자리 자동 OTP Secret을 즉시 직통 전송합니다.',
                style: TextStyle(color: Colors.white70, fontSize: 11.5 * s, height: 1.3),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4)),
              tooltip: '온라인 기기 새로고침',
              onPressed: () => setState(() {}),
            ),
          ],
        ),
        SizedBox(height: 8 * s),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchOnlineClassrooms(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: Color(0xFF00F5D4), strokeWidth: 2)));
            }
            final onlineRooms = snapshot.data ?? [];
            if (onlineRooms.isEmpty) {
              return Container(
                padding: EdgeInsets.all(24 * s),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 32 * s, color: Colors.white24),
                    SizedBox(height: 8 * s),
                    Text('현재 온라인인 전자칠판이 없습니다.', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * s, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4 * s),
                    Text('전자칠판 앱(Boardest)이 켜져 있으면 5분 이내 자동 감지됩니다.', style: TextStyle(color: Colors.white38, fontSize: 10 * s)),
                  ],
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: onlineRooms.length,
              separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 8 * s),
              itemBuilder: (ctx, idx) {
                final r = onlineRooms[idx];
                final name = (r['nickname'] ?? r['docId'] ?? '전자칠판').toString();
                final docId = (r['docId'] ?? '').toString();
                return ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 4 * s),
                  leading: Stack(
                    children: [
                      Icon(Icons.tv_rounded, color: const Color(0xFF00F5D4), size: 22 * s),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 7 * s,
                          height: 7 * s,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00F5D4),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(name, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5 * s)),
                  subtitle: Text('🟢 온라인 · ID: ' + docId, style: TextStyle(color: const Color(0xFF00F5D4), fontSize: 10 * s)),
                  trailing: ElevatedButton.icon(
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('📡 [' + name + '] 으로 자동 OTP Secret 발송 중...')),
                      );
                      bool ok = false;
                      try {
                        final res = await http.post(
                          Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/auto-otp'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'email': cloud.userEmail ?? 'teacher@boardest.bst',
                            'teacherName': cloud.userName ?? '선생님',
                            'fcmToken': docId,
                            'classId': docId,
                            'display': name,
                          }),
                        );
                        ok = (res.statusCode == 200);
                      } catch (_) {
                        ok = false;
                      }
                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('✅ [' + name + '] 에 8자리 자동 OTP Secret 등록 완료!'), backgroundColor: const Color(0xFF00F5D4)),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('❌ 발송 실패. 네트워크를 확인해주세요.'), backgroundColor: Colors.redAccent),
                        );
                      }
                    },
                    icon: Icon(Icons.send_rounded, size: 12 * s, color: Colors.black),
                    label: Text('8자리 전송', style: TextStyle(color: Colors.black, fontSize: 11 * s, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4)),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
