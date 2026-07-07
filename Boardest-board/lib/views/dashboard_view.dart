import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:ffi' hide Size;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../models/lesson.dart';
import '../models/app_settings.dart';
import '../services/comcigan_service.dart';
import '../services/storage_service.dart';
import '../services/neis_service.dart';
import '../services/system_app_scanner.dart';
import '../services/sleep_scheduler.dart';
import '../services/meal_call_service.dart';
import 'timetable_view.dart';
import 'boardest_pen_view.dart';
import 'setup_wizard_view.dart';
import 'weather_view.dart';
import 'school_calendar_view.dart';
import 'ppt_overlay_view.dart';
import 'pdf_board_view.dart';
import 'website_board_view.dart';
import '../services/usb_session_service.dart';
import '../services/app_paths.dart';
import '../services/board_storage_service.dart';
import '../services/bst_save_service.dart';
import '../widgets/calculator_modal.dart';
import '../widgets/notepad_modal.dart';
import '../widgets/usb_explorer.dart';
import '../services/auth_service.dart';
import '../services/local_server_service.dart';
import '../services/update_service.dart';

class PeriodTimeRange {
  final int period; // 0 for break/lunch, 1-8 for classes
  final String label;
  final DateTime start;
  final DateTime end;
  final bool isClass;

  PeriodTimeRange({
    required this.period,
    required this.label,
    required this.start,
    required this.end,
    required this.isClass,
  });
}

class DashboardView extends StatefulWidget {
  final String? initialTool;
  final bool pptFullscreen;
  const DashboardView({super.key, this.initialTool, this.pptFullscreen = false});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final ComciganService _comciganService = ComciganService();
  final StorageService _storageService = StorageService();
  final NeisService _neisService = NeisService();

  AppSettings _settings = AppSettings();
  TimetableResult? _timetableResult;
  bool _isLoading = true;
  String? _errorMessage;
  
  // Real-time states
  DateTime _now = DateTime.now();
  Timer? _timer;
  
  PeriodTimeRange? _currentPeriod;
  String _countdownTarget = '';
  String _countdownTime = '';
  double _periodProgress = 0.0;
  
  Lesson? _currentLesson;
  Lesson? _nextLesson;
  
  String _mealInfo = '급식 데이터를 불러오는 중...';
  bool _isLoadingMeal = true;
  List<Map<String, dynamic>> _apiScheduleEvents = [];

  DateTime? _debugTimeOverride;

  // USB & App layout state
  bool _isUsbConnected = false;
  bool _showFullUsbExplorer = false;
  String _usbDriveLetter = '';
  String _usbSessionId = ''; // USB 고유 세션 ID
  bool _debugUsbOverride = false;
  Timer? _usbTimer;
  bool _initialToolTriggered = false;
  List<String> _usbSortedFiles = [];
  bool _usbAutoOpenEnabled = true;
  bool _usbHandling = false;
  int _timetableCheckCounter = 0;
  int _onlineStatusCounter = 0;
  BoardestUser? _currentUser;

  // In-app premium floating mini widgets states
  bool _showMiniTimer = false;
  Offset _timerWindowOffset = const Offset(360, 200);
  bool _timerFullscreen = false;
  int _timerSecondsElapsed = 0;
  bool _timerRunning = false;
  Timer? _miniTimerInstance;

  bool _showMiniCalculator = false;
  Offset _calculatorWindowOffset = const Offset(500, 260);

  bool _showMiniPicker = false;
  Offset _pickerWindowOffset = const Offset(150, 100);
  int _pickerMaxStudents = 30;
  int? _pickerWinner;
  bool _pickerRolling = false;

  bool _showMiniWeather = false;
  Offset _weatherWindowOffset = const Offset(300, 100);

  bool _showMiniCalendar = false;
  Offset _calendarWindowOffset = const Offset(200, 80);
  DateTime _miniCalendarMonth = DateTime.now();

  bool _showMiniAppDrawer = false;
  Offset _appDrawerWindowOffset = const Offset(400, 120);
  String _appDrawerQuery = '';
  final TextEditingController _appDrawerSearchController = TextEditingController();
  bool _showWeeklyTimetableInCalendar = false;
  List<ScannedApp>? _cachedAppsList;
  bool _appsListLoading = false;
  final SleepSchedulerService _sleepScheduler = SleepSchedulerService();
  bool _showSleepWarning = false;
  int _sleepCountdownSeconds = 30;
  Timer? _sleepWarningTimer;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _loadPreferencesAndFetch();
    _preloadAppsList();
    // _startLocalServer(); // LAN 서버 가동 (연동 철회)

    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkAndUpdate(context);
    });


    // Register the platform channel listener for launch arguments (e.g. from single-instance deep linking)
    const channel = MethodChannel('com.boardest/launch_args');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewLaunchArgs') {
        final String? arg = call.arguments as String?;
        if (arg != null && mounted) {
          String? toolId;
          if (arg == '-board') {
            toolId = 'whiteboard';
          } else if (arg == '-timer') {
            toolId = 'timer';
          } else if (arg == '-picker') {
            toolId = 'picker';
          } else if (arg == '-weather') {
            toolId = 'weather';
          } else if (arg == '-calendar') {
            toolId = 'school_calendar';
          } else if (arg == '-ppt' || arg == '-ppt_board') {
            toolId = 'ppt_board';
          } else if (arg == '-pdf' || arg == '-pdf_board') {
            toolId = 'pdf_board';
          } else if (arg == '-site' || arg == '-website_board') {
            toolId = 'website_board';
          } else if (arg == '-calculator') {
            toolId = 'calculator';
          } else if (arg == '-notepad') {
            toolId = 'notepad';
          } else if (arg == '-dice') {
            toolId = 'dice';
          } else if (arg == '-timetable') {
            toolId = 'timetable';
          } else if (arg == '-noise') {
            toolId = 'noise';
          } else if (arg == '-settings') {
            toolId = 'settings';
          } else if (arg == '-apps' || arg == '-app_drawer') {
            toolId = 'app_drawer';
          } else if (arg == '-explorer' || arg == '-file_explorer') {
            toolId = 'file_explorer';
          }
          if (toolId != null) {
            final toolOnTap = _getToolOnTap(toolId);
            toolOnTap();
          }
        }
      }
      return null;
    });
    
    // USB logic is Windows-only. Keep APK builds free of USB polling and explorer flow.
    if (Platform.isWindows) {
      _checkUsbConnection();
      _usbTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        _checkUsbConnection();
      });
    }
  }

  @override
  void dispose() {
    // LocalServerService.instance.stop(); // LAN 서버 종료 (연동 철회)
    MealCallService.instance.stopListening();
    _timer?.cancel();
    _usbTimer?.cancel();
    _miniTimerInstance?.cancel();
    _sleepWarningTimer?.cancel();
    _sleepScheduler.dispose();
    _appDrawerSearchController.dispose();
    super.dispose();
  }

  Future<void> _preloadAppsList() async {
    if (_cachedAppsList != null || _appsListLoading) return;
    _appsListLoading = true;
    try {
      final apps = await SystemAppScanner.scanInstalledApps();
      if (mounted) {
        setState(() {
          _cachedAppsList = apps;
          _appsListLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _appsListLoading = false);
    }
  }

  List<SchedulePeriodRange> _scheduleRangesForSleep(DateTime now) {
    return buildScheduleRanges(_settings.timeSettings, now);
  }

  void _applyAutoSleepSchedule() {
    if (!Platform.isWindows || !_settings.autoSleepEnabled) {
      _sleepScheduler.disableAutoSleep();
      return;
    }
    final now = _debugTimeOverride ?? DateTime.now();
    final ranges = _scheduleRangesForSleep(now);
    _sleepScheduler.enableAutoSleep(ranges);
    _sleepScheduler.refreshRanges(ranges);
  }

  Future<void> _showAutoSleepSettingsDialog(double scale) async {
    var enabled = _settings.autoSleepEnabled;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '자동 절전 (Windows)',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '쉬는 시간·점심·하교 후 모니터를 끄고, 수업 교시가 시작되면 자동으로 켭니다.',
                style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * scale, height: 1.5),
              ),
              SizedBox(height: 12 * scale),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                activeThumbColor: const Color(0xFF2EC4B6),
                onChanged: (v) => setD(() => enabled = v),
                title: Text(
                  '자동 절전 사용',
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            TextButton(
              onPressed: () async {
                final updated = _settings.copyWith(autoSleepEnabled: enabled);
                await _storageService.saveSettings(updated);
                if (mounted) {
                  setState(() => _settings = updated);
                  _applyAutoSleepSchedule();
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('저장', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6))),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // USB 감지 + 스마트 세션
  // ══════════════════════════════════════════════

  void _checkUsbConnection() async {
    if (!Platform.isWindows) return;
    if (!mounted || _usbHandling) return;
    try {
      if (_debugUsbOverride) {
        final mockPath = Directory.current.path;
        if (!_isUsbConnected || _usbDriveLetter != mockPath) {
          if (!mounted) return;
          setState(() { _isUsbConnected = true; _usbDriveLetter = mockPath; });
          await _handleNewUsbConnected(mockPath);
        }
        return;
      }

      String? foundDrive;

      if (Platform.isWindows) {
        for (final letter in 'DEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
          final drive = '$letter:\\';
          final drivePtr = drive.toNativeUtf16();
          try {
            if (GetDriveType(drivePtr) == DRIVE_REMOVABLE) {
              foundDrive = drive;
              break;
            }
          } finally {
            calloc.free(drivePtr);
          }
        }
      } else if (Platform.isAndroid) {
        try {
          final dir = Directory('/storage');
          if (await dir.exists()) {
            await for (final entity in dir.list()) {
              final path = entity.path;
              final name = path.split('/').last.toLowerCase();
              if (name != 'self' &&
                  name != 'emulated' &&
                  !name.contains('knox') &&
                  !name.startsWith('.')) {
                foundDrive = path;
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('Android USB detection error: $e');
        }
      }

      if (!mounted) return;

      if (foundDrive != null) {
        if (!_isUsbConnected || _usbDriveLetter != foundDrive) {
          setState(() {
            _isUsbConnected = true;
            _usbDriveLetter = foundDrive!;
          });
          await _handleNewUsbConnected(foundDrive);
        }
      } else if (_isUsbConnected) {
        setState(() {
          _isUsbConnected = false;
          _usbDriveLetter = '';
          _usbSessionId = '';
        });
      }
    } catch (e, st) {
      debugPrint('USB check error: $e\n$st');
    }
  }

  Future<void> _handleNewUsbConnected(String usbRoot) async {
    if (!Platform.isWindows) return;
    if (!mounted || _usbHandling) return;
    _usbHandling = true;
    try {
    // 1. USB 고유 ID 획득
    final usbId = await UsbSessionService.getUsbSerialId(usbRoot) ?? usbRoot;
    if (!mounted) return;
    setState(() => _usbSessionId = usbId);

    // 2. 파일 스캔
    final schoolName = _settings.selectedSchool?.name ?? _settings.connectionName;
    final yearStr = DateTime.now().year.toString();
    final sortedFiles = await UsbSessionService.scanAndSortFiles(
      usbRoot,
      schoolName: schoolName,
      year: yearStr,
      grade: _settings.selectedGrade,
    );
    if (!mounted) return;
    if (sortedFiles.isEmpty) {
      setState(() {
        _usbSortedFiles = [];
      });
      return;
    }

    // 3. 기존 세션 확인
    final hasSession = await UsbSessionService.instance.hasSession(usbId);
    if (!mounted) return;
    bool autoOpen = true;
    if (!hasSession) {
      // 첫 번째 삽입: 세션 생성
      await UsbSessionService.instance.initSession(usbId, usbRoot, sortedFiles);
    } else {
      // 이후 삽입: 세션 업데이트
      await UsbSessionService.instance.updateSortedFiles(usbId, sortedFiles);
      if (!mounted) return;
      final session = await UsbSessionService.instance.getSession(usbId);
      autoOpen = session?.autoOpenEnabled ?? true;
    }

    if (!mounted) return;
    setState(() {
      _usbSortedFiles = sortedFiles;
      _usbAutoOpenEnabled = autoOpen;
    });

    // 4. 자동 열기 처리 (다이얼로그 팝업 없이 자동 실행!)
    if (autoOpen) {
      final lastFile = await UsbSessionService.instance.getLastOpenedFile(usbId);
      if (lastFile != null && sortedFiles.contains(lastFile)) {
        final state = await UsbSessionService.instance.getFileState(usbId, lastFile);
        final lastPage = state?.lastPage ?? 0;
        _openUsbFileWithSession(usbId, lastFile, lastPage);
      } else if (sortedFiles.isNotEmpty) {
        _openUsbFileWithSession(usbId, sortedFiles.first, 0);
      }
    }
    } finally {
      _usbHandling = false;
    }
  }

  // ── 첫 번째 삽입 다이얼로그 ────────────────────
  void _showUsbFirstTimeDialog(String usbId, List<String> sortedFiles) {
    final scale = _settings.scaleFactor;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20 * scale),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
          ),
          title: _usbDialogTitle('USB 수업 자료 감지', '파일을 선택해 주세요', scale),
          content: SizedBox(
            width: 420 * scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '수업 자료 ${sortedFiles.length}개를 찾았습니다. 어떤 자료를 열까요?',
                  style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale, height: 1.5),
                ),
                SizedBox(height: 12 * scale),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 240 * scale),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sortedFiles.length,
                    itemBuilder: (_, idx) => _buildFileListTile(
                      filePath: sortedFiles[idx],
                      scale: scale,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _openUsbFileWithSession(usbId, sortedFiles[idx], 0);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUsbExplorer(usbId);
              },
              child: Text('파일탐색기', style: GoogleFonts.notoSansKr(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('닫기', style: GoogleFonts.notoSansKr(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 재삽입 다이얼로그 (자동 열기) ──────────────
  void _showUsbReturnDialog(String usbId, List<String> sortedFiles, bool autoOpenEnabled) {
    final scale = _settings.scaleFactor;
    bool localAutoOpen = autoOpenEnabled;
    int countdown = 2;
    Timer? countdownTimer;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) {
          // 첫 build에서만 타이머 시작
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) async {
            if (countdown > 1) {
              setDState(() => countdown--);
            } else {
              t.cancel();
              if (!mounted) return;
              Navigator.of(ctx).pop();
              if (localAutoOpen) {
                await _openLastUsbFile(usbId);
              }
            }
          });

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AlertDialog(
              backgroundColor: const Color(0xFF16161A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20 * scale),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
              ),
              title: _usbDialogTitle(
                'USB 연결됨',
                localAutoOpen ? '⏱️ ${countdown}초 후 이전 자료 자동 열기' : '자동 열기 꺼짐',
                scale,
              ),
              content: SizedBox(
                width: 420 * scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 자동 열기 체크박스
                    InkWell(
                      onTap: () async {
                        setDState(() => localAutoOpen = !localAutoOpen);
                        await UsbSessionService.instance.setAutoOpen(usbId, localAutoOpen);
                        if (!localAutoOpen) countdownTimer?.cancel();
                      },
                      borderRadius: BorderRadius.circular(8 * scale),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8 * scale),
                        child: Row(
                          children: [
                            Checkbox(
                              value: !localAutoOpen,
                              onChanged: (v) async {
                                setDState(() => localAutoOpen = !(v ?? false));
                                await UsbSessionService.instance.setAutoOpen(usbId, localAutoOpen);
                                if (!localAutoOpen) countdownTimer?.cancel();
                              },
                              activeColor: Colors.redAccent,
                            ),
                            SizedBox(width: 4 * scale),
                            Text(
                              '다음 연결 시 자동 열기 사용 안 함',
                              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      '최근 자료 목록 (${sortedFiles.length}개)',
                      style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 11 * scale),
                    ),
                    SizedBox(height: 6 * scale),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 180 * scale),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: sortedFiles.length,
                        itemBuilder: (_, idx) => _buildFileListTileWithPage(
                          usbId: usbId,
                          filePath: sortedFiles[idx],
                          scale: scale,
                          onTap: () async {
                            countdownTimer?.cancel();
                            Navigator.of(ctx).pop();
                            final state = await UsbSessionService.instance.getFileState(usbId, sortedFiles[idx]);
                            _openUsbFileWithSession(usbId, sortedFiles[idx], state?.lastPage ?? 0);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    Navigator.of(ctx).pop();
                    _openUsbExplorer(usbId);
                  },
                  child: Text('파일탐색기', style: GoogleFonts.notoSansKr(color: Colors.white38)),
                ),
                TextButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    Navigator.of(ctx).pop();
                  },
                  child: Text('닫기', style: GoogleFonts.notoSansKr(color: Colors.white38)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2EC4B6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                  ),
                  onPressed: () async {
                    countdownTimer?.cancel();
                    Navigator.of(ctx).pop();
                    await _openLastUsbFile(usbId);
                  },
                  child: Text('이어서 열기', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) => countdownTimer?.cancel());
  }

  // ── 다음 파일 제안 다이얼로그 ─────────────────
  Future<bool> _openNextUsbFile(String usbId, String currentFilePath) async {
    final nextFile = await UsbSessionService.instance.findNextFile(usbId, currentFilePath);
    if (nextFile == null || !mounted) return false;
    await _openUsbFileWithSession(usbId, nextFile, 0);
    return true;
  }

  // ── 헬퍼: 마지막 파일 이어서 열기 ──────────────
  Future<void> _openLastUsbFile(String usbId) async {
    final lastFile = await UsbSessionService.instance.getLastOpenedFile(usbId);
    if (lastFile == null || !mounted) return;
    final state = await UsbSessionService.instance.getFileState(usbId, lastFile);
    final lastPage = state?.lastPage ?? 0;
    final totalPages = state?.totalPages ?? 1;

    // 마지막으로 저장된 페이지 == 마지막 페이지 → 다음 파일 열기
    if (UsbSessionService.instance.shouldOpenNextUsbFile(lastPage, totalPages)) {
      final nextFile = await UsbSessionService.instance.findNextFile(usbId, lastFile);
      if (nextFile != null && mounted) {
        await _openUsbFileWithSession(usbId, nextFile, 0);
        return;
      }
    }

    await _openUsbFileWithSession(usbId, lastFile, lastPage);
  }

  // ── 파일 열기 (세션 포함) ──────────────────────
  Future<void> _openUsbFileWithSession(String usbId, String filePath, int startPage) async {
    await UsbSessionService.instance.setLastOpenedFile(usbId, filePath);
    final ext = p.extension(filePath).toLowerCase();

    if (ext == '.pptx' || ext == '.ppt') {
      if (Platform.isAndroid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Android에서는 PPT 판서를 지원하지 않습니다.')),
        );
        return;
      }
      final shouldOpenNext = await _pushBoardRoute<bool>(PptOverlayView(
        initialFilePath: filePath,
        scaleFactor: _settings.scaleFactor,
        fullscreen: widget.pptFullscreen,
        usbSessionId: usbId,
        initialSlide: startPage,
        onLastSlideNext: (path) => _openNextUsbFile(usbId, path),
        onPageChanged: (path, page, total) async {
          await UsbSessionService.instance.updateFileState(usbId, path, page, total);
        },
      ));
      if (shouldOpenNext == true) {
        await _openNextUsbFile(usbId, filePath);
      }
      setState(() {});
    } else if (ext == '.pdf') {
      if (Platform.isWindows) {
        try {
          const channel = MethodChannel('com.boardest/launch_args');
          await channel.invokeMethod('restoreWindow');
        } catch (e) {
          debugPrint('Failed to restore window: $e');
        }
      }
      final shouldOpenNext = await _pushBoardRoute<bool>(PdfBoardView(
        initialFilePath: filePath,
        scaleFactor: _settings.scaleFactor,
        usbSessionId: usbId,
        initialPage: startPage,
        onLastPageNext: (path) => _openNextUsbFile(usbId, path),
        onPageChanged: (path, page, total) async {
          await UsbSessionService.instance.updateFileState(usbId, path, page, total);
        },
      ));
      if (shouldOpenNext == true) {
        await _openNextUsbFile(usbId, filePath);
      }
      setState(() {});
    } else if (['.mp4', '.mkv', '.avi', '.mov', '.wmv'].contains(ext)) {
      if (Platform.isWindows) {
        Process.run('explorer.exe', [filePath]);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('지원하지 않는 플랫폼 또는 파일 형식입니다.')),
        );
      }
    }
  }


  void _showUsbExplorerDialog() {
    final scale = _settings.scaleFactor;
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF13171F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.2),
          ),
          child: Container(
            width: 500 * scale,
            height: 600 * scale,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_open_rounded, color: const Color(0xFF00F5D4), size: 24 * scale),
                        const SizedBox(width: 8),
                        Text(
                          'USB 전체 파일 탐색기',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: UsbExplorer(
                    drivePath: _usbDriveLetter,
                    scaleFactor: scale,
                    onFileOpen: (filePath) async {
                      Navigator.pop(context); // Close explorer modal
                      int startPage = 0;
                      if (_usbSessionId.isNotEmpty) {
                        final state = await UsbSessionService.instance.getFileState(_usbSessionId, filePath);
                        startPage = state?.lastPage ?? 0;
                      }
                      _openUsbFileWithSession(_usbSessionId, filePath, startPage);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateOnlineStatusBackground() async {
    final user = await AuthService().getCurrentUser();
    if (user != null && user.email.isNotEmpty) {
      await AuthService().updateOnlineStatus(user.email);
    }
  }

  void _openUsbExplorer(String usbId) {
    if (!Platform.isWindows) return;
    final root = _usbDriveLetter.isNotEmpty ? _usbDriveLetter : '/';
    Process.run('explorer.exe', [root]);
  }

  // ── UI 헬퍼 ───────────────────────────────────
  Widget _usbDialogTitle(String title, String subtitle, double scale) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8 * scale),
          decoration: BoxDecoration(
            color: const Color(0xFF2EC4B6).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10 * scale),
          ),
          child: Icon(Icons.usb_rounded, color: const Color(0xFF2EC4B6), size: 22 * scale),
        ),
        SizedBox(width: 12 * scale),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 16 * scale, color: Colors.white)),
            Text(subtitle, style: GoogleFonts.notoSansKr(fontSize: 11 * scale, color: const Color(0xFF2EC4B6))),
          ],
        ),
      ],
    );
  }

  Widget _buildFileListTile({
    required String filePath,
    required double scale,
    required VoidCallback? onTap,
  }) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    IconData fileIcon = Icons.insert_drive_file_rounded;
    Color iconColor = const Color(0xFF7B61FF);
    if (ext == 'pptx' || ext == 'ppt') {
      fileIcon = Icons.slideshow_rounded;
      iconColor = const Color(0xFFFF8E3C);
    } else if (ext == 'pdf') {
      fileIcon = Icons.picture_as_pdf_rounded;
      iconColor = const Color(0xFFFF5E5B);
    } else if (['mp4', 'mkv', 'avi'].contains(ext)) {
      fileIcon = Icons.video_library_rounded;
      iconColor = const Color(0xFF2CB67D);
    }
    return Container(
      margin: EdgeInsets.only(bottom: 6 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(fileIcon, color: iconColor, size: 20 * scale),
        title: Text(p.basename(filePath), style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * scale, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: onTap != null ? Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 12 * scale) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildFileListTileWithPage({
    required String usbId,
    required String filePath,
    required double scale,
    required VoidCallback onTap,
  }) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    IconData fileIcon = Icons.insert_drive_file_rounded;
    Color iconColor = const Color(0xFF7B61FF);
    if (ext == 'pptx' || ext == 'ppt') { fileIcon = Icons.slideshow_rounded; iconColor = const Color(0xFFFF8E3C); }
    else if (ext == 'pdf') { fileIcon = Icons.picture_as_pdf_rounded; iconColor = const Color(0xFFFF5E5B); }
    else if (['mp4', 'mkv', 'avi'].contains(ext)) { fileIcon = Icons.video_library_rounded; iconColor = const Color(0xFF2CB67D); }

    return FutureBuilder<UsbFileState?>(
      future: UsbSessionService.instance.getFileState(usbId, filePath),
      builder: (_, snap) {
        final state = snap.data;
        final subtitle = state != null ? '마지막: ${state.lastPage + 1} / ${state.totalPages}쪽' : '저장 없음';
        return Container(
          margin: EdgeInsets.only(bottom: 6 * scale),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10 * scale),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: ListTile(
            dense: true,
            leading: Icon(fileIcon, color: iconColor, size: 20 * scale),
            title: Text(p.basename(filePath), style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * scale, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitle, style: GoogleFonts.outfit(color: Colors.white30, fontSize: 10 * scale)),
            trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 12 * scale),
            onTap: onTap,
          ),
        );
      },
    );
  }

  String _getPeriodTimeString(int period) {
    final ts = _settings.timeSettings;
    if (period == -1) {
      return '${ts.morningAssemblyStart} ~ ${ts.morningAssemblyEnd}';
    }
    if (period == -2) {
      return '${ts.afternoonAssemblyStart} ~ ${ts.afternoonAssemblyEnd}';
    }

    final timeParts = ts.firstPeriodStart.split(':');
    final startH = int.tryParse(timeParts[0]) ?? 8;
    final startM = int.tryParse(timeParts[1]) ?? 40;
    int currentMinutes = startH * 60 + startM;

    for (int p = 1; p <= 8; p++) {
      int startMin = currentMinutes;
      int endMin = currentMinutes + ts.lessonDuration;
      if (p == period) {
        final sH = startMin ~/ 60;
        final sM = startMin % 60;
        final eH = endMin ~/ 60;
        final eM = endMin % 60;
        return '${sH.toString().padLeft(2, '0')}:${sM.toString().padLeft(2, '0')} ~ ${eH.toString().padLeft(2, '0')}:${eM.toString().padLeft(2, '0')}';
      }
      currentMinutes += ts.lessonDuration;
      if (p == ts.lunchAfterPeriod) {
        currentMinutes += ts.lunchDuration;
      } else {
        currentMinutes += ts.breakDuration;
      }
    }
    return '';
  }

  Future<bool> _fetchTimetableWithRetry(int schoolCode, DateTime targetDate) async {
    final weekOffset = _getWeekOffset(targetDate, DateTime.now());
    try {
      final rawData = await _comciganService.fetchTimetableRaw(schoolCode, weekOffset: weekOffset);
      final result = _comciganService.parseTimetable(rawData);
      
      final cacheKey = 'cached_timetable_${schoolCode}_$weekOffset';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, json.encode(rawData));
      
      if (mounted) {
        setState(() {
          _timetableResult = result;
        });
        _updateLiveSchedule();
      }
      return true;
    } catch (e) {
      debugPrint('[Boardest] fetchTimetableRaw failed: $e');
      return false;
    }
  }

  Future<bool> _fetchLunchMenuWithRetry(String schoolName, DateTime targetDate) async {
    try {
      final meal = await _neisService.fetchTodayMeal(schoolName, targetDate);
      if (mounted) {
        setState(() {
          _mealInfo = meal;
          _isLoadingMeal = false;
        });
      }
      return true;
    } catch (e) {
      debugPrint('[Boardest] fetchTodayMeal failed: $e');
      return false;
    }
  }

  Future<bool> _fetchSchoolScheduleWithRetry(String schoolName, DateTime targetDate) async {
    try {
      final todayStart = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final events = await _neisService.fetchSchoolSchedule(schoolName, todayStart);
      if (mounted) {
        setState(() {
          _apiScheduleEvents = events;
        });
      }
      return true;
    } catch (e) {
      debugPrint('[Boardest] fetchSchoolSchedule failed: $e');
      return false;
    }
  }

  Future<void> _loadAndroidDataWithRetry(String schoolName, int schoolCode, DateTime targetDate) async {
    final startTime = DateTime.now();
    bool timetableSuccess = false;
    bool lunchSuccess = false;
    bool scheduleSuccess = false;

    final weekOffset = _getWeekOffset(targetDate, DateTime.now());
    final cacheKey = 'cached_timetable_${schoolCode}_$weekOffset';
    final prefs = await SharedPreferences.getInstance();
    final cachedStr = prefs.getString(cacheKey);
    if (cachedStr != null && mounted) {
      try {
        final cachedData = json.decode(cachedStr) as Map<String, dynamic>;
        final result = _comciganService.parseTimetable(cachedData);
        setState(() {
          _timetableResult = result;
        });
        _updateLiveSchedule();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _mealInfo = '불러오는 중...';
        _isLoadingMeal = true;
      });
    }

    while (mounted) {
      if (!timetableSuccess) {
        timetableSuccess = await _fetchTimetableWithRetry(schoolCode, targetDate);
      }
      if (!lunchSuccess) {
        lunchSuccess = await _fetchLunchMenuWithRetry(schoolName, targetDate);
      }
      if (!scheduleSuccess) {
        scheduleSuccess = await _fetchSchoolScheduleWithRetry(schoolName, targetDate);
      }

      final elapsed = DateTime.now().difference(startTime).inSeconds;
      if ((timetableSuccess && lunchSuccess && scheduleSuccess) || elapsed >= 30) {
        break;
      }
      await Future.delayed(const Duration(seconds: 5));
    }

    if (!timetableSuccess && mounted && _timetableResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('시간표 데이터를 가져오지 못했습니다. 네트워크 연결을 확인해 주세요.'),
          backgroundColor: Color(0xFFEF4565),
          duration: Duration(seconds: 4),
        ),
      );
    }
    if (!lunchSuccess && mounted) {
      setState(() {
        _mealInfo = '급식 정보를 불러올 수 없습니다.';
        _isLoadingMeal = false;
      });
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _applyAutoSleepSchedule();
      _startDashboardTimer();
      
      if (!_initialToolTriggered && widget.initialTool != null) {
        _initialToolTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final toolOnTap = _getToolOnTap(widget.initialTool!);
          toolOnTap();
        });
      }
    }
  }

  Future<void> _loadPreferencesAndFetch() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      AppSettings? settings;
      try {
        settings = await _storageService.getSettings();
        if (settings == null) {
          throw Exception('Settings null after loading');
        }
        setState(() {
          _settings = settings!;
        });

        // Apply Special Classroom Mode on startup/load
        if (Platform.isWindows) {
          const channel = MethodChannel('com.boardest/launch_args');
          try {
            channel.invokeMethod('setSpecialClassroomMode', _settings.specialClassroomMode);
          } catch (e) {
            debugPrint('Failed to apply special classroom mode on startup: $e');
          }
        }

        // 백그라운드에서 저장된 슬롯의 누락된 아이콘 경로 자동 복구
        if (Platform.isWindows) {
          final loadedSettings = settings;
          SystemAppScanner.scanInstalledApps().then((scannedList) {
            bool needUpdate = false;
            final scannedIconMap = <String, String>{};
            for (final app in scannedList) {
              if (app.iconPath != null) {
                scannedIconMap[app.appId] = app.iconPath!;
              }
            }
            
            final updatedSlots = loadedSettings.launcherSlots.map((slot) {
              if (slot.type == LauncherSlotType.systemApp && (slot.iconPath == null || slot.iconPath!.isEmpty)) {
                final newIcon = scannedIconMap[slot.id];
                if (newIcon != null) {
                  needUpdate = true;
                  return LauncherSlot(
                    type: slot.type,
                    name: slot.name,
                    id: slot.id,
                    iconPath: newIcon,
                  );
                }
              }
              return slot;
            }).toList();

            if (needUpdate) {
              final updatedSettings = loadedSettings.copyWith(launcherSlots: updatedSlots);
              _storageService.saveSettings(updatedSettings).then((_) {
                if (mounted) {
                  setState(() {
                    _settings = updatedSettings;
                  });
                }
              }).catchError((e) {
                debugPrint('Error saving auto-restored launcher icons: $e');
              });
            }
          }).catchError((err) {
            debugPrint('Error scanning installed apps in dashboard: $err');
          });
        }
      } catch (e) {
        debugPrint('Error loading settings: $e');
        setState(() {
          _errorMessage = '설정 정보를 불러오지 못했습니다. 초기 설정을 다시 실행해주세요.';
          _isLoading = false;
        });
        return;
      }

      if (settings == null || settings.selectedSchool == null) {
        setState(() {
          _errorMessage = '학교 설정이 완료되지 않았습니다.';
          _isLoading = false;
        });
        return;
      }

      _startMealCallListener(settings);

      final schoolName = settings.selectedSchool!.name;
      final schoolCode = settings.selectedSchool!.code;
      final targetDate = _debugTimeOverride ?? DateTime.now();

      if (Platform.isAndroid) {
        _loadAndroidDataWithRetry(schoolName, schoolCode, targetDate);
        return;
      }

      // 1. Fetch Timetable with Offline Cache Fallback
      try {
        final weekOffset = _getWeekOffset(targetDate, DateTime.now());
        final cacheKey = 'cached_timetable_${schoolCode}_$weekOffset';
        
        try {
          final rawData = await _comciganService.fetchTimetableRaw(schoolCode, weekOffset: weekOffset);
          final result = _comciganService.parseTimetable(rawData);
          
          // Save to persistent cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(cacheKey, json.encode(rawData));
          
          if (mounted) {
            setState(() {
              _timetableResult = result;
            });
            _updateLiveSchedule();
          }
        } catch (e) {
          debugPrint('Error loading timetable raw data, attempting to load from cache: $e');
          
          // Attempt loading from local persistent cache
          final prefs = await SharedPreferences.getInstance();
          final cachedStr = prefs.getString(cacheKey);
          if (cachedStr != null) {
            final cachedData = json.decode(cachedStr) as Map<String, dynamic>;
            final result = _comciganService.parseTimetable(cachedData);
            if (mounted) {
              setState(() {
                _timetableResult = result;
              });
              _updateLiveSchedule();
              
              // Notify user that cached data is being displayed
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('네트워크 불안정으로 인해 마지막으로 저장된 시간표를 불러왔습니다.'),
                  backgroundColor: Color(0xFF7F5AF0),
                  duration: Duration(seconds: 4),
                ),
              );
            }
          } else {
            // No cached data exists, but we DO NOT show a full-screen _errorMessage that blocks the entire app!
            // Instead, we just let _timetableResult be null, keeping other panels active.
            debugPrint('No cached timetable found.');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('시간표 데이터를 가져오지 못했습니다. 네트워크 연결을 확인해 주세요.'),
                  backgroundColor: Color(0xFFEF4565),
                  duration: Duration(seconds: 4),
                ),
              );
            }
          }
        }
      } catch (outerErr) {
        debugPrint('Fatal error in timetable section: $outerErr');
      }

      // 2. Fetch school lunch & schedule
      try {
        _fetchLunchMenu(schoolName, targetDate);
        _fetchSchoolSchedule(schoolName, targetDate);
      } catch (e) {
        debugPrint('Error fetching lunch or schedule: $e');
      }

      setState(() {
        _isLoading = false;
      });

      _applyAutoSleepSchedule();
      _startDashboardTimer();

      if (!_initialToolTriggered && widget.initialTool != null) {
        _initialToolTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final toolOnTap = _getToolOnTap(widget.initialTool!);
          toolOnTap();
        });
      }
    } catch (e) {
      debugPrint('Fatal error in _loadPreferencesAndFetch: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '앱에 오류가 발생했습니다. 앱을 재시작해주세요.';
          _isLoading = false;
        });
      }
    }
  }

  void _startMealCallListener(AppSettings settings) {
    // 특별실 모드일 때는 Firebase 구독(급식실, 메시지 등)을 절대 시작하지 않음 (로컬 연동만 허용)
    if (settings.specialClassroomMode) {
      debugPrint('[Firebase] 특별실 모드이므로 Firebase 리스너를 시작하지 않습니다.');
      return;
    }
    if (settings.connectionName.isEmpty && settings.selectedSchool == null) return;
    
    MealCallService.instance.startListening(
      settings,
      onCall: () {
        if (!mounted) return;
        _showMealCallNotificationAlert();
      },
      onMessage: (message, from) {
        if (!mounted) return;
        _showMessageNotificationAlert(message, from);
      },
      onStudentCall: (message, from) {
        if (!mounted) return;
        _showStudentCallNotificationAlert(message, from);
      },
    );
  }

  void _showMessageNotificationAlert(String message, String from) {
    if (MealCallService.instance.isPopupShowing) return;
    MealCallService.instance.isPopupShowing = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'MessageAlert',
      barrierColor: Colors.black.withAlpha(220),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        final scale = _settings.scaleFactor;
        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: ScaleTransition(
              scale: anim1,
              child: Container(
                width: 480 * scale,
                padding: EdgeInsets.all(32 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(24 * scale),
                  border: Border.all(color: const Color(0xFF7F5AF0), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7F5AF0).withAlpha(100),
                      blurRadius: 30 * scale,
                      spreadRadius: 4 * scale,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80 * scale,
                      height: 80 * scale,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7F5AF0).withAlpha(38),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.message_rounded,
                        color: const Color(0xFF7F5AF0),
                        size: 38 * scale,
                      ),
                    ),
                    SizedBox(height: 24 * scale),
                    Text(
                      '선생님 메시지 알림',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 22 * scale,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (from.isNotEmpty) ...[
                      SizedBox(height: 6 * scale),
                      Text(
                        '보낸 사람: $from 선생님',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF7F5AF0),
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                    SizedBox(height: 20 * scale),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 15 * scale,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    SizedBox(height: 32 * scale),
                    SizedBox(
                      width: double.infinity,
                      height: 48 * scale,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7F5AF0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12 * scale),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          await MealCallService.instance.clearMessage();
                        },
                        child: Text(
                          '확인',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showStudentCallNotificationAlert(String message, String from) {
    if (MealCallService.instance.isPopupShowing) return;
    MealCallService.instance.isPopupShowing = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'StudentCallAlert',
      barrierColor: Colors.black.withAlpha(220),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        final scale = _settings.scaleFactor;
        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: ScaleTransition(
              scale: anim1,
              child: Container(
                width: 480 * scale,
                padding: EdgeInsets.all(32 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(24 * scale),
                  border: Border.all(color: const Color(0xFFFF8E3C), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF8E3C).withAlpha(100),
                      blurRadius: 30 * scale,
                      spreadRadius: 4 * scale,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80 * scale,
                      height: 80 * scale,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8E3C).withAlpha(38),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.campaign_rounded,
                        color: const Color(0xFFFF8E3C),
                        size: 42 * scale,
                      ),
                    ),
                    SizedBox(height: 24 * scale),
                    Text(
                      '학생 호출 알림',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 22 * scale,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (from.isNotEmpty) ...[
                      SizedBox(height: 6 * scale),
                      Text(
                        '호출인: $from 선생님',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFFFF8E3C),
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                    SizedBox(height: 20 * scale),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 15 * scale,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    SizedBox(height: 32 * scale),
                    SizedBox(
                      width: double.infinity,
                      height: 48 * scale,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8E3C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12 * scale),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          await MealCallService.instance.clearStudentCall();
                        },
                        child: Text(
                          '확인',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMealCallNotificationAlert() {
    if (MealCallService.instance.isPopupShowing) return;
    MealCallService.instance.isPopupShowing = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'MealCallAlert',
      barrierColor: Colors.black.withAlpha(220),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        final scale = _settings.scaleFactor;
        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: ScaleTransition(
              scale: anim1,
              child: Container(
                width: 480 * scale,
                padding: EdgeInsets.all(32 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(24 * scale),
                  border: Border.all(color: const Color(0xFF00F5D4), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F5D4).withAlpha(100),
                      blurRadius: 30 * scale,
                      spreadRadius: 4 * scale,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80 * scale,
                      height: 80 * scale,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withAlpha(38),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.restaurant_menu_rounded,
                        color: const Color(0xFF00F5D4),
                        size: 40 * scale,
                      ),
                    ),
                    SizedBox(height: 24 * scale),
                    Text(
                      '급식실 호출 알림',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 22 * scale,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    SizedBox(height: 16 * scale),
                    Text(
                      '점심 먹을 시간입니다.\n급식실로 와주세요.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white70,
                        fontSize: 16 * scale,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    SizedBox(height: 32 * scale),
                    SizedBox(
                      width: double.infinity,
                      height: 48 * scale,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F5D4),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12 * scale),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          await MealCallService.instance.clearMealCall();
                        },
                        child: Text(
                          '확인',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _getWeekOffset(DateTime debugDate, DateTime currentDate) {
    DateTime getMonday(DateTime date) {
      return DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));
    }
    final debugMonday = getMonday(debugDate);
    final currentMonday = getMonday(currentDate);
    final diffDays = debugMonday.difference(currentMonday).inDays;
    return (diffDays / 7).round();
  }

  Future<void> _fetchLunchMenu(String schoolName, DateTime date) async {
    setState(() {
      _isLoadingMeal = true;
    });
    try {
      final meal = await _neisService.fetchTodayMeal(schoolName, date);
      if (mounted) {
        setState(() {
          _mealInfo = meal;
          _isLoadingMeal = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching lunch menu: $e');
      if (mounted) {
        setState(() {
          _mealInfo = '급식 정보를 불러올 수 없습니다.';
          _isLoadingMeal = false;
        });
      }
    }
  }

  Future<void> _fetchSchoolSchedule(String schoolName, DateTime startDate) async {
    try {
      final todayStart = DateTime(startDate.year, startDate.month, startDate.day);
      final events = await _neisService.fetchSchoolSchedule(schoolName, todayStart);
      if (mounted) {
        setState(() {
          _apiScheduleEvents = events;
        });
      }
    } catch (e) {
      debugPrint('Error fetching school schedule: $e');
    }
  }

  List<DDayEvent> get _schoolScheduleDdayEvents {
    final events = <DDayEvent>[];
    for (final raw in _apiScheduleEvents) {
      final title = raw['title'] as String?;
      final date = raw['date'] as DateTime?;
      if (title != null && title.isNotEmpty && date != null) {
        events.add(DDayEvent(title: title, date: date));
      }
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  DateTime get _todayDateOnly =>
      DateTime(_now.year, _now.month, _now.day);

  String _ddayCountLabel(DateTime eventDate) {
    final day = DateTime(eventDate.year, eventDate.month, eventDate.day);
    final diff = day.difference(_todayDateOnly).inDays;
    if (diff == 0) return 'D-Day';
    if (diff > 0) return 'D-$diff';
    return 'D+${diff.abs()}';
  }

  DDayEvent? get _activeDdayEvent {
    if (_settings.pinnedDday != null) {
      return _settings.pinnedDday;
    }
    final upcoming = _schoolScheduleDdayEvents.where((e) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      return !d.isBefore(_todayDateOnly);
    }).toList();
    if (upcoming.isNotEmpty) return upcoming.first;
    if (_settings.ddayEvents.isNotEmpty) {
      final manual = _settings.ddayEvents.where((e) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        return !d.isBefore(_todayDateOnly);
      }).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (manual.isNotEmpty) return manual.first;
      return _settings.ddayEvents.first;
    }
    return null;
  }

  bool _isSameDday(DDayEvent? a, DDayEvent b) {
    if (a == null) return false;
    return a.title == b.title &&
        a.date.year == b.date.year &&
        a.date.month == b.date.month &&
        a.date.day == b.date.day;
  }

  Future<void> _pinDday(DDayEvent? event, {bool clearPin = false}) async {
    final updated = _settings.copyWith(
      pinnedDday: event,
      clearPinnedDday: clearPin,
    );
    await _storageService.saveSettings(updated);
    if (mounted) setState(() => _settings = updated);
  }

  List<Lesson> _getLessonsForDay(int day) {
    if (_timetableResult == null) return [];
    
    if (_settings.specialClassroomMode) {
      final teacherName = _settings.selectedTeacher.replaceAll('*', '').trim();
      if (teacherName.isEmpty) return [];

      final rawLessons = _timetableResult!.lessons.where((lesson) {
        return lesson.weekday == day &&
            lesson.teacher.replaceAll('*', '').trim() == teacherName;
      }).toList();

      if (rawLessons.isEmpty) return [];

      // 특별실을 거쳐가는 모든 학급(학년-반) 정보 추출
      final classes = rawLessons.map((l) => '${l.grade}-${l.classNum}').toSet();

      // 그 학급들 중 오늘 가장 늦게 끝나는 반의 마지막 교시 찾기
      int maxPeriod = 0;
      for (final lesson in _timetableResult!.lessons) {
        if (lesson.weekday == day && classes.contains('${lesson.grade}-${lesson.classNum}')) {
          if (lesson.classTime > maxPeriod) {
            maxPeriod = lesson.classTime;
          }
        }
      }

      if (maxPeriod == 0) maxPeriod = 7; // 기본 백업

      // 1교시부터 maxPeriod까지 채우기
      List<Lesson> filledLessons = [];
      for (int period = 1; period <= maxPeriod; period++) {
        final lesson = rawLessons.firstWhere(
          (l) => l.classTime == period,
          orElse: () => Lesson(
            grade: 0,
            classNum: 0,
            weekday: day,
            classTime: period,
            subject: '',
            teacher: '',
            classroom: '',
            isChanged: false,
          ),
        );
        
        if (lesson.grade == 0) {
          filledLessons.add(lesson);
        } else {
          filledLessons.add(Lesson(
            grade: lesson.grade,
            classNum: lesson.classNum,
            weekday: lesson.weekday,
            classTime: lesson.classTime,
            subject: lesson.subject,
            teacher: '${lesson.grade}-${lesson.classNum}',
            classroom: lesson.classroom,
            isChanged: lesson.isChanged,
          ));
        }
      }
      return filledLessons;
    } else {
      final rawLessons = _timetableResult!.lessons.where((lesson) {
        return lesson.grade == _settings.selectedGrade &&
            lesson.classNum == _settings.selectedClass &&
            lesson.weekday == day;
      }).toList();

      if (rawLessons.isEmpty) return [];

      int maxPeriod = 0;
      for (final l in rawLessons) {
        if (l.classTime > maxPeriod) {
          maxPeriod = l.classTime;
        }
      }
      if (maxPeriod == 0) maxPeriod = 7;

      List<Lesson> filledLessons = [];
      for (int period = 1; period <= maxPeriod; period++) {
        final lesson = rawLessons.firstWhere(
          (l) => l.classTime == period,
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
        
        if (lesson.subject.isEmpty) {
          filledLessons.add(lesson);
        } else {
          filledLessons.add(Lesson(
            grade: lesson.grade,
            classNum: lesson.classNum,
            weekday: lesson.weekday,
            classTime: lesson.classTime,
            subject: lesson.subject,
            teacher: AppSettings.formatTeacherDisplayName(lesson.teacher),
            classroom: lesson.classroom,
            isChanged: lesson.isChanged,
          ));
        }
      }
      return filledLessons;
    }
  }

  Lesson _emptyLesson(int period, int weekday) {
    return Lesson(
      grade: _settings.selectedGrade,
      classNum: _settings.selectedClass,
      weekday: weekday,
      classTime: period,
      subject: '',
      teacher: '',
      classroom: '',
      isChanged: false,
    );
  }

  List<PeriodTimeRange> _generatePeriodRanges(TimeSettings ts, DateTime now) {
    final List<PeriodTimeRange> ranges = [];

    // Parse morning assembly
    try {
      final morningBefore = ts.morningAssemblyBeforeMinutes;
      if (morningBefore != null) {
        // Relative mode: starts at firstPeriodStart - morningBefore minutes, duration is in morningAssemblyEnd
        final timeParts = ts.firstPeriodStart.split(':');
        final startH = int.tryParse(timeParts[0]) ?? 8;
        final startM = int.tryParse(timeParts.length > 1 ? timeParts[1] : '40') ?? 40;
        final classStart = DateTime(now.year, now.month, now.day, startH, startM);

        final morningStart = classStart.subtract(Duration(minutes: morningBefore));
        final durationMinutes = int.tryParse(ts.morningAssemblyEnd) ?? morningBefore;
        final morningEnd = morningStart.add(Duration(minutes: durationMinutes));

        ranges.add(PeriodTimeRange(
          period: -1,
          label: '조회 시간',
          start: morningStart,
          end: morningEnd,
          isClass: false,
        ));
      } else {
        // Fixed mode
        final morningPartsStart = ts.morningAssemblyStart.split(':');
        final morningHStart = int.tryParse(morningPartsStart[0]) ?? 8;
        final morningMStart = int.tryParse(morningPartsStart[1]) ?? 25;

        final morningPartsEnd = ts.morningAssemblyEnd.split(':');
        final morningHEnd = int.tryParse(morningPartsEnd[0]) ?? 8;
        final morningMEnd = int.tryParse(morningPartsEnd[1]) ?? 40;

        final morningStart = DateTime(now.year, now.month, now.day, morningHStart, morningMStart);
        final morningEnd = DateTime(now.year, now.month, now.day, morningHEnd, morningMEnd);

        ranges.add(PeriodTimeRange(
          period: -1,
          label: '조회 시간',
          start: morningStart,
          end: morningEnd,
          isClass: false,
        ));
      }
    } catch (_) {}

    // Parse classes
    final timeParts = ts.firstPeriodStart.split(':');
    final startH = int.tryParse(timeParts[0]) ?? 8;
    final startM = int.tryParse(timeParts.length > 1 ? timeParts[1] : '40') ?? 40;
    int currentMinutes = startH * 60 + startM;

    final weekday = now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    final displayWeekday = isWeekend ? 1 : weekday;
    final lessons = _getLessonsForDay(displayWeekday);
    int maxPeriod = 7;
    if (lessons.isNotEmpty) {
      final activeLessons = lessons.where((l) => l.subject.trim().isNotEmpty);
      if (activeLessons.isNotEmpty) {
        maxPeriod = activeLessons.map((l) => l.classTime).reduce((a, b) => a > b ? a : b);
      } else {
        maxPeriod = lessons.map((l) => l.classTime).reduce((a, b) => a > b ? a : b);
      }
    }
    if (maxPeriod < 4) maxPeriod = 7;

    for (int p = 1; p <= maxPeriod; p++) {
      final classStart = DateTime(now.year, now.month, now.day, currentMinutes ~/ 60, currentMinutes % 60);
      currentMinutes += ts.lessonDuration;
      final classEnd = DateTime(now.year, now.month, now.day, currentMinutes ~/ 60, currentMinutes % 60);

      ranges.add(PeriodTimeRange(
        period: p,
        label: '$p교시',
        start: classStart,
        end: classEnd,
        isClass: true,
      ));

      // Add lunch break after lunchAfterPeriod
      if (p == ts.lunchAfterPeriod) {
        final lunchStart = classEnd;
        final lunchEnd = lunchStart.add(Duration(minutes: ts.lunchDuration));
        ranges.add(PeriodTimeRange(
          period: 0,
          label: '점심 시간',
          start: lunchStart,
          end: lunchEnd,
          isClass: false,
        ));
        currentMinutes += ts.lunchDuration;
      } else if (p < maxPeriod) {
        // Add break between classes, but NOT after the last period
        final breakStart = classEnd;
        final breakEnd = breakStart.add(Duration(minutes: ts.breakDuration));
        ranges.add(PeriodTimeRange(
          period: 0,
          label: '쉬는 시간',
          start: breakStart,
          end: breakEnd,
          isClass: false,
        ));
        currentMinutes += ts.breakDuration;
      }
    }

    // Parse afternoon assembly - support relative mode (minutes after last period)
    try {
      final afterMinutes = ts.afternoonAssemblyAfterMinutes;
      if (afterMinutes != null) {
        // Relative: lastPeriodEnd + afterMinutes
        final afternoonStart = DateTime(now.year, now.month, now.day, currentMinutes ~/ 60, currentMinutes % 60)
            .add(Duration(minutes: afterMinutes));
        // afternoonAssemblyEnd holds duration as plain int string when relative mode
        final durationMinutes = int.tryParse(ts.afternoonAssemblyEnd) ?? 20;
        final afternoonEnd = afternoonStart.add(Duration(minutes: durationMinutes));
        ranges.add(PeriodTimeRange(
          period: -2,
          label: '종례 시간',
          start: afternoonStart,
          end: afternoonEnd,
          isClass: false,
        ));
      } else {
        final afternoonPartsStart = ts.afternoonAssemblyStart.split(':');
        final afternoonHStart = int.tryParse(afternoonPartsStart[0]) ?? 16;
        final afternoonMStart = int.tryParse(afternoonPartsStart.length > 1 ? afternoonPartsStart[1] : '10') ?? 10;
        final afternoonPartsEnd = ts.afternoonAssemblyEnd.split(':');
        final afternoonHEnd = int.tryParse(afternoonPartsEnd[0]) ?? 16;
        final afternoonMEnd = int.tryParse(afternoonPartsEnd.length > 1 ? afternoonPartsEnd[1] : '30') ?? 30;
        final afternoonStart = DateTime(now.year, now.month, now.day, afternoonHStart, afternoonMStart);
        final afternoonEnd = DateTime(now.year, now.month, now.day, afternoonHEnd, afternoonMEnd);
        ranges.add(PeriodTimeRange(
          period: -2,
          label: '종례 시간',
          start: afternoonStart,
          end: afternoonEnd,
          isClass: false,
        ));
      }
    } catch (_) {}

    // Sort ranges by start time
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  void _updateLiveSchedule() {
    if (_timetableResult == null) return;

    final now = _debugTimeOverride ?? DateTime.now();
    final weekday = now.weekday;
    
    // Weekend displays Monday schedule as preview
    final isWeekend = weekday == 6 || weekday == 7;
    final displayWeekday = isWeekend ? 1 : weekday;
    final lessons = _getLessonsForDay(displayWeekday);

    final ts = _settings.timeSettings;
    final ranges = _generatePeriodRanges(ts, now);

    PeriodTimeRange? activeRange;
    if (!isWeekend) {
      for (final r in ranges) {
        if ((now.isAfter(r.start) || now.isAtSameMomentAs(r.start)) && now.isBefore(r.end)) {
          activeRange = r;
          break;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _now = now;
      
      if (activeRange != null) {
        final active = activeRange;
        _currentPeriod = active;
        final remaining = active.end.difference(now);
        final totalSec = active.end.difference(active.start).inSeconds;
        final elapsedSec = now.difference(active.start).inSeconds;
        
        _periodProgress = (elapsedSec / totalSec).clamp(0.0, 1.0);
        
        if (active.isClass) {
          _countdownTarget = '${active.label} 종료까지';
        } else if (active.period == -1) {
          _countdownTarget = '조회 종료까지';
        } else if (active.period == -2) {
          _countdownTarget = '종례 종료까지';
        } else {
          _countdownTarget = '${active.label} 종료까지';
        }
        
        final hours = remaining.inHours;
        final mins = remaining.inMinutes % 60;
        _countdownTime = '$hours시간 $mins분';

        if (active.isClass) {
          _currentLesson = lessons.firstWhere(
            (l) => l.classTime == active.period,
            orElse: () => _emptyLesson(active.period, displayWeekday),
          );
          
          _nextLesson = lessons.firstWhere(
            (l) => l.classTime > active.period && l.subject.isNotEmpty,
            orElse: () => null,
          );
        } else {
          _currentLesson = null;
          final nextClassRanges = ranges.where((r) => r.isClass && r.start.isAfter(now));
          final nextClassRange = nextClassRanges.isNotEmpty ? nextClassRanges.first : null;
          if (nextClassRange != null) {
            _nextLesson = lessons.firstWhere(
              (l) => l.classTime >= nextClassRange.period && l.subject.isNotEmpty,
              orElse: () => null,
            );
          } else {
            _nextLesson = null;
          }
        }
      } else {
        // Outside school hours or in a gap
        _currentPeriod = null;
        _currentLesson = null;
        _periodProgress = 0.0;

        final nextRanges = ranges.where((r) => r.start.isAfter(now));
        if (nextRanges.isNotEmpty && !isWeekend) {
          // We are in a gap before some event today (e.g. before school, or break time)
          final nextR = nextRanges.first;
          final diff = nextR.start.difference(now);
          if (nextR.period == -1) {
            _countdownTarget = '조회 시작까지';
          } else if (nextR.period == -2) {
            _countdownTarget = '종례 시작까지';
          } else {
            _countdownTarget = '${nextR.label} 시작까지';
          }
          final hours = diff.inHours;
          final mins = diff.inMinutes % 60;
          _countdownTime = '$hours시간 $mins분';

          if (nextR.isClass) {
            _nextLesson = lessons.firstWhere(
              (l) => l.classTime >= nextR.period && l.subject.isNotEmpty,
              orElse: () => null,
            );
          } else {
            final nextClassRanges = ranges.where((r) => r.isClass && r.start.isAfter(now));
            if (nextClassRanges.isNotEmpty) {
              final nextClass = nextClassRanges.first;
              _nextLesson = lessons.firstWhere(
                (l) => l.classTime >= nextClass.period && l.subject.isNotEmpty,
                orElse: () => null,
              );
            } else {
              _nextLesson = null;
            }
          }
        } else {
          // After school or weekend (no more events today)
          int daysUntilNextSchoolDay = 1;
          if (weekday == 5) daysUntilNextSchoolDay = 3;
          else if (weekday == 6) daysUntilNextSchoolDay = 2;

          final nextSchoolDate = now.add(Duration(days: daysUntilNextSchoolDay));
          
          // Parse dynamic class start time
          final startParts = ts.firstPeriodStart.split(':');
          final targetH = int.tryParse(startParts[0]) ?? 8;
          final targetM = int.tryParse(startParts[1]) ?? 40;
          final nextSchoolStart = DateTime(
            nextSchoolDate.year,
            nextSchoolDate.month,
            nextSchoolDate.day,
            targetH, targetM,
          );
          
          final diff = nextSchoolStart.difference(now);
          _countdownTarget = isWeekend ? '월요일 등교까지' : '내일 등교까지';
          final hours = diff.inHours;
          final mins = diff.inMinutes % 60;
          _countdownTime = '$hours시간 $mins분';

          final targetWeekday = (weekday == 5 || isWeekend) ? 1 : weekday + 1;
          final targetLessons = _getLessonsForDay(targetWeekday);
          _nextLesson = targetLessons.isNotEmpty
              ? targetLessons.firstWhere(
                  (l) => l.classTime == 1,
                  orElse: () => _emptyLesson(1, targetWeekday),
                )
              : null;
        }
      }
    });

    if (Platform.isWindows && _settings.autoSleepEnabled) {
      _sleepScheduler.refreshRanges(_scheduleRangesForSleep(now));
    }
  }

  // _getTeacherDisplayName 제거됨 (개인정보 보호 - 교사 실명 매핑 삭제)

  /// 특별실 모드: 다음 교시에 이 특별실(교사 약칭 = 교실명 앞 2자)을 사용하는 학급을 찾습니다.
  /// [nextLesson]: 다음 수업 정보 (teacher 필드에 특별실 약칭 포함)
  /// 반환: "X학년 Y반" 문자열 또는 null
  String? _getNextClassForSpecialRoom(Lesson? nextLesson) {
    if (nextLesson == null) return null;
    if (_timetableResult == null) return null;
    
    final teacherAbbr = _settings.selectedTeacher.replaceAll('*', '').trim();
    if (teacherAbbr.isEmpty) return null;

    final today = DateTime.now();
    final weekday = today.weekday; // 1=Mon ~ 7=Sun
    if (weekday > 5) return null; // 주말이면 null

    final classInfo = _timetableResult!.findClassByTeacherAndPeriod(
      weekday: weekday,
      period: nextLesson.classTime,
      teacherAbbr: teacherAbbr,
    );

    if (classInfo == null) return null;
    return '${classInfo['grade']}학년 ${classInfo['classNum']}반';
  }

  Future<void> _startLocalServer() async {
    final server = LocalServerService.instance;
    server.onStatusRequest = () {
      return {
        'schoolName': _settings.selectedSchool?.name ?? '',
        'grade': _settings.selectedGrade,
        'classNum': _settings.selectedClass,
        'specialClassroomMode': _settings.specialClassroomMode,
        'currentLesson': _currentLesson != null ? {
          'subject': _currentLesson!.subject,
          'classroom': _currentLesson!.classroom,
          'period': _currentLesson!.classTime,
        } : null,
        'nextLesson': _nextLesson != null ? {
          'subject': _nextLesson!.subject,
          'classroom': _nextLesson!.classroom,
          'period': _nextLesson!.classTime,
        } : null,
        'timetable': _timetableResult != null ? {
          'schoolName': _timetableResult!.schoolName,
          'classCounts': _timetableResult!.classCounts,
          'lessons': _timetableResult!.lessons.map((l) => {
            'grade': l.grade,
            'classNum': l.classNum,
            'weekday': l.weekday,
            'classTime': l.classTime,
            'subject': l.subject,
            'classroom': l.classroom,
            'teacher': AppSettings.formatTeacherDisplayName(l.teacher), // 마스킹된 교사명 포함
          }).toList(),
        } : null,
      };
    };
    
    server.onCommandReceived = (command, params) {
      if (!mounted) return;
      debugPrint('[Boardest] 원격 명령 수신: $command (파라미터: $params)');
      
      switch (command) {
        case BoardCommand.mealCall:
          // Firebase meal_call과 동일한 급식 호출
          MealCallService.instance.triggerMealCallDirectly(); 
          break;
        case BoardCommand.showMessage:
          final msg = params['message'] as String? ?? '';
          final from = params['from'] as String? ?? '선생님';
          if (msg.isNotEmpty) {
            _showMessageNotificationAlert(msg, from);
          }
          break;
        case BoardCommand.openTool:
          final toolId = params['id'] as String? ?? '';
          if (toolId.isNotEmpty) {
            final toolOnTap = _getToolOnTap(toolId);
            toolOnTap();
          }
          break;
        case BoardCommand.nextSlide:
          _sendKeyEventToActivePresentation(true);
          break;
        case BoardCommand.prevSlide:
          _sendKeyEventToActivePresentation(false);
          break;
        case BoardCommand.startTimer:
          final sec = (params['seconds'] as num?)?.toInt() ?? 300;
          _startMiniTimerFromRemote(sec);
          break;
        case BoardCommand.stopTimer:
          _stopMiniTimerFromRemote();
          break;
      }
    };
    server.onFileReceived = (filePath) {
      _handleRemoteReceivedFile(filePath);
    };

    final success = await server.start();
    if (success) {
      setState(() {});
    }
  }

  void _handleRemoteReceivedFile(String filePath) {
    if (!mounted) return;
    final extension = p.extension(filePath).toLowerCase();
    
    Future.microtask(() async {
      if (extension == '.pdf') {
        _pushBoardRoute(PdfBoardView(
          initialFilePath: filePath,
          scaleFactor: _settings.scaleFactor,
        ));
      } else if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(extension)) {
        _showRemoteImageDialog(filePath);
      } else {
        if (Platform.isWindows) {
          try {
            await Process.run('cmd.exe', ['/c', 'start', '""', filePath]);
          } catch (e) {
            debugPrint('[Boardest] 로컬 실행 실패: $e');
            await launchUrl(Uri.file(filePath));
          }
        } else {
          await launchUrl(Uri.file(filePath));
        }
      }
    });
  }

  void _showRemoteImageDialog(String filePath) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final scale = _settings.scaleFactor;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black.withValues(alpha: 0.85),
                  alignment: Alignment.center,
                  child: InteractiveViewer(
                    maxScale: 4.0,
                    child: Image.file(
                      File(filePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 20,
                right: 20,
                child: FloatingActionButton(
                  backgroundColor: const Color(0xFFEF4565),
                  mini: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  void _startMiniTimerFromRemote(int seconds) {
    if (!mounted) return;
    setState(() {
      _showMiniTimer = true;
      _timerTargetSeconds = seconds;
      _timerSecondsElapsed = seconds;
    });
    _startMiniTimer();
  }

  void _stopMiniTimerFromRemote() {
    if (!mounted) return;
    _pauseMiniTimer();
  }

  // win32 user32.dll keybd_event FFI 바인딩
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final void Function(int, int, int, int) _keybdEvent = _user32
      .lookup<NativeFunction<Void Function(Uint8, Uint8, Uint32, IntPtr)>>('keybd_event')
      .asFunction<void Function(int, int, int, int)>();

  void _sendKeyEventToActivePresentation(bool isNext) {
    if (!Platform.isWindows) return;
    try {
      // 0x22: VK_NEXT (PageDown), 0x21: VK_PRIOR (PageUp)
      final int vk = isNext ? 0x22 : 0x21;
      
      // Key press
      _keybdEvent(vk, 0, 0, 0);
      // Key release
      _keybdEvent(vk, 0, 2, 0); // 2: KEYEVENTF_KEYUP
      debugPrint('[Boardest] Win32 KeySent: ${isNext ? "PageDown" : "PageUp"}');
    } catch (e) {
      debugPrint('[Boardest] Win32 KeySend error: $e');
    }
  }

  Future<void> _launchURL(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }



  void _openWeeklyTimetable() async {
    if (_settings.selectedSchool == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TimetableView(
          school: _settings.selectedSchool!,
          apiScheduleEvents: _apiScheduleEvents,
          initialShowCalendar: false,
        ),
      ),
    );
    _loadPreferencesAndFetch(); // Reload settings in case they changed
  }

  void _openSettingsWizard() async {
    // 설정 메뉴 바텀 시트 (설정 / 로그아웃 / 탈퇴)
    final scale = _settings.scaleFactor;
    _pauseDashboardTimer();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24 * scale)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        padding: EdgeInsets.fromLTRB(24 * scale, 20 * scale, 24 * scale, 32 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40 * scale,
                height: 4 * scale,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 20 * scale),
            Text('설정',
                style: GoogleFonts.notoSansKr(
                    color: Colors.white, fontSize: 18 * scale, fontWeight: FontWeight.bold)),
            SizedBox(height: 16 * scale),
            _SettingsMenuTile(
              icon: Icons.tune_rounded,
              color: const Color(0xFF7F5AF0),
              label: '앱 설정',
              subtitle: '학교, 시간표, 시스템 앱 설정',
              scale: scale,
              onTap: () => Navigator.pop(sheetCtx, 'settings'),
            ),
            SizedBox(height: 10 * scale),
            _SettingsMenuTile(
              icon: Icons.meeting_room_rounded,
              color: const Color(0xFF2EC4B6),
              label: '특별실 모드 전환',
              subtitle: _settings.specialClassroomMode
                  ? '특별실 사용 중 (${_settings.selectedTeacher}교사) — 클릭해 일반교실로 전환'
                  : '일반교실 사용 중 — 클릭해 특별실 교과교실로 전환',
              scale: scale,
              onTap: () => Navigator.pop(sheetCtx, 'toggle_special_mode'),
            ),
            if (Platform.isWindows) ...[
              SizedBox(height: 10 * scale),
              _SettingsMenuTile(
                icon: Icons.bedtime_rounded,
                color: const Color(0xFF2EC4B6),
                label: '자동 절전',
                subtitle: _settings.autoSleepEnabled
                    ? '쉬는 시간·점심·하교 후 화면 끔 (켜짐)'
                    : '꺼짐 — 탭하여 설정',
                scale: scale,
                onTap: () => Navigator.pop(sheetCtx, 'auto_sleep'),
              ),
            ],
            if (Platform.isAndroid) ...[
              SizedBox(height: 10 * scale),
              _SettingsMenuTile(
                icon: Icons.home_rounded,
                color: const Color(0xFF2EC4B6),
                label: '기본 홈 앱',
                subtitle: 'Boardest를 기본 런처로 설정',
                scale: scale,
                onTap: () => Navigator.pop(sheetCtx, 'home_launcher'),
              ),
            ],
            SizedBox(height: 10 * scale),
            _SettingsMenuTile(
              icon: Icons.logout_rounded,
              color: const Color(0xFF2EC4B6),
              label: '로그아웃',
              subtitle: '현재 기기에서 로그아웃',
              scale: scale,
              onTap: () => Navigator.pop(sheetCtx, 'logout'),
            ),
            SizedBox(height: 10 * scale),
            _SettingsMenuTile(
              icon: Icons.person_off_rounded,
              color: const Color(0xFFEF4565),
              label: '회원 탈퇴',
              subtitle: '계정 영구 삭제',
              scale: scale,
              onTap: () => Navigator.pop(sheetCtx, 'withdraw'),
            ),
          ],
        ),
      ),
    );
    _resumeDashboardTimer();

    if (!mounted) return;
    if (choice == 'settings') {
      final setupComplete = _settings.isSetupComplete;
      _pauseDashboardTimer();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SetupWizardView(startWithStepList: setupComplete),
        ),
      );
      _resumeDashboardTimer();
      _loadPreferencesAndFetch();
    } else if (choice == 'toggle_special_mode') {
      if (_settings.specialClassroomMode) {
        // 특별실 모드 해제 -> 일반 교실로 전환
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: const Color(0xFF0F0E17).withOpacity(0.85),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: const Color(0xFF2EC4B6).withOpacity(0.2)),
              ),
              title: Text('일반 교실 모드로 전환', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Text('특별실 모드를 해제하고 일반 교실 시간표 모드로 돌아가시겠습니까?', style: GoogleFonts.notoSansKr(color: Colors.white70)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('전환', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );

        if (confirmed == true) {
          final newSettings = _settings.copyWith(
            specialClassroomMode: false,
            selectedTeacher: '',
          );
          await _storageService.saveSettings(newSettings);
          setState(() {
            _settings = newSettings;
          });
          _loadPreferencesAndFetch();
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('일반 교실 모드로 성공적으로 전환되었습니다.')),
            );
          }
        }
      } else {
        // 일반 교실 -> 특별실 전환 (교사 약칭 2글자 입력받음)
        final teacherController = TextEditingController();
        final formKey = GlobalKey<FormState>();

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: const Color(0xFF0F0E17).withOpacity(0.85),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: const Color(0xFF2EC4B6).withOpacity(0.2)),
              ),
              title: Text('특별실 모드로 전환', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('특별실에서 수업을 진행하는 담당 교사 약칭(2글자)을 입력하세요.', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: teacherController,
                      style: GoogleFonts.notoSansKr(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '예: 김희, 이정, 홍길',
                        hintStyle: GoogleFonts.notoSansKr(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.03),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF2EC4B6)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().length != 2) {
                          return '정확히 2글자의 교사명을 입력해 주세요.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: Text('전환 및 저장', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );

        if (confirmed == true) {
          final newSettings = _settings.copyWith(
            specialClassroomMode: true,
            selectedTeacher: teacherController.text.trim(),
          );
          await _storageService.saveSettings(newSettings);
          setState(() {
            _settings = newSettings;
          });
          _loadPreferencesAndFetch();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('특별실 모드로 전환되었습니다. (${teacherController.text.trim()}교사)')),
            );
          }
        }
      }
    } else if (choice == 'auto_sleep') {
      await _showAutoSleepSettingsDialog(scale);
    } else if (choice == 'home_launcher') {
      const channel = MethodChannel('com.boardest/launch_args');
      try {
        await channel.invokeMethod('openHomeSettings');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('홈 앱 설정을 열 수 없습니다: $e')),
          );
        }
      }
    } else if (choice == 'logout') {
      await _logout();
    } else if (choice == 'withdraw') {
      await _showWithdrawDialog();
    }
  }

  /// 로그아웃 – 로컬 세션만 삭제하고 SetupWizardView로 이동
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('로그아웃',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('로그아웃 하시겠습니까?\n다음 실행 시 다시 로그인이 필요합니다.',
            style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('로그아웃', style: GoogleFonts.notoSansKr(color: const Color(0xFF7F5AF0), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AuthService().logout();
    if (!mounted) return;

    final updated = _settings.copyWith(isSetupComplete: false);
    await _storageService.saveSettings(updated);

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SetupWizardView()),
      (_) => false,
    );
  }

  /// 회원 탈퇴 – 비밀번호 확인 후 Firestore 문서 삭제 + 로컬 초기화
  Future<void> _showWithdrawDialog() async {
    final pwCtrl = TextEditingController();
    bool pwVisible = false;
    String? errMsg;

    final authService = AuthService();
    final user = await authService.getCurrentUser();
    if (user == null) return;

    final isPasswordless = user.email.toLowerCase().contains('.nopw.bst') || user.email.startsWith('Class.');

    if (isPasswordless) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('회원 탈퇴',
              style: GoogleFonts.notoSansKr(
                  color: const Color(0xFFEF4565), fontWeight: FontWeight.bold)),
          content: Text('정말로 탈퇴하시겠습니까?\n이 임시/교실 계정 정보가 즉시 영구 삭제됩니다.',
              style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소',
                  style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('탈퇴 확인',
                  style: GoogleFonts.notoSansKr(
                      color: const Color(0xFFEF4565), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      // 로딩 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4565)),
          ),
        ),
      );

      final err = await authService.deleteAccount(password: '');
      if (!mounted) return;
      Navigator.pop(context); // 로딩창 닫기

      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4565),
            content: Text(err, style: GoogleFonts.notoSansKr(color: Colors.white)),
          ),
        );
        return;
      }
    } else {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF16161A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('회원 탈퇴',
                  style: GoogleFonts.notoSansKr(
                      color: const Color(0xFFEF4565), fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('탈퇴하면 계정이 영구 삭제됩니다.\n비밀번호를 입력하여 확인해 주세요.',
                      style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF94A1B2), fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pwCtrl,
                    obscureText: !pwVisible,
                    style: GoogleFonts.notoSansKr(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      labelStyle: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
                      errorText: errMsg,
                      errorStyle: GoogleFonts.notoSansKr(color: const Color(0xFFEF4565), fontSize: 12),
                      suffixIcon: IconButton(
                        icon: Icon(
                          pwVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: const Color(0xFF94A1B2),
                        ),
                        onPressed: () => setDialogState(() => pwVisible = !pwVisible),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: const Color(0xFFEF4565).withValues(alpha: 0.4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFEF4565)),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F0E17),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('취소',
                      style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2))),
                ),
                TextButton(
                  onPressed: () async {
                    setDialogState(() => errMsg = null);
                    final err = await AuthService().deleteAccount(password: pwCtrl.text);
                    if (err != null) {
                      setDialogState(() => errMsg = err);
                      return;
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: Text('탈퇴 확인',
                      style: GoogleFonts.notoSansKr(
                          color: const Color(0xFFEF4565), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        ),
      );
    }

    // 탈퇴 후 로컬 설정 초기화 및 SetupWizardView로 이동
    final currentUser = await authService.getCurrentUser();
    if (currentUser == null && mounted) {
      await StorageService().clearAll();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SetupWizardView()),
        (_) => false,
      );
    }
  }

  Widget _buildNumberAdjuster({
    required String label,
    required int value,
    required int min,
    required int max,
    required double scale,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF24242B),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11 * scale)),
          SizedBox(height: 4 * scale),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.remove_rounded, color: Colors.white70, size: 16 * scale),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  int newVal = value - 1;
                  if (newVal < min) newVal = max;
                  onChanged(newVal);
                },
              ),
              SizedBox(width: 8 * scale),
              Text(
                value.toString().padLeft(2, '0'),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8 * scale),
              IconButton(
                icon: Icon(Icons.add_rounded, color: Colors.white70, size: 16 * scale),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  int newVal = value + 1;
                  if (newVal > max) newVal = min;
                  onChanged(newVal);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setDebugTime() async {
    final DateTime now = _debugTimeOverride ?? DateTime.now();
    int year = now.year;
    int month = now.month;
    int day = now.day;
    int hour = now.hour;
    int minute = now.minute;
    bool isPm = hour >= 12;
    int displayHour = hour % 12;
    if (displayHour == 0) displayHour = 12;

    _pauseDashboardTimer();
    await showDialog(
      context: context,
      builder: (dialogCtx) {
        final scale = _settings.scaleFactor;
        return StatefulBuilder(
          builder: (context, setDState) {
            return Dialog(
              backgroundColor: const Color(0xFF16161A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale)),
              child: Container(
                padding: EdgeInsets.all(24 * scale),
                width: 420 * scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '디버그 시간 설정',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20 * scale),
                    // Date Adjusters
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumberAdjuster(
                            label: '년',
                            value: year,
                            min: 2020,
                            max: 2030,
                            scale: scale,
                            onChanged: (val) => setDState(() => year = val),
                          ),
                        ),
                        SizedBox(width: 8 * scale),
                        Expanded(
                          child: _buildNumberAdjuster(
                            label: '월',
                            value: month,
                            min: 1,
                            max: 12,
                            scale: scale,
                            onChanged: (val) => setDState(() => month = val),
                          ),
                        ),
                        SizedBox(width: 8 * scale),
                        Expanded(
                          child: _buildNumberAdjuster(
                            label: '일',
                            value: day,
                            min: 1,
                            max: 31,
                            scale: scale,
                            onChanged: (val) => setDState(() => day = val),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16 * scale),
                    // Time Adjusters
                    Row(
                      children: [
                        // AM/PM Toggle
                        GestureDetector(
                          onTap: () {
                            setDState(() {
                              isPm = !isPm;
                            });
                          },
                          child: Container(
                            height: 60 * scale,
                            padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF24242B),
                              borderRadius: BorderRadius.circular(12 * scale),
                              border: Border.all(color: const Color(0xFF7F5AF0), width: 1.5 * scale),
                            ),
                            child: Text(
                              isPm ? 'PM' : 'AM',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16 * scale,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12 * scale),
                        Expanded(
                          child: _buildNumberAdjuster(
                            label: '시',
                            value: displayHour,
                            min: 1,
                            max: 12,
                            scale: scale,
                            onChanged: (val) => setDState(() => displayHour = val),
                          ),
                        ),
                        SizedBox(width: 8 * scale),
                        Expanded(
                          child: _buildNumberAdjuster(
                            label: '분',
                            value: minute,
                            min: 0,
                            max: 59,
                            scale: scale,
                            onChanged: (val) => setDState(() => minute = val),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 24 * scale),
                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: Text('취소', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 14 * scale)),
                        ),
                        SizedBox(width: 12 * scale),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7F5AF0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                            padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 12 * scale),
                          ),
                          onPressed: () {
                            int finalHour = displayHour % 12;
                            if (isPm) finalHour += 12;
                            setState(() {
                              _debugTimeOverride = DateTime(
                                year,
                                month,
                                day,
                                finalHour,
                                minute,
                                0,
                              );
                            });
                            _loadPreferencesAndFetch();
                            Navigator.pop(dialogCtx);
                          },
                          child: Text('적용', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14 * scale)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    _resumeDashboardTimer();
  }

  void _showDebugTimeDialog() async {
    _pauseDashboardTimer();
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('디버그 시간 & USB 설정'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _debugTimeOverride != null
                      ? '현재 디버그 시간: ${_debugTimeOverride.toString().split('.')[0]}'
                      : '현재 실시간 사용 중',
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('USB 모드 강제 활성화', style: TextStyle(fontWeight: FontWeight.bold)),
                    Switch(
                      value: _debugUsbOverride,
                      onChanged: (val) {
                        setDialogState(() {
                          _debugUsbOverride = val;
                        });
                        setState(() {
                          _debugUsbOverride = val;
                        });
                        _checkUsbConnection();
                      },
                    ),
                  ],
                ),
                if (_isUsbConnected) ...[
                  const SizedBox(height: 8),
                  Text(
                    '연결된 경로: $_usbDriveLetter',
                    style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop('restore');
                },
                child: const Text('실시간 복원'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop('set_time');
                },
                child: const Text('시간 설정하기'),
              ),
            ],
          );
        },
      ),
    );

    if (action == 'restore') {
      setState(() {
        _debugTimeOverride = null;
      });
      _loadPreferencesAndFetch();
      _resumeDashboardTimer();
    } else if (action == 'set_time') {
      // Transition directly without restarting timer in between
      _resumeDashboardTimer(); // Decrement overlay count from first dialog
      _setDebugTime(); // Opens second dialog which increments count back to 1
    } else {
      // Direct dialog dismiss
      _resumeDashboardTimer();
    }
  }

  Future<void> _openSchoolScheduleDdayPicker() async {
    if (_settings.selectedSchool == null) return;

    if (_schoolScheduleDdayEvents.isEmpty) {
      final schoolName = _settings.selectedSchool!.name;
      final targetDate = _debugTimeOverride ?? DateTime.now();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '학사일정을 불러오는 중…',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF1E1B24),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
      await _fetchSchoolSchedule(schoolName, targetDate);
      if (!mounted) return;
      if (_schoolScheduleDdayEvents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '학사일정이 없거나 아직 불러오지 못했습니다.',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFF1E1B24),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final events = _schoolScheduleDdayEvents;
    final pinned = _settings.pinnedDday;
    final queryController = TextEditingController();

    _pauseDashboardTimer();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final q = queryController.text.trim().toLowerCase();
            final filtered = events.where((e) {
              if (q.isEmpty) return true;
              return e.title.toLowerCase().contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.62,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.school_rounded, color: Color(0xFF00F5D4)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '학사일정에서 D-Day 선택',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white54),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: queryController,
                          onChanged: (_) => setSheetState(() {}),
                          style: GoogleFonts.notoSansKr(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: '일정 이름 검색',
                            hintStyle: GoogleFonts.notoSansKr(color: Colors.white38),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2EC4B6)),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await _pinDday(null, clearPin: true);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                                label: Text(
                                  '자동 (가까운 일정)',
                                  style: GoogleFonts.notoSansKr(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF00F5D4),
                                  side: BorderSide(
                                    color: _settings.pinnedDday == null
                                        ? const Color(0xFF2EC4B6)
                                        : Colors.white24,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  '검색 결과가 없습니다',
                                  style: GoogleFonts.notoSansKr(color: Colors.white38),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (_, i) {
                                  final e = filtered[i];
                                  final selected = _isSameDday(pinned, e);
                                  final dateStr =
                                      '${e.date.year}.${e.date.month.toString().padLeft(2, '0')}.${e.date.day.toString().padLeft(2, '0')}';
                                  final count = _ddayCountLabel(e.date);

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        await _pinDday(e);
                                        if (ctx.mounted) Navigator.pop(ctx);
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? const Color(0xFF2EC4B6).withValues(alpha: 0.12)
                                              : Colors.white.withValues(alpha: 0.03),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: selected
                                                ? const Color(0xFF2EC4B6)
                                                : Colors.white.withValues(alpha: 0.06),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 44,
                                              alignment: Alignment.center,
                                              child: Text(
                                                count,
                                                style: GoogleFonts.outfit(
                                                  color: const Color(0xFF00F5D4),
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    e.title,
                                                    style: GoogleFonts.notoSansKr(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 15,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    dateStr,
                                                    style: GoogleFonts.notoSansKr(
                                                      color: Colors.white38,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (selected)
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                color: Color(0xFF2EC4B6),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    _resumeDashboardTimer();
    queryController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0E17),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2EC4B6)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _openSettingsWizard,
                child: const Text('초기 설정 실행'),
              ),
            ],
          ),
        ),
      );
    }

    final todayName = ['월', '화', '수', '목', '금', '토', '일'][_now.weekday - 1];
    final dateString = '${_now.year}년 ${_now.month}월 ${_now.day}일 ($todayName)';
    
    // Choose schedule to render
    final isWeekend = _now.weekday == 6 || _now.weekday == 7;
    final displayWeekday = isWeekend ? 1 : _now.weekday;
    final todayLessons = _getLessonsForDay(displayWeekday);
    final scale = AppPaths.adaptiveUiScale(context, _settings.scaleFactor);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
        body: Stack(
          children: [
            // Aurora background glow
            Positioned(
              top: -100,
              left: -100,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2EC4B6).withValues(alpha: 0.14),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              right: -100,
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2CB67D).withValues(alpha: 0.08),
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(color: Colors.transparent),
            ),
            
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Column 1: Today's Timetable (flex 19)
                    Expanded(
                      flex: 19,
                      child: _buildTodayTimetablePanel(todayLessons, isWeekend),
                    ),
                    const SizedBox(width: 16),
                          
                          if (_isUsbConnected) ...[
                            // Combined Column 2 & 3 when USB is connected (flex 113)
                            Expanded(
                              flex: 113,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Top Row: Clock & Timer (Left) and BST Tools (Right) (flex 4)
                                  Expanded(
                                    flex: 4,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          flex: 81,
                                          child: _buildClockAndTimerSection(dateString),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 32,
                                          child: _buildRightSidePanel(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Bottom Row: Next Class (Left) and USB Card (Right) (flex 7)
                                  Expanded(
                                    flex: 7,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          flex: 1,
                                          child: _buildNowPlayingSubjectCard(),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 1,
                                          child: _buildUsbCard(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // Original Column 2 (flex 81)
                            Expanded(
                              flex: 81,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _buildClockAndTimerSection(dateString),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    flex: 6,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          flex: 8,
                                          child: _buildNowPlayingSubjectCard(),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 3,
                                          child: _buildMealCard(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Original Column 3 (flex 32)
                            Expanded(
                              flex: 32,
                              child: _buildRightSidePanel(),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            
            // In-app floating widgets overlay
            if (_showMiniTimer) _buildMiniTimerWindow(scale),
            if (_showMiniCalculator) _buildMiniCalculatorWindow(scale),
            if (_showMiniPicker) _buildMiniPickerWindow(scale),
            if (_showMiniWeather) _buildMiniWeatherWindow(scale),
            if (_showMiniCalendar) _buildMiniCalendarWindow(scale),
            if (_showMiniAppDrawer) _buildMiniAppDrawerWindow(scale),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTimetablePanel(List<Lesson> lessons, bool isWeekend) {
    final scale = _settings.scaleFactor;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(12.0 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            isWeekend ? '월요일 시간표' : '오늘의 시간표',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14 * scale,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8 * scale),
                          TextButton.icon(
                            onPressed: _openWeeklyTimetable,
                            icon: Icon(Icons.calendar_view_week_rounded, color: const Color(0xFF00F5D4), size: 12 * scale),
                            label: Text(
                              '주간 보기',
                              style: GoogleFonts.notoSansKr(
                                color: const Color(0xFF00F5D4),
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
                              backgroundColor: const Color(0xFF00F5D4).withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      if (isWeekend) ...[
                        SizedBox(width: 12 * scale),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '주말',
                            style: GoogleFonts.notoSansKr(color: Colors.amberAccent, fontSize: 10 * scale, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_settings.selectedSchool?.name ?? ''}   |   ${_settings.selectedGrade}학년 ${_settings.selectedClass}반',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11 * scale,
                    color: Colors.white38,
                  ),
                ),
                SizedBox(height: 8 * scale),
                Expanded(
                  child: lessons.isEmpty
                      ? Center(
                          child: Text(
                            '수업 일정이 없습니다.',
                            style: GoogleFonts.notoSansKr(color: Colors.white38),
                          ),
                        )
                      : Column(
                          children: lessons.asMap().entries.map((entry) {
                            final index = entry.key;
                            final lesson = entry.value;
                            final isCurrent = _currentPeriod?.period == lesson.classTime;
                            final isPassed = _currentPeriod != null &&
                                _currentPeriod!.isClass &&
                                _currentPeriod!.period > lesson.classTime;
                                
                            final imgPath = _settings.getTextbookPath(lesson.subject);
                            final hasImage = imgPath != null && File(imgPath).existsSync();
                            // 교사 이름 표시 제거됨 (개인정보 보호)

                            final itemCount = lessons.length;
                            double verticalPadding = 6.0;
                            double marginBottom = 8.0;
                            double subjectFontSize = 12.0;
                            double teacherFontSize = 10.0;
                            double timeFontSize = 9.0;
                            double circleSize = 22.0;
                            double circleFontSize = 11.0;
                            double classroomFontSize = 9.0;
                            double sizeBoxWidth = 10.0;

                            if (itemCount > 6) {
                              verticalPadding = 4.0;
                              marginBottom = 5.0;
                              subjectFontSize = 10.5;
                              teacherFontSize = 8.5;
                              timeFontSize = 8.0;
                              circleSize = 18.0;
                              circleFontSize = 9.5;
                              classroomFontSize = 8.0;
                              sizeBoxWidth = 7.0;
                            }
                            if (itemCount > 7) {
                              verticalPadding = 1.5;
                              marginBottom = 3.0;
                              subjectFontSize = 9.5;
                              teacherFontSize = 7.5;
                              timeFontSize = 7.0;
                              circleSize = 15.0;
                              circleFontSize = 8.0;
                              classroomFontSize = 7.0;
                              sizeBoxWidth = 5.0;
                            }

                            final isLast = index == itemCount - 1;

                            return Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: EdgeInsets.only(bottom: isLast ? 0.0 : marginBottom * scale),
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: verticalPadding * scale),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? const Color(0xFF2EC4B6).withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isCurrent
                                        ? const Color(0xFF2EC4B6)
                                        : Colors.white.withValues(alpha: 0.05),
                                    width: isCurrent ? 1.5 : 1,
                                  ),
                                  image: hasImage
                                      ? DecorationImage(
                                          image: FileImage(File(imgPath)),
                                          fit: BoxFit.cover,
                                          colorFilter: ColorFilter.mode(
                                            Colors.black.withValues(alpha: isCurrent ? 0.72 : 0.88),
                                            BlendMode.srcOver,
                                          ),
                                        )
                                      : null,
                                ),
                                child: Center(
                                  child: Opacity(
                                    opacity: isPassed ? 0.45 : 1.0,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: circleSize * scale,
                                          height: circleSize * scale,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isCurrent
                                                ? const Color(0xFF2EC4B6)
                                                : Colors.white.withValues(alpha: 0.08),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${lesson.classTime}',
                                            style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.bold,
                                              fontSize: circleFontSize * scale,
                                              color: isCurrent ? Colors.white : Colors.white70,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: sizeBoxWidth * scale),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                lesson.subject.isEmpty ? '수업 없음' : lesson.subject,
                                                style: GoogleFonts.notoSansKr(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: subjectFontSize * scale,
                                                  color: lesson.subject.isEmpty ? Colors.white30 : Colors.white,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (_settings.specialClassroomMode && lesson.teacher.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Container(
                                                  padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF00F5D4).withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3), width: 0.8),
                                                  ),
                                                  child: Text(
                                                    '${lesson.teacher}반',
                                                    style: GoogleFonts.outfit(
                                                      fontSize: (classroomFontSize) * scale,
                                                      fontWeight: FontWeight.bold,
                                                      color: const Color(0xFF00F5D4),
                                                    ),
                                                  ),
                                                ),
                                              ] else ...[
                                                if (lesson.classroom.isNotEmpty) ...[  
                                                  const SizedBox(height: 1),
                                                  Text(
                                                    lesson.classroom,
                                                    style: GoogleFonts.notoSansKr(
                                                      fontSize: (teacherFontSize) * scale,
                                                      color: const Color(0xFF2CB67D).withValues(alpha: 0.9),
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ],
                                              const SizedBox(height: 1),
                                              Text(
                                                _getPeriodTimeString(lesson.classTime),
                                                style: GoogleFonts.outfit(
                                                  fontSize: timeFontSize * scale,
                                                  color: const Color(0xFF00F5D4).withValues(alpha: 0.8),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (lesson.classroom.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2CB67D).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              lesson.classroom,
                                              style: GoogleFonts.notoSansKr(
                                                color: const Color(0xFF2CB67D),
                                                fontSize: classroomFontSize * scale,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Right Panel Top Widget: Clock & Linear Remaining Progress ---
  Widget _buildClockAndTimerSection(String dateString) {
    final scale = _settings.scaleFactor;
    final timeString = '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}';
    
    // Status text (e.g. 2교시 수업 중 또는 쉬는 시간 등)
    String statusLabel = '방과 후';
    if (_currentPeriod != null) {
      statusLabel = _currentPeriod!.label;
      if (_currentPeriod!.isClass) {
        statusLabel += ' 수업 중';
      }
    } else if (_now.isBefore(DateTime(_now.year, _now.month, _now.day, 8, 40))) {
      statusLabel = '일과 시작 전';
    }

    final activeDday = _activeDdayEvent;
    final String? ddayLabel = activeDday != null
        ? '${activeDday.title} ${_ddayCountLabel(activeDday.date)}'
        : null;
    final bool ddayPinned = _settings.pinnedDday != null;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1단: 날짜 & D-Day Row (상단)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    dateString,
                    style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * scale),
                  ),
                  // LAN 원격 연결 안내 제거 (연동 철회)
                ],
              ),
              GestureDetector(
                onLongPress: _openSchoolScheduleDdayPicker,
                child: Tooltip(
                  message: '길게 눌러 학사일정에서 D-Day 선택',
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2EC4B6).withValues(alpha: ddayLabel != null ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(6 * scale),
                      border: Border.all(
                        color: ddayPinned
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFF2EC4B6).withValues(alpha: 0.35),
                        width: ddayPinned ? 1.2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          ddayPinned ? Icons.push_pin_rounded : Icons.event_rounded,
                          size: 11 * scale,
                          color: const Color(0xFF00F5D4),
                        ),
                        SizedBox(width: 4 * scale),
                        Text(
                          ddayLabel ?? 'D-Day · 길게 눌러 선택',
                          style: GoogleFonts.notoSansKr(
                            color: ddayLabel != null
                                ? const Color(0xFF00F5D4)
                                : Colors.white38,
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4 * scale),
          
          // 2단: 시계 (중앙)
          Center(
            child: GestureDetector(
              onLongPress: _showDebugTimeDialog,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeString,
                    style: GoogleFonts.outfit(
                      fontSize: 90 * scale,
                      fontWeight: FontWeight.bold,
                      color: _debugTimeOverride != null ? Colors.orangeAccent : Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  if (_debugTimeOverride != null) ...[
                    SizedBox(width: 10 * scale),
                    Icon(Icons.bug_report_rounded, color: Colors.orangeAccent, size: 24 * scale),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 4 * scale),

          // 3단: 남은 시간 상태 (하단으로 길게)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 상태 (Status)
              Row(
                children: [
                  Container(
                    width: 8 * scale,
                    height: 8 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPeriod != null ? const Color(0xFF2CB67D) : Colors.white38,
                      boxShadow: _currentPeriod != null
                          ? [
                              BoxShadow(
                                color: const Color(0xFF2CB67D).withValues(alpha: 0.4),
                                blurRadius: 6 * scale,
                                spreadRadius: 2 * scale,
                              )
                            ]
                          : null,
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  Text(
                    statusLabel,
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              
              // 남은 시간
              Row(
                children: [
                  if (_countdownTarget.isNotEmpty) ...[
                    Text(
                      '$_countdownTarget ',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11 * scale,
                        color: Colors.white38,
                      ),
                    ),
                    SizedBox(width: 4 * scale),
                  ],
                  Text(
                    _countdownTime,
                    style: GoogleFonts.outfit(
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.bold,
                      color: _currentPeriod != null ? const Color(0xFF00F5D4) : Colors.white60,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 6 * scale),
          
          // Progress indicator
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _periodProgress,
              minHeight: 6 * scale,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6)),
            ),
          ),
        ],
      ),
    );
  }

  // --- Right Panel Bottom Left: Now Playing Subject Card ---
  Widget _buildNowPlayingSubjectCard() {
    final isAssembly = _currentPeriod?.period == -1;
    final isDismissal = _currentPeriod?.period == -2;

    final String subjectName;
    final String teacherText;
    final String classroomText;
    final String badgeText;
    final bool isUpcoming;
    final String? imgPath;

    if (isAssembly) {
      subjectName = '조회시간';
      teacherText = '오늘 하루도 힘차게 시작해봐요!';
      classroomText = '';
      badgeText = '조회 시간';
      isUpcoming = false;
      imgPath = null;
    } else if (isDismissal) {
      subjectName = '종례시간';
      teacherText = '하루 동안 수고 많으셨습니다!';
      classroomText = '';
      badgeText = '종례 시간';
      isUpcoming = false;
      imgPath = null;
    } else {
      final hasCurrent = _currentLesson != null && _currentLesson!.subject.isNotEmpty;
      final displayLesson = hasCurrent ? _currentLesson : _nextLesson;
      isUpcoming = !hasCurrent;

      final hasActiveSubject = displayLesson != null && displayLesson.subject.isNotEmpty;
      subjectName = hasActiveSubject ? displayLesson.subject : '일과 종료';
      
      // 특별실 모드: '다음 X학년 Y반' 표시
      // 일반 모드: 교사 이름 없이 교실명만 표시
      if (_settings.specialClassroomMode && isUpcoming && displayLesson != null) {
        final nextClass = _getNextClassForSpecialRoom(displayLesson);
        teacherText = nextClass ?? '다음 수업 대기 중';
      } else if (hasActiveSubject) {
        teacherText = displayLesson!.classroom.isNotEmpty
            ? displayLesson.classroom
            : '교실 정보 없음';
      } else {
        teacherText = '오늘의 모든 수업이 끝났습니다';
      }
      classroomText = hasActiveSubject ? displayLesson!.classroom : '';
      
      imgPath = (displayLesson != null && hasActiveSubject) ? _settings.getTextbookPath(displayLesson.subject) : null;
      badgeText = isUpcoming ? '다음 수업' : '지금 수업';
    }

    final hasImage = imgPath != null && File(imgPath).existsSync();
    final scale = _settings.scaleFactor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Darkened textbook background blur
            if (hasImage)
              Positioned.fill(
                child: Image.file(
                  File(imgPath),
                  fit: BoxFit.cover,
                ),
              ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: hasImage ? 14 : 0, sigmaY: hasImage ? 14 : 0),
                child: Container(
                  color: Colors.black.withValues(alpha: hasImage ? 0.76 : 0.45),
                ),
              ),
            ),
            
            // Card Content
            Padding(
              padding: EdgeInsets.all(24.0 * scale),
              child: Row(
                children: [
                  // Left: Visual Textbook Cover representation in 3D frame
                  SizedBox(
                    height: (_isUsbConnected ? 260 : 340) * scale,
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16 * scale,
                              offset: Offset(0, 8 * scale),
                            ),
                            if (hasImage)
                              BoxShadow(
                                color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                                blurRadius: 20 * scale,
                                spreadRadius: 2 * scale,
                              ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: hasImage
                              ? Image.file(File(imgPath), fit: BoxFit.cover)
                              : Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF2E2C38), Color(0xFF1E1B24)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.menu_book_rounded,
                                    color: Colors.white24,
                                    size: 50 * scale,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 32 * scale),
                  
                  // Right: Subject details and badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // State badge
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
                          decoration: BoxDecoration(
                            color: isUpcoming
                                ? Colors.white.withValues(alpha: 0.12)
                                : const Color(0xFF2EC4B6).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isUpcoming
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : const Color(0xFF2EC4B6),
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: GoogleFonts.notoSansKr(
                              color: isUpcoming ? Colors.white70 : Colors.white,
                              fontSize: 14 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 20 * scale),
                        
                        Builder(
                          builder: (context) {
                            final double subjectFontSize = !_isUsbConnected
                                ? (isUpcoming ? 104.0 : 96.0)
                                : (isUpcoming ? 88.0 : 64.0);
                            final double teacherFontSize = subjectFontSize / 2;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: subjectFontSize * scale,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      subjectName,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: subjectFontSize * scale,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: isUpcoming && !_isUsbConnected ? 0.5 : 0,
                                      ),
                                      maxLines: 2,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 10 * scale),
                                
                                // Teacher and Classroom
                                Row(
                                  children: [
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            teacherText,
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: teacherFontSize * scale,
                                              color: Colors.white60,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (classroomText.isNotEmpty) ...[
                                      SizedBox(width: 14 * scale),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 5 * scale),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2CB67D).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          classroomText,
                                          style: GoogleFonts.notoSansKr(
                                            color: const Color(0xFF2CB67D),
                                            fontSize: (!_isUsbConnected ? 28 : 20) * scale,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsbCard() {
    if (!Platform.isWindows) return const SizedBox.shrink();
    final scale = _settings.scaleFactor;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0 * scale, vertical: 12.0 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 헤더 영역 (USB 아이콘, 타이틀, 자동 열기 체크박스)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.usb_rounded, color: const Color(0xFF00F5D4), size: 20 * scale),
                        SizedBox(width: 8 * scale),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '수업 자료 탐색기',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13 * scale,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '이 중 파일을 선택해주세요',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 9.5 * scale,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF00F5D4),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // 자동 열기 스위치
                    Row(
                      children: [
                        Text(
                          '자동 열기',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10 * scale,
                            color: Colors.white54,
                          ),
                        ),
                        SizedBox(width: 4 * scale),
                        SizedBox(
                          height: 20 * scale,
                          width: 32 * scale,
                          child: Switch(
                            value: _usbAutoOpenEnabled,
                            activeColor: const Color(0xFF00F5D4),
                            activeTrackColor: const Color(0xFF00F5D4).withValues(alpha: 0.3),
                            inactiveThumbColor: Colors.white30,
                            inactiveTrackColor: Colors.white10,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) async {
                              setState(() {
                                _usbAutoOpenEnabled = val;
                              });
                              if (_usbSessionId.isNotEmpty) {
                                await UsbSessionService.instance.setAutoOpen(_usbSessionId, val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 8 * scale),
                
                Container(
                  margin: EdgeInsets.only(bottom: 8 * scale),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _showFullUsbExplorer = false;
                            });
                          },
                          child: Container(
                            alignment: Alignment.center,
                            padding: EdgeInsets.symmetric(vertical: 6 * scale),
                            decoration: BoxDecoration(
                              color: !_showFullUsbExplorer
                                  ? const Color(0xFF00F5D4).withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: !_showFullUsbExplorer
                                    ? const Color(0xFF00F5D4).withOpacity(0.3)
                                    : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '매칭 교안 (수자탐)',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.bold,
                                color: !_showFullUsbExplorer ? const Color(0xFF00F5D4) : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _showFullUsbExplorer = true;
                            });
                          },
                          child: Container(
                            alignment: Alignment.center,
                            padding: EdgeInsets.symmetric(vertical: 6 * scale),
                            decoration: BoxDecoration(
                              color: _showFullUsbExplorer
                                  ? const Color(0xFF00F5D4).withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: _showFullUsbExplorer
                                    ? const Color(0xFF00F5D4).withOpacity(0.3)
                                    : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '전체 폴더 (USB 파탐)',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.bold,
                                color: _showFullUsbExplorer ? const Color(0xFF00F5D4) : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 2. 파일 목록 / 탐색기 영역
                Expanded(
                  child: _showFullUsbExplorer
                      ? UsbExplorer(
                          drivePath: _usbDriveLetter,
                          scaleFactor: scale,
                          onFileOpen: (filePath) async {
                            int startPage = 0;
                            if (_usbSessionId.isNotEmpty) {
                              final state = await UsbSessionService.instance.getFileState(_usbSessionId, filePath);
                              startPage = state?.lastPage ?? 0;
                            }
                            _openUsbFileWithSession(_usbSessionId, filePath, startPage);
                          },
                        )
                      : (_usbSortedFiles.isEmpty
                          ? Center(
                              child: Text(
                                '수업 자료가 존재하지 않습니다.',
                                style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 12 * scale),
                              ),
                            )
                          : FutureBuilder<String?>(
                              future: _usbSessionId.isNotEmpty
                                  ? UsbSessionService.instance.getLastOpenedFile(_usbSessionId)
                                  : Future.value(null),
                              builder: (context, lastOpenedSnapshot) {
                                final lastOpened = lastOpenedSnapshot.data;

                                return Scrollbar(
                                  thickness: 3 * scale,
                                  radius: const Radius.circular(2),
                                  child: ListView.builder(
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: _usbSortedFiles.length,
                                    itemBuilder: (context, index) {
                                      final filePath = _usbSortedFiles[index];
                                      final fileName = p.basename(filePath);
                                      final ext = p.extension(filePath).toLowerCase();
                                      final isLastOpened = lastOpened == filePath;

                                      // 아이콘 & 색상 매핑
                                      IconData iconData = Icons.insert_drive_file_rounded;
                                      Color iconColor = Colors.white54;
                                      if (ext == '.pptx' || ext == '.ppt') {
                                        iconData = Icons.slideshow_rounded;
                                        iconColor = const Color(0xFFFF8E3C);
                                      } else if (ext == '.pdf') {
                                        iconData = Icons.picture_as_pdf_rounded;
                                        iconColor = const Color(0xFFEF4565);
                                      } else if (['.mp4', '.mkv', '.avi', '.mov', '.wmv'].contains(ext)) {
                                        iconData = Icons.play_circle_fill_rounded;
                                        iconColor = const Color(0xFF2CB67D);
                                      }

                                      return Padding(
                                        padding: EdgeInsets.only(bottom: 6.0 * scale),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () async {
                                              int startPage = 0;
                                              if (_usbSessionId.isNotEmpty) {
                                                final state = await UsbSessionService.instance.getFileState(_usbSessionId, filePath);
                                                startPage = state?.lastPage ?? 0;
                                              }
                                              _openUsbFileWithSession(_usbSessionId, filePath, startPage);
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
                                              decoration: BoxDecoration(
                                                color: isLastOpened
                                                    ? const Color(0xFF00F5D4).withValues(alpha: 0.1)
                                                    : Colors.white.withValues(alpha: 0.015),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isLastOpened
                                                      ? const Color(0xFF00F5D4).withValues(alpha: 0.3)
                                                      : Colors.white.withValues(alpha: 0.04),
                                                  width: isLastOpened ? 1.2 : 1,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(iconData, color: iconColor, size: 18 * scale),
                                                  SizedBox(width: 8 * scale),
                                                  Expanded(
                                                    child: Text(
                                                      fileName,
                                                      style: GoogleFonts.notoSansKr(
                                                        color: isLastOpened ? const Color(0xFF00F5D4) : Colors.white.withValues(alpha: 0.85),
                                                        fontSize: 11 * scale,
                                                        fontWeight: isLastOpened ? FontWeight.bold : FontWeight.normal,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isLastOpened) ...[
                                                    SizedBox(width: 6 * scale),
                                                    Container(
                                                      width: 5 * scale,
                                                      height: 5 * scale,
                                                      decoration: const BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: Color(0xFF00F5D4),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  // --- Right Panel Bottom Right: NEIS Lunch Menu ---
  Widget _buildMealCard() {
    final scale = _settings.scaleFactor;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0 * scale, vertical: 12.0 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.restaurant_rounded, color: const Color(0xFF2CB67D), size: 18 * scale),
                        SizedBox(width: 8 * scale),
                        Text(
                          '오늘의 급식',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 15 * scale,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.sync_rounded, color: Colors.white30, size: 18 * scale),
                      onPressed: () {
                        final targetDate = _debugTimeOverride ?? DateTime.now();
                        _fetchLunchMenu(_settings.selectedSchool!.name, targetDate);
                        _fetchSchoolSchedule(_settings.selectedSchool!.name, targetDate);
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                SizedBox(height: 8 * scale),
                Expanded(
                  child: _isLoadingMeal
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF2CB67D),
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final lines = _mealInfo.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

                            double mealFontSize = 12.0;
                            double mealLineHeight = 1.25;

                            if (lines.length > 6) {
                              mealFontSize = 11.0;
                              mealLineHeight = 1.2;
                            }
                            if (lines.length > 8) {
                              mealFontSize = 10.0;
                              mealLineHeight = 1.15;
                            }

                            return ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: lines.map((line) => Padding(
                                    padding: EdgeInsets.only(bottom: 4.0 * scale),
                                    child: Text(
                                      line,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: mealFontSize * scale,
                                        color: Colors.white.withValues(alpha: 0.8),
                                        height: mealLineHeight,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )).toList(),
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

  // --- New unified right side panel: 7x2 launcher ---
  Widget _buildRightSidePanel() {
    if (_isUsbConnected) {
      return _buildCompact4x4Launcher();
    }
    return _buildCategorizedDashboardLauncher();
  }

  Widget _buildCompact4x4Launcher() {
    final scale = _settings.scaleFactor;
    final slots = _settings.launcherSlots;

    Widget buildHeader(String title, Color accentColor) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 4 * scale),
        child: Row(
          children: [
            Container(
              width: 4 * scale,
              height: 12 * scale,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
            SizedBox(width: 6 * scale),
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12 * scale,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(width: 4 * scale),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor.withOpacity(0.3),
                      accentColor.withOpacity(0.01)
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(8 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.015),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildHeader('BST 도구 (Compact)', const Color(0xFF00F5D4)),
          SizedBox(height: 6 * scale),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 6 * scale,
                mainAxisSpacing: 6 * scale,
                childAspectRatio: 1.0,
              ),
              itemCount: 16,
              itemBuilder: (context, index) {
                if (index == 14) {
                  return _buildCompactAutoOpenAndEjectSlot(scale);
                }
                if (index == 15) {
                  return _buildCompactExplorerToggleSlot(scale);
                }
                final slot = index < slots.length ? slots[index] : null;
                final globalIndex = index;
                if (slot == null || slot.type == LauncherSlotType.empty) {
                  return _buildEmptySlot(scale, globalIndex);
                }
                return _buildGridSlot(slot, scale, globalIndex);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAutoOpenAndEjectSlot(double scale) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(9),
                  topRight: Radius.circular(9),
                ),
                onTap: () async {
                  setState(() {
                    _usbAutoOpenEnabled = !_usbAutoOpenEnabled;
                  });
                  if (_usbSessionId.isNotEmpty) {
                    await UsbSessionService.instance.setAutoOpen(_usbSessionId, _usbAutoOpenEnabled);
                  }
                },
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _usbAutoOpenEnabled ? Icons.play_circle_filled_rounded : Icons.pause_circle_filled_rounded,
                        color: _usbAutoOpenEnabled ? const Color(0xFF00F5D4) : Colors.white38,
                        size: 14 * scale,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _usbAutoOpenEnabled ? '자동 실행 On' : '자동 실행 Off',
                        style: GoogleFonts.notoSansKr(
                          color: _usbAutoOpenEnabled ? const Color(0xFF00F5D4) : Colors.white38,
                          fontSize: 7.5 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(height: 1, color: Colors.white.withOpacity(0.05)),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(9),
                  bottomRight: Radius.circular(9),
                ),
                onTap: _ejectUsbDrive,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.eject_rounded,
                        color: const Color(0xFFEF4565),
                        size: 14 * scale,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'USB 안전 제거',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFFEF4565),
                          fontSize: 7.5 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactExplorerToggleSlot(double scale) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _showFullUsbExplorer = !_showFullUsbExplorer;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF00F5D4).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3), width: 1.2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _showFullUsbExplorer ? Icons.folder_rounded : Icons.auto_awesome_motion_rounded,
                color: const Color(0xFF00F5D4),
                size: 20 * scale,
              ),
              const SizedBox(height: 4),
              Text(
                _showFullUsbExplorer ? '수자탐으로' : '저파탐으로',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _showFullUsbExplorer ? '전체폴더 중' : '수업자료 중',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white38,
                  fontSize: 7.5 * scale,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ejectUsbDrive() async {
    if (_usbDriveLetter.isEmpty) return;
    try {
      final driveLetter = _usbDriveLetter.replaceAll('\\', '');
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(New-Object -ComObject Shell.Application).Namespace(17).ParseName('$driveLetter').InvokeVerb('Eject')"
      ]);
      if (result.exitCode == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2EC4B6),
              content: Text(
                'USB가 안전하게 제거되었습니다.',
                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
        _checkUsbConnection();
      } else {
        throw Exception('Powershell exit code ${result.exitCode}: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('Eject USB error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4565),
            content: Text(
              'USB 제거 실패: $e',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    }
  }

  Widget _buildCategorizedDashboardLauncher() {
    final scale = _settings.scaleFactor;
    final slots = _settings.launcherSlots;

    Widget buildSingleHeader(String title, Color accentColor) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 4 * scale),
        child: Row(
          children: [
            Container(
              width: 5 * scale,
              height: 14 * scale,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
            SizedBox(width: 8 * scale),
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13 * scale,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(width: 6 * scale),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor.withOpacity(0.3),
                      accentColor.withOpacity(0.01)
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(8 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.015),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildSingleHeader('Bst도구', const Color(0xFF00F5D4)),
          SizedBox(height: 6 * scale),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1열 (BST 도구 1)
                Expanded(
                  child: Column(
                    children: List.generate(7, (index) {
                      final slot = index < slots.length ? slots[index] : null;
                      final globalIndex = index;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(3 * scale),
                          child: (slot == null || slot.type == LauncherSlotType.empty)
                              ? _buildEmptySlot(scale, globalIndex)
                              : _buildGridSlot(slot, scale, globalIndex),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(width: 8 * scale),
                // 2열 (BST 도구 2)
                Expanded(
                  child: Column(
                    children: List.generate(7, (index) {
                      final globalIndex = index + 7;
                      final slot = globalIndex < slots.length ? slots[globalIndex] : null;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(3 * scale),
                          child: (slot == null || slot.type == LauncherSlotType.empty)
                              ? _buildEmptySlot(scale, globalIndex)
                              : _buildGridSlot(slot, scale, globalIndex),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(width: 8 * scale),
                // 3열 (기타 시스템 앱)
                Expanded(
                  child: Column(
                    children: List.generate(7, (index) {
                      final globalIndex = index + 14;
                      final slot = globalIndex < slots.length ? slots[globalIndex] : null;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(3 * scale),
                          child: (slot == null || slot.type == LauncherSlotType.empty)
                              ? _buildEmptySlot(scale, globalIndex)
                              : _buildGridSlot(slot, scale, globalIndex),
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

  Widget _buildStudentConnectionBanner(double scale) {
    return const SizedBox.shrink(); // Stubbed out since connection is integrated into Grid Row 2 Slot 4!
  }

  Widget _buildEmptySlot(double scale, int slotIndex) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAppSelectorForSlot(slotIndex),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.01),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04), width: 1),
          ),
          child: Icon(Icons.add_rounded, color: Colors.white12, size: 18 * scale),
        ),
      ),
    );
  }

  Widget _buildGridSlot(LauncherSlot slot, double scale, int slotIndex) {
    final isUpcoming = slot.id == 'student_connect';
    final colors = [
      const Color(0xFF2EC4B6),
      const Color(0xFF00F5D4),
      const Color(0xFF2CB67D),
    ];

    Color accentColor;
    IconData icon;

    if (slot.type == LauncherSlotType.systemApp) {
      final hasIcon = slot.iconPath != null &&
          slot.iconPath!.isNotEmpty &&
          File(slot.iconPath!).existsSync();
      accentColor = colors[slot.name.codeUnits.first % colors.length];
      final avatar = slot.name.length >= 2 ? slot.name.substring(0, 2) : slot.name;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _launchSystemApp(SystemApp(name: slot.name, appId: slot.id, iconPath: slot.iconPath)),
          onLongPress: () => _removeAppFromSlot(slotIndex),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: Container(
                    width: hasIcon ? 27 * scale : 22 * scale,
                    height: hasIcon ? 27 * scale : 22 * scale,
                    decoration: BoxDecoration(
                      color: hasIcon ? Colors.transparent : accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6 * scale),
                      border: hasIcon ? null : Border.all(color: accentColor.withValues(alpha: 0.5), width: 1),
                    ),
                    child: hasIcon
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6 * scale),
                            child: Image.file(
                              File(slot.iconPath!),
                              fit: BoxFit.contain,
                              width: 27 * scale,
                              height: 27 * scale,
                            ),
                          )
                        : Center(
                            child: Text(avatar,
                              style: GoogleFonts.notoSansKr(fontSize: 8.0 * scale, fontWeight: FontWeight.bold, color: accentColor)),
                          ),
                  ),
                ),
                SizedBox(height: 3 * scale),
                Text(slot.name,
                  style: GoogleFonts.notoSansKr(fontSize: 8.5 * scale, fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.75)),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Boardest tool slot
    accentColor = colors[slot.id.hashCode.abs() % colors.length];
    icon = _getToolIcon(slot.id);
    final onTap = _getToolOnTap(slot.id);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          InkWell(
            onTap: isUpcoming ? null : onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Center(
                    child: Container(
                      width: 22 * scale,
                      height: 22 * scale,
                      decoration: BoxDecoration(
                        color: (isUpcoming ? Colors.grey : accentColor).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6 * scale),
                        border: Border.all(color: (isUpcoming ? Colors.grey : accentColor).withValues(alpha: 0.5), width: 1),
                      ),
                      child: Center(
                        child: Icon(icon, color: isUpcoming ? Colors.grey : accentColor, size: 12 * scale),
                      ),
                    ),
                  ),
                  SizedBox(height: 3 * scale),
                  Text(slot.name,
                    style: GoogleFonts.notoSansKr(fontSize: 8.5 * scale, fontWeight: FontWeight.w600,
                      color: isUpcoming ? Colors.white30 : Colors.white.withValues(alpha: 0.75)),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (isUpcoming)
            Positioned(
              top: 2 * scale, right: 2 * scale,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF2EC4B6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF2EC4B6), width: 0.7),
                ),
                child: Text('예정', style: GoogleFonts.notoSansKr(fontSize: 6 * scale, fontWeight: FontWeight.bold, color: const Color(0xFF00F5D4))),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getToolIcon(String id) {
    switch (id) {
      // 단순 도구 (Simple Tools)
      case 'timer': return Icons.timer_rounded;
      case 'calculator': return Icons.calculate_rounded;
      case 'picker': return Icons.person_search_rounded;
      case 'weather': return Icons.wb_sunny_rounded;
      case 'school_calendar': return Icons.calendar_month_rounded;
      case 'notepad': return Icons.note_alt_rounded;

      // 판서 관련 (Annotation Tools)
      case 'whiteboard': return Icons.draw_rounded;
      case 'document_board': return Icons.description_rounded;
      case 'website_board': return Icons.language_rounded;
      case 'student_connect': return Icons.wifi_tethering_rounded;
      case 'settings': return Icons.tune_rounded;

      // 기타/유틸리티
      case 'file_explorer': return Icons.folder_open_rounded;
      case 'timetable': return Icons.calendar_view_week_rounded;
      case 'app_drawer': return Icons.apps_rounded;
      default: return Icons.apps_rounded;
    }
  }

  VoidCallback _getToolOnTap(String id) {
    switch (id) {
      // 단순 도구 (Simple Tools)
      case 'timer': return _openTimer;
      case 'calculator': return _openCalculator;
      case 'picker': return _openRandomPicker;
      case 'weather': return _openWeatherDialog;
      case 'school_calendar': return _openSchoolCalendarDialog;
      case 'notepad': return _openNotepad;

      // 판서 관련 (Annotation Tools)
      case 'whiteboard': return _openWhiteboard;
      case 'document_board': return _openDocumentBoard;
      case 'website_board': return _openWebsiteBoard;
      case 'ppt_board': return _openPptOverlay;
      case 'pdf_board': return _openPdfBoard;
      case 'student_connect': return _openStudentConnect;
      case 'settings': return _openSettingsWizard;

      // 기타/유틸리티
      case 'file_explorer': return _openFileExplorer;
      case 'timetable': return _openWeeklyTimetable;
      case 'app_drawer': return _openAppDrawer;
      default: return () {};
    }
  }

  Future<void> _fetchTimetableBackground() async {
    final settings = _settings;
    if (settings.selectedSchool == null) return;
    
    final schoolCode = settings.selectedSchool!.code;
    final targetDate = _debugTimeOverride ?? DateTime.now();
    final weekOffset = _getWeekOffset(targetDate, DateTime.now());
    
    try {
      final rawData = await _comciganService.fetchTimetableRaw(schoolCode, weekOffset: weekOffset);
      final cacheKey = 'cached_timetable_${schoolCode}_$weekOffset';
      
      final prefs = await SharedPreferences.getInstance();
      final previousCachedStr = prefs.getString(cacheKey);
      final newRawStr = json.encode(rawData);
      
      if (previousCachedStr != newRawStr) {
        final result = _comciganService.parseTimetable(rawData);
        await prefs.setString(cacheKey, newRawStr);
        if (mounted) {
          setState(() {
            _timetableResult = result;
          });
          _updateLiveSchedule();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '시간표 변경 사항이 실시간 인식되어 업데이트되었습니다. 🗓️',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFF00F5D4),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Background timetable refresh error: $e');
    }
  }

  void _startDashboardTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_debugTimeOverride != null) {
        setState(() {
          _debugTimeOverride = _debugTimeOverride!.add(const Duration(seconds: 1));
        });
      }
      _updateLiveSchedule();
      
      // 시간표 변경 자동 실시간 감지 (매 10분마다 실행)
      _timetableCheckCounter++;
      if (_timetableCheckCounter >= 600) {
        _timetableCheckCounter = 0;
        _fetchTimetableBackground();
      }
      
      // 매 60초마다 Class 계정 온라인 상태 Firestore 갱신
      _onlineStatusCounter++;
      if (_onlineStatusCounter >= 60) {
        _onlineStatusCounter = 0;
        _updateOnlineStatusBackground();
      }
      
      if (Platform.isWindows && _settings.autoSleepEnabled) {
        final now = _debugTimeOverride ?? DateTime.now();
        final ranges = _scheduleRangesForSleep(now);
        _sleepScheduler.refreshRanges(ranges);
        
        if (_sleepScheduler.isDeviceAsleep) {
          if (!_sleepScheduler.shouldSleep(now)) {
            _sleepScheduler.checkAndExecuteSleep(customNow: now);
          }
        } else {
          if (_sleepScheduler.shouldSleep(now)) {
            if (!_showSleepWarning) {
              _triggerSleepWarning();
            }
          } else {
            if (_showSleepWarning) {
              _cancelSleepWarning();
            }
          }
        }
      }
    });
  }

  void _triggerSleepWarning() {
    if (_showSleepWarning) return;
    _showSleepWarning = true;
    _sleepCountdownSeconds = 30;
    _dialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _sleepWarningTimer?.cancel();
            _sleepWarningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (!mounted || !_showSleepWarning) {
                timer.cancel();
                if (_dialogOpen) {
                  _dialogOpen = false;
                  Navigator.of(dialogContext).pop();
                }
                return;
              }
              if (_sleepCountdownSeconds <= 1) {
                timer.cancel();
                _showSleepWarning = false;
                if (_dialogOpen) {
                  _dialogOpen = false;
                  Navigator.of(dialogContext).pop();
                }
                final now = _debugTimeOverride ?? DateTime.now();
                _sleepScheduler.checkAndExecuteSleep(customNow: now);
              } else {
                setDialogState(() {
                  _sleepCountdownSeconds--;
                });
              }
            });

            final scale = _settings.scaleFactor;
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AlertDialog(
                backgroundColor: const Color(0xFF0F0E17).withOpacity(0.9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: const Color(0xFFEF4565).withOpacity(0.4), width: 2),
                ),
                title: Row(
                  children: [
                    const Icon(Icons.power_settings_new_rounded, color: Color(0xFFEF4565), size: 28),
                    const SizedBox(width: 12),
                    Text(
                      '모니터 절전모드 진입 예정',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),
                    Text(
                      '하교 후 또는 쉬는 시간 시간표 일정에 따라\n$_sleepCountdownSeconds초 후 화면이 자동으로 꺼집니다.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white70,
                        fontSize: 14 * scale,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80 * scale,
                          height: 80 * scale,
                          child: CircularProgressIndicator(
                            value: _sleepCountdownSeconds / 30,
                            strokeWidth: 6,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEF4565)),
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        Text(
                          '$_sleepCountdownSeconds',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 32 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
                actionsAlignment: MainAxisAlignment.center,
                actionsPadding: EdgeInsets.only(bottom: 20 * scale, left: 20 * scale, right: 20 * scale),
                actions: [
                  ElevatedButton(
                    onPressed: _snoozeSleep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4565),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 32 * scale, vertical: 14 * scale),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      '절전 취소 (5분 연장)',
                      style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.bold,
                        fontSize: 13 * scale,
                      ),
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

  void _snoozeSleep() {
    _sleepWarningTimer?.cancel();
    _showSleepWarning = false;
    if (_dialogOpen) {
      _dialogOpen = false;
      Navigator.of(context).pop();
    }
    final now = _debugTimeOverride ?? DateTime.now();
    _sleepScheduler.snooze(const Duration(minutes: 5), customNow: now);
    debugPrint('[SleepScheduler] Sleep warning snoozed for 5 minutes.');
  }

  void _cancelSleepWarning() {
    _sleepWarningTimer?.cancel();
    _showSleepWarning = false;
    if (_dialogOpen) {
      _dialogOpen = false;
      Navigator.of(context).pop();
    }
  }

  void _pauseDashboardTimer() {
    _timer?.cancel();
    _timer = null;
    debugPrint('[Boardest] Dashboard timer paused.');
  }

  void _resumeDashboardTimer() {
    _startDashboardTimer();
    debugPrint('[Boardest] Dashboard timer resumed.');
  }

  Future<T?> _pushBoardRoute<T>(Widget page) async {
    _pauseDashboardTimer();
    final wasSpecial = _settings.specialClassroomMode;
    if (wasSpecial && Platform.isWindows) {
      const channel = MethodChannel('com.boardest/launch_args');
      try {
        await channel.invokeMethod('setSpecialClassroomMode', false);
      } catch (e) {
        debugPrint('Failed to disable special classroom mode: $e');
      }
    }
    
    final result = await Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (context) => page),
    );
    
    if (wasSpecial && Platform.isWindows) {
      const channel = MethodChannel('com.boardest/launch_args');
      try {
        await channel.invokeMethod('setSpecialClassroomMode', true);
      } catch (e) {
        debugPrint('Failed to enable special classroom mode: $e');
      }
    }
    _resumeDashboardTimer();
    return result;
  }

  void _openUpcomingToolDialog(String title, String description, Color accentColor) {
    final scale = _settings.scaleFactor;
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F0E17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: accentColor.withOpacity(0.3), width: 1.5),
          ),
          title: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: accentColor, size: 28),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentColor.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: accentColor, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '모바일 기기 연결 및 기능 고도화 작업이 진행 중입니다.',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '확인',
                style: GoogleFonts.notoSansKr(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAppSelectorForSlot(int slotIndex) async {
    final scale = _settings.scaleFactor;
    
    // Get the cached/scanned apps
    final apps = SystemAppScanner.externalAppsOnly(
      await SystemAppScanner.scanInstalledApps(),
    );
    
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final filteredApps = apps.where((app) {
              return app.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                     app.appId.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AlertDialog(
                backgroundColor: const Color(0xFF0F0E17).withOpacity(0.9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: const Color(0xFF2EC4B6).withOpacity(0.3), width: 1.5),
                ),
                titlePadding: EdgeInsets.fromLTRB(24 * scale, 20 * scale, 20 * scale, 12 * scale),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.apps_rounded, color: Color(0xFF00F5D4)),
                        SizedBox(width: 10 * scale),
                        Text(
                          '바로가기 앱 추가',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.white54, size: 20 * scale),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 20 * scale),
                content: SizedBox(
                  width: 460 * scale,
                  height: 480 * scale,
                  child: Column(
                    children: [
                      // Search TextField
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: TextField(
                          style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * scale),
                          decoration: InputDecoration(
                            hintText: '프로그램 이름 검색...',
                            hintStyle: GoogleFonts.notoSansKr(color: Colors.white24, fontSize: 13 * scale),
                            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white30),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12 * scale),
                          ),
                          onChanged: (val) {
                            setStateDialog(() {
                              searchQuery = val;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 16 * scale),
                      // System apps list
                      Expanded(
                        child: filteredApps.isEmpty
                            ? Center(
                                child: Text(
                                  '검색 결과가 없습니다.',
                                  style: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 13 * scale),
                                ),
                              )
                            : ListView.separated(
                                physics: const BouncingScrollPhysics(),
                                itemCount: filteredApps.length,
                                separatorBuilder: (_, __) => SizedBox(height: 8 * scale),
                                itemBuilder: (context, idx) {
                                  final app = filteredApps[idx];
                                  final hasIcon = app.iconPath != null && app.iconPath!.isNotEmpty && File(app.iconPath!).existsSync();
                                  
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () async {
                                        // Update the slot!
                                        final updatedSlots = List<LauncherSlot>.from(_settings.launcherSlots);
                                        updatedSlots[slotIndex] = LauncherSlot(
                                          type: LauncherSlotType.systemApp,
                                          name: app.name,
                                          id: app.appId,
                                          iconPath: app.iconPath,
                                        );
                                        
                                        final newSettings = _settings.copyWith(launcherSlots: updatedSlots);
                                        await _storageService.saveSettings(newSettings);
                                        setState(() {
                                          _settings = newSettings;
                                        });
                                        
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                        }
                                      },
                                      child: Container(
                                        padding: EdgeInsets.all(10 * scale),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.015),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white.withOpacity(0.03)),
                                        ),
                                        child: Row(
                                          children: [
                                            // Icon
                                            Container(
                                              width: 32 * scale,
                                              height: 32 * scale,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.02),
                                                borderRadius: BorderRadius.circular(8 * scale),
                                              ),
                                              child: hasIcon
                                                  ? ClipRRect(
                                                      borderRadius: BorderRadius.circular(8 * scale),
                                                      child: Image.file(
                                                        File(app.iconPath!),
                                                        fit: BoxFit.contain,
                                                      ),
                                                    )
                                                  : Icon(Icons.insert_drive_file_rounded, color: Colors.white30, size: 16 * scale),
                                            ),
                                            SizedBox(width: 14 * scale),
                                            // Name and AppId
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    app.name,
                                                    style: GoogleFonts.notoSansKr(
                                                      color: Colors.white.withOpacity(0.9),
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12 * scale,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  SizedBox(height: 2 * scale),
                                                  Text(
                                                    app.appId,
                                                    style: GoogleFonts.outfit(
                                                      color: Colors.white24,
                                                      fontSize: 9 * scale,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actionsPadding: EdgeInsets.fromLTRB(0, 0, 20 * scale, 16 * scale),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '닫기',
                      style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 13 * scale),
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

  void _removeAppFromSlot(int slotIndex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F0E17).withOpacity(0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: const Color(0xFF2EC4B6).withOpacity(0.2)),
          ),
          title: Text('앱 바로가기 삭제', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text('해당 슬롯의 바로가기 앱을 삭제하시겠습니까?', style: GoogleFonts.notoSansKr(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('삭제', style: GoogleFonts.notoSansKr(color: const Color(0xFFEF4565), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final updatedSlots = List<LauncherSlot>.from(_settings.launcherSlots);
      updatedSlots[slotIndex] = LauncherSlot(type: LauncherSlotType.empty, name: '', id: '');
      final newSettings = _settings.copyWith(launcherSlots: updatedSlots);
      await _storageService.saveSettings(newSettings);
      setState(() {
        _settings = newSettings;
      });
    }
  }

  Future<void> _launchSystemApp(SystemApp app) async {
    final appId = app.appId;
    if (appId.startsWith('http://') || appId.startsWith('https://')) {
      _launchURL(appId);
    } else {
      final success = await SystemAppScanner.launchApp(appId);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${app.name} 앱을 실행할 수 없습니다.')),
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
        _pickerWindowOffset = const Offset(150, 100);
      }
    });
  }

  void _openWhiteboard() {
    _openWhiteboardAsync();
  }

  Future<void> _openWhiteboardAsync() async {
    await BstSaveService.instance.ensureStructure();

    String? teacher;
    String? subject;
    String targetPath;

    final period = _currentPeriod;
    final lesson = _currentLesson;
    final isBreakTime = period == null ||
        !period.isClass ||
        period.label.contains('쉬는') ||
        period.label.contains('점심');

    if (isBreakTime) {
      final boardDir =
          await BstSaveService.instance.directoryFor(BstSaveService.subBoard);
      targetPath = p.join(boardDir.path, 'quick_board.iwb');
    } else if (lesson != null &&
        lesson.teacher.isNotEmpty &&
        lesson.subject.isNotEmpty) {
      teacher = lesson.teacher;
      subject = lesson.subject;
      targetPath = await BoardStorageService.instance.resolveBoardPathForLesson(
        teacher: teacher,
        subject: subject,
      );
    } else {
      final boardDir =
          await BstSaveService.instance.directoryFor(BstSaveService.subBoard);
      targetPath = p.join(boardDir.path, 'quick_board.iwb');
    }

    _pushBoardRoute(BoardestPenView(
      filePath: targetPath,
      scaleFactor: _settings.scaleFactor,
      teacher: teacher,
      subject: subject,
    ));
  }

  void _openStudentConnect() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF00F5D4)),
            const SizedBox(width: 8),
            Text(
              '학생 기기 연동 기능은 추후 지원될 예정입니다.',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1B24),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF2EC4B6), width: 1.5),
        ),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openClassroomDice() {
    showDialog(
      context: context,
      builder: (context) => const ClassroomDiceModal(),
    );
  }

  void _openNoiseMeter() {
    showDialog(
      context: context,
      builder: (context) => const NoiseMeterModal(),
    );
  }

  int _timerTargetSeconds = 0;

  void _startMiniTimer() {
    if (_timerRunning) return;
    setState(() {
      _timerRunning = true;
    });
    _miniTimerInstance?.cancel();
    _miniTimerInstance = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_timerTargetSeconds > 0) {
          if (_timerSecondsElapsed > 0) {
            _timerSecondsElapsed--;
            if (_timerSecondsElapsed == 0) {
              _timerRunning = false;
              _miniTimerInstance?.cancel();
              _miniTimerInstance = null;
            }
          } else {
            _timerRunning = false;
            _miniTimerInstance?.cancel();
            _miniTimerInstance = null;
          }
        } else {
          _timerSecondsElapsed++;
        }
      });
    });
  }

  void _pauseMiniTimer() {
    _miniTimerInstance?.cancel();
    _miniTimerInstance = null;
    setState(() {
      _timerRunning = false;
    });
  }

  void _resetMiniTimer() {
    _miniTimerInstance?.cancel();
    _miniTimerInstance = null;
    setState(() {
      _timerSecondsElapsed = _timerTargetSeconds;
      _timerRunning = false;
    });
  }

  void _adjustMiniTimer(int additionalSeconds) {
    setState(() {
      if (!_timerRunning && _timerSecondsElapsed == 0) {
        _timerTargetSeconds = additionalSeconds;
        _timerSecondsElapsed = additionalSeconds;
      } else {
        _timerTargetSeconds += additionalSeconds;
        if (_timerTargetSeconds < 0) _timerTargetSeconds = 0;
        _timerSecondsElapsed += additionalSeconds;
        if (_timerSecondsElapsed < 0) _timerSecondsElapsed = 0;
      }
    });
  }

  Widget _buildMiniTimerWindow(double scale) {
    final accentColor = const Color(0xFF00F5D4);
    final String timeText = '${(_timerSecondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_timerSecondsElapsed % 60).toString().padLeft(2, '0')}';
    final isCountdown = _timerTargetSeconds > 0;
    final isZero = _timerSecondsElapsed == 0;
    
    if (_timerFullscreen) {
      return Positioned.fill(
        child: Container(
          color: const Color(0xFF0A0A0D).withOpacity(0.98),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 600 * scale,
                  height: 600 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_timerRunning ? accentColor : const Color(0xFFEF4565)).withValues(alpha: 0.025),
                    boxShadow: _timerRunning
                        ? [
                            BoxShadow(
                              color: accentColor.withOpacity(0.04),
                              blurRadius: 150 * scale,
                              spreadRadius: 10 * scale,
                            )
                          ]
                        : null,
                  ),
                ),
              ),
              
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isCountdown ? '남은 시간' : '경과 시간',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white38,
                        fontSize: 24 * scale,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: 20 * scale),
                    
                    Text(
                      timeText,
                      style: GoogleFonts.outfit(
                        fontSize: 220 * scale,
                        fontWeight: FontWeight.w900,
                        color: isZero && isCountdown ? const Color(0xFFEF4565) : accentColor,
                        letterSpacing: 6,
                        shadows: [
                          Shadow(
                            color: (isZero && isCountdown ? const Color(0xFFEF4565) : accentColor).withOpacity(0.8),
                            blurRadius: 40 * scale,
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: 40 * scale),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _timerRunning ? _pauseMiniTimer : _startMiniTimer,
                          icon: Icon(_timerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28 * scale),
                          label: Text(_timerRunning ? '일시정지' : '시작', style: GoogleFonts.notoSansKr(fontSize: 20 * scale, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _timerRunning ? Colors.orangeAccent : const Color(0xFF2EC4B6),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 40 * scale, vertical: 18 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                        SizedBox(width: 20 * scale),
                        ElevatedButton.icon(
                          onPressed: _resetMiniTimer,
                          icon: Icon(Icons.replay_rounded, size: 28 * scale),
                          label: Text('초기화', style: GoogleFonts.notoSansKr(fontSize: 20 * scale, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4565),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 40 * scale, vertical: 18 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: 40 * scale),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildBigPresetBtn('+1분', () => _adjustMiniTimer(60), scale),
                        _buildBigPresetBtn('+3분', () => _adjustMiniTimer(180), scale),
                        _buildBigPresetBtn('+5분', () => _adjustMiniTimer(300), scale),
                        _buildBigPresetBtn('+10분', () => _adjustMiniTimer(600), scale),
                        _buildBigPresetBtn('Clear', () {
                          setState(() {
                            _timerTargetSeconds = 0;
                            _timerSecondsElapsed = 0;
                            _timerRunning = false;
                            _miniTimerInstance?.cancel();
                          });
                        }, scale, isClear: true),
                      ],
                    ),
                  ],
                ),
              ),
              
              Positioned(
                top: 20 * scale,
                right: 20 * scale,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.fullscreen_exit_rounded, color: Colors.white70, size: 36 * scale),
                      onPressed: () {
                        setState(() {
                          _timerFullscreen = false;
                        });
                      },
                      tooltip: '전체화면 종료',
                    ),
                    SizedBox(width: 10 * scale),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: const Color(0xFFEF4565), size: 36 * scale),
                      onPressed: () {
                        setState(() {
                          _showMiniTimer = false;
                          _miniTimerInstance?.cancel();
                        });
                      },
                      tooltip: '타이머 닫기',
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      );
    }
    
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
          color: Colors.transparent,
          child: Container(
            width: 250 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withOpacity(0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
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
                      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                      color: Colors.white.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(Icons.timer_rounded, color: accentColor, size: 14 * scale),
                          SizedBox(width: 8 * scale),
                          Text(
                            isCountdown ? '타이머' : '스톱워치',
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
                            icon: Icon(Icons.fullscreen_rounded, color: Colors.white60, size: 14 * scale),
                            onPressed: () {
                              setState(() {
                                _timerFullscreen = true;
                              });
                            },
                            tooltip: '전체화면 교실 모드',
                          ),
                          SizedBox(width: 10 * scale),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.close_rounded, color: const Color(0xFFEF4565), size: 14 * scale),
                            onPressed: () {
                              setState(() {
                                _showMiniTimer = false;
                                _miniTimerInstance?.cancel();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    Padding(
                      padding: EdgeInsets.all(12.0 * scale),
                      child: Column(
                        children: [
                          Text(
                            timeText,
                            style: GoogleFonts.outfit(
                              fontSize: 48 * scale,
                              fontWeight: FontWeight.bold,
                              color: isZero && isCountdown ? const Color(0xFFEF4565) : accentColor,
                              shadows: [
                                Shadow(
                                  color: (isZero && isCountdown ? const Color(0xFFEF4565) : accentColor).withOpacity(0.5),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 6 * scale),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildMiniPresetBtn('+1m', () => _adjustMiniTimer(60), scale),
                              _buildMiniPresetBtn('+3m', () => _adjustMiniTimer(180), scale),
                              _buildMiniPresetBtn('+5m', () => _adjustMiniTimer(300), scale),
                              _buildMiniPresetBtn('Reset', () {
                                setState(() {
                                  _timerTargetSeconds = 0;
                                  _timerSecondsElapsed = 0;
                                  _timerRunning = false;
                                  _miniTimerInstance?.cancel();
                                });
                              }, scale, isClear: true),
                            ],
                          ),
                          SizedBox(height: 10 * scale),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: _timerRunning ? _pauseMiniTimer : _startMiniTimer,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _timerRunning ? Colors.orangeAccent : const Color(0xFF2EC4B6),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(_timerRunning ? '일시정지' : '시작', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
                              ),
                              SizedBox(width: 8 * scale),
                              ElevatedButton(
                                onPressed: _resetMiniTimer,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4565),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text('초기화', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          )
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

  Widget _buildMiniPresetBtn(String label, VoidCallback onTap, double scale, {bool isClear = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
        decoration: BoxDecoration(
          color: isClear ? const Color(0xFFEF4565).withOpacity(0.12) : const Color(0xFF00F5D4).withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isClear ? const Color(0xFFEF4565).withOpacity(0.3) : const Color(0xFF00F5D4).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 9 * scale,
            fontWeight: FontWeight.bold,
            color: isClear ? const Color(0xFFEF4565) : const Color(0xFF00F5D4),
          ),
        ),
      ),
    );
  }

  Widget _buildBigPresetBtn(String label, VoidCallback onTap, double scale, {bool isClear = false}) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8 * scale),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isClear ? const Color(0xFFEF4565).withOpacity(0.15) : const Color(0xFF00F5D4).withOpacity(0.1),
          foregroundColor: isClear ? const Color(0xFFEF4565) : const Color(0xFF00F5D4),
          padding: EdgeInsets.symmetric(horizontal: 30 * scale, vertical: 14 * scale),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isClear ? const Color(0xFFEF4565).withOpacity(0.4) : const Color(0xFF00F5D4).withOpacity(0.4), width: 1.5),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 18 * scale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _calcExpression = '';
  String _calcResult = '';

  void _onCalcKeyPress(String val) {
    setState(() {
      if (val == 'C' || val == 'AC') {
        _calcExpression = '';
        _calcResult = '';
      } else if (val == '⌫') {
        if (_calcExpression.isNotEmpty) {
          _calcExpression = _calcExpression.substring(0, _calcExpression.length - 1);
        }
      } else if (val == '=') {
        _evaluateCalcExpression();
      } else {
        final operators = ['+', '-', '*', '/'];
        if (_calcExpression.isNotEmpty) {
          final lastChar = _calcExpression[_calcExpression.length - 1];
          if (operators.contains(lastChar) && operators.contains(val)) {
            _calcExpression = _calcExpression.substring(0, _calcExpression.length - 1) + val;
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
      String expr = _calcExpression.replaceAll('*', ' * ').replaceAll('/', ' / ').replaceAll('+', ' + ').replaceAll('-', ' - ');
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
              border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
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
                      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                      color: Colors.white.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(Icons.calculate_rounded, color: accentColor, size: 14 * scale),
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
                            icon: Icon(Icons.close_rounded, color: const Color(0xFFEF4565), size: 14 * scale),
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
                      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
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
                                  color: const Color(0xFF00F5D4).withOpacity(0.4),
                                  blurRadius: 8,
                                )
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
                            : (isClear ? const Color(0xFFEF4565).withOpacity(0.3) : Colors.white.withOpacity(0.06)),
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
              border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
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
                      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                      color: Colors.white.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(Icons.emoji_people_rounded, color: accentColor, size: 14 * scale),
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
                            icon: Icon(Icons.close_rounded, color: const Color(0xFFEF4565), size: 14 * scale),
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
                                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11 * scale),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                                    icon: Icon(Icons.remove_circle_outline, color: const Color(0xFF2EC4B6), size: 16 * scale),
                                    onPressed: _pickerRolling ? null : () {
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
                                    padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                                    icon: Icon(Icons.add_circle_outline, color: const Color(0xFF2EC4B6), size: 16 * scale),
                                    onPressed: _pickerRolling ? null : () {
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
                                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
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
                                disabledBackgroundColor: const Color(0xFF2EC4B6).withOpacity(0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: _pickerRolling ? null : () async {
                                setState(() {
                                  _pickerRolling = true;
                                  _pickerWinner = null;
                                });
                                final random = DateTime.now().millisecondsSinceEpoch;
                                int rollCount = 15;
                                for (int i = 0; i < rollCount; i++) {
                                  await Future.delayed(Duration(milliseconds: 50 + (i * 15)));
                                  if (!mounted) return;
                                  final candidate = ((random + i) % _pickerMaxStudents) + 1;
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

  Widget _buildMiniWeatherWindow(double scale) {
    final accentColor = const Color(0xFF00F5D4);
    const String temp = '23°';
    const String status = '대체로 맑음';
    const String loc = '우리학교 (교실)';
    const String humidity = '48%';
    const String wind = '3.2 m/s';
    const String fineDust = '18 ㎍/㎥ (좋음)';
    const String uv = '보통 (4)';
    final weeklyForecast = [
      {'day': '오늘', 'temp': '15°/24°', 'icon': Icons.wb_sunny_rounded, 'color': Colors.amberAccent},
      {'day': '내일', 'temp': '16°/25°', 'icon': Icons.wb_cloudy_rounded, 'color': Colors.blueGrey},
      {'day': '화요일', 'temp': '14°/23°', 'icon': Icons.umbrella_rounded, 'color': Colors.blueAccent},
      {'day': '수요일', 'temp': '15°/26°', 'icon': Icons.wb_sunny_rounded, 'color': Colors.amberAccent},
      {'day': '목요일', 'temp': '17°/27°', 'icon': Icons.wb_sunny_rounded, 'color': Colors.amberAccent},
    ];

    return Positioned(
      left: _weatherWindowOffset.dx,
      top: _weatherWindowOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _weatherWindowOffset += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 320 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withOpacity(0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
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
                      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                      color: Colors.white.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(Icons.wb_sunny_rounded, color: accentColor, size: 14 * scale),
                          SizedBox(width: 8 * scale),
                          Text(
                            '기상 정보',
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
                            icon: Icon(Icons.close_rounded, color: const Color(0xFFEF4565), size: 14 * scale),
                            onPressed: () {
                              setState(() {
                                _showMiniWeather = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    // Main Area
                    Padding(
                      padding: EdgeInsets.all(12.0 * scale),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: EdgeInsets.all(10 * scale),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF2EC4B6).withOpacity(0.15),
                                  const Color(0xFF2CB67D).withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.06)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.wb_sunny_rounded, size: 40 * scale, color: Colors.amberAccent),
                                SizedBox(width: 12 * scale),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        loc,
                                        style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 9 * scale),
                                      ),
                                      Text(
                                        temp,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 24 * scale,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        status,
                                        style: GoogleFonts.notoSansKr(
                                          color: accentColor,
                                          fontSize: 10 * scale,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 10 * scale),
                          Row(
                            children: [
                              Expanded(child: _buildMiniWeatherDetailCard('습도', humidity, Icons.water_drop_rounded, const Color(0xFF00F5D4), scale)),
                              SizedBox(width: 6 * scale),
                              Expanded(child: _buildMiniWeatherDetailCard('바람', wind, Icons.air_rounded, const Color(0xFF2CB67D), scale)),
                            ],
                          ),
                          SizedBox(height: 6 * scale),
                          Row(
                            children: [
                              Expanded(child: _buildMiniWeatherDetailCard('미세먼지', fineDust, Icons.grain_rounded, Colors.amberAccent, scale)),
                              SizedBox(width: 6 * scale),
                              Expanded(child: _buildMiniWeatherDetailCard('자외선', uv, Icons.wb_sunny_outlined, Colors.orangeAccent, scale)),
                            ],
                          ),
                          SizedBox(height: 10 * scale),
                          Divider(color: Colors.white.withOpacity(0.08), height: 1),
                          SizedBox(height: 8 * scale),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '주간 예보',
                              style: GoogleFonts.notoSansKr(color: Colors.white60, fontSize: 9 * scale, fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(height: 6 * scale),
                          SizedBox(
                            height: 62 * scale,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: weeklyForecast.map((f) {
                                return Container(
                                  width: 54 * scale,
                                  padding: EdgeInsets.symmetric(vertical: 4 * scale),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.02),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        f['day'] as String,
                                        style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 8 * scale),
                                      ),
                                      SizedBox(height: 2 * scale),
                                      Icon(
                                        f['icon'] as IconData,
                                        color: f['color'] as Color,
                                        size: 14 * scale,
                                      ),
                                      SizedBox(height: 2 * scale),
                                      Text(
                                        f['temp'] as String,
                                        style: GoogleFonts.outfit(color: Colors.white.withOpacity(0.85), fontSize: 8 * scale, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
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

  Widget _buildMiniWeatherDetailCard(String title, String val, IconData icon, Color iconColor, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 6 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 12 * scale),
          SizedBox(width: 6 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 8 * scale),
                ),
                Text(
                  val,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 9 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCalendarWindow(double scale) {
    final accentColor = const Color(0xFF00F5D4);
    final firstDay = DateTime(_miniCalendarMonth.year, _miniCalendarMonth.month, 1);
    final lastDay = DateTime(_miniCalendarMonth.year, _miniCalendarMonth.month + 1, 0);
    final daysCount = lastDay.day;
    final startWeekday = firstDay.weekday % 7;
    final totalCells = ((daysCount + startWeekday) / 7).ceil() * 7;
    final weekDays = ['일', '월', '화', '수', '목', '금', '토'];

    List<String> getEventsForDay(DateTime day) {
      final list = <String>[];
      for (final ev in _apiScheduleEvents) {
        final date = ev['date'] as DateTime?;
        final title = ev['title'] as String?;
        if (date != null && title != null) {
          if (date.year == day.year && date.month == day.month && date.day == day.day) {
            list.add(title);
          }
        }
      }
      if (list.isEmpty && _apiScheduleEvents.isEmpty) {
        final now = DateTime.now();
        if (day.year == now.year && day.month == now.month) {
          if (day.day == 10) list.add('수행평가');
          if (day.day == 14) list.add('학부모상담');
          if (day.day == 24) list.add('중간고사');
          if (day.day == 25) list.add('중간고사');
        }
      }
      return list;
    }

    return Positioned(
      left: _calendarWindowOffset.dx,
      top: _calendarWindowOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _calendarWindowOffset += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 380 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withOpacity(0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
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
                      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                      color: Colors.white.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(
                            _showWeeklyTimetableInCalendar ? Icons.view_week_rounded : Icons.calendar_month_rounded,
                            color: accentColor,
                            size: 14 * scale,
                          ),
                          SizedBox(width: 8 * scale),
                          Text(
                            _showWeeklyTimetableInCalendar ? '주간 시간표' : '학사달력',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.bold,
                              fontSize: 11 * scale,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            icon: Icon(
                              _showWeeklyTimetableInCalendar ? Icons.calendar_month_rounded : Icons.view_week_rounded,
                              color: accentColor,
                              size: 16 * scale,
                            ),
                            tooltip: _showWeeklyTimetableInCalendar ? '학사달력 보기' : '주간 시간표 보기',
                            onPressed: () {
                              setState(() {
                                _showWeeklyTimetableInCalendar = !_showWeeklyTimetableInCalendar;
                              });
                            },
                          ),
                          SizedBox(width: 4 * scale),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.close_rounded, color: const Color(0xFFEF4565), size: 14 * scale),
                            onPressed: () {
                              setState(() {
                                _showMiniCalendar = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(12.0 * scale),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _showWeeklyTimetableInCalendar
                            ? [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '주간 수업 시간표',
                                      style: GoogleFonts.notoSansKr(
                                        color: Colors.white,
                                        fontSize: 12 * scale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${_settings.selectedGrade}학년 ${_settings.selectedClass}반',
                                      style: GoogleFonts.notoSansKr(
                                        color: accentColor,
                                        fontSize: 10 * scale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10 * scale),
                                Row(
                                  children: [
                                    SizedBox(width: 32 * scale),
                                    ...['월', '화', '수', '목', '금'].map((dayName) => Expanded(
                                      child: Center(
                                        child: Text(
                                          dayName,
                                          style: GoogleFonts.notoSansKr(
                                            color: accentColor,
                                            fontSize: 10 * scale,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )),
                                  ],
                                ),
                                SizedBox(height: 6 * scale),
                                ...List.generate(7, (periodIdx) {
                                  final period = periodIdx + 1;
                                  return Padding(
                                    padding: EdgeInsets.symmetric(vertical: 3 * scale),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 26 * scale,
                                          height: 32 * scale,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.04),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '$period',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white70,
                                              fontSize: 10 * scale,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 6 * scale),
                                        ...List.generate(5, (dayIdx) {
                                          final weekday = dayIdx + 1;
                                          final dayLessons = _getLessonsForDay(weekday);
                                          final lesson = dayLessons.firstWhere(
                                            (l) => l.classTime == period,
                                            orElse: () => Lesson(
                                              grade: 1,
                                              classNum: 1,
                                              weekday: weekday,
                                              classTime: period,
                                              subject: '',
                                              teacher: '',
                                              classroom: '',
                                              isChanged: false,
                                            ),
                                          );
                                          final hasLesson = lesson.subject.isNotEmpty;
                                          return Expanded(
                                            child: Container(
                                              height: 32 * scale,
                                              margin: EdgeInsets.symmetric(horizontal: 2 * scale),
                                              decoration: BoxDecoration(
                                                color: hasLesson 
                                                    ? accentColor.withOpacity(0.06)
                                                    : Colors.white.withOpacity(0.01),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: hasLesson
                                                      ? accentColor.withOpacity(0.15)
                                                      : Colors.white.withOpacity(0.03),
                                                  width: 0.8,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: hasLesson
                                                  ? Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          lesson.subject,
                                                          style: GoogleFonts.notoSansKr(
                                                            color: Colors.white.withOpacity(0.95),
                                                            fontSize: 9 * scale,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        if (lesson.classroom.isNotEmpty)
                                                          Text(
                                                            lesson.classroom,
                                                            style: GoogleFonts.notoSansKr(
                                                              color: const Color(0xFF2CB67D).withOpacity(0.8),
                                                              fontSize: 7 * scale,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                      ],
                                                    )
                                                  : Text(
                                                      '-',
                                                      style: GoogleFonts.outfit(
                                                        color: Colors.white24,
                                                        fontSize: 10 * scale,
                                                      ),
                                                    ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                }),
                              ]
                            : [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      icon: Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 20 * scale),
                                      onPressed: () {
                                        setState(() {
                                          _miniCalendarMonth = DateTime(_miniCalendarMonth.year, _miniCalendarMonth.month - 1, 1);
                                        });
                                      },
                                    ),
                                    Text(
                                      '${_miniCalendarMonth.year}년 ${_miniCalendarMonth.month}월',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 14 * scale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      icon: Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 20 * scale),
                                      onPressed: () {
                                        setState(() {
                                          _miniCalendarMonth = DateTime(_miniCalendarMonth.year, _miniCalendarMonth.month + 1, 1);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8 * scale),
                                Row(
                                  children: weekDays.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final dayName = entry.value;
                                    Color textColor = Colors.white54;
                                    if (idx == 0) textColor = const Color(0xFFEF4565);
                                    if (idx == 6) textColor = const Color(0xFF00F5D4);
                                    return Expanded(
                                      child: Center(
                                        child: Text(
                                          dayName,
                                          style: GoogleFonts.notoSansKr(
                                            color: textColor,
                                            fontSize: 10 * scale,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                SizedBox(height: 6 * scale),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    childAspectRatio: 1.15,
                                    crossAxisSpacing: 3,
                                    mainAxisSpacing: 3,
                                  ),
                                  itemCount: totalCells,
                                  itemBuilder: (context, index) {
                                    final dayNum = index - startWeekday + 1;
                                    final isCurrentMonth = dayNum > 0 && dayNum <= daysCount;
                                    if (!isCurrentMonth) return const SizedBox.shrink();
                                    final cellDate = DateTime(_miniCalendarMonth.year, _miniCalendarMonth.month, dayNum);
                                    final dayEvents = getEventsForDay(cellDate);
                                    final hasEvents = dayEvents.isNotEmpty;
                                    final isToday = DateTime.now().year == cellDate.year &&
                                        DateTime.now().month == cellDate.month &&
                                        DateTime.now().day == cellDate.day;
                                    final weekdayIdx = index % 7;
                                    Color dayColor = Colors.white;
                                    if (weekdayIdx == 0) dayColor = const Color(0xFFEF4565);
                                    if (weekdayIdx == 6) dayColor = const Color(0xFF00F5D4);
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: isToday
                                            ? const Color(0xFF2EC4B6).withOpacity(0.18)
                                            : Colors.white.withOpacity(0.02),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isToday ? const Color(0xFF2EC4B6) : Colors.white.withOpacity(0.04),
                                          width: isToday ? 1.2 : 1,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$dayNum',
                                            style: GoogleFonts.outfit(
                                              color: isToday ? Colors.white : dayColor.withOpacity(0.8),
                                              fontSize: 9 * scale,
                                              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (hasEvents)
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF7F5AF0).withOpacity(0.85),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                dayEvents.first,
                                                style: GoogleFonts.notoSansKr(
                                                  color: Colors.white,
                                                  fontSize: 6 * scale,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
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

  Widget _buildMiniAppDrawerWindow(double scale) {
    final accentColor = const Color(0xFF00F5D4);
    
    return Positioned(
      left: _appDrawerWindowOffset.dx,
      top: _appDrawerWindowOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _appDrawerWindowOffset += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 360 * scale,
            height: 380 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withOpacity(0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
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
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                      color: Colors.white.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(Icons.apps_rounded, color: accentColor, size: 14 * scale),
                          SizedBox(width: 8 * scale),
                          Text(
                            '전체 앱 목록',
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
                            icon: Icon(Icons.close_rounded, color: const Color(0xFFEF4565), size: 14 * scale),
                            onPressed: () {
                              setState(() {
                                _showMiniAppDrawer = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _appsListLoading && _cachedAppsList == null
                          ? const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F5D4)),
                              ),
                            )
                          : StatefulBuilder(
                            builder: (context, setDrawerState) {
                              final allApps = SystemAppScanner.externalAppsOnly(_cachedAppsList ?? []);
                              final filtered = allApps
                                  .where((app) => app.name.toLowerCase().contains(_appDrawerQuery.toLowerCase()))
                                  .toList();
                              
                              return Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(12 * scale, 12 * scale, 12 * scale, 8 * scale),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                                      ),
                                      child: TextField(
                                        style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 11 * scale),
                                        decoration: InputDecoration(
                                          hintText: '앱 이름 검색...',
                                          hintStyle: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 11 * scale),
                                          prefixIcon: Icon(Icons.search_rounded, color: Colors.white38, size: 14 * scale),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(vertical: 8 * scale),
                                        ),
                                        controller: _appDrawerSearchController,
                                        onChanged: (text) {
                                          setDrawerState(() {
                                            _appDrawerQuery = text;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: filtered.isEmpty
                                        ? Center(
                                            child: Text(
                                              '검색 결과가 없습니다.',
                                              style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 12 * scale),
                                            ),
                                          )
                                        : GridView.builder(
                                            padding: EdgeInsets.all(12 * scale),
                                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 4,
                                              childAspectRatio: 0.95,
                                              crossAxisSpacing: 8 * scale,
                                              mainAxisSpacing: 8 * scale,
                                            ),
                                            itemCount: filtered.length,
                                            itemBuilder: (context, idx) {
                                              final app = filtered[idx];
                                              final isBoardest = app.appId.startsWith('boardest://');
                                              final avatar = app.name.length >= 2 ? app.name.substring(0, 2) : app.name;
                                              
                                              return Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius: BorderRadius.circular(10),
                                                  onTap: () {
                                                    setState(() {
                                                      _showMiniAppDrawer = false;
                                                    });
                                                    if (isBoardest) {
                                                      final toolId = app.appId.replaceFirst('boardest://', '');
                                                      if (toolId != 'main') {
                                                        _getToolOnTap(toolId)();
                                                      }
                                                    } else {
                                                      SystemAppScanner.launchApp(app.appId);
                                                    }
                                                  },
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Container(
                                                        width: 32 * scale,
                                                        height: 32 * scale,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withOpacity(0.05),
                                                          shape: BoxShape.circle,
                                                        ),
                                                        alignment: Alignment.center,
                                                        child: app.hasIcon && app.iconPath != null
                                                            ? Image.file(
                                                                File(app.iconPath!),
                                                                key: ValueKey(app.iconPath),
                                                                width: 18 * scale,
                                                                height: 18 * scale,
                                                              )
                                                            : Text(
                                                                avatar,
                                                                style: GoogleFonts.notoSansKr(
                                                                  color: accentColor,
                                                                  fontSize: 9 * scale,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                      ),
                                                      SizedBox(height: 4 * scale),
                                                      Text(
                                                        app.name,
                                                        style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 8 * scale),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
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
      ),
    );
  }

  void _openTimer() {
    setState(() {
      _showMiniTimer = !_showMiniTimer;
      if (_showMiniTimer) {
        _timerSecondsElapsed = 0;
        _timerTargetSeconds = 0;
        _timerRunning = false;
        _miniTimerInstance?.cancel();
        _timerWindowOffset = const Offset(200, 150);
        _timerFullscreen = false;
      } else {
        _miniTimerInstance?.cancel();
        _miniTimerInstance = null;
      }
    });
  }

  void _openAppDrawer() {
    setState(() {
      _showMiniAppDrawer = !_showMiniAppDrawer;
      if (_showMiniAppDrawer) {
        _appDrawerWindowOffset = const Offset(400, 120);
        _appDrawerQuery = '';
        _appDrawerSearchController.clear();
        _preloadAppsList();
      }
    });
  }

  void _openCalculator() {
    setState(() {
      _showMiniCalculator = !_showMiniCalculator;
      if (_showMiniCalculator) {
        _calculatorWindowOffset = const Offset(500, 200);
      }
    });
  }

  void _openNotepad() {
    showDialog(
      context: context,
      builder: (context) => const NotepadModal(),
    );
  }

  void _openFileExplorer() {
    final defaultPath = Platform.environment['USERPROFILE'] != null
        ? '${Platform.environment['USERPROFILE']}\\Documents'
        : 'C:\\';
    final targetPath = _isUsbConnected && _usbDriveLetter.isNotEmpty
        ? _usbDriveLetter
        : defaultPath;
    if (Platform.isWindows) {
      Process.run('explorer.exe', [targetPath]);
    }
  }

  Future<void> _openPptBoard() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'pptx', 'ppt', 'iwb'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!mounted) return;
        final ext = p.extension(path).toLowerCase();

        if (ext == '.pptx' || ext == '.ppt') {
          if (!Platform.isWindows) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PPT 판서는 Windows에서만 지원됩니다.')),
            );
            return;
          }
          _pushBoardRoute(PptOverlayView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
            fullscreen: widget.pptFullscreen,
          ));
          return;
        }

        if (ext == '.pdf') {
          _pushBoardRoute(PdfBoardView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
          ));
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => BoardestPenView(
              filePath: path,
              scaleFactor: _settings.scaleFactor,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일을 열 수 없습니다: $e')),
      );
    }
  }

  void _openWeatherDialog() {
    setState(() {
      _showMiniWeather = !_showMiniWeather;
      if (_showMiniWeather) {
        _weatherWindowOffset = const Offset(300, 100);
      }
    });
  }

  void _openSchoolCalendarDialog() {
    setState(() {
      _showMiniCalendar = !_showMiniCalendar;
      if (_showMiniCalendar) {
        _calendarWindowOffset = const Offset(200, 80);
        _miniCalendarMonth = DateTime.now();
      }
    });
  }

  Future<void> _openPptOverlay() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pptx', 'ppt'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!mounted) return;
        if (!Platform.isWindows) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PPT 판서는 Windows에서만 지원됩니다.')),
          );
          return;
        }
        _pushBoardRoute(PptOverlayView(
          initialFilePath: path,
          scaleFactor: _settings.scaleFactor,
          fullscreen: widget.pptFullscreen,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PPT 파일을 열 수 없습니다: $e')),
      );
    }
  }

  Future<void> _openPdfBoard() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!mounted) return;
        _pushBoardRoute(PdfBoardView(
          initialFilePath: path,
          scaleFactor: _settings.scaleFactor,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 파일을 열 수 없습니다: $e')),
      );
    }
  }

  Future<void> _openDocumentBoard() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: Platform.isAndroid ? ['pdf'] : ['pdf', 'pptx', 'ppt', 'iwb'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final ext = path.split('.').last.toLowerCase();
        if (!mounted) return;
        if (ext == 'pdf') {
          _pushBoardRoute(PdfBoardView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
          ));
        } else if (ext == 'pptx' || ext == 'ppt') {
          if (Platform.isAndroid) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Android에서는 PPT 판서를 지원하지 않습니다. PDF만 사용해 주세요.')),
            );
            return;
          }
          _pushBoardRoute(PptOverlayView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
            fullscreen: widget.pptFullscreen,
          ));
        } else {
          _pushBoardRoute(BoardestPenView(
            filePath: path,
            scaleFactor: _settings.scaleFactor,
          ));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('문서를 열 수 없습니다: $e')),
      );
    }
  }

  void _openWebsiteBoard() {
    _pushBoardRoute(WebsiteBoardView(
      scaleFactor: _settings.scaleFactor,
    ));
  }
}



class ClassroomDiceModal extends StatefulWidget {
  const ClassroomDiceModal({super.key});

  @override
  State<ClassroomDiceModal> createState() => _ClassroomDiceModalState();
}

class _ClassroomDiceModalState extends State<ClassroomDiceModal> {
  int _diceCount = 1;
  List<int> _diceValues = [1];
  bool _isRolling = false;

  void _rollDice() async {
    if (_isRolling) return;
    setState(() {
      _isRolling = true;
    });

    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      setState(() {
        _diceValues = List.generate(_diceCount, (_) => (1 + (DateTime.now().microsecondsSinceEpoch % 6)));
      });
    }

    setState(() {
      _isRolling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          const Icon(Icons.casino_rounded, color: Color(0xFF00F5D4)),
          const SizedBox(width: 10),
          Text(
            '수업 주사위',
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [1, 2, 3].map((count) {
              final isSelected = _diceCount == count;
              return GestureDetector(
                onTap: () {
                  if (_isRolling) return;
                  setState(() {
                    _diceCount = count;
                    _diceValues = List.generate(count, (_) => 1);
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2EC4B6).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF00F5D4) : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    '${count}개',
                    style: GoogleFonts.notoSansKr(
                      color: isSelected ? const Color(0xFF00F5D4) : Colors.white60,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_diceCount, (index) {
              final val = _diceValues[index];
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 12),
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isRolling ? const Color(0xFF00F5D4) : const Color(0xFF2EC4B6).withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isRolling ? const Color(0xFF00F5D4) : const Color(0xFF2EC4B6)).withValues(alpha: _isRolling ? 0.35 : 0.15),
                      blurRadius: _isRolling ? 20 : 10,
                      spreadRadius: _isRolling ? 2 : 0,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '${val}',
                  style: GoogleFonts.outfit(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: _isRolling ? const Color(0xFF00F5D4) : Colors.white,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 32),
        ],
      ),
      actionsPadding: const EdgeInsets.only(bottom: 20, right: 20, left: 20),
      actions: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EC4B6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _isRolling ? null : _rollDice,
                child: Text(
                  _isRolling ? '주사위 굴리는 중...' : '주사위 던지기 🎲',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class NoiseMeterModal extends StatefulWidget {
  const NoiseMeterModal({super.key});

  @override
  State<NoiseMeterModal> createState() => _NoiseMeterModalState();
}

class _NoiseMeterModalState extends State<NoiseMeterModal> {
  double _decibels = 42.0;
  String _mode = '자습'; // 자습, 모둠, 발표
  double _threshold = 50.0;
  bool _alertActive = false;
  bool _isMonitoring = true;

  final List<double> _history = List.generate(24, (_) => 35.0);

  @override
  void initState() {
    super.initState();
    _simulateDecibels();
  }

  void _simulateDecibels() async {
    while (mounted && _isMonitoring) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) break;
      
      setState(() {
        double base = 35.0;
        double variance = 12.0;
        if (_mode == '자습') {
          base = 32.0;
          variance = 8.0;
        } else if (_mode == '모둠') {
          base = 65.0;
          variance = 20.0;
        } else if (_mode == '발표') {
          base = 45.0;
          variance = 15.0;
        }

        double roll = DateTime.now().millisecond / 1000.0;
        _decibels = base + (roll * variance);
        
        if (roll > 0.92) {
          _decibels += 15.0;
        }

        _alertActive = _decibels > _threshold;

        _history.removeAt(0);
        _history.add(_decibels);
      });
    }
  }

  @override
  void dispose() {
    _isMonitoring = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: _alertActive ? const Color(0xFFEF4565) : const Color(0xFF2EC4B6).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.volume_up_rounded,
                color: _alertActive ? const Color(0xFFEF4565) : const Color(0xFF00F5D4),
              ),
              const SizedBox(width: 10),
              Text(
                '교실 소음 측정기',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _alertActive ? const Color(0xFFEF4565).withValues(alpha: 0.15) : const Color(0xFF2EC4B6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _alertActive ? '경고: 소음 초과!' : '정상 수치',
              style: GoogleFonts.notoSansKr(
                color: _alertActive ? const Color(0xFFEF4565) : const Color(0xFF00F5D4),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModeTab('자습', '🤫 자습 시간'),
                _buildModeTab('발표', '📢 발표 시간'),
                _buildModeTab('모둠', '🗣️ 모둠 활동'),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              height: 140,
              width: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF16161A),
                border: Border.all(
                  color: _alertActive ? const Color(0xFFEF4565) : const Color(0xFF2EC4B6),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_alertActive ? const Color(0xFFEF4565) : const Color(0xFF2EC4B6)).withValues(alpha: 0.2),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _decibels.toStringAsFixed(1),
                    style: GoogleFonts.outfit(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: _alertActive ? const Color(0xFFEF4565) : Colors.white,
                    ),
                  ),
                  Text(
                    'dB',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  '경고 임계치: ${_threshold.toInt()} dB',
                  style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF2EC4B6),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFF00F5D4),
                      overlayColor: const Color(0xFF00F5D4).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _threshold,
                      min: 40,
                      max: 90,
                      onChanged: (val) {
                        setState(() {
                          _threshold = val;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 60,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16161A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _history.map((dbVal) {
                  final double h = 5 + ((dbVal - 30) / 60) * 40;
                  final clampedH = h.clamp(5.0, 48.0);
                  final isOver = dbVal > _threshold;

                  return Container(
                    width: 10,
                    height: clampedH,
                    decoration: BoxDecoration(
                      color: isOver ? const Color(0xFFEF4565) : const Color(0xFF2CB67D),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('닫기', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2))),
        ),
      ],
    );
  }

  Widget _buildModeTab(String targetMode, String label) {
    final isSelected = _mode == targetMode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mode = targetMode;
          if (targetMode == '자습') _threshold = 50.0;
          if (targetMode == '발표') _threshold = 60.0;
          if (targetMode == '모둠') _threshold = 78.0;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2EC4B6).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class TimerModal extends StatefulWidget {
  const TimerModal({super.key});

  @override
  State<TimerModal> createState() => _TimerModalState();
}

class _TimerModalState extends State<TimerModal> {
  int _secondsElapsed = 0;
  Timer? _timer;
  bool _isRunning = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() {
        _isRunning = false;
      });
    } else {
      setState(() {
        _isRunning = true;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _secondsElapsed++;
        });
      });
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _secondsElapsed = 0;
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          const Icon(Icons.timer_rounded, color: Color(0xFF00F5D4)),
          const SizedBox(width: 10),
          Text(
            '타이머 / 스톱워치',
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(_secondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_secondsElapsed % 60).toString().padLeft(2, '0')}',
            style: GoogleFonts.outfit(
              fontSize: 64,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF00F5D4),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRunning ? Colors.orange : const Color(0xFF2EC4B6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _toggleTimer,
                child: Text(_isRunning ? '일시정지' : '시작'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4565),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _resetTimer,
                child: const Text('초기화'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('닫기', style: GoogleFonts.notoSansKr(color: Colors.white60)),
        ),
      ],
    );
  }
}

class AppDrawerDialog extends StatefulWidget {
  final double scale;
  final Function(String toolId)? onLaunchTool;
  const AppDrawerDialog({super.key, required this.scale, this.onLaunchTool});

  @override
  State<AppDrawerDialog> createState() => _AppDrawerDialogState();
}

class _AppDrawerDialogState extends State<AppDrawerDialog> {
  List<ScannedApp> _allApps = [];
  List<ScannedApp> _filteredApps = [];
  bool _loading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final apps = SystemAppScanner.externalAppsOnly(
        await SystemAppScanner.scanInstalledApps(),
      );
      if (mounted) {
        setState(() {
          _allApps = apps;
          _filteredApps = apps;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _filterApps(String query) {
    setState(() {
      _searchQuery = query;
      if (query.trim().isEmpty) {
        _filteredApps = _allApps;
      } else {
        _filteredApps = _allApps
            .where((app) => app.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 60 * scale, vertical: 40 * scale),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0E17).withOpacity(0.85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ]
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: EdgeInsets.all(20.0 * scale),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.apps_rounded, color: const Color(0xFF00F5D4), size: 24 * scale),
                          SizedBox(width: 10 * scale),
                          Text(
                            '설치된 앱 목록',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 18 * scale,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: Colors.white60, size: 22 * scale),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  SizedBox(height: 15 * scale),
                  // Search Box
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filterApps,
                      style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * scale),
                      decoration: InputDecoration(
                        hintText: '앱 이름 검색...',
                        hintStyle: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * scale),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.white38, size: 18 * scale),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded, color: Colors.white38, size: 18 * scale),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterApps('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12 * scale),
                      ),
                    ),
                  ),
                  SizedBox(height: 15 * scale),
                  // Grid List
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF00F5D4),
                            ),
                          )
                        : _filteredApps.isEmpty
                            ? Center(
                                child: Text(
                                  '검색 결과가 없습니다.',
                                  style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 14 * scale),
                                ),
                              )
                            : GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6,
                                  childAspectRatio: 1.1,
                                  crossAxisSpacing: 12 * scale,
                                  mainAxisSpacing: 12 * scale,
                                ),
                                itemCount: _filteredApps.length,
                                itemBuilder: (context, index) {
                                  final app = _filteredApps[index];
                                  final colors = [
                                    const Color(0xFF2EC4B6),
                                    const Color(0xFF00F5D4),
                                    const Color(0xFF2CB67D),
                                    const Color(0xFFFF007F),
                                    const Color(0xFF7F00FF),
                                  ];
                                  final accentColor = colors[app.name.codeUnits.first % colors.length];
                                  final avatar = app.name.length >= 2
                                      ? app.name.substring(0, 2)
                                      : app.name;
                                  final hasIcon = app.iconPath != null &&
                                      app.iconPath!.isNotEmpty &&
                                      File(app.iconPath!).existsSync();

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        if (app.appId.startsWith('boardest://')) {
                                          final toolId = app.appId.replaceFirst('boardest://', '');
                                          if (toolId != 'main') {
                                            widget.onLaunchTool?.call(toolId);
                                          }
                                          Navigator.of(context).pop();
                                        } else {
                                          SystemAppScanner.launchApp(app.appId);
                                          Navigator.of(context).pop();
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.02),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.04),
                                          ),
                                        ),
                                        padding: EdgeInsets.all(8 * scale),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: hasIcon ? 42 * scale : 32 * scale,
                                              height: hasIcon ? 42 * scale : 32 * scale,
                                              decoration: BoxDecoration(
                                                color: hasIcon ? Colors.transparent : accentColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(8 * scale),
                                                border: hasIcon ? null : Border.all(
                                                  color: accentColor.withOpacity(0.4),
                                                  width: 1,
                                                ),
                                              ),
                                              child: hasIcon
                                                  ? ClipRRect(
                                                      borderRadius: BorderRadius.circular(8 * scale),
                                                      child: Image.file(
                                                        File(app.iconPath!),
                                                        fit: BoxFit.contain,
                                                        width: 42 * scale,
                                                        height: 42 * scale,
                                                      ),
                                                    )
                                                  : Center(
                                                      child: Text(
                                                        avatar,
                                                        style: GoogleFonts.notoSansKr(
                                                          fontSize: 10 * scale,
                                                          fontWeight: FontWeight.bold,
                                                          color: accentColor,
                                                        ),
                                                      ),
                                                    ),
                                            ),
                                            SizedBox(height: 6 * scale),
                                            Expanded(
                                              child: Text(
                                                app.name,
                                                style: GoogleFonts.notoSansKr(
                                                  fontSize: 10 * scale,
                                                  color: Colors.white.withOpacity(0.8),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ],
                                        ),
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
      ),
    );
  }
}

/// 설정 메뉴 타일 (바텀 시트용)
class _SettingsMenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final double scale;
  final VoidCallback onTap;

  const _SettingsMenuTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14 * scale),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 14 * scale),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 40 * scale,
                height: 40 * scale,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10 * scale),
                ),
                child: Icon(icon, color: color, size: 22 * scale),
              ),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontSize: 15 * scale,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 2 * scale),
                    Text(subtitle,
                        style: GoogleFonts.notoSansKr(
                            color: const Color(0xFF94A1B2), fontSize: 12 * scale)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.5), size: 20 * scale),
            ],
          ),
        ),
      ),
    );
  }
}
