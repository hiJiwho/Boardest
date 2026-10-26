import '../helpers/download_helper.dart';
import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:archive/archive.dart';
import '../helpers/ffi_stub.dart' hide GetDriveType, DRIVE_REMOVABLE;
import 'package:win32/win32.dart' if (dart.library.html) '../helpers/win32_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../helpers/fullscreen_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:bst_core/bst_core.dart' show PanserPluginService;

import '../models/school.dart';
import '../models/lesson.dart';
import '../models/app_settings.dart';
import '../models/meal_models.dart';
import '../services/comcigan_service.dart';
import '../services/storage_service.dart';
import '../services/neis_service.dart';
import '../services/system_app_scanner.dart';
import '../services/sleep_scheduler.dart';
import '../services/meal_call_service.dart';
import '../services/meal_vote_service.dart';
import '../services/demo_timetable_service.dart';
import '../services/demo_class_allocator_service.dart';
import 'timetable_view.dart';
import 'boardest_pen_view.dart';
import 'setup_wizard_view.dart';
import 'settings_fullscreen_view.dart';
import 'school_calendar_view.dart';
import 'ppt_overlay_view.dart';
import 'hwp_overlay_view.dart';
import 'pdf_board_view.dart';
import 'website_board_view.dart';
import 'youtube_board_view.dart';
import 'canva_board_view.dart';
import 'video_collection_board_view.dart';
import 'tbp/tbp_viewer_route.dart';
import '../services/usb_session_service.dart';
import '../services/app_paths.dart';
import '../services/board_storage_service.dart';
import '../services/bst_save_service.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../widgets/calculator_modal.dart';
import '../widgets/notepad_modal.dart';
import '../widgets/usb_explorer.dart';
import '../widgets/bst_cloud_modal.dart';
import '../services/bst_cloud_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'web_hwp_ppt_view.dart';
import 'plugin_store_view.dart';
import 'canva_overlay_view.dart';
import 'plugin_runner_view.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import 'components/bst_class_main_layout.dart';
import 'components/bst_today_timetable_strip.dart';
import 'components/bst_app_header.dart';
import 'components/bst_academic_schedule_card.dart';
import 'components/bst_dual_meal_card.dart';
import 'components/monthly_meal_calendar_dialog.dart';
import 'components/bst_tools_dock.dart';
import 'components/bst_cloud_passkey_modal.dart';
import 'components/bst_cloud_auth_modal.dart';
import 'modals/classroom_dice_modal.dart';
import 'modals/noise_meter_modal.dart';
import 'modals/timer_modal.dart';
import 'modals/app_drawer_dialog.dart';
import 'browser_board_view.dart';
import '../services/passkey_service.dart';
import '../services/timetable_schedule_calculator.dart';
import 'timetable/bst_today_timetable_panel.dart';
export '../services/timetable_schedule_calculator.dart' show PeriodTimeRange;

class DashboardView extends StatefulWidget {
  final String? initialTool;
  final bool pptFullscreen;
  const DashboardView({
    super.key,
    this.initialTool,
    this.pptFullscreen = false,
  });

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> with TickerProviderStateMixin {
  final ComciganService _comciganService = ComciganService();
  final StorageService _storageService = StorageService();
  final NeisService _neisService = NeisService();

  AppSettings _settings = AppSettings();
  final Map<String, Uint8List> _inMemoryTextbookBytes = {};
  bool _isTextbookZipDownloading = false;
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
  MealDayInfo? _todayMeal;
  MealDayInfo? _tomorrowMeal;
  final Set<String> _highlightedDishes = {};
  List<Map<String, dynamic>> _apiScheduleEvents = [];

  DateTime? _debugTimeOverride;

  // 쪽지 답장 직접 입력 상태
  bool _showCustomReplyInput = false;
  final TextEditingController _customReplyController = TextEditingController();

  // USB & App layout state
  bool _isUsbConnected = false;
  bool _isUsbEjected = false;
  bool _showFullUsbExplorer = false;
  String _usbDriveLetter = '';
  String _enteredOtp = '';
  String _enteredTeacherId = '';
  String _activeKeypadTarget = 'otp'; // 'otp' | 'teacherId'
  bool _isVerifyingOtp = false;
  String? _otpErrorMsg;
  bool _isCloudQrMode = true; // 스마트폰 QR 모드 기본 활성화
  bool _hideCloudPanel = false; // 클라우드 패널 최소화/닫기 시 로그인 상태 유지용
  ReversePairSession? _reversePairSession;
  bool _isLoadingQrSession = false;
  bool _qrSessionCancelled = false;
  String _usbSessionId = ''; // USB 고유 세션 ID
  bool _debugUsbOverride = false;
  Timer? _usbTimer;
  bool _initialToolTriggered = false;
  List<String> _usbSortedFiles = [];
  String? _activePluginId;
  String? _activePluginName;
  bool _usbAutoOpenEnabled = true;
  bool _usbHandling = false;
  int _timetableCheckCounter = 0;
  int _onlineStatusCounter = 0;
  BoardestUser? _currentUser;
  Timer? _cloudAutoLogoutTimer;
  Timer? _cloudSessionKeepAliveTimer;
  bool _isReloading = false;

  /// 클라우드 탈출(급식으로 토글 / 닫기) 시 3분 뒤 자동 로그아웃 예약
  void _scheduleCloudEscapeAutoLogout() {
    _cloudAutoLogoutTimer?.cancel();
    _cloudAutoLogoutTimer = Timer(const Duration(minutes: 3), () {
      if (mounted && BstCloudService.instance.activeToken != null) {
        setState(() {
          BstCloudService.instance.activeToken = null;
        });
        debugPrint('[Dashboard] 🔒 클라우드 탈출(급식 보기) 3분이 경과하여 Cloud 세션이 자동으로 안전하게 로그아웃되었습니다.');
      }
    });
  }

  void _cancelCloudEscapeAutoLogout() {
    _cloudAutoLogoutTimer?.cancel();
  }

  /// 클라우드 로그인 시 최소 1시간(60분) 세션 유지 보장
  void _startCloudSessionTimer() {
    _cloudSessionKeepAliveTimer?.cancel();
    _cloudSessionKeepAliveTimer = Timer(const Duration(hours: 1), () {
      if (mounted && BstCloudService.instance.activeToken != null) {
        setState(() {
          BstCloudService.instance.activeToken = null;
        });
        debugPrint('[Dashboard] 🔒 세션 유지 시간(1시간)이 만료되어 Cloud 세션이 안전하게 로그아웃되었습니다.');
      }
    });
  }

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

      bool _showMiniCalendar = false;
  Offset _calendarWindowOffset = const Offset(200, 80);
  DateTime _miniCalendarMonth = DateTime.now();

  bool _showMiniAppDrawer = false;
  Offset _appDrawerWindowOffset = const Offset(400, 120);
  String _appDrawerQuery = '';
  final TextEditingController _appDrawerSearchController =
      TextEditingController();
  bool _showWeeklyTimetableInCalendar = false;
  List<ScannedApp>? _cachedAppsList;
  bool _appsListLoading = false;
  final SleepSchedulerService _sleepScheduler = SleepSchedulerService();
  bool _showSleepWarning = false;
  int _sleepCountdownSeconds = 30;
  Timer? _sleepWarningTimer;
  bool _dialogOpen = false;
  String _cloudCategoryFilter = 'all'; // 'all', 'lesson', 'tbp_canva', 'pen'
  bool _isTrustDeviceSaved = false;
  Future<List<BstCloudFile>>? _cloudFilesFuture;

  void _refreshCloudFiles() {
    final token = BstCloudService.instance.activeToken;
    if (token != null && token.isNotEmpty) {
      _hideCloudPanel = false;
      _cloudFilesFuture = BstCloudService.instance.fetchAllCloudDriveFiles(accessToken: token);
      _checkTrustDeviceStatus();
    } else {
      _cloudFilesFuture = null;
      _isTrustDeviceSaved = false;
    }
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleDemoFullscreenKey);
    _refreshCloudFiles();

    // Auto OTP 등록 완료 FCM 리스너
    MealCallService.instance.onAutoOtpRegistered = (teacherName, teacherEmail) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: Color(0xFF00F5D4)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🔐 $teacherName 선생님 OTP 자동 로그인이 성공적으로 등록되었습니다!',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E1B4B),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUnreadFcmNotifications();
    });
    _loadPreferencesAndFetch();
    _preloadAppsList();
    _loadSavedTextbooksToMemory().then((_) {
      _syncSchoolTextbooksFromFirestore();
    });

    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        UpdateService.checkAndUpdate(context, silent: true, channel: _settings.updateChannel);
        if (Platform.isAndroid) {
          _checkAndPromptHomeLauncher();
        }
        PanserPluginService.checkAndAutoInstallOnStartup(
          onStatus: (msg) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.extension_rounded, color: Color(0xFF00F5D4)),
                      const SizedBox(width: 8),
                      Text(msg),
                    ],
                  ),
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        );
      });
    }

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
          } else if (false) {
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
    if (!kIsWeb && Platform.isWindows) {
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
    MealCallService.instance.stopListening();
    _timer?.cancel();
    _cloudAutoLogoutTimer?.cancel();
    _usbTimer?.cancel();
    _miniTimerInstance?.cancel();
    _sleepWarningTimer?.cancel();
    _sleepScheduler.dispose();
    _appDrawerSearchController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleDemoFullscreenKey);
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
    if (kIsWeb || !Platform.isWindows || !_settings.autoSleepEnabled) {
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '자동 절전 (Windows)',
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '쉬는 시간·점심·하교 후 모니터를 끄고, 수업 교시가 시작되면 자동으로 켭니다.',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white54,
                  fontSize: 12 * scale,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 12 * scale),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                activeThumbColor: const Color(0xFF2EC4B6),
                onChanged: (v) => setD(() => enabled = v),
                title: Text(
                  '자동 절전 사용',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 14 * scale,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
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
              child: Text(
                '저장',
                style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6)),
              ),
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
    if (kIsWeb || !Platform.isWindows) return;
    if (!mounted || _usbHandling) return;
    try {
      if (_debugUsbOverride) {
        final mockPath = Directory.current.path;
        if (!_isUsbConnected || _usbDriveLetter != mockPath) {
          if (!mounted) return;
          setState(() {
            _isUsbConnected = true;
            _usbDriveLetter = mockPath;
          });
          await _handleNewUsbConnected(mockPath);
        }
        return;
      }

      String? foundDrive;

      if (!kIsWeb && Platform.isWindows) {
        for (final letter in 'DEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
          final drive = '$letter:\\';
          final drivePtr = TEXT(drive);
          try {
            if (GetDriveType(drivePtr) == DRIVE_REMOVABLE) {
              foundDrive = drive;
              break;
            }
          } finally {
            free(drivePtr);
          }
        }
      } else if (!kIsWeb && Platform.isAndroid) {
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
            _isUsbEjected = false;
            _usbDriveLetter = foundDrive!;
          });
          await _handleNewUsbConnected(foundDrive);
        }
      } else if (_isUsbConnected || _isUsbEjected) {
        setState(() {
          _isUsbConnected = false;
          _isUsbEjected = false;
          _usbDriveLetter = '';
          _usbSessionId = '';
        });
      }
    } catch (e, st) {
      debugPrint('USB check error: $e\n$st');
    }
  }

  Future<void> _handleNewUsbConnected(String usbRoot) async {
    if (kIsWeb || !Platform.isWindows) return;
    if (!mounted || _usbHandling) return;
    _usbHandling = true;
    _isUsbEjected = false;
    try {
      // 1. USB 고유 ID 획득
      final usbId = await UsbSessionService.getUsbSerialId(usbRoot) ?? usbRoot;
      if (!mounted) return;
      setState(() {
        _usbSessionId = usbId;
        _isUsbEjected = false;
      });

      // 2. 파일 스캔
      final schoolName =
          _settings.selectedSchool?.name ?? _settings.connectionName;
      final yearStr = DateTime.now().year.toString();
      final sortedFiles = await UsbSessionService.scanAndSortFiles(
        usbRoot,
        schoolName: schoolName,
        year: yearStr,
        grade: _settings.selectedGrade,
      );
      if (!mounted) return;
      setState(() {
        _usbSortedFiles = sortedFiles;
      });
      if (sortedFiles.isEmpty) {
        // 파일 없으면 파일탐색기만 띄우기
        _showUsbNoFilesDialog(usbRoot);
        return;
      }

      // 3. 기존 세션 확인 (자동 열기는 수행하지 않음: 사용자 요청으로 자동 실행 비활성화)
      final hasSession = await UsbSessionService.instance.hasSession(usbId);
      if (!mounted) return;
      if (!hasSession) {
        // 첫 번째 삽입: 세션 생성
        await UsbSessionService.instance.initSession(
          usbId,
          usbRoot,
          sortedFiles,
        );
      } else {
        // 이후 삽입: 세션 업데이트
        await UsbSessionService.instance.updateSortedFiles(usbId, sortedFiles);
      }

      if (!mounted) return;
      setState(() {
        _usbSortedFiles = sortedFiles;
        _usbAutoOpenEnabled = false;
      });

      // 4. 자동 열기 제거: 사용자가 직접 클릭하여 수업 파일을 열도록 함
    } finally {
      _usbHandling = false;
    }
  }

  // ── USB 파일 없을 때 탐색기 안내 다이얼로그 ────────────────────
  void _showUsbNoFilesDialog(String usbRoot) {
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
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          title: _usbDialogTitle('USB 감지됨', '수업 자료가 없습니다', scale),
          content: Text(
            'USB($usbRoot)가 삽입되었지만 지원되는 수업 자료(PDF, PPT, PPTX 등)가 없습니다.\n파일탐색기로 직접 탐색하시겠습니까?',
            style: GoogleFonts.notoSansKr(
              color: Colors.white70,
              fontSize: 13 * scale,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUsbExplorer(usbRoot);
              },
              child: Text(
                '파일탐색기 열기',
                style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                '닫기',
                style: GoogleFonts.notoSansKr(color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
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
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
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
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white70,
                    fontSize: 13 * scale,
                    height: 1.5,
                  ),
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
              child: Text(
                '파일탐색기',
                style: GoogleFonts.notoSansKr(color: Colors.white38),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                '닫기',
                style: GoogleFonts.notoSansKr(color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 재삽입 다이얼로그 (자동 열기) ──────────────
  void _showUsbReturnDialog(
    String usbId,
    List<String> sortedFiles,
    bool autoOpenEnabled,
  ) {
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
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (
            t,
          ) async {
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
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
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
                        await UsbSessionService.instance.setAutoOpen(
                          usbId,
                          localAutoOpen,
                        );
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
                                await UsbSessionService.instance.setAutoOpen(
                                  usbId,
                                  localAutoOpen,
                                );
                                if (!localAutoOpen) countdownTimer?.cancel();
                              },
                              activeColor: Colors.redAccent,
                            ),
                            SizedBox(width: 4 * scale),
                            Text(
                              '다음 연결 시 자동 열기 사용 안 함',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white70,
                                fontSize: 13 * scale,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      '최근 자료 목록 (${sortedFiles.length}개)',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white38,
                        fontSize: 11 * scale,
                      ),
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
                            final state = await UsbSessionService.instance
                                .getFileState(usbId, sortedFiles[idx]);
                            _openUsbFileWithSession(
                              usbId,
                              sortedFiles[idx],
                              state?.lastPage ?? 0,
                            );
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
                  child: Text(
                    '파일탐색기',
                    style: GoogleFonts.notoSansKr(color: Colors.white38),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    Navigator.of(ctx).pop();
                  },
                  child: Text(
                    '닫기',
                    style: GoogleFonts.notoSansKr(color: Colors.white38),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2EC4B6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8 * scale),
                    ),
                  ),
                  onPressed: () async {
                    countdownTimer?.cancel();
                    Navigator.of(ctx).pop();
                    await _openLastUsbFile(usbId);
                  },
                  child: Text(
                    '이어서 열기',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
                  ),
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
    final nextFile = await UsbSessionService.instance.findNextFile(
      usbId,
      currentFilePath,
    );
    if (nextFile == null || !mounted) return false;
    await _openUsbFileWithSession(usbId, nextFile, 0);
    return true;
  }

  // ── 헬퍼: 마지막 파일 이어서 열기 ──────────────
  Future<void> _openLastUsbFile(String usbId) async {
    final lastFile = await UsbSessionService.instance.getLastOpenedFile(usbId);
    if (lastFile == null || !mounted) return;
    final state = await UsbSessionService.instance.getFileState(
      usbId,
      lastFile,
    );
    final lastPage = state?.lastPage ?? 0;
    final totalPages = state?.totalPages ?? 1;

    // 마지막으로 저장된 페이지 == 마지막 페이지 → 다음 파일 열기
    if (UsbSessionService.instance.shouldOpenNextUsbFile(
      lastPage,
      totalPages,
    )) {
      final nextFile = await UsbSessionService.instance.findNextFile(
        usbId,
        lastFile,
      );
      if (nextFile != null && mounted) {
        await _openUsbFileWithSession(usbId, nextFile, 0);
        return;
      }
    }

    await _openUsbFileWithSession(usbId, lastFile, lastPage);
  }

  // ── 파일 열기 (세션 포함) ──────────────────────
  Future<void> _openUsbFileWithSession(
    String usbId,
    String filePath,
    int startPage,
  ) async {
    await UsbSessionService.instance.setLastOpenedFile(usbId, filePath);
    final ext = p.extension(filePath).toLowerCase();

    if (ext == '.pptx' || ext == '.ppt') {
      if (!kIsWeb && Platform.isAndroid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Android에서는 PPT 판서를 지원하지 않습니다.')),
        );
        return;
      }
      final shouldOpenNext = await _pushBoardRoute<bool>(
        PptOverlayView(
          initialFilePath: filePath,
          scaleFactor: _settings.scaleFactor,
          fullscreen: widget.pptFullscreen,
          usbSessionId: usbId,
          initialSlide: startPage,
          onLastSlideNext: (path) => _openNextUsbFile(usbId, path),
          onPageChanged: (path, page, total) async {
            await UsbSessionService.instance.updateFileState(
              usbId,
              path,
              page,
              total,
            );
          },
        ),
      );
      if (shouldOpenNext == true) {
        await _openNextUsbFile(usbId, filePath);
      }
      setState(() {});
    } else if (ext == '.pdf') {
      if (!kIsWeb && Platform.isWindows) {
        try {
          const channel = MethodChannel('com.boardest/launch_args');
          await channel.invokeMethod('restoreWindow');
        } catch (e) {
          debugPrint('Failed to restore window: $e');
        }
      }
      final shouldOpenNext = await _pushBoardRoute<bool>(
        PdfBoardView(
          initialFilePath: filePath,
          scaleFactor: _settings.scaleFactor,
          usbSessionId: usbId,
          initialPage: startPage,
          onLastPageNext: (path) => _openNextUsbFile(usbId, path),
          onPageChanged: (path, page, total) async {
            await UsbSessionService.instance.updateFileState(
              usbId,
              path,
              page,
              total,
            );
          },
        ),
      );
      if (shouldOpenNext == true) {
        await _openNextUsbFile(usbId, filePath);
      }
      setState(() {});
    } else if (ext == '.tbp') {
      await _pushBoardRoute(
        TbpViewerRoute(
          tbpFilePath: filePath,
          scaleFactor: _settings.scaleFactor,
        ),
      );
      setState(() {});
    } else if (ext == '.yt') {
      _openYoutubeBoard(filePath: filePath);
    } else if (ext == '.canva') {
      _openCanvaBoard(filePath: filePath);
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
                        Icon(
                          Icons.folder_open_rounded,
                          color: const Color(0xFF00F5D4),
                          size: 24 * scale,
                        ),
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
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: UsbExplorer(
                    drivePath: _usbDriveLetter,
                    scaleFactor: scale,
                    isEjected: _isUsbEjected,
                    onFileOpen: (filePath) async {
                      Navigator.pop(context); // Close explorer modal
                      int startPage = 0;
                      if (_usbSessionId.isNotEmpty) {
                        final state = await UsbSessionService.instance
                            .getFileState(_usbSessionId, filePath);
                        startPage = state?.lastPage ?? 0;
                      }
                      _openUsbFileWithSession(
                        _usbSessionId,
                        filePath,
                        startPage,
                      );
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

  void _openUsbExplorer(String drivePath) {
    if (kIsWeb || !Platform.isWindows) return;
    final root = drivePath.isNotEmpty
        ? drivePath
        : (_usbDriveLetter.isNotEmpty ? _usbDriveLetter : 'C:\\');
    Process.run('explorer.exe', [root]).catchError((e) {
      debugPrint('[USB] Failed to open explorer: $e');
      return ProcessResult(0, -1, '', e.toString());
    });
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
          child: Icon(
            Icons.usb_rounded,
            color: const Color(0xFF2EC4B6),
            size: 22 * scale,
          ),
        ),
        SizedBox(width: 12 * scale),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.bold,
                fontSize: 16 * scale,
                color: Colors.white,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.notoSansKr(
                fontSize: 11 * scale,
                color: const Color(0xFF2EC4B6),
              ),
            ),
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
        title: Text(
          p.basename(filePath),
          style: GoogleFonts.notoSansKr(
            color: Colors.white,
            fontSize: 12 * scale,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: onTap != null
            ? Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white30,
                size: 12 * scale,
              )
            : null,
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

    return FutureBuilder<UsbFileState?>(
      future: UsbSessionService.instance.getFileState(usbId, filePath),
      builder: (_, snap) {
        final state = snap.data;
        final subtitle = state != null
            ? '마지막: ${state.lastPage + 1} / ${state.totalPages}쪽'
            : '저장 없음';
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
            title: Text(
              p.basename(filePath),
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              subtitle,
              style: GoogleFonts.outfit(
                color: Colors.white30,
                fontSize: 10 * scale,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white30,
              size: 12 * scale,
            ),
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

  (String, String) _getPeriodStartAndEndTime(int period) {
    final str = _getPeriodTimeString(period);
    final parts = str.split('~');
    if (parts.length == 2) {
      return (parts[0].trim(), parts[1].trim());
    }
    return ('09:00', '09:50');
  }

  Future<bool> _fetchTimetableWithRetry(
    int schoolCode,
    DateTime targetDate,
  ) async {
    final isDemo = AppConfig.isDemoMode ||
        _settings.schoolId.toLowerCase() == 'demo' ||
        (_settings.selectedSchool?.name.contains('데모') == true);
    if (isDemo) {
      final classKey = _settings.classNickname.isNotEmpty ? _settings.classNickname : 'Demo-class1';
      final lessons = DemoTimetableService.getAllDemoLessons(classKey);
      final demoResult = TimetableResult(
        schoolName: '데모 중학교',
        periodTimes: ['09:00', '09:50', '10:40', '11:30', '12:20', '13:50', '14:40'],
        classCounts: {1: 10, 2: 10, 3: 10},
        lessons: lessons,
        homeroomTeachers: {},
      );
      if (mounted) {
        setState(() {
          _timetableResult = demoResult;
        });
        _updateLiveSchedule();
      }
      return true;
    }

    final weekOffset = _getWeekOffset(targetDate, DateTime.now());
    try {
      final rawData = await _comciganService.fetchTimetableRaw(
        schoolCode,
        weekOffset: weekOffset,
      );
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

  Future<bool> _fetchLunchMenuWithRetry(
    String schoolName,
    DateTime targetDate,
  ) async {
    try {
      final todayInfo = await _neisService.fetchMealDayInfo(schoolName, targetDate);
      DateTime nextDate = targetDate.add(const Duration(days: 1));
      if (nextDate.weekday == DateTime.saturday) {
        nextDate = nextDate.add(const Duration(days: 2));
      } else if (nextDate.weekday == DateTime.sunday) {
        nextDate = nextDate.add(const Duration(days: 1));
      }
      final tomorrowInfo = await _neisService.fetchMealDayInfo(schoolName, nextDate);

      final prefs = await SharedPreferences.getInstance();
      final dateKey = '${targetDate.year}${targetDate.month.toString().padLeft(2, '0')}${targetDate.day.toString().padLeft(2, '0')}';
      final savedHighlights = prefs.getStringList('meal_highlights_$dateKey') ?? [];
      _highlightedDishes.clear();
      _highlightedDishes.addAll(savedHighlights);

      final currentSchoolId = _settings.schoolId.isNotEmpty ? _settings.schoolId : schoolName;
      MealVoteService.instance.startListening(currentSchoolId, targetDate);

      if (mounted) {
        setState(() {
          _todayMeal = todayInfo;
          _tomorrowMeal = tomorrowInfo;
          _mealInfo = todayInfo.dishes.map((d) => d.name + (d.allergies.isNotEmpty ? ' (${d.allergies.join(', ')})' : '')).join('\n');
          _isLoadingMeal = false;
        });
      }
      return true;
    } catch (e) {
      debugPrint('[Boardest] fetchLunchMenuWithRetry failed: $e');
      return false;
    }
  }

  Future<bool> _fetchSchoolScheduleWithRetry(
    String schoolName,
    DateTime targetDate,
  ) async {
    try {
      final todayStart = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      );
      final events = await _neisService.fetchSchoolSchedule(
        schoolName,
        todayStart,
      );
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

  Future<void> _loadAndroidDataWithRetry(
    String schoolName,
    int schoolCode,
    DateTime targetDate,
  ) async {
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
        timetableSuccess = await _fetchTimetableWithRetry(
          schoolCode,
          targetDate,
        );
      }
      if (!lunchSuccess) {
        lunchSuccess = await _fetchLunchMenuWithRetry(schoolName, targetDate);
      }
      if (!scheduleSuccess) {
        scheduleSuccess = await _fetchSchoolScheduleWithRetry(
          schoolName,
          targetDate,
        );
      }

      final elapsed = DateTime.now().difference(startTime).inSeconds;
      if ((timetableSuccess && lunchSuccess && scheduleSuccess) ||
          elapsed >= 30) {
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
      _syncSchoolTextbooksFromFirestore();

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
    if (_isReloading) return;
    _isReloading = true;
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      AppSettings? settings;
      try {
        final isDemo = AppConfig.isDemoMode ||
            (kIsWeb && (Uri.base.queryParameters.containsKey('Demo') || Uri.base.queryParameters.containsKey('demo') || Uri.base.host.contains('demo')));
        if (isDemo) {
          AppConfig.isDemoMode = true;
          final loaded = await _storageService.getSettings();
          settings = await DemoClassAllocatorService.instance.allocateDemoSettings(loaded ?? AppSettings());
        } else {
          settings = await _storageService.getSettings();
        }
        if (settings == null) {
          throw Exception('Settings null after loading');
        }
        if (mounted) {
          setState(() {
            _settings = settings!;
          });
        }

        // Apply Special Classroom Mode on startup/load
        if (!kIsWeb && Platform.isWindows) {
          const channel = MethodChannel('com.boardest/launch_args');
          try {
            channel.invokeMethod(
              'setSpecialClassroomMode',
              _settings.specialClassroomMode,
            );
          } catch (e) {
            debugPrint('Failed to apply special classroom mode on startup: $e');
          }
        }

        // 백그라운드에서 저장된 슬롯의 누락된 아이콘 경로 자동 복구
        if (!kIsWeb && Platform.isWindows) {
          final loadedSettings = settings;
          SystemAppScanner.scanInstalledApps()
              .then((scannedList) {
                bool needUpdate = false;
                final scannedIconMap = <String, String>{};
                for (final app in scannedList) {
                  if (app.iconPath != null) {
                    scannedIconMap[app.appId] = app.iconPath!;
                  }
                }

                final updatedSlots = loadedSettings.launcherSlots.map((slot) {
                  if (slot.type == LauncherSlotType.systemApp &&
                      (slot.iconPath == null || slot.iconPath!.isEmpty)) {
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
                  final updatedSettings = loadedSettings.copyWith(
                    launcherSlots: updatedSlots,
                  );
                  _storageService
                      .saveSettings(updatedSettings)
                      .then((_) {
                        if (mounted) {
                          setState(() {
                            _settings = updatedSettings;
                          });
                        }
                      })
                      .catchError((e) {
                        debugPrint(
                          'Error saving auto-restored launcher icons: $e',
                        );
                      });
                }
              })
              .catchError((err) {
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
        final isDemo = AppConfig.isDemoMode ||
            (kIsWeb && (Uri.base.queryParameters.containsKey('Demo') || Uri.base.queryParameters.containsKey('demo') || Uri.base.host.contains('demo'))) ||
            (settings?.schoolId.toLowerCase() == 'demo');
        if (isDemo) {
          AppConfig.isDemoMode = true;
          settings = await DemoClassAllocatorService.instance.allocateDemoSettings(settings ?? AppSettings());
          _settings = settings;
        } else {
          setState(() {
            _errorMessage = '학교 설정이 완료되지 않았습니다.';
            _isLoading = false;
          });
          return;
        }
      }

      _startMealCallListener(settings);

      final schoolName = settings.selectedSchool!.name;
      final schoolCode = settings.selectedSchool!.code;
      final targetDate = _debugTimeOverride ?? DateTime.now();

      if (!kIsWeb && Platform.isAndroid) {
        _loadAndroidDataWithRetry(schoolName, schoolCode, targetDate);
        return;
      }

      // 1. Fetch Timetable with Offline Cache Fallback
      try {
        final isDemo = AppConfig.isDemoMode || _settings.schoolId.toLowerCase() == 'demo' || _settings.selectedSchool?.name.contains('데모') == true;
        if (isDemo) {
          final classKey = _settings.classNickname.isNotEmpty ? _settings.classNickname : 'Demo-class1';
          final lessons = DemoTimetableService.getAllDemoLessons(classKey);
          final demoResult = TimetableResult(
            schoolName: '데모 중학교',
            periodTimes: ['09:00', '09:50', '10:40', '11:30', '12:20', '13:50', '14:40', '15:30'],
            classCounts: {1: 10, 2: 10, 3: 10},
            lessons: lessons,
            homeroomTeachers: {},
          );
          if (mounted) {
            setState(() {
              _timetableResult = demoResult;
            });
            _updateLiveSchedule();
          }
        } else {
          final weekOffset = _getWeekOffset(targetDate, DateTime.now());
          final cacheKey = 'cached_timetable_${schoolCode}_$weekOffset';

          try {
            final rawData = await _comciganService.fetchTimetableRaw(
              schoolCode,
              weekOffset: weekOffset,
            );
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
          debugPrint(
            'Error loading timetable raw data, attempting to load from cache: $e',
          );

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
        }
      } catch (outerErr) {
        debugPrint('Fatal error in timetable section: $outerErr');
      }

      // 2. Fetch school lunch & schedule
      try {
        _fetchLunchMenu(schoolName, targetDate);
        _fetchSchoolSchedule(schoolName, targetDate);
        _syncSchoolConfigsFromFirestore();
        _updateOnlineStatusBackground();
      } catch (e) {
        debugPrint('Error fetching lunch or schedule: $e');
      }

      setState(() {
        _isLoading = false;
      });

      _applyAutoSleepSchedule();
      _startDashboardTimer();

      final isDemoModeActive = AppConfig.isDemoMode ||
          _settings.schoolId.toLowerCase() == 'demo' ||
          (_settings.selectedSchool?.name.contains('데모') ?? false);
      if (isDemoModeActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.sports_esports_rounded, color: Color(0xFFFF9F1C)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '🎮 가상 데모 모드 진입됨 (하단 [설정]을 꾹 누르면 언제든 데모를 탈출할 수 있습니다)',
                        style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF16161A),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        });
      }

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
    } finally {
      _isReloading = false;
    }
  }

  void _startMealCallListener(AppSettings settings) {
    if (settings.connectionName.isEmpty && settings.selectedSchool == null && !settings.specialClassroomMode) {
      return;
    }

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

    final trimmedFrom = from.trim();
    final displayFrom = trimmedFrom.endsWith('선생님') || trimmedFrom.endsWith('선생')
        ? trimmedFrom
        : (trimmedFrom.isNotEmpty ? '$trimmedFrom 선생님' : '교사');

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
                        Icons.mark_email_unread_rounded,
                        color: const Color(0xFF7F5AF0),
                        size: 38 * scale,
                      ),
                    ),
                    SizedBox(height: 20 * scale),
                    Text(
                      '교내 긴급 쪽지 알림',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 22 * scale,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (displayFrom.isNotEmpty) ...[
                      SizedBox(height: 6 * scale),
                      Text(
                        '보낸 분: $displayFrom',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF7F5AF0),
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                    SizedBox(height: 20 * scale),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: 20 * scale,
                        vertical: 16 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16 * scale),
                        border: Border.all(
                          color: const Color(0xFF7F5AF0).withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 16 * scale,
                          height: 1.6,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    SizedBox(height: 24 * scale),
                    StatefulBuilder(
                      builder: (ctx, setModalState) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showCustomReplyInput) ...[
                              Container(
                                margin: EdgeInsets.only(bottom: 14 * scale),
                                padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(12 * scale),
                                  border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.5)),
                                ),
                                child: TextField(
                                  controller: _customReplyController,
                                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                                  decoration: InputDecoration(
                                    hintText: '선생님께 전달할 답장 내용을 입력하세요...',
                                    hintStyle: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * scale),
                                    border: InputBorder.none,
                                  ),
                                  autofocus: true,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 48 * scale,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white70,
                                          side: const BorderSide(color: Colors.white24),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                                        ),
                                        onPressed: () {
                                          setModalState(() {
                                            _showCustomReplyInput = false;
                                            _customReplyController.clear();
                                          });
                                        },
                                        child: Text('취소', style: GoogleFonts.notoSansKr(fontSize: 14 * scale)),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8 * scale),
                                  Expanded(
                                    flex: 2,
                                    child: SizedBox(
                                      height: 48 * scale,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF7F5AF0),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                                        ),
                                        onPressed: () async {
                                          final replyText = _customReplyController.text.trim();
                                          if (replyText.isEmpty) return;
                                          Navigator.pop(context);
                                          final clName = _settings.classNickname.isNotEmpty
                                              ? _settings.classNickname
                                              : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';
                                          final ok = await MealCallService.instance.sendResponseToTeacher(
                                            response: 'TEXT',
                                            responseText: replyText,
                                            classroomName: clName,
                                          );
                                          _customReplyController.clear();
                                          if (mounted && ok) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('💬 선생님께 "$replyText" 답장을 보냈습니다.'),
                                                duration: const Duration(seconds: 2),
                                                backgroundColor: const Color(0xFF7F5AF0),
                                              ),
                                            );
                                          }
                                        },
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.send_rounded, size: 18 * scale, color: Colors.white),
                                            SizedBox(width: 6 * scale),
                                            Text('답장 전송', style: GoogleFonts.notoSansKr(fontSize: 14 * scale, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  // X 버튼 (거절 / 불가 - 빨강)
                                  Expanded(
                                    child: SizedBox(
                                      height: 52 * scale,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFEF4444),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14 * scale),
                                          ),
                                        ),
                                        onPressed: () async {
                                          Navigator.pop(context);
                                          final clName = _settings.classNickname.isNotEmpty
                                              ? _settings.classNickname
                                              : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';
                                          final ok = await MealCallService.instance.sendResponseToTeacher(
                                            response: 'X',
                                            classroomName: clName,
                                          );
                                          if (mounted && ok) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('🔴 선생님께 "X (불가)" 답장을 보냈습니다.'),
                                                duration: Duration(seconds: 2),
                                                backgroundColor: Color(0xFFEF4444),
                                              ),
                                            );
                                          }
                                        },
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.close_rounded, size: 20 * scale, color: Colors.white),
                                            SizedBox(width: 4 * scale),
                                            Text(
                                              'X (불가)',
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 14 * scale,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8 * scale),
                                  // 메시지 직접 입력 버튼
                                  Expanded(
                                    child: SizedBox(
                                      height: 52 * scale,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF7F5AF0),
                                          side: const BorderSide(color: Color(0xFF7F5AF0), width: 1.5),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14 * scale),
                                          ),
                                        ),
                                        onPressed: () {
                                          setModalState(() {
                                            _showCustomReplyInput = true;
                                          });
                                        },
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.edit_note_rounded, size: 20 * scale, color: const Color(0xFF7F5AF0)),
                                            SizedBox(width: 4 * scale),
                                            Text(
                                              '메시지 입력',
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 14 * scale,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF7F5AF0),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8 * scale),
                                  // O 버튼 (승낙 / 확인 - 초록)
                                  Expanded(
                                    child: SizedBox(
                                      height: 52 * scale,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14 * scale),
                                          ),
                                        ),
                                        onPressed: () async {
                                          Navigator.pop(context);
                                          final clName = _settings.classNickname.isNotEmpty
                                              ? _settings.classNickname
                                              : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';
                                          final ok = await MealCallService.instance.sendResponseToTeacher(
                                            response: 'O',
                                            classroomName: clName,
                                          );
                                          if (mounted && ok) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('🟢 선생님께 "O (확인)" 답장을 보냈습니다!'),
                                                duration: Duration(seconds: 2),
                                                backgroundColor: Color(0xFF10B981),
                                              ),
                                            );
                                          }
                                        },
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.check_rounded, size: 20 * scale, color: Colors.white),
                                            SizedBox(width: 4 * scale),
                                            Text(
                                              'O (확인)',
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 14 * scale,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 16 * scale,
                        vertical: 12 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.06),
                        ),
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

  void _playMealCallChime() {
    try {
      SystemSound.play(SystemSoundType.alert);
      Future.delayed(const Duration(milliseconds: 350), () {
        SystemSound.play(SystemSoundType.alert);
      });
    } catch (e) {
      debugPrint('[Boardest] Meal call chime error: $e');
    }
  }

  void _showMealCallNotificationAlert() {
    if (MealCallService.instance.isPopupShowing) return;
    MealCallService.instance.isPopupShowing = true;
    _playMealCallChime();

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
                      height: 52 * scale,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F5D4),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14 * scale),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          final clName = _settings.classNickname.isNotEmpty
                              ? _settings.classNickname
                              : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';
                          final ok = await MealCallService.instance.sendResponseToTeacher(
                            response: 'MOVE',
                            classroomName: clName,
                          );
                          if (mounted && ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🍱 급식실에 "이동 시작" 신호를 보냈습니다!'),
                                duration: Duration(seconds: 2),
                                backgroundColor: Color(0xFF00F5D4),
                              ),
                            );
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_walk_rounded, size: 24 * scale, color: Colors.black),
                            SizedBox(width: 8 * scale),
                            Text(
                              '이동하기',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 17 * scale,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
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
      },
    );
  }

  int _getWeekOffset(DateTime debugDate, DateTime currentDate) {
    DateTime getMonday(DateTime date) {
      return DateTime(
        date.year,
        date.month,
        date.day,
      ).subtract(Duration(days: date.weekday - 1));
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
      final todayInfo = await _neisService.fetchMealDayInfo(schoolName, date);
      DateTime nextDate = date.add(const Duration(days: 1));
      if (nextDate.weekday == DateTime.saturday) {
        nextDate = nextDate.add(const Duration(days: 2));
      } else if (nextDate.weekday == DateTime.sunday) {
        nextDate = nextDate.add(const Duration(days: 1));
      }
      final tomorrowInfo = await _neisService.fetchMealDayInfo(schoolName, nextDate);
      
      // Load saved highlights
      final prefs = await SharedPreferences.getInstance();
      final dateKey = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
      final savedHighlights = prefs.getStringList('meal_highlights_$dateKey') ?? [];
      _highlightedDishes.clear();
      _highlightedDishes.addAll(savedHighlights);

      // Start listening to real-time votes
      final currentSchoolId = _settings.schoolId.isNotEmpty ? _settings.schoolId : schoolName;
      MealVoteService.instance.startListening(currentSchoolId, date);

      if (mounted) {
        setState(() {
          _todayMeal = todayInfo;
          _tomorrowMeal = tomorrowInfo;
          _mealInfo = todayInfo.dishes.map((d) => d.name + (d.allergies.isNotEmpty ? ' (${d.allergies.join(', ')})' : '')).join('\n');
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

  Future<void> _fetchSchoolSchedule(
    String schoolName,
    DateTime startDate,
  ) async {
    try {
      final todayStart = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      );
      final events = await _neisService.fetchSchoolSchedule(
        schoolName,
        todayStart,
      );
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

  DateTime get _todayDateOnly => DateTime(_now.year, _now.month, _now.day);

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
      }).toList()..sort((a, b) => a.date.compareTo(b.date));
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
    return TimetableScheduleCalculator.getLessonsForDay(
      timetableResult: _timetableResult,
      settings: _settings,
      day: day,
    );
  }

  Lesson _emptyLesson(int period, int weekday) {
    return TimetableScheduleCalculator.emptyLesson(_settings, period, weekday);
  }

  List<PeriodTimeRange> _generatePeriodRanges(TimeSettings ts, DateTime now) {
    final weekday = now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    final displayWeekday = isWeekend ? 1 : weekday;
    return TimetableScheduleCalculator.generatePeriodRanges(
      ts: ts,
      now: now,
      lessonsForDisplayDay: _getLessonsForDay(displayWeekday),
    );
  }

  void _updateLiveSchedule() {
    final now = _debugTimeOverride ?? DateTime.now();
    final weekday = now.weekday;

    // Weekend displays Monday schedule as preview
    final isWeekend = weekday == 6 || weekday == 7;
    final displayWeekday = isWeekend ? 1 : weekday;
    final lessons = _timetableResult != null ? _getLessonsForDay(displayWeekday) : <Lesson>[];

    final ts = _settings.timeSettings;
    final ranges = _generatePeriodRanges(ts, now);

    PeriodTimeRange? activeRange;
    if (!isWeekend) {
      for (final r in ranges) {
        if ((now.isAfter(r.start) || now.isAtSameMomentAs(r.start)) &&
            now.isBefore(r.end)) {
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
        }

        if (active.isClass) {
        } else if (active.period == -3) {
          _countdownTarget = '조회 시작까지';
        } else if (active.period == -1) {
          _countdownTarget = '조회 종료까지';
        } else if (active.period == -2) {
          _countdownTarget = '종례 종료까지';
        } else if (active.label == '점심 시간') {
          _countdownTarget = '점심시간 종료까지';
        } else {
          final nextRanges = ranges.where(
            (r) => r.start.isAfter(now) || r.start.isAtSameMomentAs(active.end),
          );
          final nextEvent = nextRanges.isNotEmpty ? nextRanges.first : null;
          if (nextEvent != null) {
            if (nextEvent.isClass) {
              _countdownTarget = '${nextEvent.label} 시작까지';
            } else if (nextEvent.period == -2) {
              _countdownTarget = '종례 시작까지';
            } else {
              _countdownTarget = '${nextEvent.label} 시작까지';
            }
          } else {
            _countdownTarget = '쉬는시간 종료까지';
          }
        }

        final hours = remaining.inHours;
        final mins = remaining.inMinutes % 60;
        if (hours > 0) {
          _countdownTime = '$hours시간 $mins분';
        } else if (mins > 0) {
          _countdownTime = '$mins분';
        } else {
          final secs = remaining.inSeconds % 60;
          _countdownTime = '$secs초';
        }

        if (active.isClass) {
          _currentLesson = lessons.firstWhere(
            (l) => l.classTime == active.period,
            orElse: () => _emptyLesson(active.period, displayWeekday),
          );

          final nextMatches = lessons.where(
            (l) => l.classTime > active.period && l.subject.isNotEmpty,
          );
          _nextLesson = nextMatches.isNotEmpty ? nextMatches.first : null;

          // 종 치면 시간표 진도 맞춰 자동 PPT 실행 (Auto Lesson Flow)
          _checkAutoLessonFlow(active, _currentLesson);
        } else {
          _currentLesson = null;
          final nextClassRanges = ranges.where(
            (r) => r.isClass && (r.start.isAfter(now) || r.start.isAtSameMomentAs(active.end)),
          );
          final nextClassRange = nextClassRanges.isNotEmpty
              ? nextClassRanges.first
              : null;
          if (nextClassRange != null) {
            final nextMatches = lessons.where(
              (l) =>
                  l.classTime >= nextClassRange.period && l.subject.isNotEmpty,
            );
            _nextLesson = nextMatches.isNotEmpty ? nextMatches.first : null;
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
            final nextMatches = lessons.where(
              (l) => l.classTime >= nextR.period && l.subject.isNotEmpty,
            );
            _nextLesson = nextMatches.isNotEmpty ? nextMatches.first : null;
          } else {
            final nextClassRanges = ranges.where(
              (r) => r.isClass && r.start.isAfter(now),
            );
            if (nextClassRanges.isNotEmpty) {
              final nextClass = nextClassRanges.first;
              final nextMatches = lessons.where(
                (l) => l.classTime >= nextClass.period && l.subject.isNotEmpty,
              );
              _nextLesson = nextMatches.isNotEmpty ? nextMatches.first : null;
            } else {
              _nextLesson = null;
            }
          }
        } else {
          // After school or weekend (no more events today)
          int daysUntilNextSchoolDay = 1;
          if (weekday == 5)
            daysUntilNextSchoolDay = 3;
          else if (weekday == 6)
            daysUntilNextSchoolDay = 2;

          final nextSchoolDate = now.add(
            Duration(days: daysUntilNextSchoolDay),
          );

          // Parse dynamic class start time
          final startParts = ts.firstPeriodStart.split(':');
          final targetH = int.tryParse(startParts[0]) ?? 8;
          final targetM = int.tryParse(startParts[1]) ?? 40;
          final nextSchoolStart = DateTime(
            nextSchoolDate.year,
            nextSchoolDate.month,
            nextSchoolDate.day,
            targetH,
            targetM,
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

    if (!kIsWeb && Platform.isWindows && _settings.autoSleepEnabled) {
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

    final candidates = [
      _settings.selectedTeacherId.replaceAll('*', '').replaceAll(' ', '').trim(),
      _settings.selectedTeacher.replaceAll('*', '').replaceAll(' ', '').trim(),
      _settings.selectedTeacherName.replaceAll('*', '').replaceAll(' ', '').trim(),
    ].where((s) => s.isNotEmpty).toList();

    if (candidates.isEmpty) return null;

    final today = DateTime.now();
    final weekday = today.weekday; // 1=Mon ~ 7=Sun
    if (weekday > 5) return null; // 주말이면 null

    Map<String, int>? classInfo;
    for (final cand in candidates) {
      classInfo = _timetableResult!.findClassByTeacherAndPeriod(
        weekday: weekday,
        period: nextLesson.classTime,
        teacherAbbr: cand,
      );
      if (classInfo != null) break;
    }

    if (classInfo == null) return null;
    return '${classInfo['grade']}학년 ${classInfo['classNum']}반';
  }

  void _sendKeyEventToActivePresentation(bool isNext) {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final key = isNext ? '{PGDN}' : '{PGUP}';
      Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '\$wshell = New-Object -ComObject WScript.Shell; \$wshell.SendKeys("$key")',
      ]);
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

  Widget _buildQuickTimeBtn(BuildContext ctx, DateTime current, int hour, int minute, String label) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        final newDate = DateTime(current.year, current.month, current.day, hour, minute);
        setState(() {
          _debugTimeOverride = newDate;
          _updateLiveSchedule();
          if (_settings.selectedSchool != null) {
            _fetchLunchMenu(_settings.selectedSchool!.name, newDate);
          }
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _openDebugDatePicker() async {
    final current = _debugTimeOverride ?? DateTime.now();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_calendar_rounded, color: Color(0xFF00F5D4)),
            SizedBox(width: 8),
            Text('일자 및 시간 디버깅', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '현재 설정: ${current.year}년 ${current.month}월 ${current.day}일 ${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '원하는 날짜와 시간을 지정하여 특정 교시의 시간표와 급식을 시뮬레이션할 수 있습니다.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      final prev = current.subtract(const Duration(days: 1));
                      _debugTimeOverride = prev;
                      _updateLiveSchedule();
                      if (_settings.selectedSchool != null) {
                        _fetchLunchMenu(_settings.selectedSchool!.name, prev);
                      }
                    });
                  },
                  icon: const Icon(Icons.arrow_back, size: 14),
                  label: const Text('◀ 어제'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      final next = current.add(const Duration(days: 1));
                      _debugTimeOverride = next;
                      _updateLiveSchedule();
                      if (_settings.selectedSchool != null) {
                        _fetchLunchMenu(_settings.selectedSchool!.name, next);
                      }
                    });
                  },
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: const Text('내일 ▶'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('시간/분 미세 조정 (실시간 시뮬레이션):', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('-1분'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _debugTimeOverride = current.subtract(const Duration(minutes: 1));
                      _updateLiveSchedule();
                    });
                  },
                ),
                ActionChip(
                  label: const Text('+1분'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _debugTimeOverride = current.add(const Duration(minutes: 1));
                      _updateLiveSchedule();
                    });
                  },
                ),
                ActionChip(
                  label: const Text('-5분'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _debugTimeOverride = current.subtract(const Duration(minutes: 5));
                      _updateLiveSchedule();
                    });
                  },
                ),
                ActionChip(
                  label: const Text('+5분'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _debugTimeOverride = current.add(const Duration(minutes: 5));
                      _updateLiveSchedule();
                    });
                  },
                ),
                ActionChip(
                  label: const Text('-10분'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _debugTimeOverride = current.subtract(const Duration(minutes: 10));
                      _updateLiveSchedule();
                    });
                  },
                ),
                ActionChip(
                  label: const Text('+10분'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _debugTimeOverride = current.add(const Duration(minutes: 10));
                      _updateLiveSchedule();
                    });
                  },
                ),
                ActionChip(
                  label: const Text('-1시간'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _debugTimeOverride = current.subtract(const Duration(hours: 1));
                      _updateLiveSchedule();
                    });
                  },
                ),
                ActionChip(
                  label: const Text('+1시간'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _debugTimeOverride = current.add(const Duration(hours: 1));
                      _updateLiveSchedule();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('빠른 교시 이동:', style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildQuickTimeBtn(ctx, current, 9, 20, '1교시(09:20)'),
                _buildQuickTimeBtn(ctx, current, 10, 20, '2교시(10:20)'),
                _buildQuickTimeBtn(ctx, current, 12, 40, '점심(12:40)'),
                _buildQuickTimeBtn(ctx, current, 13, 40, '5교시(13:40)'),
              ],
            ),
          ],
        ),
        actions: [
          if (_debugTimeOverride != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _debugTimeOverride = null;
                  _updateLiveSchedule();
                  if (_settings.selectedSchool != null) {
                    _fetchLunchMenu(_settings.selectedSchool!.name, DateTime.now());
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔄 실제 오늘 날짜/시간으로 복귀되었습니다.')),
                );
              },
              child: const Text('오늘로 초기화', style: TextStyle(color: Colors.orangeAccent)),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
              );
              if (time != null) {
                final newDate = DateTime(current.year, current.month, current.day, time.hour, time.minute);
                setState(() {
                  _debugTimeOverride = newDate;
                  _updateLiveSchedule();
                });
              }
            },
            icon: const Icon(Icons.access_time_rounded, size: 16),
            label: const Text('시간 변경'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final picked = await showDatePicker(
                context: context,
                initialDate: current,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (picked != null) {
                final newDate = DateTime(picked.year, picked.month, picked.day, current.hour, current.minute);
                setState(() {
                  _debugTimeOverride = newDate;
                  _updateLiveSchedule();
                  if (_settings.selectedSchool != null) {
                    _fetchLunchMenu(_settings.selectedSchool!.name, newDate);
                  }
                });
              }
            },
            icon: const Icon(Icons.calendar_month_rounded, size: 16),
            label: const Text('날짜 선택'),
          ),
        ],
      ),
    );
  }

  void _openWeeklyTimetable() async {
    final isDemo = AppConfig.isDemoMode ||
        _settings.schoolId.toLowerCase() == 'demo' ||
        _settings.selectedSchool?.name.contains('데모') == true;
    if (_settings.selectedSchool == null && !isDemo) return;
    final targetSchool = _settings.selectedSchool ??
        School(id: 0, region: '데모', name: '데모 중학교', code: 0);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TimetableView(
          school: targetSchool,
          apiScheduleEvents: _apiScheduleEvents,
          initialShowCalendar: false,
          initialTimetableResult: _timetableResult,
        ),
      ),
    );
    _loadPreferencesAndFetch(); // Reload settings in case they changed
  }

  /// 설정 메뉴 타일 (바텀 시트용 - 모던 글래스모피즘)
  Widget _buildSettingsMenuTile({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required double scale,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16 * scale),
        splashColor: color.withValues(alpha: 0.15),
        highlightColor: color.withValues(alpha: 0.08),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * scale,
            vertical: 12 * scale,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1E212B).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(
              color: color.withValues(alpha: 0.22),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10 * scale,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42 * scale,
                height: 42 * scale,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.25),
                      color.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12 * scale),
                  border: Border.all(
                    color: color.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, color: color, size: 21 * scale),
              ),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 14.5 * scale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansKr(
                        color: const Color(0xFF94A1B2),
                        fontSize: 11.5 * scale,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Container(
                    padding: EdgeInsets.all(6 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: color.withValues(alpha: 0.6),
                      size: 18 * scale,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSectionHeader(String title, double scale) {
    return Padding(
      padding: EdgeInsets.only(left: 4 * scale, bottom: 8 * scale, top: 4 * scale),
      child: Text(
        title,
        style: GoogleFonts.notoSansKr(
          color: const Color(0xFF00F5D4),
          fontSize: 12 * scale,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
  /// [비밀 데모 제어판] 데모 버전에서만 설정 문구를 길게 누를 때 실행되는 비밀 제어 모달
  void _showDemoSecretControllerDialog() async {
    final isDemo = AppConfig.isDemoMode || _settings.schoolId.toLowerCase() == 'demo';
    if (!isDemo) return;

    final scale = _settings.scaleFactor;
    String selectedClass = _settings.classNickname.isNotEmpty ? _settings.classNickname : 'Demo-class1';
    final currentLessons = _timetableResult?.lessons ?? [];

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161F2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20 * scale),
                side: const BorderSide(color: Colors.purpleAccent, width: 2),
              ),
              title: Row(
                children: [
                  const Icon(Icons.admin_panel_settings_rounded, color: Colors.purpleAccent, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    'Boardest 비밀 데모 제어판',
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18 * scale),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480 * scale,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 교실 변경
                      Text('1. 교실 변경 (Demo ID)', style: GoogleFonts.notoSansKr(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 14 * scale)),
                      SizedBox(height: 8 * scale),
                      Wrap(
                        spacing: 8 * scale,
                        runSpacing: 6 * scale,
                        children: List.generate(6, (i) {
                          final cId = 'Demo-class${i + 1}';
                          final isSelected = selectedClass == cId;
                          return ChoiceChip(
                            label: Text(cId, style: TextStyle(color: isSelected ? Colors.black : Colors.white)),
                            selected: isSelected,
                            selectedColor: Colors.purpleAccent,
                            backgroundColor: const Color(0xFF0F1722),
                            onSelected: (val) async {
                              if (val) {
                                setModalState(() => selectedClass = cId);
                                setState(() {
                                  _settings = _settings.copyWith(classNickname: cId);
                                });
                                await _storageService.saveSettings(_settings);
                                await _fetchTimetableWithRetry(0, _debugTimeOverride ?? DateTime.now());
                              }
                            },
                          );
                        }),
                      ),
                      Divider(color: Colors.white12, height: 24 * scale),

                      // 2. 시간 변경 (시뮬레이션)
                      Text('2. 시간 변경 (현재 교시 시뮬레이션)', style: GoogleFonts.notoSansKr(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 14 * scale)),
                      SizedBox(height: 8 * scale),
                      Wrap(
                        spacing: 6 * scale,
                        runSpacing: 6 * scale,
                        children: [
                          {'label': '1교시 (09:10)', 'h': 9, 'm': 10},
                          {'label': '2교시 (10:05)', 'h': 10, 'm': 5},
                          {'label': '3교시 (11:00)', 'h': 11, 'm': 0},
                          {'label': '4교시 (11:55)', 'h': 11, 'm': 55},
                          {'label': '🍽️ 점심시간 (12:40)', 'h': 12, 'm': 40},
                          {'label': '5교시 (13:50)', 'h': 13, 'm': 50},
                          {'label': '6교시 (14:45)', 'h': 14, 'm': 45},
                          {'label': '7교시 (15:35)', 'h': 15, 'm': 35},
                          {'label': '실제 시간 복원', 'h': -1, 'm': -1},
                        ].map((t) {
                          return ActionChip(
                            backgroundColor: (t['h'] == -1) ? Colors.redAccent.withValues(alpha: 0.2) : const Color(0xFF0F1722),
                            side: BorderSide(color: (t['h'] == -1) ? Colors.redAccent : Colors.white24),
                            label: Text(
                              t['label'] as String,
                              style: TextStyle(
                                color: (t['h'] == -1) ? Colors.redAccent : Colors.white,
                                fontSize: 12 * scale,
                              ),
                            ),
                            onPressed: () {
                              final h = t['h'] as int;
                              final m = t['m'] as int;
                              setState(() {
                                if (h == -1) {
                                  _debugTimeOverride = null;
                                } else {
                                  final now = DateTime.now();
                                  _debugTimeOverride = DateTime(now.year, now.month, now.day, h, m);
                                }
                                _updateLiveSchedule();
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        }).toList(),
                      ),
                      Divider(color: Colors.white12, height: 24 * scale),

                      // 3. 과목 변경
                      Text('3. 오늘의 과목 변경', style: GoogleFonts.notoSansKr(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 14 * scale)),
                      SizedBox(height: 8 * scale),
                      if (currentLessons.isEmpty)
                        Text('수업이 등록되어 있지 않습니다.', style: TextStyle(color: Colors.white38, fontSize: 12 * scale))
                      else
                        Column(
                          children: currentLessons.take(7).map((lesson) {
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 3 * scale),
                              child: Row(
                                children: [
                                  Text('${lesson.classTime}교시: ', style: const TextStyle(color: Colors.white70)),
                                  Expanded(
                                    child: Text(
                                      lesson.subject.isNotEmpty ? lesson.subject : '(비어있음)',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final newSub = await showDialog<String>(
                                        context: context,
                                        builder: (c) {
                                          final ctrl = TextEditingController(text: lesson.subject);
                                          return AlertDialog(
                                            backgroundColor: const Color(0xFF161F2E),
                                            title: Text('${lesson.classTime}교시 과목 변경', style: const TextStyle(color: Colors.white)),
                                            content: TextField(
                                              controller: ctrl,
                                              style: const TextStyle(color: Colors.white),
                                              decoration: const InputDecoration(hintText: '과목명 입력 (예: 로봇공학, AI윤리)'),
                                            ),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
                                              TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('변경')),
                                            ],
                                          );
                                        },
                                      );
                                      if (newSub != null && newSub.isNotEmpty) {
                                        setState(() {
                                          final idx = currentLessons.indexOf(lesson);
                                          if (idx != -1) {
                                            currentLessons[idx] = Lesson(
                                              grade: lesson.grade,
                                              classNum: lesson.classNum,
                                              weekday: lesson.weekday,
                                              classTime: lesson.classTime,
                                              teacher: lesson.teacher,
                                              subject: newSub,
                                              classroom: lesson.classroom,
                                              isChanged: true,
                                            );
                                          }
                                          _updateLiveSchedule();
                                        });
                                        setModalState(() {});
                                      }
                                    },
                                    child: const Text('수정', style: TextStyle(color: Colors.purpleAccent)),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기', style: TextStyle(color: Colors.purpleAccent)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onSettingsLongPress() {
    final isDemo = AppConfig.isDemoMode ||
        _settings.schoolId.toLowerCase() == 'demo' ||
        (_settings.selectedSchool?.name.contains('데모') ?? false);
    if (isDemo) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: Row(
            children: [
              const Icon(Icons.exit_to_app_rounded, color: Color(0xFFFF9F1C), size: 26),
              const SizedBox(width: 10),
              Text(
                'Demo 탈출',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            '가상 데모 모드를 종료하고, 시작 마법사(OOBE)로 돌아가시겠습니까?',
            style: GoogleFonts.notoSansKr(
              color: const Color(0xFF94A1B2),
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                '취소',
                style: GoogleFonts.notoSansKr(color: Colors.white70),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4565),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await _exitDemoMode();
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                'Demo 탈출',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } else {
      _openSettingsWizard();
    }
  }

  Future<void> _exitDemoMode() async {
    AppConfig.isDemoMode = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bst_persisted_demo');
    } catch (_) {}
    final clearedSettings = _settings.copyWith(
      isSetupComplete: false,
      schoolId: '',
      classNickname: '',
    );
    await _storageService.saveSettings(clearedSettings);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupWizardView()),
      );
    }
  }

  void _openSettingsWizard() async {
    final isDemo = AppConfig.isDemoMode ||
        _settings.schoolId.toLowerCase() == 'demo' ||
        (_settings.selectedSchool?.name.contains('데모') ?? false);
    if (isDemo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '🔒 데모 모드에서는 설정을 변경할 수 없습니다.\n([설정] 버튼을 1.5초간 꾹 누르면 데모를 탈출할 수 있습니다)',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: '데모 탈출',
            textColor: const Color(0xFFFF9F1C),
            onPressed: _onSettingsLongPress,
          ),
          backgroundColor: const Color(0xFFEF4565),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    _pauseDashboardTimer();
    bool settingsChanged = false;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SettingsFullscreenView(
            settings: _settings,
            onSettingsChanged: () {
              settingsChanged = true;
            },
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[Dashboard] settings route error: $e');
      debugPrint('[Dashboard] SettingsRoute error: $e, stack: $st');
    }
    if (!mounted) return;
    try {
      _resumeDashboardTimer();
      if (settingsChanged) {
        await _loadPreferencesAndFetch();
      }
    } catch (e, st) {
      debugPrint('[Dashboard] settings reload error: $e');
      debugPrint('[Dashboard] SettingsReload error: $e, stack: $st');
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _showUpdateChannelDialog() {
    final scale = _settings.scaleFactor;
    String selectedChannel = _settings.updateChannel;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20 * scale),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: Row(
            children: [
              Icon(Icons.system_update_rounded, color: const Color(0xFF00F5D4), size: 26 * scale),
              SizedBox(width: 10 * scale),
              Text(
                '시스템 업데이트 & 채널 설정',
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '현재 설치 버전: v${UpdateService.currentVersion}',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white70,
                  fontSize: 14 * scale,
                ),
              ),
              SizedBox(height: 16 * scale),
              Text(
                '업데이트 채널 선택',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8 * scale),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12 * scale),
                      onTap: () => setDlgState(() => selectedChannel = 'beta'),
                      child: Container(
                        padding: EdgeInsets.all(12 * scale),
                        decoration: BoxDecoration(
                          color: selectedChannel == 'beta'
                              ? const Color(0xFF7F5AF0).withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12 * scale),
                          border: Border.all(
                            color: selectedChannel == 'beta'
                                ? const Color(0xFF7F5AF0)
                                : Colors.white.withValues(alpha: 0.1),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '🚀 Beta (체험판)',
                              style: GoogleFonts.notoSansKr(
                                color: selectedChannel == 'beta' ? const Color(0xFF7F5AF0) : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13 * scale,
                              ),
                            ),
                            SizedBox(height: 4 * scale),
                            Text(
                              '최신 신기능 우선 적용',
                              style: TextStyle(color: Colors.white38, fontSize: 11 * scale),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10 * scale),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12 * scale),
                      onTap: () => setDlgState(() => selectedChannel = 'normal'),
                      child: Container(
                        padding: EdgeInsets.all(12 * scale),
                        decoration: BoxDecoration(
                          color: selectedChannel == 'normal'
                              ? const Color(0xFF00F5D4).withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12 * scale),
                          border: Border.all(
                            color: selectedChannel == 'normal'
                                ? const Color(0xFF00F5D4)
                                : Colors.white.withValues(alpha: 0.1),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '🛡️ Normal (안정판)',
                              style: GoogleFonts.notoSansKr(
                                color: selectedChannel == 'normal' ? const Color(0xFF00F5D4) : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13 * scale,
                              ),
                            ),
                            SizedBox(height: 4 * scale),
                            Text(
                              '검증된 정식 버전만 수신',
                              style: TextStyle(color: Colors.white38, fontSize: 11 * scale),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('닫기', style: TextStyle(color: Colors.white54, fontSize: 13 * scale)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                if (selectedChannel != _settings.updateChannel) {
                  final updated = _settings.copyWith(updateChannel: selectedChannel);
                  await _storageService.saveSettings(updated);
                  if (mounted) {
                    setState(() => _settings = updated);
                  }
                }
                UpdateService.checkAndUpdate(
                  context,
                  silent: false,
                  force: true,
                  channel: selectedChannel,
                );
              },
              child: Text('업데이트 확인', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13 * scale)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWithdrawDialog() async {
    final authService = AuthService();
    final user = await authService.getCurrentUser();
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          '회원 탈퇴',
          style: GoogleFonts.notoSansKr(
            color: const Color(0xFFEF4565),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '정말로 탈퇴하시겠습니까?\n이 계정 및 설정 정보가 즉시 영구 삭제됩니다.',
          style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '탈퇴 확인',
              style: GoogleFonts.notoSansKr(
                color: const Color(0xFFEF4565),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4565)),
        ),
      ),
    );

    final err = await authService.deleteAccount();
    if (!mounted) return;
    Navigator.pop(context);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4565),
          content: Text(
            err,
            style: GoogleFonts.notoSansKr(color: Colors.white),
          ),
        ),
      );
      return;
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

  Future<void> _checkAndPromptHomeLauncher() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool('boardest_home_launcher_dismissed') ?? false;
      if (dismissed) return;

      const channel = MethodChannel('com.boardest/launch_args');
      final isHome = await channel.invokeMethod<bool>('isDefaultHomeLauncher') ?? false;
      if (!isHome && mounted) {
        _showHomeLauncherDialog();
      }
    } catch (e) {
      debugPrint('[HomeLauncher] Error checking home launcher: $e');
    }
  }

  void _showHomeLauncherDialog() {
    final scale = _settings.scaleFactor;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20 * scale),
            side: const BorderSide(color: Color(0xFF242629)),
          ),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF2EC4B6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10 * scale),
                ),
                child: Icon(Icons.home_rounded, color: const Color(0xFF2EC4B6), size: 24 * scale),
              ),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Text(
                  '기본 홈 앱(런처) 설정',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18 * scale,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '전자칠판과 태블릿에서 홈 버튼을 누르면 언제든지 Boardest 대시보드로 바로 돌아올 수 있도록 기본 홈 앱으로 설정하시겠습니까?',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white70,
                  fontSize: 14 * scale,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 8 * scale),
              Text(
                '수업 중 다른 앱을 열었다가도 홈 버튼만 누르면 시간표와 판서 도구로 즉시 복귀할 수 있습니다.',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white38,
                  fontSize: 12 * scale,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('boardest_home_launcher_dismissed', true);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('나중에', style: GoogleFonts.notoSansKr(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2EC4B6),
                foregroundColor: const Color(0xFF003831),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  const channel = MethodChannel('com.boardest/launch_args');
                  await channel.invokeMethod('openHomeLauncherSettings');
                } catch (e) {
                  debugPrint('[HomeLauncher] Error opening settings: $e');
                }
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text('기본 홈 앱으로 설정', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDpiScaleDialog() {
    double currentScale = _settings.scaleFactor;
    final scale = currentScale;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16161A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20 * scale),
              side: const BorderSide(color: Color(0xFF242629)),
            ),
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10 * scale),
                  ),
                  child: Icon(Icons.aspect_ratio_rounded, color: const Color(0xFF00F5D4), size: 22 * scale),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Text(
                    '화면 배율 (DPI) 조정',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18 * scale,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '전자칠판 크기 및 해상도에 맞춰 UI 배율을 자유롭게 조절할 수 있습니다.',
                  style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale),
                ),
                SizedBox(height: 20 * scale),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('배율: ${(currentScale * 100).round()}%',
                        style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 15 * scale)),
                    Text(
                      currentScale < 1.0 ? '컴팩트 모드' : (currentScale > 1.0 ? '확대 모드' : '기본 100%'),
                      style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 12 * scale),
                    ),
                  ],
                ),
                Slider(
                  value: currentScale,
                  min: 0.6,
                  max: 1.5,
                  divisions: 18,
                  activeColor: const Color(0xFF00F5D4),
                  inactiveColor: Colors.white12,
                  label: '${(currentScale * 100).round()}%',
                  onChanged: (val) {
                    setDialogState(() => currentScale = (val * 10).round() / 10.0);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('60% (작게)', style: TextStyle(color: Colors.white24, fontSize: 10 * scale)),
                    TextButton(
                      onPressed: () => setDialogState(() => currentScale = 1.0),
                      child: Text('기본값(100%) 복원', style: TextStyle(color: const Color(0xFF2EC4B6), fontSize: 11 * scale)),
                    ),
                    Text('150% (크게)', style: TextStyle(color: Colors.white24, fontSize: 10 * scale)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EC4B6),
                  foregroundColor: const Color(0xFF003831),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                ),
                onPressed: () async {
                  final newSettings = _settings.copyWith(scaleFactor: currentScale);
                  await _storageService.saveSettings(newSettings);
                  setState(() => _settings = newSettings);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('화면 배율이 ${(currentScale * 100).round()}%로 설정되었습니다.'),
                        backgroundColor: const Color(0xFF2EC4B6),
                      ),
                    );
                  }
                },
                child: Text('적용하기', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
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
          Text(
            label,
            style: GoogleFonts.notoSansKr(
              color: const Color(0xFF94A1B2),
              fontSize: 11 * scale,
            ),
          ),
          SizedBox(height: 4 * scale),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.remove_rounded,
                  color: Colors.white70,
                  size: 16 * scale,
                ),
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
                icon: Icon(
                  Icons.add_rounded,
                  color: Colors.white70,
                  size: 16 * scale,
                ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20 * scale),
              ),
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
                            padding: EdgeInsets.symmetric(
                              horizontal: 16 * scale,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF24242B),
                              borderRadius: BorderRadius.circular(12 * scale),
                              border: Border.all(
                                color: const Color(0xFF7F5AF0),
                                width: 1.5 * scale,
                              ),
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
                            onChanged: (val) =>
                                setDState(() => displayHour = val),
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
                      children: [
                        if (_debugTimeOverride != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4565),
                            ),
                            icon: Icon(Icons.history_rounded, size: 16 * scale),
                            label: Text(
                              '실시간 복원',
                              style: GoogleFonts.notoSansKr(
                                fontWeight: FontWeight.bold,
                                fontSize: 13 * scale,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _debugTimeOverride = null;
                              });
                              _loadPreferencesAndFetch();
                              Navigator.pop(dialogCtx);
                            },
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: Text(
                            '취소',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF94A1B2),
                              fontSize: 14 * scale,
                            ),
                          ),
                        ),
                        SizedBox(width: 12 * scale),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7F5AF0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10 * scale),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 20 * scale,
                              vertical: 12 * scale,
                            ),
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
                          child: Text(
                            '적용',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14 * scale,
                            ),
                          ),
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
                    const Text(
                      'USB 모드 강제 활성화',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blueAccent,
                    ),
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
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.all(
                      color: const Color(0xFF2EC4B6).withValues(alpha: 0.25),
                    ),
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
                            const Icon(
                              Icons.school_rounded,
                              color: Color(0xFF00F5D4),
                            ),
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
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                              ),
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
                            hintStyle: GoogleFonts.notoSansKr(
                              color: Colors.white38,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF2EC4B6),
                            ),
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
                                icon: const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 18,
                                ),
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
                                  style: GoogleFonts.notoSansKr(
                                    color: Colors.white38,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  24,
                                ),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
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
                                              ? const Color(
                                                  0xFF2EC4B6,
                                                ).withValues(alpha: 0.12)
                                              : Colors.white.withValues(
                                                  alpha: 0.03,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: selected
                                                ? const Color(0xFF2EC4B6)
                                                : Colors.white.withValues(
                                                    alpha: 0.06,
                                                  ),
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
                                                  color: const Color(
                                                    0xFF00F5D4,
                                                  ),
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    e.title,
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 15,
                                                        ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    dateStr,
                                                    style:
                                                        GoogleFonts.notoSansKr(
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
  bool _handleDemoFullscreenKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyF) return false;
    if (!AppConfig.isDemoMode) return false;

    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context?.widget is EditableText) {
      return false;
    }

    if (!kIsWeb && Platform.isWindows) {
      windowManager.isFullScreen().then((fs) => windowManager.setFullScreen(!fs));
      return true;
    }
    return false;
  }

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
              Text(
                _errorMessage!,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
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

    String remainingTimeText = '';
    String clockRemainingDetailText = '';
    double? clockRemainingProgress;

    if (_currentPeriod != null) {
      final diff = _currentPeriod!.end.difference(_now);
      final minutes = diff.inMinutes;
      final seconds = diff.inSeconds % 60;
      final totalSec = _currentPeriod!.end.difference(_currentPeriod!.start).inSeconds;
      final elapsedSec = _now.difference(_currentPeriod!.start).inSeconds;
      if (totalSec > 0) {
        clockRemainingProgress = (elapsedSec / totalSec).clamp(0.0, 1.0);
      }

      if (diff.inSeconds > 0) {
        final totalMinutes = diff.inSeconds ~/ 60;
        final secStr = seconds > 0 ? ' $seconds초' : '';
        clockRemainingDetailText = _currentPeriod!.isClass
            ? '${_currentPeriod!.period}교시 종료까지 $totalMinutes분$secStr 남음'
            : '쉬는시간 $totalMinutes분$secStr 남음';
        remainingTimeText = _currentPeriod!.isClass
            ? '수업 종료까지 $totalMinutes분$secStr'
            : '쉬는 시간 $totalMinutes분$secStr 남음';
      } else {
        clockRemainingDetailText = '수업 준비 중';
      }
    }

    final activeDday = _activeDdayEvent;
    String? ddayLabel;
    if (activeDday != null) {
      final diffDays = DateTime(activeDday.date.year, activeDday.date.month, activeDday.date.day)
          .difference(_todayDateOnly)
          .inDays;
      final ddayNum = diffDays == 0 ? 'D-Day' : (diffDays > 0 ? 'D-$diffDays' : 'D+${diffDays.abs()}');
      ddayLabel = '$ddayNum ${activeDday.title}';
    }

    final effectiveDpiScale = AppPaths.adaptiveUiScale(context, _settings.scaleFactor);

    final dashboardScaffold = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Root route must not pop on desktop to prevent accidental app shutdown
      },
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(effectiveDpiScale.clamp(0.5, 4.0))),
        child: Scaffold(
        backgroundColor: const Color(0xFF06100E),
        body: Stack(
          children: [
            // Aurora background glow in pure mint spectrum
            Positioned(
              top: -100,
              left: -100,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.16),
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
                  color: const Color(0xFF2EC4B6).withValues(alpha: 0.12),
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.transparent),
            ),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final userScale = _settings.scaleFactor.clamp(0.8, 2.5);
                  final fitW = constraints.maxWidth / 1920.0;
                  final fitH = constraints.maxHeight / 1080.0;
                  final fit = fitW < fitH ? fitW : fitH;

                  // 디스플레이 불변 배율: FHD(1920) 기준 150%, 4K(3840) 기준 300%
                  // 브라우저 줌이나 OS 배율(DPI)과 무관하게 언제나 동일한 물리 시각 비율 유지
                  final scale = (userScale * fit).clamp(0.5, 4.0);
                  final baseW = constraints.maxWidth / scale;
                  final baseH = constraints.maxHeight / scale;

                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: baseW,
                        height: baseH,
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: const TextScaler.linear(1.0),
                          ),
                          child: BstClassMainLayout(
                            scaleFactor: 1.0,
                            appName: kIsWeb
                                ? (_settings.specialClassroomMode ? 'Class Teacher' : 'Class')
                                : (_settings.specialClassroomMode ? 'Teacher PRO' : 'Class PRO'),
                            schoolName: _settings.selectedSchool?.name ?? (_settings.schoolId.isNotEmpty ? _settings.schoolId : '보데스트 중학교'),
                            gradeClass: '${_settings.selectedGrade}학년 ${_settings.selectedClass}반',
                            isSpecialRoom: _settings.specialClassroomMode,
                            specialSubjectName: _settings.selectedSubject.isNotEmpty ? _settings.selectedSubject : null,
                            showCloudFiles: !_hideCloudPanel,
                            cloudFilesWidget: _buildInlineCloudDockPanel(1.0),
                periods: todayLessons.map((l) {
                  final times = _getPeriodStartAndEndTime(l.classTime);
                  return TimetablePeriodItem(
                    period: l.classTime,
                    subject: l.subject,
                    isCurrent: _currentLesson?.classTime == l.classTime,
                    isUpcoming: _nextLesson?.classTime == l.classTime,
                    targetClass: (_settings.specialClassroomMode && l.grade > 0 && l.classNum > 0)
                        ? '${l.grade}-${l.classNum}반'
                        : (l.subject.isNotEmpty ? l.subject : null),
                    startTime: times.$1,
                    endTime: times.$2,
                  );
                }).toList(),
                onPeriodTap: (p) => _openWeeklyTimetable(),
                getTextbookPath: (subject) => _settings.getTextbookPath(subject, grade: _settings.selectedGrade),
                getTextbookBytes: _getTextbookBytesForSubject,
                dateString: dateString,
                ddayLabel: ddayLabel,
                onDdayLongPress: _openSchoolScheduleDdayPicker,
                currentPeriodStatus: _currentLesson != null
                    ? '● ${_currentLesson!.classTime}교시 ${_currentLesson!.subject} 진행 중'
                    : '수업 준비 중',
                onClockLongPress: _openDebugDatePicker,
                clockRemainingDetailText: clockRemainingDetailText,
                clockRemainingProgress: clockRemainingProgress,
                currentTime: _now,
                activeSpecialPeriod: () {
                  if (_currentPeriod == null) return null;
                  if (_currentPeriod!.period == -3) return '아침시간';
                  if (_currentPeriod!.period == -1) return '조회시간';
                  if (_currentPeriod!.label.contains('점심')) {
                    final diff = _currentPeriod!.end.difference(_now);
                    if (diff.inSeconds <= 10 * 60) {
                      // 점심시간 종료 10분전은 그 다음교시 쉬는시간 취급
                      return null;
                    }
                    return '점심시간';
                  }
                  if (_currentPeriod!.period == -2) return '종례시간';
                  return null;
                }(),
                specialPeriodRemainingText: () {
                  if (_currentPeriod == null) return null;
                  final diff = _currentPeriod!.end.difference(_now);
                  final mins = diff.inMinutes;
                  if (mins >= 0) {
                    return '종료까지 ${mins + 1}분 남음';
                  }
                  return null;
                }(),
                currentSubject: () {
                  if (_currentPeriod != null) {
                    if (_currentPeriod!.period == -3) return '아침시간';
                    if (_currentPeriod!.period == -1) return '조회 시간';
                    if (_currentPeriod!.period == -2) return '종례 시간';
                    if (_currentPeriod!.period == -4) return '방과후';
                    if (_currentPeriod!.label.contains('점심')) return '점심시간';
                    if (!_currentPeriod!.isClass) {
                      if (_currentPeriod!.label.contains('종례')) return '종례 시간';
                      if (_currentPeriod!.label.contains('조회')) return '조회 시간';
                    }
                  }
                  if (_currentLesson != null) {
                    return _currentLesson!.subject;
                  }
                  if (_currentPeriod != null) {
                    return _currentPeriod!.label;
                  }
                  return _nextLesson?.subject ?? '수업 없음';
                }(),
                subjectDescription: () {
                  if (_currentPeriod != null) {
                    if (_currentPeriod!.period == -3) return '00:00 ~ 조회 전 • 상쾌한 아침 맞이';
                    if (_currentPeriod!.period == -1) return '학급 담임 선생님과 함께하는 아침 조회';
                    if (_currentPeriod!.period == -2) return '하루 일과를 마무리하는 종례 시간';
                    if (_currentPeriod!.period == -4) return '종례 후 방과후 자율 활동 및 귀가';
                    if (_currentPeriod!.label.contains('점심')) return '맛있는 점심 식사 & 자유 투표 시간';
                    if (!_currentPeriod!.isClass) return '쉬는 시간 • 다음 교시 준비';
                  }
                  if (_currentLesson != null) {
                    return '${_settings.selectedGrade}학년 교과서 • 수업 진행 중';
                  }
                  return _nextLesson != null
                      ? '쉬는 시간 • ${_nextLesson!.classTime}교시 교과서 준비'
                      : '오늘 수업 일과 종료';
                }(),
                onLessonInfoTap: _openTextbookProModal,
                nextSubject: _nextLesson?.subject ?? '일과 종료',
                nextSubjectRoom: _nextLesson != null ? '${_nextLesson!.classTime}교시 예정' : '',
                subjectIcon: '📘',
                currentTextbookImagePath: _currentLesson != null
                    ? _settings.getTextbookPath(_currentLesson!.subject, grade: _settings.selectedGrade)
                    : (_nextLesson != null
                        ? _settings.getTextbookPath(_nextLesson!.subject, grade: _settings.selectedGrade)
                        : null),
                currentTextbookBytes: _currentLesson != null
                    ? _getTextbookBytesForSubject(_currentLesson!.subject)
                    : (_nextLesson != null
                        ? _getTextbookBytesForSubject(_nextLesson!.subject)
                        : null),
                remainingTimeText: remainingTimeText,
                todayDishes: _todayMeal?.dishes ?? [],
                todayCalories: (_todayMeal?.calories.isNotEmpty == true)
                    ? _todayMeal!.calories
                    : '745 kcal',
                tomorrowDishes: _tomorrowMeal?.dishes ?? [],
                tomorrowCalories: (_tomorrowMeal?.calories.isNotEmpty == true)
                    ? _tomorrowMeal!.calories
                    : '682 kcal',
                tomorrowDateLabel: '다음 급식',
                lunchStartTime: TimeOfDay(
                  hour: _getLunchStartMinutes() ~/ 60,
                  minute: _getLunchStartMinutes() % 60,
                ),
                lunchEndTime: TimeOfDay(
                  hour: _getLunchEndMinutes() ~/ 60,
                  minute: _getLunchEndMinutes() % 60,
                ),
                onMealVote: _handleDishVote,
                onShowVoteBreakdown: _showDishVotesBreakdown,
                isCloudActive: BstCloudService.instance.activeToken != null,
                onCloudToggle: () {
                  if (BstCloudService.instance.activeToken != null) {
                    setState(() {
                      _hideCloudPanel = !_hideCloudPanel;
                    });
                    if (_hideCloudPanel) {
                      _scheduleCloudEscapeAutoLogout();
                    } else {
                      _cancelCloudEscapeAutoLogout();
                    }
                  } else {
                    _openCloudPairingModal();
                  }
                },
                isPro: !kIsWeb,
                isWindows: !kIsWeb && Platform.isWindows,
                onToolTap: (tool) {
                  switch (tool) {
                    case BstToolType.pen:
                      _openUnifiedPenDialog();
                      break;
                    case BstToolType.timer:
                      _openTimer();
                      break;
                    case BstToolType.random:
                      _openRandomPicker();
                      break;
                    case BstToolType.calculator:
                      _openCalculator();
                      break;
                    case BstToolType.web:
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BrowserBoardView(
                          scaleFactor: _settings.scaleFactor,
                          onBack: () => Navigator.of(context).pop(),
                        ),
                      ));
                      break;
                    case BstToolType.pdf:
                      _openTextbookProModal();
                      break;
                    case BstToolType.cloud:
                      _openCloudPairingModal();
                      break;
                    case BstToolType.settings:
                      _openSettingsWizard();
                      break;
                  }
                },
                customSlots: _getProCustomSlots(),
                onLaunchApp: (slot) => _launchSystemApp(
                  SystemApp(name: slot.name, appId: slot.id, iconPath: slot.iconPath),
                ),
                onRemoveApp: (customIdx) => _removeAppFromSlot(_getProSlotIndex(customIdx)),
                onAddAppToSlot: (customIdx) => _openAppSelectorForSlot(_getProSlotIndex(customIdx)),
                onAddAppTap: () {
                  final targetSlot = _getNextAvailableProSlotIndex();
                  _openAppSelectorForSlot(targetSlot);
                },
                onMinimizeTap: () async {
                  if (!kIsWeb && Platform.isWindows) {
                    await windowManager.minimize();
                  }
                },
                onCloseTap: () async {
                  if (!kIsWeb && Platform.isWindows) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF16161A),
                        title: const Text('앱 종료', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: const Text('Boardest 앱을 종료하시겠습니까?', style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4565)),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('종료', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      try {
                        await windowManager.close();
                      } catch (_) {
                        exit(0);
                      }
                    }
                  }
                },
                onLogoTap: _openWeeklyTimetable,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // In-app floating widgets overlay
            if (_showMiniTimer) _buildMiniTimerWindow(scale),
            if (_showMiniCalculator) _buildMiniCalculatorWindow(scale),
            if (_showMiniPicker) _buildMiniPickerWindow(scale),
                        if (_showMiniCalendar) _buildMiniCalendarWindow(scale),
            if (_showMiniAppDrawer) _buildMiniAppDrawerWindow(scale),
            if (_activePluginId != null)
              PluginRunnerView(
                pluginId: _activePluginId!,
                pluginName: _activePluginName!,
                scaleFactor: _settings.scaleFactor,
              ),
          ],
        ),
      ),
    ),
    );

    // Web 전용 가상 16:9 / 4:3 캔버스 래퍼 (화면 크기/비율에 관계없이 정확한 화면 비율 유지)
    if (kIsWeb) {
      final targetRatio = _settings.canvasAspectRatio;
      return Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: targetRatio,
            child: ClipRect(
              child: dashboardScaffold,
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        debugPrint('[DashboardView] Root route pop prevented to ensure desktop stability.');
      },
      child: dashboardScaffold,
    );
  }

  int? _lastTriggeredAutoLessonPeriod;

  void _checkAutoLessonFlow(PeriodTimeRange active, Lesson? currentLesson) async {
    if (active.period == _lastTriggeredAutoLessonPeriod) return;
    _lastTriggeredAutoLessonPeriod = active.period;

    if (currentLesson == null || currentLesson.subject.trim().isEmpty) return;

    try {
      final teachers = await BstCloudService.instance.getCloudTeachers(
        targetSchoolCode: _settings.schoolId.isNotEmpty ? _settings.schoolId : _settings.selectedSchool?.code?.toString(),
        targetSchoolName: _settings.selectedSchool?.name,
      );
      if (teachers.isEmpty) return;

      for (final teacher in teachers) {
        if (!teacher.autoLessonFlowEnabled) continue;
        if (teacher.ownerEmail.contains('demo') || teacher.teacherName == '이수학') {
          if (!AppConfig.isDemoMode && _settings.schoolId.toLowerCase() != 'demo') {
            continue;
          }
        }
        final secret = await BstCloudService.instance.getTrustedSecret(teacher.ownerEmail);
        if (secret == null || secret.isEmpty) continue;

        debugPrint('[AutoLessonFlow] 🔔 Period ${active.period} (${currentLesson.subject}) started! Teacher: ${teacher.teacherName}');

        final authRes = await BstCloudService.instance.autoAuthenticateWithTrustedSecret(
          teacher: teacher,
          classroomName: '${_settings.selectedGrade}학년 ${_settings.selectedClass}반',
        );

        if (authRes.success && authRes.accessToken != null) {
          // 보안상 학생 앞 자동 파일 열기 제거 -> 최신 본 폴더(수업 자료 탭)가 화면에 뜨도록만 처리
          BstCloudService.instance.activeToken = authRes.accessToken;
          if (mounted) {
            setState(() {
              _hideCloudPanel = false;
              _cloudCategoryFilter = 'lesson'; // 최신 수업 자료 폴더 표시
            });
            _refreshCloudFiles();
          }
          debugPrint('[AutoLessonFlow] 📂 수업 시작: 자동 파일 실행 대신 최신 수업 자료 폴더를 열었습니다.');
          break;
        }
      }
    } catch (e) {
      debugPrint('[AutoLessonFlow] Error during auto lesson flow: $e');
    }
  }

  void _openCloudPresentation(BstCloudFile file, BstCloudTeacher teacher, {int initialPage = 1}) {
    final lower = file.name.toLowerCase();
    if (kIsWeb) {
      final driveUrl = 'https://drive.google.com/file/d/${file.id}/view';
      launchUrl(Uri.parse(driveUrl), mode: LaunchMode.externalApplication);
    } else {
      BstCloudService.instance.downloadDriveFile(file.id, file.name, teacher.directAccessToken ?? '').then((localPath) {
        if (localPath != null && mounted) {
          if (lower.endsWith('.pptx') || lower.endsWith('.ppt')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PptOverlayView(
                  initialFilePath: localPath,
                  scaleFactor: _settings.scaleFactor,
                ),
              ),
            );
          } else if (lower.endsWith('.pdf')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PdfBoardView(
                  initialFilePath: localPath,
                  scaleFactor: _settings.scaleFactor,
                ),
              ),
            );
          } else if (lower.endsWith('.tbp') || lower.endsWith('.bsttbp')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TbpViewerRoute(
                  tbpFilePath: localPath,
                  scaleFactor: _settings.scaleFactor,
                ),
              ),
            );
          } else if (lower.endsWith('.canva') || lower.endsWith('.bstcanva')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CanvaBoardView(
                  filePath: localPath,
                  scaleFactor: _settings.scaleFactor,
                ),
              ),
            );
          }
        }
      });
    }
  }

  // --- 1. Left Timetable Panel (오늘의 시간표 - 교과서 배경, 교시 순서, 진행시간, 남은시간 게이지) ---
  Widget _buildTodayTimetablePanel(List<Lesson> lessons, bool isWeekend) {
    return BstTodayTimetablePanel(
      lessons: lessons,
      isWeekend: isWeekend,
      settings: _settings,
      currentPeriod: _currentPeriod,
      nextLesson: _nextLesson,
      countdownTime: _countdownTime,
      periodProgress: _periodProgress,
      onOpenWeeklyTimetable: _openWeeklyTimetable,
      onSelectLesson: (lesson) {
        setState(() {
          _currentLesson = lesson;
        });
      },
      getPeriodTimeString: _getPeriodTimeString,
      getAdaptiveImageProvider: _getAdaptiveImageProvider,
    );
  }

  // --- 2. PPT Clock Card (Center Top - 꾹 누르면 전체화면 & 급식실 선택) ---
  Widget _buildPptClockCard(String dateString) {
    final scale = _settings.scaleFactor;
    final timeString = _debugTimeOverride != null
        ? '${_debugTimeOverride!.hour.toString().padLeft(2, '0')}:${_debugTimeOverride!.minute.toString().padLeft(2, '0')}:${_debugTimeOverride!.second.toString().padLeft(2, '0')}'
        : '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}';

    final activeDday = _activeDdayEvent;
    final String ddayLabel = activeDday != null
        ? '${activeDday.title} ${_ddayCountLabel(activeDday.date)}'
        : 'D-Day';

    String statusLabel = '방과 후';
    if (_currentPeriod != null) {
      if (_currentPeriod!.isClass) {
        statusLabel = '${_currentPeriod!.label} 수업 중';
      } else if (_currentPeriod!.period == -3) {
        statusLabel = '아침 시간';
      } else if (_currentPeriod!.period == -1) {
        statusLabel = '조회 시간';
      } else if (_currentPeriod!.period == -2) {
        statusLabel = '종례 시간';
      } else if (_currentPeriod!.label == '점심 시간') {
        statusLabel = '점심 시간';
      } else {
        statusLabel = '쉬는 시간';
      }
    } else if (_now.isBefore(DateTime(_now.year, _now.month, _now.day, 8, 40))) {
      statusLabel = '아침 시간';
    }

    final dateFormatted = '${_now.year}.${_now.month.toString().padLeft(2, '0')}.${_now.day.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 10 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Date (Left) & Quick Badges (Aspect Ratio, D-Day)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateFormatted,
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
                    decoration: BoxDecoration(
                      color: AppConfig.isLiteMode
                          ? const Color(0xFF2EC4B6).withValues(alpha: 0.18)
                          : (!kIsWeb
                              ? const Color(0xFF7F5AF0).withValues(alpha: 0.22)
                              : const Color(0xFF00F5D4).withValues(alpha: 0.15)),
                      borderRadius: BorderRadius.circular(8 * scale),
                      border: Border.all(
                        color: AppConfig.isLiteMode
                            ? const Color(0xFF2EC4B6).withValues(alpha: 0.5)
                            : (!kIsWeb
                                ? const Color(0xFF7F5AF0).withValues(alpha: 0.5)
                                : const Color(0xFF00F5D4).withValues(alpha: 0.4)),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      AppConfig.isLiteMode ? 'LITE' : (!kIsWeb ? 'PRO' : 'CLASS'),
                      style: GoogleFonts.outfit(
                        color: AppConfig.isLiteMode
                            ? const Color(0xFF2EC4B6)
                            : (!kIsWeb ? const Color(0xFFE0B0FF) : const Color(0xFF00F5D4)),
                        fontSize: 11 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (kIsWeb) ...[
                    SizedBox(width: 8 * scale),
                    // Aspect Ratio & Fullscreen Switcher (짧게 탭: 전체화면, 길게 꾹: 16:9/4:3 화면비 토글)
                    GestureDetector(
                      onTap: toggleAppFullscreen,
                      onLongPress: _toggleAspectRatio,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8 * scale),
                          border: Border.all(
                            color: const Color(0xFF00F5D4).withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _settings.aspectRatio,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF00F5D4),
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(width: 8 * scale),
                  // D-Day
                  GestureDetector(
                    onLongPress: _openSchoolScheduleDdayPicker,
                    child: Text(
                      ddayLabel,
                      style: GoogleFonts.notoSansKr(
                        color: const Color(0xFF00F5D4),
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Center: Massive Ultra-Large Digital Clock (꾹 누르면 날짜/시간 변경)
          Expanded(
            child: GestureDetector(
              onLongPress: _setDebugTime,
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                    child: Text(
                      timeString,
                      style: GoogleFonts.outfit(
                        fontSize: 200,
                        fontWeight: FontWeight.w900,
                        color: _debugTimeOverride != null ? Colors.orangeAccent : Colors.white,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Dynamic Animated Progress Gauge Bar (실시간 진행 게이지 바)
          if (_currentPeriod != null && _periodProgress > 0) ...[
            SizedBox(height: 6 * scale),
            Stack(
              children: [
                // Track
                Container(
                  height: 5 * scale,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(2.5 * scale),
                  ),
                ),
                // Indicator
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  widthFactor: _periodProgress.clamp(0.0, 1.0),
                  child: Container(
                    height: 5 * scale,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2EC4B6), Color(0xFF00F5D4)],
                      ),
                      borderRadius: BorderRadius.circular(2.5 * scale),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00F5D4).withValues(alpha: 0.45),
                          blurRadius: 5 * scale,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8 * scale),
          ] else ...[
            SizedBox(height: 10 * scale),
          ],
          // Bottom Row: Status (Left) & Countdown (Right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                statusLabel,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _countdownTime.isNotEmpty ? '$_countdownTime 남음' : '',
                style: GoogleFonts.notoSansKr(
                  color: const Color(0xFF00F5D4),
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _getLunchStartMinutes() {
    try {
      final ts = _settings.timeSettings;
      final timeParts = ts.firstPeriodStart.split(':');
      final firstPeriodH = int.tryParse(timeParts[0]) ?? 8;
      final firstPeriodM = int.tryParse(timeParts.length > 1 ? timeParts[1] : '40') ?? 40;
      int currentMinutes = firstPeriodH * 60 + firstPeriodM;
      for (int p = 1; p <= ts.lunchAfterPeriod; p++) {
        currentMinutes += ts.lessonDuration.toInt();
        if (p < ts.lunchAfterPeriod) {
          currentMinutes += ts.breakDuration.toInt();
        }
      }
      return currentMinutes;
    } catch (_) {
      return 12 * 60; // 기본 12:00
    }
  }

  int _getLunchEndMinutes() {
    try {
      final ts = _settings.timeSettings;
      final startMin = _getLunchStartMinutes();
      return startMin + ts.lunchDuration.toInt();
    } catch (_) {
      return 12 * 60 + 50; // 기본 12:50
    }
  }

  bool _isLunchTimeNow() {
    final now = _debugTimeOverride ?? DateTime.now();
    if (_currentPeriod != null && !_currentPeriod!.isClass && _currentPeriod!.label.contains('점심')) {
      return true;
    }
    final minutes = now.hour * 60 + now.minute;
    final start = _getLunchStartMinutes();
    final end = _getLunchEndMinutes();
    return minutes >= start && minutes <= end;
  }

  /// [신규] 급식 메뉴 투표 가능 시간: 점심시간 시작 ~ 점심시간 종료 5분 전까지
  /// - 종료 5분 전까지: 우리 반 투표 (버튼 활성화)
  /// - 종료 5분 전 ~ 4분 전: 1분간 서버 1회 PUT 전송 중 (투표 버튼 비활성화)
  /// - 종료 4분 전 이후: 전교 득표 공개 및 투표 마감
  bool _isMealVoteTimeNow() {
    final now = _debugTimeOverride ?? DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final start = _getLunchStartMinutes();
    final end = _getLunchEndMinutes();
    // 데모모드든 일반이든 급식 투표는 점심시간 시작 ~ 5분전까지
    return minutes >= start && minutes < (end - 5);
  }

  /// [신규] 다른 반 표수 및 전교 득표수 공개 시점:
  /// - 종료 5분 전~4분 전 1분간 서버 동기화 후, 종료 4분 전부터 타 반 표수 포함 전교 표수 공개!
  bool _isMealVoteResultTimeNow() {
    final now = _debugTimeOverride ?? DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final end = _getLunchEndMinutes();
    // 점심시간 종료 5분 전부터 결과 노출
    return minutes >= (end - 5) && minutes < end;
  }

  /// [신규] 점심시간 끝나고 20분 뒤인지 판별 (20분 뒤면 다음날 급식으로 자동 전환)
  bool _isAfterLunchPlus20Min() {
    final now = _debugTimeOverride ?? DateTime.now();
    final lunchEndMinutes = _getLunchEndMinutes();
    final switchMinutes = lunchEndMinutes + 20; // 점심시간 끝나고 20분 뒤
    final nowMinutes = now.hour * 60 + now.minute;
    return nowMinutes >= switchMinutes;
  }

  Future<void> _toggleDishHighlight(String dishName) async {
    final now = _debugTimeOverride ?? DateTime.now();
    final dateKey = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    setState(() {
      if (_highlightedDishes.contains(dishName)) {
        _highlightedDishes.remove(dishName);
      } else {
        _highlightedDishes.add(dishName);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('meal_highlights_$dateKey', _highlightedDishes.toList());
  }

  /// [신규] 음식 꾹 누르면 알레르기 정보가 먼저 뜨고 형광펜 토글도 가능한 다이얼로그
  void _showDishAllergyDialog(MealDishItem dish) {
    final scale = _settings.scaleFactor;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final highlighted = _highlightedDishes.contains(dish.name);
            return AlertDialog(
              backgroundColor: const Color(0xFF161F2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18 * scale),
                side: BorderSide(color: const Color(0xFF00F5D4).withValues(alpha: 0.35)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8 * scale),
                    ),
                    child: Icon(Icons.shield_outlined, color: const Color(0xFF00F5D4), size: 22 * scale),
                  ),
                  SizedBox(width: 10 * scale),
                  Expanded(
                    child: Text(
                      dish.name,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18 * scale,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '알레르기 유발 식품 정보',
                    style: GoogleFonts.notoSansKr(
                      color: const Color(0xFF00F5D4),
                      fontWeight: FontWeight.bold,
                      fontSize: 14 * scale,
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  dish.allergies.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12 * scale),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8 * scale),
                          ),
                          child: Text(
                            '표시된 알레르기 유발 성분이 없습니다. 안심하고 드셔도 됩니다! 🥗',
                            style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale),
                          ),
                        )
                      : Wrap(
                          spacing: 6 * scale,
                          runSpacing: 6 * scale,
                          children: dish.allergies.map((allergy) {
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB703).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20 * scale),
                                border: Border.all(color: const Color(0xFFFFB703).withValues(alpha: 0.6)),
                              ),
                              child: Text(
                                '⚠️ $allergy',
                                style: GoogleFonts.notoSansKr(
                                  color: const Color(0xFFFFD166),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13 * scale,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                  SizedBox(height: 16 * scale),
                  Divider(color: Colors.white12, height: 1),
                  SizedBox(height: 12 * scale),
                  InkWell(
                    onTap: () async {
                      await _toggleDishHighlight(dish.name);
                      setDialogState(() {});
                    },
                    borderRadius: BorderRadius.circular(10 * scale),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 10 * scale, horizontal: 12 * scale),
                      decoration: BoxDecoration(
                        color: highlighted
                            ? const Color(0xFFFFEE58).withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10 * scale),
                        border: Border.all(
                          color: highlighted
                              ? const Color(0xFFFFEE58)
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            highlighted ? Icons.brush : Icons.brush_outlined,
                            size: 16 * scale,
                            color: highlighted ? const Color(0xFFFFF176) : Colors.white70,
                          ),
                          SizedBox(width: 8 * scale),
                          Text(
                            highlighted ? '형광펜 해제하기' : '이 메뉴 형광펜으로 칠하기',
                            style: GoogleFonts.notoSansKr(
                              color: highlighted ? const Color(0xFFFFF176) : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13 * scale,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('닫기', style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleDishVote(String dishName, {int amount = 1}) async {
    if (!_isMealVoteTimeNow()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🍽️ 메뉴 투표는 점심시간 종료 5분 전까지만 가능합니다! (메뉴를 꾹 누르면 투표 내역/알레르기 확인)'),
          backgroundColor: Color(0xFFE53935),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final now = _debugTimeOverride ?? DateTime.now();
    final voteDate = DateTime(now.year, now.month, now.day);
    final currentSchoolId = _settings.schoolId.isNotEmpty
        ? _settings.schoolId
        : (_settings.selectedSchool?.name ?? 'Demo');
    final classKey = _settings.classNickname.isNotEmpty
        ? _settings.classNickname
        : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';

    await MealVoteService.instance.recordLocalVote(
      schoolId: currentSchoolId,
      date: voteDate,
      dishName: dishName,
      classKey: classKey,
      amount: amount,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(amount > 1 ? '🔥 "$dishName"에 $amount표를 투표했습니다!' : '✨ "$dishName"에 투표했습니다!'),
        backgroundColor: const Color(0xFF00F5D4),
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }

  void _showDishVotesBreakdown(String dishName) {
    final votesMap = MealVoteService.instance.getClassVotes(dishName);
    final total = MealVoteService.instance.getTotalVotes(dishName);
    final scale = _settings.scaleFactor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16 * scale),
          side: BorderSide(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            const Icon(Icons.bar_chart_rounded, color: Color(0xFF00F5D4)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$dishName 투표 통계 (총 $total표)',
                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18 * scale),
              ),
            ),
          ],
        ),
        content: votesMap.isEmpty
            ? Text('아직 투표한 반이 없습니다.', style: GoogleFonts.notoSansKr(color: Colors.white70))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: votesMap.entries.map((e) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 4 * scale),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15 * scale)),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F5D4).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10 * scale),
                            ),
                            child: Text(
                              '${e.value}표',
                              style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 13 * scale),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Color(0xFF00F5D4))),
          ),
        ],
      ),
    );
  }

  void _showMonthlyMealsDialog() {
    final schoolName = _settings.selectedSchool?.name ?? (_settings.schoolId.isNotEmpty ? _settings.schoolId : '양동중학교');
    MonthlyMealCalendarDialog.show(
      context,
      schoolName: schoolName,
      initialDate: _debugTimeOverride ?? DateTime.now(),
    );
  }

  /// [신규 개편] 단일 일자 전면 급식 카드 (점심 20분 후 내일 급식 자동 전환, 알레르기 텍스트 완전 제거, 꾹 누르면 알레르기 팝업)
  Widget _buildNeisMealCard(double scale, {bool isCompact = false}) {
    final currentCafeteria = _settings.cafeteriaNum.isNotEmpty ? _settings.cafeteriaNum : '급식실1';
    final showTomorrow = _isAfterLunchPlus20Min();
    final displayMeal = (showTomorrow && _tomorrowMeal != null) ? _tomorrowMeal : _todayMeal;
    final isDisplayingTomorrow = showTomorrow && _tomorrowMeal != null;

    return ValueListenableBuilder<Map<String, Map<String, int>>>(
      valueListenable: MealVoteService.instance.votesNotifier,
      builder: (context, _, __) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _showMealInfoDialog,
            onLongPress: _showMonthlyMealsDialog, // 빈 공간 꾹 누르면 한달치 급식 모달
            borderRadius: BorderRadius.circular(24 * scale),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D141C),
                borderRadius: BorderRadius.circular(24 * scale),
                border: Border.all(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10 * scale,
                    offset: Offset(0, 4 * scale),
                  ),
                ],
              ),
              padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 14 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Header
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(6 * scale),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8 * scale),
                        ),
                        child: Icon(Icons.restaurant_rounded, size: 16 * scale, color: const Color(0xFF00F5D4)),
                      ),
                      SizedBox(width: 10 * scale),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '급식 식단 ($currentCafeteria)',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontSize: 17 * scale,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 8 * scale),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
                              decoration: BoxDecoration(
                                color: isDisplayingTomorrow
                                    ? const Color(0xFFFFB703).withValues(alpha: 0.2)
                                    : const Color(0xFF00F5D4).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6 * scale),
                                border: Border.all(
                                  color: isDisplayingTomorrow
                                      ? const Color(0xFFFFB703).withValues(alpha: 0.5)
                                      : const Color(0xFF00F5D4).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                isDisplayingTomorrow ? '내일 식단' : '오늘 식단',
                                style: GoogleFonts.notoSansKr(
                                  color: isDisplayingTomorrow ? const Color(0xFFFFD166) : const Color(0xFF00F5D4),
                                  fontSize: 11 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _showMonthlyMealsDialog,
                        icon: Icon(Icons.calendar_month_rounded, size: 18 * scale, color: const Color(0xFF00F5D4)),
                        tooltip: '한 달치 급식 전체보기 (길게 눌러도 열림)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      SizedBox(width: 8 * scale),
                      IconButton(
                        onPressed: _showCafeteriaSelectorDialog,
                        icon: Icon(Icons.tune_rounded, size: 18 * scale, color: Colors.white60),
                        tooltip: '급식실 선택',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  SizedBox(height: 10 * scale),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                  SizedBox(height: 10 * scale),

                  // Meal Content (단일 일자 100% 전면 표시)
                  Expanded(
                    child: _isLoadingMeal
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF00F5D4)))
                        : _buildSingleDayMealSection(displayMeal, scale, isToday: !isDisplayingTomorrow),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSingleDayMealSection(MealDayInfo? mealInfo, double scale, {required bool isToday}) {
    if (mealInfo == null || mealInfo.dishes.isEmpty) {
      return Center(
        child: Text(
          isToday ? '오늘 급식 정보가 없습니다' : '내일 급식 정보가 없습니다',
          style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * scale),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date Title (e.g. "9/23 급식 (오늘)")
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
          decoration: BoxDecoration(
            color: isToday
                ? const Color(0xFF00F5D4).withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6 * scale),
          ),
          child: Text(
            mealInfo.dateLabel,
            style: GoogleFonts.notoSansKr(
              fontSize: 12 * scale,
              fontWeight: FontWeight.bold,
              color: isToday ? const Color(0xFF00F5D4) : Colors.white70,
            ),
          ),
        ),
        SizedBox(height: 6 * scale),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: mealInfo.dishes.length,
              itemBuilder: (context, idx) {
                final dish = mealInfo.dishes[idx];
                final isHighlighted = _highlightedDishes.contains(dish.name);
                final totalVotes = MealVoteService.instance.getTotalVotes(dish.name);

                return Padding(
                  padding: EdgeInsets.only(bottom: 5 * scale),
                  child: InkWell(
                    // 탭: 점심시간이면 투표, 점심시간 아니면 알레르기 정보 다이얼로그
                    onTap: () {
                      if (_isMealVoteTimeNow()) {
                        _handleDishVote(dish.name);
                      } else {
                        _showDishAllergyDialog(dish);
                      }
                    },
                    onLongPress: () {
                      if (isToday && _isMealVoteResultTimeNow()) {
                        _showDishVotesBreakdown(dish.name);
                      } else {
                        _showDishAllergyDialog(dish);
                      }
                    },
                    borderRadius: BorderRadius.circular(6 * scale),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 5 * scale),
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? const Color(0xFFFFF176).withValues(alpha: 0.28)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6 * scale),
                        border: isHighlighted
                            ? Border.all(color: const Color(0xFFFFEE58).withValues(alpha: 0.6), width: 1)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              dish.name, // 알레르기 괄호 완전 제거, 음식명만 깔끔하게 표시
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15 * scale,
                                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                                color: isHighlighted ? const Color(0xFFFFF59D) : Colors.white,
                              ),
                            ),
                          ),
                          if (totalVotes > 0 && (!isToday || _isMealVoteResultTimeNow()))
                            GestureDetector(
                              onLongPress: () => _showDishVotesBreakdown(dish.name),
                              child: Container(
                                margin: EdgeInsets.only(left: 4 * scale),
                                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 1.5 * scale),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4565).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10 * scale),
                                  border: Border.all(color: const Color(0xFFEF4565).withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  '🔥 $totalVotes',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10 * scale,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFFF85A1),
                                  ),
                                ),
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
        ),
      ],
    );
  }

  void _showMealInfoDialog() {
    final scale = _settings.scaleFactor;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            const Icon(Icons.restaurant_rounded, color: Color(0xFF00F5D4), size: 26),
            const SizedBox(width: 10),
            Text(
              '오늘의 급식 식단',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            _mealInfo.isNotEmpty ? _mealInfo : '급식 정보가 없습니다.',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 20, height: 1.8, fontWeight: FontWeight.w500),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('확인', style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 18)),
          ),
        ],
      ),
    );
  }

  /// [신규] Cloud 연결 시 1:3 좁은 폭을 위한 세로형 지금 수업 카드 (상단 교과서, 하단 과목명)
  Widget _buildVerticalPptSubjectCard(List<Lesson> todayLessons, double scale) {
    Lesson? liveLesson = _currentLesson;
    if (liveLesson == null || liveLesson.subject.isEmpty) {
      if (_currentPeriod != null && _currentPeriod!.isClass) {
        liveLesson = todayLessons.where((l) => l.classTime == _currentPeriod!.period).firstOrNull;
      }
    }
    liveLesson ??= todayLessons.firstOrNull;
    final subjectName = (liveLesson != null && liveLesson.subject.isNotEmpty) ? liveLesson.subject : '수업 준비';
    final String? imgPath = _settings.getTextbookPath(subjectName);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(20 * scale),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.2),
          width: 1.2,
        ),
      ),
      padding: EdgeInsets.all(10 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6 * scale),
                border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.4)),
              ),
              child: Text(
                '지금 수업',
                style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontSize: 10 * scale, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(height: 6 * scale),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10 * scale),
                    border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.3), width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9 * scale),
                    child: _buildAdaptiveTextbookImage(imgPath, fit: BoxFit.cover, subjectTitle: subjectName),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 6 * scale),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                subjectName,
                style: GoogleFonts.notoSansKr(
                  fontSize: 22 * scale,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. PPT Subject Card (Center Bottom-Left - 실시간 교시 수업 및 교과서 배경 연동) ---
  Widget _buildPptSubjectCard(List<Lesson> todayLessons, {bool isExpandedDock = false}) {
    final scale = _settings.scaleFactor;

    // Determine current live lesson dynamically (탭한 수업 > 현재 진행 수업 > 다음 수업 > 1교시 수업)
    Lesson? activeLesson;
    String statusBadge = '';
    String defaultTitle = '수업 준비';

    if (_currentLesson != null && _currentLesson!.subject.isNotEmpty) {
      activeLesson = _currentLesson;
      statusBadge = '선택된 수업';
    } else if (_currentPeriod != null && _currentPeriod!.isClass) {
      try {
        activeLesson = todayLessons.firstWhere((l) => l.classTime == _currentPeriod!.period);
      } catch (_) {
        activeLesson = null;
      }
      statusBadge = '${_currentPeriod!.label} 수업 중';
    } else if (_currentPeriod != null && !_currentPeriod!.isClass) {
      if (_currentPeriod!.period == -3) {
        activeLesson = _nextLesson ?? (todayLessons.isNotEmpty ? todayLessons.first : null);
        statusBadge = '아침 시간 (1교시 준비)';
        defaultTitle = '아침 시간';
      } else if (_currentPeriod!.period == -1) {
        activeLesson = _nextLesson ?? (todayLessons.isNotEmpty ? todayLessons.first : null);
        statusBadge = '조회 시간 (1교시 준비)';
        defaultTitle = '조회 시간';
      } else if (_currentPeriod!.period == -2) {
        activeLesson = null;
        statusBadge = '종례 시간';
        defaultTitle = '종례 및 하루 마무리';
      } else if (_currentPeriod!.label == '점심 시간') {
        activeLesson = _nextLesson;
        statusBadge = activeLesson != null ? '점심 시간 (${activeLesson.classTime}교시 준비)' : '점심 시간';
        defaultTitle = '맛있는 점심 시간';
      } else {
        // 쉬는 시간
        activeLesson = _nextLesson ?? (todayLessons.isNotEmpty ? todayLessons.first : null);
        statusBadge = activeLesson != null ? '쉬는 시간 (${activeLesson.classTime}교시 준비)' : '쉬는 시간';
        defaultTitle = '쉬는 시간';
      }
    } else if (_now.isBefore(DateTime(_now.year, _now.month, _now.day, 8, 40))) {
      activeLesson = todayLessons.isNotEmpty ? todayLessons.first : null;
      statusBadge = '일과 시작 전';
      defaultTitle = '일과 시작 전';
    } else {
      activeLesson = todayLessons.isNotEmpty ? todayLessons.first : null;
      statusBadge = '방과 후 (다음 수업 준비)';
      defaultTitle = '방과 후';
    }

    final String subjectName = (activeLesson != null && activeLesson.subject.isNotEmpty)
        ? activeLesson.subject
        : defaultTitle;
    final String? imgPath = activeLesson != null ? _settings.getTextbookPath(activeLesson.subject) : null;
    final imgProvider = _getAdaptiveImageProvider(imgPath, subject: subjectName);

    // 교수학습실: 시간표/교과서 대신 시계 아래 크게 현재 교시 상태 표시
    if (_settings.isLearningLab) {
      String labPeriodStatus = statusBadge;
      if (_currentPeriod != null && _currentPeriod!.isClass) {
        labPeriodStatus = '${_currentPeriod!.label} 수업 중';
      }
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF081714),
          borderRadius: BorderRadius.circular(24 * scale),
          border: Border.all(
            color: const Color(0xFF00F5D4).withValues(alpha: 0.25),
            width: 1.5,
          ),
          gradient: const LinearGradient(
            colors: [Color(0xFF081714), Color(0xFF0F2922)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 16 * scale),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10 * scale),
                  border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.4)),
                ),
                child: Text(
                  _settings.classNickname.isNotEmpty ? _settings.classNickname : '교수학습실',
                  style: GoogleFonts.notoSansKr(color: const Color(0xFF74f8e5), fontSize: 13 * scale, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(height: 10 * scale),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  labPeriodStatus,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 72 * scale,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                    shadows: [
                      Shadow(color: const Color(0xFF00F5D4).withOpacity(0.4), blurRadius: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
          width: 1.2,
        ),
        image: imgProvider != null
            ? DecorationImage(
                image: imgProvider,
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  const Color(0xFF040E0C).withValues(alpha: 0.90),
                  BlendMode.srcOver,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.all(isExpandedDock ? 12 * scale : 16 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: Textbook cover
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16 * scale),
                border: Border.all(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.3),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                    blurRadius: 10 * scale,
                    offset: Offset(0, 4 * scale),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15 * scale),
                child: _buildAdaptiveTextbookImage(
                  imgPath,
                  fit: BoxFit.cover,
                  subjectTitle: subjectName,
                ),
              ),
            ),
          ),
          SizedBox(width: isExpandedDock ? 14 * scale : 24 * scale),
          // Right: Real-time status badge & Giant Subject Name / 수업 중 OTP 바로가기
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 5 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10 * scale),
                        border: Border.all(
                          color: const Color(0xFF00F5D4).withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        statusBadge,
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF74f8e5),
                          fontSize: 13.5 * scale,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (BstCloudService.instance.activeToken != null && _hideCloudPanel) ...[
                      SizedBox(width: 8 * scale),
                      InkWell(
                        onTap: () => setState(() => _hideCloudPanel = false),
                        borderRadius: BorderRadius.circular(8 * scale),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8 * scale),
                            border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_rounded, color: const Color(0xFF00F5D4), size: 13 * scale),
                              SizedBox(width: 4 * scale),
                              Text(
                                '클라우드 다시 열기',
                                style: GoogleFonts.notoSansKr(
                                  color: const Color(0xFF00F5D4),
                                  fontSize: 11 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 10 * scale),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    subjectName,
                    style: GoogleFonts.notoSansKr(
                      fontSize: isExpandedDock ? 50 * scale : 68 * scale,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1.5,
                      shadows: [
                        Shadow(
                          color: const Color(0xFF00F5D4).withOpacity(0.3),
                          blurRadius: 16 * scale,
                        ),
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.9),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _initReverseQrSession() async {
    if (_reversePairSession != null || _isLoadingQrSession) return;
    if (!mounted) return;
    setState(() {
      _isLoadingQrSession = true;
      _qrSessionCancelled = false;
    });

    try {
      final user = _currentUser;
      final session = await BstCloudService.instance.createReversePairSession(
        schoolCode: _settings.schoolId.isNotEmpty ? _settings.schoolId : _settings.selectedSchool?.code?.toString(),
        grade: user?.grade,
        classNum: user?.classNum,
      );
      if (!mounted) return;
      setState(() {
        _reversePairSession = session;
        _isLoadingQrSession = false;
      });

      final res = await BstCloudService.instance.waitForReversePairAuth(
        session.secret,
        isCancelled: () => !mounted || _qrSessionCancelled || BstCloudService.instance.activeToken != null,
      );

      if (!mounted) return;
      if (res.success) {
        setState(() {
          _refreshCloudFiles();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 [${res.teacherName ?? "선생님"}] 전자칠판 연동 성공! 수업자료가 연결되었습니다.',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF2CB67D),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingQrSession = false);
      }
    }
  }

  void _refreshReverseQrSession() {
    setState(() {
      _qrSessionCancelled = true;
      _reversePairSession = null;
      _isLoadingQrSession = false;
    });
    _initReverseQrSession();
  }

  Widget _buildCloudQrScannerView(double scale) {
    if (_reversePairSession == null && !_isLoadingQrSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initReverseQrSession();
      });
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isLoadingQrSession)
          Padding(
            padding: EdgeInsets.all(24 * scale),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
            ),
          )
        else if (_reversePairSession != null) ...[
          Container(
            padding: EdgeInsets.all(10 * scale),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16 * scale),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F5D4).withOpacity(0.25),
                  blurRadius: 14 * scale,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: QrImageView(
              data: _reversePairSession!.qrUrl,
              version: QrVersions.auto,
              size: 130 * scale,
              backgroundColor: Colors.white,
              padding: EdgeInsets.zero,
            ),
          ),
          SizedBox(height: 8 * scale),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6 * scale,
                height: 6 * scale,
                decoration: const BoxDecoration(
                  color: Color(0xFF00F5D4),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 6 * scale),
              Text(
                '스마트폰 기본 카메라로 스캔',
                style: GoogleFonts.notoSansKr(
                  color: const Color(0xFF00F5D4),
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 2 * scale),
          Text(
            '로그인 즉시 전자칠판에 자동 연결',
            style: GoogleFonts.notoSansKr(
              color: Colors.white54,
              fontSize: 9.5 * scale,
            ),
          ),
          SizedBox(height: 4 * scale),
          InkWell(
            onTap: _refreshReverseQrSession,
            borderRadius: BorderRadius.circular(8 * scale),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white38, size: 12 * scale),
                  SizedBox(width: 4 * scale),
                  Text('새 QR 생성', style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 9.5 * scale)),
                ],
              ),
            ),
          ),
        ] else ...[
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: const Color(0xFF00F5D4), size: 28 * scale),
            onPressed: _refreshReverseQrSession,
          ),
          Text('QR 생성 실패 (터치하여 재시도)', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 11 * scale)),
        ],
      ],
    );
  }

  // --- [신규] 상단 QR 스캔 & 하단 OTP(6자리)/교사ID(2자리) 키패드 통합 패널 (수업시간 광고판 대체) ---
  Widget _buildCloudOtpKeypadPanel(double scale) {
    if (_reversePairSession == null && !_isLoadingQrSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initReverseQrSession();
      });
    }

    final isOtpFocused = _activeKeypadTarget == 'otp';
    final isTeacherIdFocused = _activeKeypadTarget == 'teacherId';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.35),
          width: 1.5,
        ),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0D231E),
            Color(0xFF071411),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F5D4).withValues(alpha: 0.12),
            blurRadius: 16 * scale,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: EdgeInsets.all(10 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 상단 배지 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_sync_rounded, color: const Color(0xFF00F5D4), size: 14 * scale),
                  SizedBox(width: 5 * scale),
                  Text(
                    '교사용 Cloud 즉시 연결',
                    style: GoogleFonts.notoSansKr(
                      color: const Color(0xFF00F5D4),
                      fontSize: 11.5 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _refreshReverseQrSession,
                borderRadius: BorderRadius.circular(6 * scale),
                child: Padding(
                  padding: EdgeInsets.all(2 * scale),
                  child: Row(
                    children: [
                      Icon(Icons.refresh_rounded, size: 12 * scale, color: Colors.white60),
                      SizedBox(width: 3 * scale),
                      Text('새로고침', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, color: Colors.white60)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6 * scale),

          // 1. [위] QR 코드 뷰 영역 (스마트폰 카메라 스캔용)
          Expanded(
            flex: 6,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 6 * scale),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14 * scale),
                border: Border.all(color: Colors.white10),
              ),
              child: _isLoadingQrSession
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
                  : (_reversePairSession != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.all(6 * scale),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12 * scale),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00F5D4).withValues(alpha: 0.2),
                                    blurRadius: 10 * scale,
                                  ),
                                ],
                              ),
                              child: QrImageView(
                                data: _reversePairSession!.qrUrl,
                                version: QrVersions.auto,
                                size: 85 * scale,
                                backgroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                            SizedBox(height: 5 * scale),
                            Text(
                              '📷 스마트폰 카메라로 QR 스캔 시 즉시 연결',
                              style: GoogleFonts.notoSansKr(
                                color: const Color(0xFF74F8E5),
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Text(
                            'QR 코드 로딩 중...',
                            style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 11 * scale),
                          ),
                        )),
            ),
          ),
          SizedBox(height: 8 * scale),

          // 2. [밑] 6자리 OTP 빈칸 & 2자리 교사 ID 빈칸
          Row(
            children: [
              // 6자리 OTP 빈칸
              Expanded(
                flex: 7,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _activeKeypadTarget = 'otp';
                      _otpErrorMsg = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(10 * scale),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 5 * scale),
                    decoration: BoxDecoration(
                      color: isOtpFocused
                          ? const Color(0xFF00F5D4).withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10 * scale),
                      border: Border.all(
                        color: isOtpFocused ? const Color(0xFF00F5D4) : Colors.white24,
                        width: isOtpFocused ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'OTP (6자리)',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 9.5 * scale,
                                fontWeight: FontWeight.bold,
                                color: isOtpFocused ? const Color(0xFF00F5D4) : Colors.white60,
                              ),
                            ),
                            if (isOtpFocused)
                              Text('입력 중', style: GoogleFonts.notoSansKr(fontSize: 8.5 * scale, color: const Color(0xFF00F5D4))),
                          ],
                        ),
                        SizedBox(height: 3 * scale),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (idx) {
                            final hasChar = idx < _enteredOtp.length;
                            final char = hasChar ? _enteredOtp[idx] : '';
                            return Container(
                              width: 17 * scale,
                              height: 22 * scale,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: hasChar ? const Color(0xFF00F5D4).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4 * scale),
                                border: Border.all(
                                  color: hasChar ? const Color(0xFF00F5D4) : (isOtpFocused && idx == _enteredOtp.length ? const Color(0xFF00F5D4).withValues(alpha: 0.6) : Colors.white12),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                char.isNotEmpty ? char : '-',
                                style: GoogleFonts.sourceCodePro(
                                  color: hasChar ? const Color(0xFF00F5D4) : Colors.white24,
                                  fontSize: 12 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 6 * scale),

              // 2자리 교사 ID 빈칸
              Expanded(
                flex: 4,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _activeKeypadTarget = 'teacherId';
                      _otpErrorMsg = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(10 * scale),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 5 * scale),
                    decoration: BoxDecoration(
                      color: isTeacherIdFocused
                          ? const Color(0xFF00F5D4).withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10 * scale),
                      border: Border.all(
                        color: isTeacherIdFocused ? const Color(0xFF00F5D4) : Colors.white24,
                        width: isTeacherIdFocused ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '교사 ID (2자리)',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 9.5 * scale,
                                fontWeight: FontWeight.bold,
                                color: isTeacherIdFocused ? const Color(0xFF00F5D4) : Colors.white60,
                              ),
                            ),
                            if (isTeacherIdFocused)
                              Text('선택', style: GoogleFonts.notoSansKr(fontSize: 8.5 * scale, color: const Color(0xFF00F5D4))),
                          ],
                        ),
                        SizedBox(height: 3 * scale),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(2, (idx) {
                            final hasChar = idx < _enteredTeacherId.length;
                            final char = hasChar ? _enteredTeacherId[idx] : '';
                            return Container(
                              width: 20 * scale,
                              height: 22 * scale,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: hasChar ? const Color(0xFF00F5D4).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4 * scale),
                                border: Border.all(
                                  color: hasChar ? const Color(0xFF00F5D4) : (isTeacherIdFocused && idx == _enteredTeacherId.length ? const Color(0xFF00F5D4).withValues(alpha: 0.6) : Colors.white12),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                char.isNotEmpty ? char : '-',
                                style: GoogleFonts.sourceCodePro(
                                  color: hasChar ? const Color(0xFF00F5D4) : Colors.white24,
                                  fontSize: 12 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_otpErrorMsg != null) ...[
            SizedBox(height: 4 * scale),
            Text(
              _otpErrorMsg!,
              style: GoogleFonts.notoSansKr(color: Colors.redAccent, fontSize: 9.5 * scale, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: 5 * scale),

          // 3. 터치 숫자 키패드 (하단 상시 배치)
          Expanded(
            flex: 7,
            child: _isVerifyingOtp
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
                : Column(
                    children: [
                      Expanded(child: _buildKeypadRow(['1', '2', '3'], scale)),
                      SizedBox(height: 2.5 * scale),
                      Expanded(child: _buildKeypadRow(['4', '5', '6'], scale)),
                      SizedBox(height: 2.5 * scale),
                      Expanded(child: _buildKeypadRow(['7', '8', '9'], scale)),
                      SizedBox(height: 2.5 * scale),
                      Expanded(child: _buildKeypadRow(['CLEAR', '0', 'BACK'], scale)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadRow(List<String> keys, double scale) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: keys.map((key) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2.5 * scale),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _handleKeypadInput(key),
                borderRadius: BorderRadius.circular(8 * scale),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (key == 'CLEAR' || key == 'BACK')
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFF00F5D4).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8 * scale),
                    border: Border.all(
                      color: (key == 'CLEAR' || key == 'BACK')
                          ? Colors.white12
                          : const Color(0xFF00F5D4).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: key == 'BACK'
                      ? Icon(Icons.backspace_rounded, size: 14 * scale, color: Colors.white70)
                      : Text(
                          key == 'CLEAR' ? 'C' : key,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 14 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _handleKeypadInput(String key) {
    setState(() {
      _otpErrorMsg = null;
      if (key == 'CLEAR') {
        if (_activeKeypadTarget == 'otp') {
          _enteredOtp = '';
        } else {
          _enteredTeacherId = '';
        }
      } else if (key == 'BACK') {
        if (_activeKeypadTarget == 'otp') {
          if (_enteredOtp.isNotEmpty) {
            _enteredOtp = _enteredOtp.substring(0, _enteredOtp.length - 1);
          }
        } else {
          if (_enteredTeacherId.isNotEmpty) {
            _enteredTeacherId = _enteredTeacherId.substring(0, _enteredTeacherId.length - 1);
          }
        }
      } else {
        if (_activeKeypadTarget == 'otp') {
          if (_enteredOtp.length < 6) {
            _enteredOtp += key;
            if (_enteredOtp.length == 6) {
              _submitCloudOtp(_enteredOtp);
            }
          }
        } else {
          if (_enteredTeacherId.length < 2) {
            _enteredTeacherId += key;
            if (_enteredTeacherId.length == 2) {
              _submitTeacherIdAutoLogin(_enteredTeacherId);
            }
          }
        }
      }
    });
  }

  Future<void> _submitTeacherIdAutoLogin(String teacherId) async {
    setState(() {
      _isVerifyingOtp = true;
      _otpErrorMsg = null;
    });
    try {
      final roomCode = '${_settings.selectedGrade}-${_settings.selectedClass}';
      final res = await BstCloudService.instance.verify2DigitAutoLogin(
        teacherId,
        roomCode,
      );
      if (res.success) {
        if (mounted) {
          setState(() {
            _enteredOtp = '';
            _enteredTeacherId = '';
            _isVerifyingOtp = false;
            _otpErrorMsg = null;
            _refreshCloudFiles();
            _startCloudSessionTimer();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('☁️ [${res.teacherName ?? "선생님"}] 교사 ID로 자동 로그인되었습니다!', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF2CB67D),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _isVerifyingOtp = false;
            _otpErrorMsg = res.errorMessage ?? '미등록 교사 ID이거나 전자칠판 인증 필요';
            _activeKeypadTarget = 'otp';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
          _otpErrorMsg = '자동 로그인 실패: $e';
          _activeKeypadTarget = 'otp';
        });
      }
    }
  }

  Future<void> _submitCloudOtp(String otp) async {
    setState(() {
      _isVerifyingOtp = true;
      _otpErrorMsg = null;
    });
    try {
      final res = await BstCloudService.instance.verify6DigitSteganoOtp(
        otp,
        teacherId2: _enteredTeacherId.isNotEmpty ? _enteredTeacherId : null,
      );
      if (res.success) {
        if (mounted) {
          setState(() {
            _enteredOtp = '';
            _enteredTeacherId = '';
            _isVerifyingOtp = false;
            _otpErrorMsg = null;
            _refreshCloudFiles();
            _startCloudSessionTimer();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('☁️ [${res.teacherName ?? "선생님"}] Cloud 연결이 완료되었습니다!', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF2CB67D),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _isVerifyingOtp = false;
            _otpErrorMsg = res.errorMessage ?? 'OTP 또는 교사 ID 불일치';
            _enteredOtp = '';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
          _otpErrorMsg = '인증 실패: $e';
          _enteredOtp = '';
        });
      }
    }
  }

  // --- [신규] 지금 수업 찌부 카드 (광고판과 동일한 폭, 상단 교과서 + 하단 과목명 크게) ---
  Widget _buildCompactCurrentLessonCard(Lesson? lesson, double scale) {
    final subject = lesson?.subject ?? '지금 수업';
    final teacher = lesson?.teacher ?? '';
    final classroom = lesson?.classroom ?? '';
    final periodStr = lesson != null ? '${lesson.classTime}교시' : '수업 중';
    final imgPath = lesson != null ? _settings.getTextbookPath(lesson.subject) : null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF00F5D4).withOpacity(0.3),
          width: 1.5,
        ),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0E2721),
            const Color(0xFF071411),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.all(12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 상단 바: 교시 배지 + Cloud 해제 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.5)),
                ),
                child: Text(
                  periodStr,
                  style: GoogleFonts.notoSansKr(
                    color: const Color(0xFF00F5D4),
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: Colors.white54, size: 16 * scale),
                tooltip: 'Cloud 패널 닫기 (로그인 유지)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _hideCloudPanel = true;
                  });
                },
              ),
            ],
          ),
          SizedBox(height: 6 * scale),

          // 상단: 교과서 표지 썸네일 (소형으로 상단 배치)
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8 * scale),
              child: Container(
                color: Colors.black38,
                alignment: Alignment.center,
                child: _buildAdaptiveTextbookImage(
                  imgPath,
                  fit: BoxFit.contain,
                  subjectTitle: subject,
                ),
              ),
            ),
          ),
          SizedBox(height: 6 * scale),

          // 하단: 대형 과목명 + 교사/교실 정보 (과목명을 크게 강조)
          Expanded(
            flex: 7,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    subject,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 42 * scale,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 10),
                      ],
                    ),
                  ),
                ),
                if (classroom.isNotEmpty || teacher.isNotEmpty) ...[
                  SizedBox(height: 6 * scale),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 3 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6 * scale),
                      border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.25)),
                    ),
                    child: Text(
                      [if (teacher.isNotEmpty) teacher, if (classroom.isNotEmpty) classroom].join(' · '),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13 * scale,
                        color: const Color(0xFF00F5D4),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- [신규] 좌측 광활한 전면 Cloud 패널 (OTP 인증 완료 시 전개) ---
  Widget _buildFullCloudPanel(double scale) {
    return _buildInlineCloudDockPanel(scale);
  }

  // --- [신규] 좌측 광활한 전면 USB 패널 (USB 연결 시 전개 - Cloud처럼 크게 표시) ---
  Widget _buildFullUsbPanel(double scale) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF2CB67D).withOpacity(0.4),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF2CB67D).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8 * scale),
                ),
                child: Icon(Icons.usb_rounded, color: const Color(0xFF2CB67D), size: 18 * scale),
              ),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'USB 드라이브 ($_usbDriveLetter)',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '수업 자료 즉시 열기 및 판서 지원',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white54,
                        fontSize: 10.5 * scale,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                onPressed: _checkUsbConnection,
                tooltip: '새로고침',
              ),
              IconButton(
                icon: const Icon(Icons.eject_rounded, color: Colors.orangeAccent),
                onPressed: _ejectUsbDrive,
                tooltip: 'USB 안전하게 분리',
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          Expanded(
            child: UsbExplorer(
              drivePath: _usbDriveLetter,
              scaleFactor: scale,
              isEjected: _isUsbEjected,
              onFileOpen: (filePath) async {
                int startPage = 0;
                if (_usbSessionId.isNotEmpty) {
                  final state = await UsbSessionService.instance
                      .getFileState(_usbSessionId, filePath);
                  startPage = state?.lastPage ?? 0;
                }
                _openUsbFileWithSession(
                  _usbSessionId,
                  filePath,
                  startPage,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- [신규] 좁은 폭의 컴팩트 USB 파일 탐색기 (USB 차등 대우) ---
  Widget _buildCompactUsbExplorer(double scale) {
    if (_isUsbEjected) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF081714),
          borderRadius: BorderRadius.circular(24 * scale),
          border: Border.all(
            color: const Color(0xFF2EC4B6).withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(16 * scale),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.eject_rounded, size: 36 * scale, color: const Color(0xFF2EC4B6)),
              SizedBox(height: 10 * scale),
              Text(
                'USB를 제거하시기 바랍니다',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14 * scale,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF2CB67D).withOpacity(0.4),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.usb_rounded, color: const Color(0xFF2CB67D), size: 18 * scale),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Text(
                  'USB 드라이브 ($_usbDriveLetter)',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          Expanded(
            child: _usbSortedFiles.isEmpty
                ? Center(
                    child: Text('수업 파일이 없습니다', style: TextStyle(color: Colors.white38, fontSize: 12 * scale)),
                  )
                : ListView.separated(
                    itemCount: _usbSortedFiles.length,
                    separatorBuilder: (_, __) => SizedBox(height: 6 * scale),
                    itemBuilder: (ctx, idx) {
                      final path = _usbSortedFiles[idx];
                      final name = p.basename(path);
                      return InkWell(
                        onTap: () => _openUsbFileWithSession(_usbSessionId, path, 0),
                        borderRadius: BorderRadius.circular(8 * scale),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 7 * scale),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8 * scale),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.insert_drive_file_rounded, color: const Color(0xFF2CB67D), size: 16 * scale),
                              SizedBox(width: 8 * scale),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(color: Colors.white, fontSize: 11.5 * scale),
                                  overflow: TextOverflow.ellipsis,
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
    );
  }


    // --- 5. Top Right 3x2 Tools Grid (6개 도구 2열 x 3행) ---
  Widget _buildTopPpt3x2Tools() {
    final scale = _settings.scaleFactor;

    final col1 = [
      {'name': '앱서랍', 'icon': Icons.apps, 'action': _openAppDrawer},
      {'name': '타이머', 'icon': Icons.timer, 'action': _openTimer},
      {'name': '달력/행사', 'icon': Icons.event, 'action': _openSchoolCalendarDialog},
    ];

    final col2 = [
            {'name': '제비뽑기', 'icon': Icons.casino, 'action': _openRandomPicker},
      {'name': '판서하기', 'icon': Icons.edit, 'action': _openUnifiedPenDialog},
    ];

    Widget buildM3ToolButton(String label, IconData icon, VoidCallback onTap) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14 * scale),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F2622),
              borderRadius: BorderRadius.circular(14 * scale),
              border: Border.all(
                color: const Color(0xFF2EC4B6).withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 3 * scale,
                  offset: Offset(0, 1.5 * scale),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: const Color(0xFF00F5D4), size: 22 * scale),
                SizedBox(height: 4 * scale),
                Text(
                  label,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 12.5 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      padding: EdgeInsets.all(8 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(3, (i) {
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(bottom: i == 2 ? 0 : 6 * scale),
                    child: buildM3ToolButton(
                      col1[i]['name'] as String,
                      col1[i]['icon'] as IconData,
                      col1[i]['action'] as VoidCallback,
                    ),
                  ),
                );
              }),
            ),
          ),
          SizedBox(width: 6 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(3, (i) {
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(bottom: i == 2 ? 0 : 6 * scale),
                    child: buildM3ToolButton(
                      col2[i]['name'] as String,
                      col2[i]['icon'] as IconData,
                      col2[i]['action'] as VoidCallback,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCloudPairingModal() async {
    if (BstCloudService.instance.activeToken != null) {
      setState(() {
        _hideCloudPanel = !_hideCloudPanel;
      });
      return;
    }

    await BstCloudAuthModal.show(
      context,
      scale: _settings.scaleFactor,
      schoolName: _settings.selectedSchool?.name ?? (_settings.schoolId.isNotEmpty ? _settings.schoolId : '보데스트 중학교'),
      gradeClass: _settings.specialClassroomMode
          ? (_settings.selectedSubject.isNotEmpty ? '${_settings.selectedSubject} 전용교실' : '전용교실')
          : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반',
      onUnlocked: () {
        if (mounted) {
          setState(() {
            _hideCloudPanel = false;
            _cloudCategoryFilter = 'lesson';
          });
          _refreshCloudFiles();
        }
      },
    );
  }

  // --- 6. Bottom Right 4-Tool Grid (1열 4행: 플러그인(비활성화), 클라우드, 계산기, 설정) ---
  Widget _buildBottomPpt4Tools() {
    final scale = _settings.scaleFactor;
    final isCloudOn = BstCloudService.instance.activeToken != null;

    final tools = [
      {'name': '플러그인', 'icon': Icons.extension_rounded, 'action': null, 'disabled': true},
      {'name': '클라우드', 'icon': isCloudOn ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded, 'action': _openCloudPairingModal, 'disabled': false},
      {'name': '계산기', 'icon': Icons.calculate, 'action': _openCalculator, 'disabled': false},
      {'name': '설정', 'icon': Icons.settings, 'action': _openSettingsWizard, 'disabled': false},
    ];

    Widget buildM3BottomButton(String label, IconData icon, VoidCallback? onTap, bool disabled) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          onLongPress: (label == '설정') ? _onSettingsLongPress : null,
          borderRadius: BorderRadius.circular(12 * scale),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10 * scale),
            decoration: BoxDecoration(
              color: disabled ? const Color(0xFF1E232A) : const Color(0xFF0F2622),
              borderRadius: BorderRadius.circular(12 * scale),
              border: Border.all(
                color: disabled
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFF2EC4B6).withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: disabled
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 3 * scale,
                        offset: Offset(0, 1.5 * scale),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: disabled ? Colors.white30 : const Color(0xFF00F5D4),
                  size: 20 * scale,
                ),
                SizedBox(width: 8 * scale),
                Text(
                  label,
                  style: GoogleFonts.notoSansKr(
                    color: disabled ? Colors.white30 : Colors.white,
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      padding: EdgeInsets.all(8 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(tools.length, (i) {
          final item = tools[i];
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: i == tools.length - 1 ? 0 : 6 * scale),
              child: buildM3BottomButton(
                item['name'] as String,
                item['icon'] as IconData,
                item['action'] as VoidCallback?,
                item['disabled'] as bool,
              ),
            ),
          );
        }),
      ),
    );
  }

  void _openMealCallDialog() {
    final scale = _settings.scaleFactor;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20 * scale),
          side: const BorderSide(color: Color(0xFF242629)),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10 * scale),
              ),
              child: Icon(Icons.restaurant_rounded, color: const Color(0xFF00F5D4), size: 24 * scale),
            ),
            SizedBox(width: 12 * scale),
            Text(
              '오늘의 급식 식단',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18 * scale,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380 * scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14 * scale),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12 * scale),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  _mealInfo.isNotEmpty ? _mealInfo : '오늘 등록된 급식 정보가 없습니다.',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 14 * scale,
                    height: 1.6,
                  ),
                ),
              ),
              SizedBox(height: 12 * scale),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '현재 배정: ${_settings.cafeteriaNum.isNotEmpty ? _settings.cafeteriaNum : "급식실1"}',
                    style: GoogleFonts.notoSansKr(
                      color: const Color(0xFF00F5D4),
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showCafeteriaSelectorDialog();
                    },
                    icon: Icon(Icons.tune_rounded, size: 14 * scale, color: Colors.white70),
                    label: Text('급식실 변경', style: GoogleFonts.notoSansKr(fontSize: 12 * scale, color: Colors.white70)),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('닫기', style: GoogleFonts.notoSansKr(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showCafeteriaSelectorDialog() {
    final scale = _settings.scaleFactor;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0D141C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20 * scale),
            side: BorderSide(
              color: const Color(0xFF00F5D4).withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          title: Text(
            '급식실 선택',
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22 * scale,
            ),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: 360 * scale,
            child: Wrap(
              spacing: 12 * scale,
              runSpacing: 12 * scale,
              alignment: WrapAlignment.center,
              children: List.generate(9, (i) {
                final num = i + 1;
                final cafeName = '급식실$num';
                final isSelected = _settings.cafeteriaNum == cafeName || _settings.cafeteriaNum == '$num';
                return InkWell(
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final updated = _settings.copyWith(cafeteriaNum: cafeName);
                    setState(() {
                      _settings = updated;
                    });
                    await _storageService.saveSettings(updated);
                    await MealCallService.instance.ensurePresence(updated);
                    _startMealCallListener(updated);
                  },
                  borderRadius: BorderRadius.circular(12 * scale),
                  child: Container(
                    width: 100 * scale,
                    padding: EdgeInsets.symmetric(vertical: 14 * scale),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00F5D4).withValues(alpha: 0.2)
                          : const Color(0xFF13222E),
                      borderRadius: BorderRadius.circular(12 * scale),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF00F5D4)
                            : Colors.white.withValues(alpha: 0.12),
                        width: isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$num 급식실',
                        style: GoogleFonts.notoSansKr(
                          color: isSelected ? const Color(0xFF00F5D4) : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          fontSize: 17 * scale,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  void _toggleAspectRatio() async {
    final nextRatio = _settings.is4by3Ratio ? '16:9' : '4:3';
    final updated = _settings.copyWith(aspectRatio: nextRatio);
    setState(() {
      _settings = updated;
    });
    await _storageService.saveSettings(updated);
  }

  File? _resolveLocalTextbookFile(String? imgPath, {String? subjectTitle}) {
    if (kIsWeb) return null;
    final candidates = <String>[];
    if (imgPath != null && imgPath.isNotEmpty) {
      candidates.add(imgPath);
      final filename = p.basename(imgPath);
      candidates.add(p.join(AppPaths.dataRootSync, 'textbooks', filename));
    }
    if (subjectTitle != null && subjectTitle.isNotEmpty) {
      final stem = AppSettings.getSubjectStem(subjectTitle);
      final grade = _settings.selectedGrade;
      for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'bmp']) {
        candidates.add(p.join(AppPaths.dataRootSync, 'textbooks', '${grade}_$stem.$ext'));
        candidates.add(p.join(AppPaths.dataRootSync, 'textbooks', '$stem.$ext'));
      }
    }
    for (final c in candidates) {
      try {
        final f = File(c);
        if (f.existsSync()) return f;
      } catch (_) {}
    }
    return null;
  }

  Future<void> _loadSavedTextbooksToMemory() async {
    if (kIsWeb) return;
    try {
      final textbookDir = Directory(p.join(AppPaths.dataRootSync, 'textbooks'));
      if (await textbookDir.exists()) {
        final files = textbookDir.listSync().whereType<File>();
        final Map<String, String> updatedPaths = Map<String, String>.from(_settings.textbookImages);
        bool needsSave = false;

        for (final file in files) {
          final filename = p.basename(file.path);
          if (filename.startsWith('.') || filename.startsWith('__MACOSX')) continue;
          final dotIdx = filename.lastIndexOf('.');
          if (dotIdx == -1) continue;
          final rawStem = filename.substring(0, dotIdx);
          final ext = filename.substring(dotIdx + 1).toLowerCase();
          if (!['png', 'jpg', 'jpeg', 'webp', 'bmp'].contains(ext)) continue;

          final bytes = await file.readAsBytes();
          _inMemoryTextbookBytes[rawStem] = bytes;
          final stem = AppSettings.getSubjectStem(rawStem);
          _inMemoryTextbookBytes[stem] = bytes;
          _inMemoryTextbookBytes['${_settings.selectedGrade}_$stem'] = bytes;

          if (updatedPaths[stem] != file.path || updatedPaths['${_settings.selectedGrade}_$stem'] != file.path) {
            updatedPaths[stem] = file.path;
            updatedPaths['${_settings.selectedGrade}_$stem'] = file.path;
            needsSave = true;
          }
        }

        if (needsSave && mounted) {
          final updated = _settings.copyWith(textbookImages: updatedPaths);
          setState(() {
            _settings = updated;
          });
          await _storageService.saveSettings(updated);
          debugPrint('[TextbookPreloader] 📚 Successfully loaded ${files.length} local textbook covers into memory and settings.');
        }
      }
    } catch (e) {
      debugPrint('[TextbookPreloader] Error loading textbooks: $e');
    }
  }

  ImageProvider? _getAdaptiveImageProvider(String? imgPath, {String? subject}) {
    if (subject != null && subject.isNotEmpty) {
      final stem = AppSettings.getSubjectStem(subject);
      final gradeKey = '${_settings.selectedGrade}_$stem';
      if (_inMemoryTextbookBytes.containsKey(gradeKey)) {
        return MemoryImage(_inMemoryTextbookBytes[gradeKey]!);
      }
      if (_inMemoryTextbookBytes.containsKey(stem)) {
        return MemoryImage(_inMemoryTextbookBytes[stem]!);
      }
    }
    if (imgPath != null && imgPath.startsWith('data:image/')) {
      try {
        final commaIdx = imgPath.indexOf(',');
        if (commaIdx != -1) {
          final bytes = base64Decode(imgPath.substring(commaIdx + 1));
          return MemoryImage(bytes);
        }
      } catch (_) {}
    }
    if (imgPath != null && (kIsWeb || imgPath.startsWith('http://') || imgPath.startsWith('https://') || imgPath.startsWith('blob:'))) {
      return NetworkImage(imgPath);
    }
    final resolvedFile = _resolveLocalTextbookFile(imgPath, subjectTitle: subject);
    if (resolvedFile != null) {
      return FileImage(resolvedFile);
    }
    return null;
  }

  Uint8List? _getTextbookBytesForSubject(String subjectTitle) {
    if (subjectTitle.isEmpty) return null;
    final stem = AppSettings.getSubjectStem(subjectTitle);
    final gradeKey = '${_settings.selectedGrade}_$stem';
    if (_inMemoryTextbookBytes.containsKey(gradeKey)) {
      return _inMemoryTextbookBytes[gradeKey];
    }
    if (_inMemoryTextbookBytes.containsKey(stem)) {
      return _inMemoryTextbookBytes[stem];
    }
    for (final entry in _inMemoryTextbookBytes.entries) {
      final keyStem = AppSettings.getSubjectStem(entry.key);
      if (entry.key == subjectTitle || keyStem == stem || entry.key.contains(stem) || stem.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  String _getCorsSafeImageUrl(String rawUrl) {
    if (!kIsWeb) return rawUrl;
    if (rawUrl.isEmpty || rawUrl.startsWith('data:') || rawUrl.startsWith('blob:')) return rawUrl;
    return 'https://wsrv.nl/?url=${Uri.encodeComponent(rawUrl)}';
  }

  Widget _buildAdaptiveTextbookImage(
    String? imgPath, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    String? subjectTitle,
  }) {
    if (_inMemoryTextbookBytes != null && subjectTitle != null) {
      final stem = AppSettings.getSubjectStem(subjectTitle);
      for (final entry in _inMemoryTextbookBytes!.entries) {
        final keyStem = AppSettings.getSubjectStem(entry.key);
        if (entry.key == subjectTitle || keyStem == stem || entry.key.contains(stem) || stem.contains(entry.key)) {
          return Image.memory(
            entry.value,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => _buildFallbackBookCover(subjectTitle),
          );
        }
      }
    }

    if (imgPath != null && imgPath.startsWith('data:image/')) {
      try {
        final commaIdx = imgPath.indexOf(',');
        if (commaIdx != -1) {
          final bytes = base64Decode(imgPath.substring(commaIdx + 1));
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => _buildFallbackBookCover(subjectTitle ?? '교과서'),
          );
        }
      } catch (_) {}
    }
    if (imgPath != null && (kIsWeb || imgPath.startsWith('http://') || imgPath.startsWith('https://') || imgPath.startsWith('blob:'))) {
      final safeUrl = _getCorsSafeImageUrl(imgPath);
      return Image.network(
        safeUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Image.network(
          imgPath,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildFallbackBookCover(subjectTitle ?? '교과서'),
        ),
      );
    }

    final resolvedFile = _resolveLocalTextbookFile(imgPath, subjectTitle: subjectTitle);
    if (resolvedFile != null) {
      return Image.file(
        resolvedFile,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildFallbackBookCover(subjectTitle ?? '교과서'),
      );
    }

    return _buildFallbackBookCover(subjectTitle ?? '교과서');
  }

  Widget _buildFallbackBookCover(String title) {
    final cleanTitle = AppSettings.getSubjectStem(title);

    // Subject theme & icon lookup in Mint palette
    Color gradientStart = const Color(0xFF003830);
    Color gradientEnd = const Color(0xFF005B4E);
    IconData subjectIcon = Icons.menu_book_rounded;
    String subCategory = '일반 교과';

    if (cleanTitle.contains('국어') || cleanTitle.contains('문학') || cleanTitle.contains('독서')) {
      gradientStart = const Color(0xFF003B32);
      gradientEnd = const Color(0xFF005F50);
      subjectIcon = Icons.auto_stories_rounded;
      subCategory = '국어과 교육과정';
    } else if (cleanTitle.contains('영어') || cleanTitle.contains('영독')) {
      gradientStart = const Color(0xFF003F46);
      gradientEnd = const Color(0xFF006D78);
      subjectIcon = Icons.translate_rounded;
      subCategory = '외국어 교육과정';
    } else if (cleanTitle.contains('수학') || cleanTitle.contains('미적') || cleanTitle.contains('기하')) {
      gradientStart = const Color(0xFF00453D);
      gradientEnd = const Color(0xFF007567);
      subjectIcon = Icons.calculate_rounded;
      subCategory = '수학과 교육과정';
    } else if (cleanTitle.contains('과학') || cleanTitle.contains('물리') || cleanTitle.contains('화학') || cleanTitle.contains('생물') || cleanTitle.contains('지구')) {
      gradientStart = const Color(0xFF004952);
      gradientEnd = const Color(0xFF007D8C);
      subjectIcon = Icons.science_rounded;
      subCategory = '과학교과 교육과정';
    } else if (cleanTitle.contains('역사') || cleanTitle.contains('사회')) {
      gradientStart = const Color(0xFF004236);
      gradientEnd = const Color(0xFF006B57);
      subjectIcon = Icons.public_rounded;
      subCategory = '사회·역사 교육과정';
    } else if (cleanTitle.contains('도덕')) {
      gradientStart = const Color(0xFF004539);
      gradientEnd = const Color(0xFF00735F);
      subjectIcon = Icons.volunteer_activism_rounded;
      subCategory = '도덕과 교육과정';
    } else if (cleanTitle.contains('음악')) {
      gradientStart = const Color(0xFF1B3D36);
      gradientEnd = const Color(0xFF286156);
      subjectIcon = Icons.music_note_rounded;
      subCategory = '예체능 교육과정';
    } else if (cleanTitle.contains('미술')) {
      gradientStart = const Color(0xFF14423A);
      gradientEnd = const Color(0xFF216E60);
      subjectIcon = Icons.palette_rounded;
      subCategory = '예체능 교육과정';
    } else if (cleanTitle.contains('체육') || cleanTitle.contains('스포츠')) {
      gradientStart = const Color(0xFF004439);
      gradientEnd = const Color(0xFF00705E);
      subjectIcon = Icons.sports_soccer_rounded;
      subCategory = '체육과 교육과정';
    } else if (cleanTitle.contains('기술') || cleanTitle.contains('가정') || cleanTitle.contains('정보') || cleanTitle.contains('기가')) {
      gradientStart = const Color(0xFF003E48);
      gradientEnd = const Color(0xFF006E7F);
      subjectIcon = Icons.memory_rounded;
      subCategory = '기술·정보 교육과정';
    } else if (cleanTitle.contains('한문') || cleanTitle.contains('일본어') || cleanTitle.contains('중국어')) {
      gradientStart = const Color(0xFF1A3B33);
      gradientEnd = const Color(0xFF2E6356);
      subjectIcon = Icons.history_edu_rounded;
      subCategory = '제2외국어 교육과정';
    } else if (cleanTitle.contains('진로') || cleanTitle.contains('자율') || cleanTitle.contains('동아리') || cleanTitle.contains('창체')) {
      gradientStart = const Color(0xFF00423A);
      gradientEnd = const Color(0xFF006E61);
      subjectIcon = Icons.stars_rounded;
      subCategory = '창의적 체험활동';
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientStart, gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -15,
            bottom: -15,
            child: Icon(
              subjectIcon,
              size: 130,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.45),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    subCategory,
                    style: GoogleFonts.notoSansKr(
                      color: const Color(0xFF00F5D4),
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    subjectIcon,
                    color: const Color(0xFF00F5D4),
                    size: 24,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title.isNotEmpty ? title : '교과서',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'BOARD EST',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Right Panel Bottom Left: Now Playing Subject Card ---
  Widget _buildNowPlayingSubjectCard() {
    final isMorning = _currentPeriod?.period == -3;
    final isAssembly = _currentPeriod?.period == -1;
    final isDismissal = _currentPeriod?.period == -2;
    final isLunch = _currentPeriod?.label == '점심 시간';

    final String subjectName;
    final String teacherText;
    final String classroomText;
    final String badgeText;
    final bool isUpcoming;
    final String? imgPath;

    if (isMorning) {
      subjectName = '아침 시간';
      teacherText = '등교 및 1교시 수업 준비';
      classroomText = '';
      badgeText = '아침 시간';
      isUpcoming = false;
      imgPath = null;
    } else if (isAssembly) {
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
    } else if (isLunch) {
      subjectName = '점심시간';
      teacherText = '맛있게 식사하고 푹 쉬세요!';
      classroomText = '';
      badgeText = '점심 시간';
      isUpcoming = false;
      imgPath = null;
    } else {
      final hasCurrent =
          _currentLesson != null && _currentLesson!.subject.isNotEmpty;
      final displayLesson = hasCurrent ? _currentLesson : _nextLesson;
      isUpcoming = !hasCurrent;

      final hasActiveSubject =
          displayLesson != null && displayLesson.subject.isNotEmpty;

      // 특별실 모드: 대형 텍스트에 방문 'X학년 Y반' 표시, 하단에 '과목명 수업' 표시
      if (_settings.specialClassroomMode && hasActiveSubject) {
        subjectName = '${displayLesson!.grade}학년 ${displayLesson.classNum}반';
        teacherText = isUpcoming
            ? '다음: ${displayLesson.subject} 수업'
            : '${displayLesson.subject} 수업 진행 중';
      } else {
        subjectName = hasActiveSubject ? displayLesson!.subject : '일과 종료';

        if (hasActiveSubject) {
          teacherText = displayLesson!.classroom.isNotEmpty
              ? displayLesson.classroom
              : '교실 정보 없음';
        } else {
          teacherText = '오늘의 모든 수업이 끝났습니다';
        }
      }
      classroomText = hasActiveSubject ? displayLesson!.classroom : '';

      imgPath = (displayLesson != null && hasActiveSubject)
          ? _settings.getTextbookPath(displayLesson.subject)
          : null;
      badgeText = isUpcoming ? '다음 수업' : '지금 수업';
    }

    final hasImage = imgPath != null && File(imgPath).existsSync();
    final scale = _settings.scaleFactor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Darkened textbook background blur
            if (hasImage)
              Positioned.fill(
                child: _buildAdaptiveTextbookImage(imgPath, fit: BoxFit.cover, subjectTitle: subjectName),
              ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: hasImage ? 14 : 0,
                  sigmaY: hasImage ? 14 : 0,
                ),
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
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16 * scale,
                              offset: Offset(0, 8 * scale),
                            ),
                            if (hasImage)
                              BoxShadow(
                                color: const Color(
                                  0xFF00F5D4,
                                ).withValues(alpha: 0.15),
                                blurRadius: 20 * scale,
                                spreadRadius: 2 * scale,
                              ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _buildAdaptiveTextbookImage(imgPath, fit: BoxFit.cover, subjectTitle: subjectName),
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
                          padding: EdgeInsets.symmetric(
                            horizontal: 12 * scale,
                            vertical: 6 * scale,
                          ),
                          decoration: BoxDecoration(
                            color: isUpcoming
                                ? Colors.white.withValues(alpha: 0.12)
                                : const Color(
                                    0xFF2EC4B6,
                                  ).withValues(alpha: 0.2),
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
                                        letterSpacing:
                                            isUpcoming && !_isUsbConnected
                                            ? 0.5
                                            : 0,
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
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12 * scale,
                                          vertical: 5 * scale,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF2CB67D,
                                          ).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          classroomText,
                                          style: GoogleFonts.notoSansKr(
                                            color: const Color(0xFF2CB67D),
                                            fontSize:
                                                (!_isUsbConnected ? 28 : 20) *
                                                scale,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
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
    if (kIsWeb || !Platform.isWindows) return const SizedBox.shrink();
    final scale = _settings.scaleFactor;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16.0 * scale,
              vertical: 12.0 * scale,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 헤더 영역 (USB 아이콘, 타이틀, 자동 열기 체크박스)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.usb_rounded,
                          color: const Color(0xFF00F5D4),
                          size: 20 * scale,
                        ),
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
                            activeTrackColor: const Color(
                              0xFF00F5D4,
                            ).withValues(alpha: 0.3),
                            inactiveThumbColor: Colors.white30,
                            inactiveTrackColor: Colors.white10,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) async {
                              setState(() {
                                _usbAutoOpenEnabled = val;
                              });
                              if (_usbSessionId.isNotEmpty) {
                                await UsbSessionService.instance.setAutoOpen(
                                  _usbSessionId,
                                  val,
                                );
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
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
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
                                color: !_showFullUsbExplorer
                                    ? const Color(0xFF00F5D4)
                                    : Colors.white60,
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
                                color: _showFullUsbExplorer
                                    ? const Color(0xFF00F5D4)
                                    : Colors.white60,
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
                          isEjected: _isUsbEjected,
                          onFileOpen: (filePath) async {
                            int startPage = 0;
                            if (_usbSessionId.isNotEmpty) {
                              final state = await UsbSessionService.instance
                                  .getFileState(_usbSessionId, filePath);
                              startPage = state?.lastPage ?? 0;
                            }
                            _openUsbFileWithSession(
                              _usbSessionId,
                              filePath,
                              startPage,
                            );
                          },
                        )
                      : (_usbSortedFiles.isEmpty
                            ? Center(
                                child: Text(
                                  '수업 자료가 존재하지 않습니다.',
                                  style: GoogleFonts.notoSansKr(
                                    color: Colors.white38,
                                    fontSize: 12 * scale,
                                  ),
                                ),
                              )
                            : FutureBuilder<String?>(
                                future: _usbSessionId.isNotEmpty
                                    ? UsbSessionService.instance
                                          .getLastOpenedFile(_usbSessionId)
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
                                        final ext = p
                                            .extension(filePath)
                                            .toLowerCase();
                                        final isLastOpened =
                                            lastOpened == filePath;

                                        // 아이콘 & 색상 매핑
                                        IconData iconData =
                                            Icons.insert_drive_file_rounded;
                                        Color iconColor = Colors.white54;
                                        if (ext == '.pptx' || ext == '.ppt') {
                                          iconData = Icons.slideshow_rounded;
                                          iconColor = const Color(0xFFFF8E3C);
                                        } else if (ext == '.pdf') {
                                          iconData =
                                              Icons.picture_as_pdf_rounded;
                                          iconColor = const Color(0xFFEF4565);
                                        } else if (ext == '.bb') {
                                          iconData = Icons.auto_stories_rounded;
                                          iconColor = const Color(0xFF7F5AF0);
                                        } else if ([
                                          '.mp4',
                                          '.mkv',
                                          '.avi',
                                          '.mov',
                                          '.wmv',
                                        ].contains(ext)) {
                                          iconData =
                                              Icons.play_circle_fill_rounded;
                                          iconColor = const Color(0xFF2CB67D);
                                        }

                                        return Padding(
                                          padding: EdgeInsets.only(
                                            bottom: 6.0 * scale,
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              onTap: () async {
                                                int startPage = 0;
                                                if (_usbSessionId.isNotEmpty) {
                                                  final state =
                                                      await UsbSessionService
                                                          .instance
                                                          .getFileState(
                                                            _usbSessionId,
                                                            filePath,
                                                          );
                                                  startPage =
                                                      state?.lastPage ?? 0;
                                                }
                                                _openUsbFileWithSession(
                                                  _usbSessionId,
                                                  filePath,
                                                  startPage,
                                                );
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 10 * scale,
                                                  vertical: 8 * scale,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isLastOpened
                                                      ? const Color(
                                                          0xFF00F5D4,
                                                        ).withValues(alpha: 0.1)
                                                      : Colors.white.withValues(
                                                          alpha: 0.015,
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: isLastOpened
                                                        ? const Color(
                                                            0xFF00F5D4,
                                                          ).withValues(
                                                            alpha: 0.3,
                                                          )
                                                        : Colors.white
                                                              .withValues(
                                                                alpha: 0.04,
                                                              ),
                                                    width: isLastOpened
                                                        ? 1.2
                                                        : 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      iconData,
                                                      color: iconColor,
                                                      size: 18 * scale,
                                                    ),
                                                    SizedBox(width: 8 * scale),
                                                    Expanded(
                                                      child: Text(
                                                        fileName,
                                                        style: GoogleFonts.notoSansKr(
                                                          color: isLastOpened
                                                              ? const Color(
                                                                  0xFF00F5D4,
                                                                )
                                                              : Colors.white
                                                                    .withValues(
                                                                      alpha:
                                                                          0.85,
                                                                    ),
                                                          fontSize: 11 * scale,
                                                          fontWeight:
                                                              isLastOpened
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (isLastOpened) ...[
                                                      SizedBox(
                                                        width: 6 * scale,
                                                      ),
                                                      Container(
                                                        width: 5 * scale,
                                                        height: 5 * scale,
                                                        decoration:
                                                            const BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              color: Color(
                                                                0xFF00F5D4,
                                                              ),
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

  /// 기기가 꺼져있을 때 수신된 부재 중 FCM 알림 확인 및 표시
  Future<void> _checkUnreadFcmNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unreadList = prefs.getStringList('unread_fcm_notifications') ?? [];
      if (unreadList.isEmpty || !mounted) return;

      // 확인 후 SharedPreferences에서 삭제
      await prefs.remove('unread_fcm_notifications');

      final items = <Map<String, dynamic>>[];
      for (final raw in unreadList) {
        try {
          final item = json.decode(raw) as Map<String, dynamic>;
          items.add(item);
        } catch (_) {}
      }
      if (items.isEmpty || !mounted) return;

      showDialog(
        context: context,
        builder: (ctx) {
          final s = _settings.scaleFactor;
          return AlertDialog(
            backgroundColor: const Color(0xFF13171F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20 * s),
              side: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.5)),
            ),
            title: Row(
              children: [
                Icon(Icons.history_rounded, color: const Color(0xFF00F5D4), size: 22 * s),
                SizedBox(width: 8 * s),
                Text(
                  '부재 중 수신된 알림 (${items.length}건)',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16 * s,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380 * s,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(color: Colors.white12, height: 12 * s),
                itemBuilder: (c, idx) {
                  final it = items[idx];
                  final data = it['data'] as Map<String, dynamic>? ?? {};
                  final sentAtStr = it['sentAt']?.toString() ?? '';
                  String timeLabel = '시간 정보 없음';
                  if (sentAtStr.isNotEmpty) {
                    final dt = DateTime.tryParse(sentAtStr);
                    if (dt != null) {
                      final local = dt.toLocal();
                      timeLabel = '${local.month}월 ${local.day}일 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
                    } else {
                      timeLabel = sentAtStr;
                    }
                  }

                  final msg = data['message'] ?? data['callMessage'] ?? (data.containsKey('called') ? '급식 호출이 도착했었습니다.' : '새 알림');
                  final from = data['messageFrom'] ?? data['callerName'] ?? '교무실/급식실';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4 * s),
                            ),
                            child: Text(
                              from.toString(),
                              style: GoogleFonts.notoSansKr(color: const Color(0xFF818CF8), fontSize: 10.5 * s, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            timeLabel,
                            style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 10 * s),
                          ),
                        ],
                      ),
                      SizedBox(height: 4 * s),
                      Text(
                        msg.toString(),
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * s),
                      ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
                ),
                child: Text('확인 완료', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    } catch (e) {
      debugPrint('[_checkUnreadFcmNotifications] error: $e');
    }
  }

  Widget _buildInlineCloudDockPanel(double scale) {
    final teacherName = BstCloudService.instance.activeTeacherName ?? '교사';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1B4B).withOpacity(0.95),
            const Color(0xFF0F172A).withOpacity(0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.2),
            blurRadius: 16,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 헤더: 교사 정보 + 신뢰기기 등록 + 새로고침 + 로그아웃
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(5 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8 * scale),
                ),
                child: Icon(Icons.cloud_done_rounded, color: const Color(0xFF818CF8), size: 16 * scale),
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$teacherName 클라우드',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '급식 전환 시 3분 뒤 자동 로그아웃 (세션 1시간 유지)',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white54,
                        fontSize: 9.5 * scale,
                      ),
                    ),
                  ],
                ),
              ),
              // 등록 교사 저장 버튼
              InkWell(
                onTap: () async {
                  final email = BstCloudService.instance.activeOwnerEmail ?? '';
                  final token = BstCloudService.instance.activeToken;
                  final refresh = BstCloudService.instance.activeRefreshToken;
                  await PasskeyService.instance.saveProTeacher(
                    teacherName: teacherName,
                    email: email,
                    schoolName: _settings.selectedSchool?.name ?? '',
                    accessToken: token,
                    refreshToken: refresh,
                  );
                  await BstCloudService.instance.registerActiveTeacherAsTrusted();
                  if (mounted) {
                    setState(() => _isTrustDeviceSaved = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('🎉 $teacherName 선생님이 등록 교사로 저장되었습니다!'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: const Color(0xFF00F5D4),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(6 * scale),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3.5 * scale),
                  decoration: BoxDecoration(
                    color: _isTrustDeviceSaved
                        ? const Color(0xFF00F5D4).withOpacity(0.2)
                        : const Color(0xFF6366F1).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6 * scale),
                    border: Border.all(
                      color: _isTrustDeviceSaved ? const Color(0xFF00F5D4) : const Color(0xFF818CF8),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isTrustDeviceSaved ? Icons.check_circle_rounded : Icons.bookmark_add_rounded,
                        size: 11 * scale,
                        color: _isTrustDeviceSaved ? const Color(0xFF00F5D4) : const Color(0xFF818CF8),
                      ),
                      SizedBox(width: 3 * scale),
                      Text(
                        _isTrustDeviceSaved ? '등록 교사' : '교사 등록',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 9.5 * scale,
                          fontWeight: FontWeight.bold,
                          color: _isTrustDeviceSaved ? const Color(0xFF00F5D4) : const Color(0xFF818CF8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 5 * scale),

              // 교사 전환 버튼
              InkWell(
                onTap: _openSavedTeachersSwitchDialog,
                borderRadius: BorderRadius.circular(6 * scale),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3.5 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6 * scale),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.switch_account_rounded, size: 11 * scale, color: Colors.white70),
                      SizedBox(width: 3 * scale),
                      Text(
                        '교사 전환',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 9.5 * scale,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 5 * scale),

              // 급식 전환 버튼 (Cloud ↔ 급식 토글)
              InkWell(
                onTap: () {
                  setState(() {
                    _hideCloudPanel = true;
                  });
                  _scheduleCloudEscapeAutoLogout();
                },
                borderRadius: BorderRadius.circular(6 * scale),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3.5 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6 * scale),
                    border: Border.all(
                      color: const Color(0xFF10B981),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.restaurant_rounded, size: 11 * scale, color: const Color(0xFF10B981)),
                      SizedBox(width: 3 * scale),
                      Text(
                        '급식',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 9.5 * scale,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 4 * scale),

              IconButton(
                icon: Icon(Icons.refresh_rounded, color: Colors.white70, size: 15 * scale),
                tooltip: '새로고침',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _refreshCloudFiles();
                  });
                },
              ),
              SizedBox(width: 4 * scale),
              IconButton(
                icon: Icon(Icons.close_rounded, color: Colors.white70, size: 15 * scale),
                tooltip: 'Cloud 패널 닫기 (급식 전환, 3분 뒤 자동 로그아웃)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _hideCloudPanel = true;
                  });
                  _scheduleCloudEscapeAutoLogout();
                },
              ),
              SizedBox(width: 4 * scale),
              IconButton(
                icon: Icon(Icons.logout_rounded, color: Colors.redAccent, size: 15 * scale),
                tooltip: '로그아웃',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    BstCloudService.instance.activeToken = null;
                    _cloudFilesFuture = null;
                  });
                },
              ),
            ],
          ),
          SizedBox(height: 7 * scale),

          // 2. Cloud 상단 카테고리 필터 스위처: [전체] | [📁 수업 자료] | [📐 TBP & Canva] | [✏️ 판서]
          Container(
            padding: EdgeInsets.all(2.5 * scale),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8 * scale),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                _buildCloudFilterPill('all', '전체', scale),
                _buildCloudFilterPill('lesson', '📁 수업 자료', scale),
                _buildCloudFilterPill('tbp_canva', '📐 TBP & Canva', scale),
                _buildCloudFilterPill('pen', '✏️ 판서', scale),
              ],
            ),
          ),
          SizedBox(height: 7 * scale),

          // 파일 목록
          Expanded(
            child: FutureBuilder<List<BstCloudFile>>(
              future: _cloudFilesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F5D4)));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 24 * scale, color: Colors.white38),
                        SizedBox(height: 4 * scale),
                        Text(
                          '자료를 불러오지 못했습니다',
                          style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 11 * scale),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _refreshCloudFiles();
                            });
                          },
                          child: Text('다시 시도', style: GoogleFonts.notoSansKr(fontSize: 11 * scale, color: const Color(0xFF818CF8))),
                        ),
                      ],
                    ),
                  );
                }

                final allFiles = snapshot.data ?? [];
                final filteredFiles = _filterCloudFiles(allFiles);

                if (filteredFiles.isEmpty) {
                  String emptyMsg = '표시할 클라우드 파일이 없습니다.';
                  if (_cloudCategoryFilter == 'lesson') emptyMsg = '수업 자료(PDF, PPT, HWP 등)가 없습니다.';
                  if (_cloudCategoryFilter == 'tbp_canva') emptyMsg = '등록된 TBP 교과서 및 Canva 디자인이 없습니다.';
                  if (_cloudCategoryFilter == 'pen') emptyMsg = '저장된 판서 기록(.pen, .bstpen)이 없습니다.';

                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(12 * scale),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open_rounded, size: 28 * scale, color: Colors.white30),
                          SizedBox(height: 6 * scale),
                          Text(
                            emptyMsg,
                            style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 11 * scale),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filteredFiles.length,
                  separatorBuilder: (_, __) => SizedBox(height: 5 * scale),
                  itemBuilder: (ctx, idx) {
                    final f = filteredFiles[idx];
                    final name = f.name.toLowerCase();
                    final isCanva = name.endsWith('.htmlp') ||
                        name.endsWith('.canva') ||
                        name.endsWith('.canva.bst') ||
                        name.endsWith('.bstcanva') ||
                        name.contains('canva') ||
                        name.contains('htmlp');
                    final isTbp = name.endsWith('.bsttbp') ||
                        name.endsWith('.tbp') ||
                        f.mimeType == 'application/x-bst-tbp-folder' ||
                        (f.mimeType == 'application/vnd.google-apps.folder' && (name.contains('tbp') || name.contains('교과서')));
                    final isPen = name.endsWith('.pen') || name.endsWith('.bstpen');
                    final isPdf = name.endsWith('.pdf');
                    final isPpt = name.endsWith('.ppt') || name.endsWith('.pptx');
                    final isHwp = name.endsWith('.hwp') || name.endsWith('.hwpx');

                    IconData iconData = Icons.insert_drive_file_rounded;
                    Color itemColor = const Color(0xFF00F5D4);
                    String badgeText = '자료';

                    if (isCanva) {
                      iconData = Icons.co_present_rounded;
                      itemColor = const Color(0xFF00C4CC);
                      badgeText = 'HTMLP';
                    } else if (isTbp) {
                      iconData = Icons.auto_stories_rounded;
                      itemColor = const Color(0xFF818CF8);
                      badgeText = '교과서';
                    } else if (isPen) {
                      iconData = Icons.history_edu_rounded;
                      itemColor = const Color(0xFF00F5D4);
                      badgeText = '판서';
                    } else if (isPdf) {
                      iconData = Icons.picture_as_pdf_rounded;
                      itemColor = Colors.redAccent;
                      badgeText = 'PDF';
                    } else if (isPpt) {
                      iconData = Icons.slideshow_rounded;
                      itemColor = Colors.orangeAccent;
                      badgeText = 'PPT';
                    } else if (isHwp) {
                      iconData = Icons.description_rounded;
                      itemColor = const Color(0xFF3B82F6);
                      badgeText = '한글';
                    }

                    return InkWell(
                      onTap: () async {
                        if (isCanva || isTbp) {
                          _pushBoardRoute(
                            TbpViewerRoute(
                              tbpFilePath: 'drive://tbp/${f.id}',
                              title: f.name,
                              scaleFactor: _settings.scaleFactor,
                              mode: isCanva ? TbpViewerMode.htmlp : TbpViewerMode.tbp,
                            ),
                          );
                        } else if (isPen) {
                          _pushBoardRoute(
                            BoardestPenView(
                              filePath: f.name,
                              scaleFactor: _settings.scaleFactor,
                              teacher: BstCloudService.instance.activeTeacherName ?? '교사',
                              subject: '화이트보드',
                            ),
                          );
                        } else {
                          _openDriveFileFromDock(f);
                        }
                      },
                      borderRadius: BorderRadius.circular(8 * scale),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 6 * scale),
                        decoration: BoxDecoration(
                          color: itemColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8 * scale),
                          border: Border.all(color: itemColor.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(iconData, color: itemColor, size: 15 * scale),
                            SizedBox(width: 6 * scale),
                            Expanded(
                              child: Text(
                                f.name,
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontSize: 10.5 * scale,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                              decoration: BoxDecoration(
                                color: itemColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4 * scale),
                              ),
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                  fontSize: 8.5 * scale,
                                  fontWeight: FontWeight.bold,
                                  color: itemColor,
                                ),
                              ),
                            ),
                            SizedBox(width: 4 * scale),
                            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 10 * scale),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudFilterPill(String filterKey, String label, double scale) {
    final isSelected = _cloudCategoryFilter == filterKey;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _cloudCategoryFilter = filterKey;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: 5 * scale),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.transparent,
            borderRadius: BorderRadius.circular(6 * scale),
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontSize: 10 * scale,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF070B14) : Colors.white70,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  List<BstCloudFile> _filterCloudFiles(List<BstCloudFile> files) {
    return files.where((f) {
      final name = f.name.toLowerCase();
      final isPen = name.endsWith('.pen') || name.endsWith('.bstpen');
      if (isPen && f.size != null && f.size! <= 0) return false;

      final isTbp = name.endsWith('.bsttbp') ||
          name.endsWith('.tbp') ||
          f.mimeType == 'application/x-bst-tbp-folder' ||
          (f.mimeType == 'application/vnd.google-apps.folder' && (name.contains('tbp') || name.contains('교과서')));
      final isCanva = name.endsWith('.htmlp') ||
          name.endsWith('.canva') ||
          name.endsWith('.canva.bst') ||
          name.endsWith('.bstcanva') ||
          name.contains('canva') ||
          name.contains('htmlp');

      switch (_cloudCategoryFilter) {
        case 'lesson':
          return !isPen && !isTbp && !isCanva;
        case 'tbp_canva':
          return isTbp || isCanva;
        case 'pen':
          return isPen;
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _checkTrustDeviceStatus() async {
    final activeTeacher = BstCloudService.instance.activeTeacherName;
    if (activeTeacher == null || activeTeacher.isEmpty) {
      if (mounted) setState(() => _isTrustDeviceSaved = false);
      return;
    }
    final saved = await PasskeyService.instance.getProSavedTeachers();
    final isSaved = saved.any((t) => t['teacherName'] == activeTeacher);
    if (mounted) {
      setState(() => _isTrustDeviceSaved = isSaved);
    }
  }

  Future<void> _openSavedTeachersSwitchDialog() async {
    final scale = _settings.scaleFactor;
    final savedTeachers = await PasskeyService.instance.getProSavedTeachers();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dlgContext) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return Dialog(
              backgroundColor: const Color(0xFF0B132B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16 * scale),
                side: const BorderSide(color: Color(0xFF00F5D4), width: 1.2),
              ),
              child: Container(
                width: 420 * scale,
                padding: EdgeInsets.all(20 * scale),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.switch_account_rounded, color: const Color(0xFF00F5D4), size: 22 * scale),
                        SizedBox(width: 8 * scale),
                        Expanded(
                          child: Text(
                            '등록 교사 선택 및 전환',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontSize: 16 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: Colors.white54, size: 20 * scale),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    SizedBox(height: 12 * scale),
                    if (savedTeachers.isEmpty) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 20 * scale),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.person_off_rounded, size: 36 * scale, color: Colors.white30),
                              SizedBox(height: 8 * scale),
                              Text(
                                '등록된 교사가 없습니다.',
                                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale),
                              ),
                              SizedBox(height: 4 * scale),
                              Text(
                                'QR 또는 OTP 로그인 후 상단의 [교사 등록] 버튼을 눌러 등록하세요.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 10.5 * scale),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 280 * scale),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: savedTeachers.length,
                          separatorBuilder: (_, __) => SizedBox(height: 8 * scale),
                          itemBuilder: (itemCtx, idx) {
                            final t = savedTeachers[idx];
                            final name = t['teacherName'] ?? '선생님';
                            final email = t['email'] ?? '';
                            final school = t['schoolName'] ?? '';
                            final token = t['accessToken'] ?? 'saved_token_$name';
                            final isCurrent = BstCloudService.instance.activeTeacherName == name;

                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
                              decoration: BoxDecoration(
                                color: isCurrent ? const Color(0xFF00F5D4).withOpacity(0.12) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10 * scale),
                                border: Border.all(
                                  color: isCurrent ? const Color(0xFF00F5D4) : Colors.white12,
                                  width: isCurrent ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16 * scale,
                                    backgroundColor: isCurrent ? const Color(0xFF00F5D4) : Colors.white24,
                                    child: Text(
                                      name.isNotEmpty ? name.substring(0, 1) : '교',
                                      style: TextStyle(
                                        color: isCurrent ? const Color(0xFF070B14) : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13 * scale,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10 * scale),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name + (isCurrent ? ' (현재 활성)' : ''),
                                          style: GoogleFonts.notoSansKr(
                                            color: Colors.white,
                                            fontSize: 12.5 * scale,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (school.isNotEmpty || email.isNotEmpty)
                                          Text(
                                            [school, email].where((e) => e.isNotEmpty).join(' • '),
                                            style: GoogleFonts.notoSansKr(
                                              color: Colors.white54,
                                              fontSize: 10 * scale,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (!isCurrent)
                                    ElevatedButton(
                                      onPressed: () {
                                        BstCloudService.instance.setDirectAccessToken(
                                          token,
                                          teacherName: name,
                                          ownerEmail: email,
                                        );
                                        setState(() {
                                          _refreshCloudFiles();
                                          _checkTrustDeviceStatus();
                                        });
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('🎉 $name 선생님으로 즉시 전환되었습니다!'),
                                            backgroundColor: const Color(0xFF00F5D4),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00F5D4),
                                        foregroundColor: const Color(0xFF070B14),
                                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6 * scale)),
                                      ),
                                      child: Text('전환', style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.bold)),
                                    ),
                                  SizedBox(width: 4 * scale),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded, size: 16 * scale, color: Colors.white38),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () async {
                                      await PasskeyService.instance.removeProTeacher(name);
                                      final updated = await PasskeyService.instance.getProSavedTeachers();
                                      setDlgState(() {
                                        savedTeachers.clear();
                                        savedTeachers.addAll(updated);
                                      });
                                      _checkTrustDeviceStatus();
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    SizedBox(height: 14 * scale),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openCloudPairingModal();
                          },
                          icon: Icon(Icons.add_rounded, size: 15 * scale, color: const Color(0xFF00F5D4)),
                          label: Text(
                            '새 교사 인증/등록',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF00F5D4),
                              fontSize: 11.5 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
  }

  void _openCloudCanvaFile(BstCloudFile file) async {
    final token = BstCloudService.instance.activeToken;
    if (token == null) return;
    try {
      final content = await BstCloudService.instance.readDriveFileText(file.id, token);
      if (content != null) {
        String canvaId = '';
        String title = file.name;
        try {
          final data = jsonDecode(content);
          canvaId = (data['embedUrl'] ?? data['url'] ?? data['webUrl'] ?? data['canvaUrl'] ?? data['canvaId'] ?? data['link'] ?? '').toString().trim();
          title = data['title']?.toString() ?? file.name;
        } catch (_) {
          canvaId = content.trim();
        }
        if (canvaId.isNotEmpty && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => HtmlPresentView(
                embedUrl: canvaId,
                title: title,
                scaleFactor: _settings.scaleFactor,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Dashboard] open HTML Present/Canva error: $e');
    }
  }

  void _openDriveFileFromDock(BstCloudFile file) async {
    final token = BstCloudService.instance.activeToken;
    if (token == null) return;
    final lower = file.name.toLowerCase();

    if (lower.endsWith('.pdf')) {
      Uint8List? bytes;
      if (file.id.isNotEmpty) {
        bytes = await BstCloudService.instance.downloadDriveFileBytes(file.id, token);
      }
      final classCode = '${_settings.selectedGrade}${_settings.selectedClass.toString().padLeft(2, '0')}';
      _pushBoardRoute(PdfBoardView(
        initialFilePath: file.name,
        pdfData: bytes,
        scaleFactor: _settings.scaleFactor,
        classCode: classCode,
      ));
    } else if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📂 [${file.name}] 다운로드 및 프레젠테이션 실행 중...'),
          duration: const Duration(seconds: 2),
        ),
      );
      if (kIsWeb) {
        final driveUrl = 'https://drive.google.com/file/d/${file.id}/view';
        launchUrl(Uri.parse(driveUrl), mode: LaunchMode.externalApplication);
      } else {
        final localPath = await BstCloudService.instance.downloadDriveFile(file.id, file.name, token);
        if (localPath != null && mounted) {
          if (Platform.isWindows) {
            _pushBoardRoute(PptOverlayView(
              initialFilePath: localPath,
              scaleFactor: _settings.scaleFactor,
              fullscreen: widget.pptFullscreen,
            ));
          } else {
            await launchUrl(Uri.file(localPath), mode: LaunchMode.externalApplication);
          }
        }
      }
    } else if (lower.endsWith('.hwp') || lower.endsWith('.hwpx')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📂 [${file.name}] 다운로드 및 한글 뷰어 실행 중...'),
          duration: const Duration(seconds: 2),
        ),
      );
      if (kIsWeb) {
        final driveUrl = 'https://drive.google.com/file/d/${file.id}/view';
        launchUrl(Uri.parse(driveUrl), mode: LaunchMode.externalApplication);
      } else {
        final localPath = await BstCloudService.instance.downloadDriveFile(file.id, file.name, token);
        if (localPath != null && mounted) {
          if (Platform.isWindows) {
            _pushBoardRoute(HwpOverlayView(
              initialFilePath: localPath,
              scaleFactor: _settings.scaleFactor,
            ));
          } else {
            await launchUrl(Uri.file(localPath), mode: LaunchMode.externalApplication);
          }
        }
      }
    } else if (lower.endsWith('.pen') || lower.endsWith('.free.pen')) {
      _pushBoardRoute(
        BoardestPenView(
          filePath: file.name,
          scaleFactor: _settings.scaleFactor,
          teacher: BstCloudService.instance.activeTeacherName ?? '교사',
          subject: '판서',
        ),
      );
    } else if (lower.endsWith('.bsttbp') ||
        lower.endsWith('.tbp') ||
        lower.endsWith('.htmlp') ||
        lower.endsWith('.canva.bst') ||
        file.mimeType == 'application/x-bst-tbp-folder') {
      final isHtmlp = lower.endsWith('.htmlp') || lower.endsWith('.canva.bst');
      _pushBoardRoute(
        TbpViewerRoute(
          tbpFilePath: 'drive://tbp/${file.id}',
          title: file.name,
          scaleFactor: _settings.scaleFactor,
          mode: isHtmlp ? TbpViewerMode.htmlp : TbpViewerMode.tbp,
        ),
      );
    } else {
      // 미지원 파일 형식: 브라우저/로컬 다운로드 확인 모달
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.download_rounded, color: Color(0xFF00F5D4), size: 22),
              const SizedBox(width: 8),
              Text(
                '파일 다운로드 안내',
                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: Text(
            '[${file.name}] 은(는) 앱 내 전용 뷰어가 없는 파일 형식입니다.\n\nGoogle Drive에서 기기로 다운로드하시겠습니까?',
            style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white38)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_download_rounded, size: 16),
              label: Text('다운로드', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('[${file.name}] 다운로드 중...', style: GoogleFonts.notoSansKr()),
                    backgroundColor: const Color(0xFF6366F1),
                    duration: const Duration(seconds: 2),
                  ),
                );
                final bytes = await BstCloudService.instance.downloadDriveFileBytes(file.id, token);
                if (bytes != null && mounted) {
                  await triggerBrowserDownload(bytes, file.name);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🎉 [${file.name}] 다운로드가 완료되었습니다!', style: GoogleFonts.notoSansKr()),
                      backgroundColor: const Color(0xFF2CB67D),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      );
    }
  }


  void _openTextbookProModal() {
    _showTbpWebSelectionDialog();
  }

  /// 학교 설정 데이터 실시간 동기화 (TimeSettings, Textbooks)
  Future<void> _syncSchoolConfigsFromFirestore() async {
    try {
      final rawSchoolId = _settings.schoolId.isNotEmpty
          ? _settings.schoolId
          : (_settings.connectionName.isNotEmpty ? _settings.connectionName : '');
      String schoolId = rawSchoolId.toLowerCase().trim();
      if (schoolId.isEmpty || schoolId == 'my') {
        return;
      }

      var url = '${AppConfig.firestoreBase}/control_configs/$schoolId?key=${AppConfig.firebaseApiKey}';
      var response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final fields = data['fields'] as Map<String, dynamic>?;

        // 학년별 교과서 ZIP 자동 다운로드 및 압축 해제 동기화
        await _syncSchoolTextbooksFromFirestore(fields);

        // 학교 일과 및 시정표 (TimeSettings) 실시간 동기화
        await _syncSchoolTimeSettingsFromFirestore(fields);
      }
    } catch (e) {
      debugPrint('[Boardest] Sync school configs error: $e');
    }
  }

  /// Firestore control_configs에 등록된 학교 일과 및 시정표 (TimeSettings) 실시간 동기화
  Future<void> _syncSchoolTimeSettingsFromFirestore(Map<String, dynamic>? fields) async {
    if (fields == null) return;
    try {
      final timeSettingsField = fields['timeSettings']?['mapValue']?['fields'] as Map<String, dynamic>?;
      if (timeSettingsField == null) return;

      final lessonDuration = int.tryParse(timeSettingsField['lessonDuration']?['integerValue']?.toString() ?? '') ?? 
                             (timeSettingsField['lessonDuration']?['doubleValue'] as num?)?.toInt() ?? 45;
      final breakDuration = int.tryParse(timeSettingsField['breakDuration']?['integerValue']?.toString() ?? '') ?? 
                            (timeSettingsField['breakDuration']?['doubleValue'] as num?)?.toInt() ?? 10;
      final lunchDuration = int.tryParse(timeSettingsField['lunchDuration']?['integerValue']?.toString() ?? '') ?? 
                            (timeSettingsField['lunchDuration']?['doubleValue'] as num?)?.toInt() ?? 50;
      final lunchAfterPeriod = int.tryParse(timeSettingsField['lunchAfterPeriod']?['integerValue']?.toString() ?? '') ?? 
                               (timeSettingsField['lunchAfterPeriod']?['doubleValue'] as num?)?.toInt() ?? 4;
      final firstPeriodStart = timeSettingsField['firstPeriodStart']?['stringValue']?.toString() ?? '08:40';
      final morningAssemblyStart = timeSettingsField['morningAssemblyStart']?['stringValue']?.toString() ?? '08:25';
      final morningAssemblyEnd = timeSettingsField['morningAssemblyEnd']?['stringValue']?.toString() ?? '08:40';
      final afternoonAssemblyStart = timeSettingsField['afternoonAssemblyStart']?['stringValue']?.toString() ?? '16:10';
      final afternoonAssemblyEnd = timeSettingsField['afternoonAssemblyEnd']?['stringValue']?.toString() ?? '16:30';
      final afternoonAssemblyAfterMinutes = int.tryParse(timeSettingsField['afternoonAssemblyAfterMinutes']?['integerValue']?.toString() ?? '') ?? 
                                           (timeSettingsField['afternoonAssemblyAfterMinutes']?['doubleValue'] as num?)?.toInt() ?? 10;
      final afternoonAssemblyDuration = int.tryParse(timeSettingsField['afternoonAssemblyDuration']?['integerValue']?.toString() ?? '') ?? 
                                       (timeSettingsField['afternoonAssemblyDuration']?['doubleValue'] as num?)?.toInt() ?? 20;

      final newTs = TimeSettings(
        lessonDuration: lessonDuration,
        breakDuration: breakDuration,
        lunchDuration: lunchDuration,
        lunchAfterPeriod: lunchAfterPeriod,
        firstPeriodStart: firstPeriodStart,
        morningAssemblyStart: morningAssemblyStart,
        morningAssemblyEnd: morningAssemblyEnd,
        afternoonAssemblyStart: afternoonAssemblyStart,
        afternoonAssemblyEnd: afternoonAssemblyEnd,
        afternoonAssemblyAfterMinutes: afternoonAssemblyAfterMinutes,
        afternoonAssemblyDuration: afternoonAssemblyDuration,
      );

      final currentTs = _settings.timeSettings;
      if (newTs.lessonDuration != currentTs.lessonDuration ||
          newTs.breakDuration != currentTs.breakDuration ||
          newTs.lunchDuration != currentTs.lunchDuration ||
          newTs.lunchAfterPeriod != currentTs.lunchAfterPeriod ||
          newTs.firstPeriodStart != currentTs.firstPeriodStart ||
          newTs.morningAssemblyStart != currentTs.morningAssemblyStart ||
          newTs.morningAssemblyEnd != currentTs.morningAssemblyEnd ||
          newTs.afternoonAssemblyStart != currentTs.afternoonAssemblyStart ||
          newTs.afternoonAssemblyEnd != currentTs.afternoonAssemblyEnd ||
          newTs.afternoonAssemblyAfterMinutes != currentTs.afternoonAssemblyAfterMinutes ||
          newTs.afternoonAssemblyDuration != currentTs.afternoonAssemblyDuration) {
        
        debugPrint('[Boardest] 🕒 Remote TimeSettings synced from Control Panel! Applying new schedule...');
        final updatedSettings = _settings.copyWith(timeSettings: newTs);
        if (mounted) {
          setState(() {
            _settings = updatedSettings;
          });
        }
        await _storageService.saveSettings(updatedSettings);
        _updateLiveSchedule();
      }
    } catch (e) {
      debugPrint('[Boardest] Error syncing remote TimeSettings: $e');
    }
  }

  /// 학년별 교과서 ZIP 다운로드 및 압축 해제 (Firestore control_configs 또는 공식 GitHub 기본 저장소)
  Future<void> _syncSchoolTextbooksFromFirestore([Map<String, dynamic>? fields]) async {
    // 데모 모드에서는 실제 학교 교과서 zip 다운로드를 차단
    if (AppConfig.isDemoMode) {
      debugPrint('[TextbookSync] 🛑 Demo mode active: skipping external textbook ZIP download.');
      return;
    }
    // 이미 다운로드 진행 중이면 중복 요청 차단
    if (_isTextbookZipDownloading) {
      debugPrint('[TextbookSync] ⏳ Textbook ZIP download already in progress. Skipping duplicate request.');
      return;
    }
    // 이미 메모리에 교과서 표지가 등록되어 있다면 재다운로드 불필요
    if (_inMemoryTextbookBytes.isNotEmpty) {
      debugPrint('[TextbookSync] ⚡ In-memory textbooks already present. Skipping re-download.');
      return;
    }

    _isTextbookZipDownloading = true;
    try {
      final grade = _settings.selectedGrade > 0 ? _settings.selectedGrade : 1;
      final zipKey = 'textbookZip$grade';
      String? zipUrl = fields?[zipKey]?['stringValue']?.toString().trim();

      // Fallback 1: textbookZip (전체 공통)
      if (zipUrl == null || zipUrl.isEmpty) {
        zipUrl = fields?['textbookZip']?['stringValue']?.toString().trim();
      }
      // Fallback 2: textbookZip1, 2, 3 순회
      if (zipUrl == null || zipUrl.isEmpty) {
        for (int g = 1; g <= 3; g++) {
          final candidate = fields?['textbookZip$g']?['stringValue']?.toString().trim();
          if (candidate != null && candidate.isNotEmpty && g == grade) {
            zipUrl = candidate;
            break;
          }
        }
      }

      // 교과서는 학교마다 출판사가 모두 다르므로, 해당 학교(control_configs)에 등록된 zipUrl이 없으면 임의 다운로드 금지
      // (기존 ydm 학교일 때만 하위 호환 유지)
      final currentSchoolId = _settings.schoolId.toLowerCase();
      final defaultZipUrl = (currentSchoolId == 'ydm' || currentSchoolId == '44134')
          ? 'https://raw.githubusercontent.com/hiJiwho/TB22-ydms/main/${grade}%ED%95%99%EB%85%84.zip'
          : '';
      final effectiveZipUrl = (zipUrl != null && zipUrl.isNotEmpty) ? zipUrl : defaultZipUrl;

      if (effectiveZipUrl.isEmpty) {
        debugPrint('[TextbookSync] ℹ️ 학교($currentSchoolId) 전용 교과서가 등록되지 않아 외부 다운로드를 건너뜁니다.');
        return;
      }

      // 로컬 디렉터리에 실제 파일들이 이미 존재하는지 확인
      Directory? localTextbookDir;
      bool hasLocalFiles = false;
      if (!kIsWeb) {
        try {
          localTextbookDir = Directory(p.join(AppPaths.dataRootSync, 'textbooks'));
          if (await localTextbookDir.exists()) {
            final files = localTextbookDir.listSync().whereType<File>();
            if (files.isNotEmpty) {
              hasLocalFiles = true;
            }
          } else {
            await localTextbookDir.create(recursive: true);
          }
        } catch (_) {}
      }

      final lastProcessedKey = 'last_downloaded_zip_$grade';
      final prefs = await SharedPreferences.getInstance();
      final lastUrl = prefs.getString(lastProcessedKey);

      // 이미 메모리에 로드되어 있거나 로컬 파일이 온전히 존재하는 경우 스킵
      if (lastUrl == effectiveZipUrl && (_inMemoryTextbookBytes.isNotEmpty || hasLocalFiles)) {
        debugPrint('[TextbookSync] Textbook covers already loaded and up to date for grade $grade.');
        return;
      }

      // CDN 파이프라인: 양동중학교만 TB22-ydms 허용, 타 학교는 관리자 등록 zipUrl만 사용
      final bool isYdm = currentSchoolId == 'ydm' || currentSchoolId == '44134' || _settings.selectedSchool?.name.contains('양동') == true;
      final List<String> candidateUrls = [];
      if (zipUrl != null && zipUrl.isNotEmpty) {
        candidateUrls.add(zipUrl);
      }
      if (isYdm) {
        if (defaultZipUrl.isNotEmpty && !candidateUrls.contains(defaultZipUrl)) {
          candidateUrls.add(defaultZipUrl);
        }
        candidateUrls.add('https://cdn.jsdelivr.net/gh/hiJiwho/TB22-ydms@main/${grade}%ED%95%99%EB%85%84.zip');
        candidateUrls.add('https://rawcdn.githack.com/hiJiwho/TB22-ydms/main/${grade}%ED%95%99%EB%85%84.zip');
      }

      http.Response? resp;
      for (final url in candidateUrls) {
        try {
          debugPrint('[TextbookSync] Downloading textbook ZIP for Grade $grade from: $url');
          final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            resp = r;
            debugPrint('[TextbookSync] Successfully received ${r.bodyBytes.length} bytes from $url');
            break;
          } else {
            debugPrint('[TextbookSync] Candidate $url returned HTTP ${r.statusCode}');
          }
        } catch (e) {
          debugPrint('[TextbookSync] Candidate $url failed: $e');
        }
      }

      if (resp == null || resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        debugPrint('[TextbookSync] All textbook CDN downloads failed for Grade $grade.');
        return;
      }

      debugPrint('[TextbookSync] Decompressing ZIP archive (${resp.bodyBytes.length} bytes)...');
      final archive = ZipDecoder().decodeBytes(resp.bodyBytes);
      final Map<String, String> updatedImages = Map<String, String>.from(_settings.textbookImages);
      int extractedCount = 0;

      for (final file in archive) {
        if (file.isFile) {
          final fullName = file.name;
          final fileName = p.basename(fullName);
          if (fileName.startsWith('.') || fileName.startsWith('__MACOSX')) continue;

          final dotIdx = fileName.lastIndexOf('.');
          if (dotIdx == -1) continue;
          final rawStem = fileName.substring(0, dotIdx);
          final ext = fileName.substring(dotIdx + 1).toLowerCase();

          if (!['png', 'jpg', 'jpeg', 'webp', 'bmp'].contains(ext)) continue;

          final rawBytes = file.content as List<int>;
          if (rawBytes.isEmpty) continue;
          final bytes = Uint8List.fromList(rawBytes);

          final stem = AppSettings.getSubjectStem(rawStem);

          // 1. Raw image bytes stored in-memory for zero-latency, zero-quota overhead rendering
          _inMemoryTextbookBytes[stem] = bytes;
          _inMemoryTextbookBytes['${grade}_$stem'] = bytes;

          // 2. On native platforms: save file to disk as well
          if (!kIsWeb && localTextbookDir != null) {
            try {
              final localFile = File(p.join(localTextbookDir.path, '${grade}_$stem.$ext'));
              await localFile.writeAsBytes(bytes);
              updatedImages[stem] = localFile.path;
              updatedImages['${grade}_$stem'] = localFile.path;
            } catch (_) {}
          }

          extractedCount++;
        }
      }

      if (extractedCount > 0) {
        await prefs.setString(lastProcessedKey, effectiveZipUrl);
        final updatedSettings = _settings.copyWith(textbookImages: updatedImages);
        if (mounted) {
          setState(() {
            _settings = updatedSettings;
          });
        }
        await _storageService.saveSettings(updatedSettings);
        debugPrint('[TextbookSync] Successfully extracted and registered $extractedCount textbooks in memory for Grade $grade!');
      }
    } catch (e, st) {
      debugPrint('[TextbookSync] Error during ZIP extraction: $e\n$st');
    } finally {
      _isTextbookZipDownloading = false;
    }
  }

  // --- Right Panel Bottom Right: NEIS Lunch Menu ---
  Widget _buildMealCard() {
    final scale = _settings.scaleFactor;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16.0 * scale,
              vertical: 12.0 * scale,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.restaurant_rounded,
                          color: const Color(0xFF2CB67D),
                          size: 18 * scale,
                        ),
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
                      icon: Icon(
                        Icons.sync_rounded,
                        color: Colors.white30,
                        size: 18 * scale,
                      ),
                      onPressed: () {
                        final targetDate = _debugTimeOverride ?? DateTime.now();
                        _fetchLunchMenu(
                          _settings.selectedSchool!.name,
                          targetDate,
                        );
                        _fetchSchoolSchedule(
                          _settings.selectedSchool!.name,
                          targetDate,
                        );
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
                            final lines = _mealInfo
                                .split('\n')
                                .map((l) => l.trim())
                                .where((l) => l.isNotEmpty)
                                .toList();

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
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: lines
                                      .map(
                                        (line) => Padding(
                                          padding: EdgeInsets.only(
                                            bottom: 4.0 * scale,
                                          ),
                                          child: Text(
                                            line,
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: mealFontSize * scale,
                                              color: Colors.white.withValues(
                                                alpha: 0.8,
                                              ),
                                              height: mealLineHeight,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
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
        padding: EdgeInsets.symmetric(
          horizontal: 4 * scale,
          vertical: 4 * scale,
        ),
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
                  ),
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
                      accentColor.withOpacity(0.01),
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
                    await UsbSessionService.instance.setAutoOpen(
                      _usbSessionId,
                      _usbAutoOpenEnabled,
                    );
                  }
                },
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _usbAutoOpenEnabled
                            ? Icons.play_circle_filled_rounded
                            : Icons.pause_circle_filled_rounded,
                        color: _usbAutoOpenEnabled
                            ? const Color(0xFF00F5D4)
                            : Colors.white38,
                        size: 14 * scale,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _usbAutoOpenEnabled ? '자동 실행 On' : '자동 실행 Off',
                        style: GoogleFonts.notoSansKr(
                          color: _usbAutoOpenEnabled
                              ? const Color(0xFF00F5D4)
                              : Colors.white38,
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
            border: Border.all(
              color: const Color(0xFF00F5D4).withOpacity(0.3),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _showFullUsbExplorer
                    ? Icons.folder_rounded
                    : Icons.auto_awesome_motion_rounded,
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
        "(New-Object -ComObject Shell.Application).Namespace(17).ParseName('$driveLetter').InvokeVerb('Eject')",
      ]);
      if (result.exitCode == 0) {
        if (mounted) {
          setState(() {
            _isUsbEjected = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2EC4B6),
              content: Text(
                'USB를 제거하시기 바랍니다.',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }
        _checkUsbConnection();
      } else {
        throw Exception(
          'Powershell exit code ${result.exitCode}: ${result.stderr}',
        );
      }
    } catch (e) {
      debugPrint('Eject USB error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4565),
            content: Text(
              'USB 제거 실패: $e',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
    }
  }

  Widget _buildCategorizedDashboardLauncher() {
    final scale = _settings.scaleFactor;
    return _buildRightSideLauncherPanel(scale);
  }

  // 1열 상단 3행 도구: 날씨, 학사달력, 앱서랍
  Widget _buildColumn1Top3Launcher(double scale) {
    return Container(
      padding: EdgeInsets.all(6 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.015),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(
        children: [
          // 1행: 날씨 (slot 0)
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(2.5 * scale),
              child: _buildGridSlot(
                LauncherSlot(id: "timer", name: "타이머", type: LauncherSlotType.boardestTool),
                scale,
                0,
              ),
            ),
          ),
          // 2행: 학사달력 (slot 1)
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(2.5 * scale),
              child: _buildGridSlot(
                LauncherSlot(id: 'school_calendar', name: '학사달력', type: LauncherSlotType.boardestTool),
                scale,
                1,
              ),
            ),
          ),
          // 3행: 앱서랍 (slot 2)
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(2.5 * scale),
              child: _buildGridSlot(
                LauncherSlot(id: 'app_drawer', name: '앱서랍', type: LauncherSlotType.boardestTool),
                scale,
                2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 우측 런처 패널: 2열 (판서 & 수업 도구 7개) + [Desktop] 3열 (시스템 앱 7개)
  Widget _buildRightSideLauncherPanel(double scale) {
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
                    color: accentColor.withValues(alpha: 0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            SizedBox(width: 6 * scale),
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(8 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.015),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildHeader(
            AppConfig.isLiteMode ? '시간표도구' : 'Bst도구',
            AppConfig.isLiteMode ? const Color(0xFF2EC4B6) : const Color(0xFF00F5D4),
          ),
          SizedBox(height: 6 * scale),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1열 (핵심 Bst도구)
                Expanded(
                  child: Column(
                    children: [
                      if (!AppConfig.isLiteMode) ...[
                        _buildToolSlotItem('unified_pen', '판서하기', 7, scale),
                        _buildToolSlotItem('bst_cloud', 'Cloud', 8, scale),
                        _buildToolSlotItem('send_message_teacher', '선생님쪽지', 9, scale),
                      ],
                                            _buildToolSlotItem('school_calendar', '학사달력', 10, scale),
                      _buildToolSlotItem('app_drawer', '앱서랍', 11, scale),
                      _buildToolSlotItem('timer', '타이머', 12, scale),
                      _buildToolSlotItem('settings', '설정', 13, scale),
                    ],
                  ),
                ),

                // 3열 (Desktop 전용: 시스템 앱 5개 + 최소화 1개 + 프로그램 닫기 1개)
                if (!kIsWeb) ...[
                  SizedBox(width: 6 * scale),
                  Expanded(
                    child: Column(
                      children: List.generate(7, (index) {
                        if (index == 5) {
                          // 6행: 앱 최소화 (설정 버튼 바로 위 위치의 앱추가 슬롯을 앱 최소화로 할당)
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(2.5 * scale),
                              child: _buildMinimizeWindowSlot(scale),
                            ),
                          );
                        } else if (index == 6) {
                          // 7행: 프로그램 닫기 (설정 버튼 옆 맨 아래 슬롯)
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(2.5 * scale),
                              child: _buildCloseWindowSlot(scale),
                            ),
                          );
                        }

                        // 1~5행 (slots 14..18: 사용자 시스템 앱 등록 슬롯)
                        final slotIndex = 14 + index;
                        final slot = slotIndex < slots.length ? slots[slotIndex] : null;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(2.5 * scale),
                            child: (slot == null || slot.type == LauncherSlotType.empty)
                                ? _buildEmptySlot(scale, slotIndex)
                                : _buildGridSlot(slot, scale, slotIndex),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolSlotItem(String id, String name, int slotIndex, double scale) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.all(2.5 * scale),
        child: _buildGridSlot(
          LauncherSlot(id: id, name: name, type: LauncherSlotType.boardestTool),
          scale,
          slotIndex,
        ),
      ),
    );
  }

  // Context-aware USB / Meal card widget inside Col 1 rows 4-7
  Widget _buildAdBannerOrContextCard(double scale) {
    if (_isUsbConnected) {
      return _buildCompactUsbExplorer(scale);
    }
    return _buildNeisMealCard(scale);
  }

  Widget _buildMinimizeWindowSlot(double scale) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (!kIsWeb && Platform.isWindows) {
            try {
              await windowManager.minimize();
            } catch (e) {
              debugPrint('[WindowManager] minimize error: $e');
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🖥️ 데스크톱 Windows 앱에서 창이 최소화됩니다.'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2EC4B6).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF2EC4B6).withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: Container(
                  width: 22 * scale,
                  height: 22 * scale,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2EC4B6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6 * scale),
                    border: Border.all(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.remove_rounded,
                      color: const Color(0xFF00F5D4),
                      size: 14 * scale,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 3 * scale),
              Text(
                '앱 최소화',
                style: GoogleFonts.notoSansKr(
                  fontSize: 8.5 * scale,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF00F5D4),
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

  Widget _buildCloseWindowSlot(double scale) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF16161A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16 * scale),
                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              title: Row(
                children: [
                  Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 24 * scale),
                  SizedBox(width: 8 * scale),
                  Text(
                    '프로그램 종료',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16 * scale,
                    ),
                  ),
                ],
              ),
              content: Text(
                'Boardest 프로그램을 종료하시겠습니까?',
                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('종료', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            if (!kIsWeb && Platform.isWindows) {
              try {
                await windowManager.close();
              } catch (_) {
                exit(0);
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🖥️ 데스크톱 Windows 앱이 종료됩니다.'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFF5376).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFFF5376).withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: Container(
                  width: 22 * scale,
                  height: 22 * scale,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5376).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6 * scale),
                    border: Border.all(
                      color: const Color(0xFFFF5376).withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      color: const Color(0xFFFF5376),
                      size: 13 * scale,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 3 * scale),
              Text(
                '프로그램 닫기',
                style: GoogleFonts.notoSansKr(
                  fontSize: 8.5 * scale,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFF8BA7),
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

  Widget _buildEmptySlot(double scale, int slotIndex) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAppSelectorForSlot(slotIndex),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                color: const Color(0xFF00F5D4).withValues(alpha: 0.7),
                size: 15 * scale,
              ),
              SizedBox(width: 4 * scale),
              Text(
                '앱 등록',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white54,
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
      final hasIcon =
          slot.iconPath != null &&
          slot.iconPath!.isNotEmpty &&
          File(slot.iconPath!).existsSync();
      accentColor = colors[slot.name.codeUnits.first % colors.length];
      final avatar = slot.name.length >= 2
          ? slot.name.substring(0, 2)
          : slot.name;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _launchSystemApp(
            SystemApp(name: slot.name, appId: slot.id, iconPath: slot.iconPath),
          ),
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
                      color: hasIcon
                          ? Colors.transparent
                          : accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6 * scale),
                      border: hasIcon
                          ? null
                          : Border.all(
                              color: accentColor.withValues(alpha: 0.5),
                              width: 1,
                            ),
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
                            child: Text(
                              avatar,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 8.0 * scale,
                                fontWeight: FontWeight.bold,
                                color: accentColor,
                              ),
                            ),
                          ),
                  ),
                ),
                SizedBox(height: 3 * scale),
                Text(
                  slot.name,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 8.5 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.75),
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

    // Boardest tool slot
    final isCloudTool = slot.id == 'bst_cloud';
    final isDisabled = isUpcoming;
    accentColor = colors[slot.id.hashCode.abs() % colors.length];
    icon = _getToolIcon(slot.id);
    final onTap = _getToolOnTap(slot.id);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          InkWell(
            onTap: isDisabled ? null : onTap,
            onLongPress: (slot.id == 'settings') ? _onSettingsLongPress : null,
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
                        color: (isDisabled ? Colors.grey : accentColor)
                            .withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6 * scale),
                        border: Border.all(
                          color: (isDisabled ? Colors.grey : accentColor)
                              .withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          color: isDisabled ? Colors.white30 : accentColor,
                          size: 12 * scale,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 3 * scale),
                  Text(
                    slot.name,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 8.5 * scale,
                      fontWeight: FontWeight.w600,
                      color: isDisabled
                          ? Colors.white30
                          : Colors.white.withValues(alpha: 0.75),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (isUpcoming)
            Positioned(
              top: 2 * scale,
              right: 2 * scale,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 4 * scale,
                  vertical: 1 * scale,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2EC4B6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFF2EC4B6),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  '예정',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 6 * scale,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF00F5D4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getToolIcon(String id) {
    switch (id) {
      // 단순 도구 (Simple Tools)
      case 'timer':
        return Icons.timer_rounded;
      case 'calculator':
        return Icons.calculate_rounded;
      case 'picker':
        return Icons.person_search_rounded;
            case 'school_calendar':
        return Icons.calendar_month_rounded;
      case 'notepad':
        return Icons.note_alt_rounded;
      case 'send_message_teacher':
        return Icons.send_rounded;

      // 판서 관련 (Annotation Tools)
      case 'unified_pen':
        return Icons.draw_rounded;
      case 'whiteboard':
        return Icons.draw_rounded;
      case 'document_board':
        return Icons.description_rounded;
      case 'website_board':
        return Icons.language_rounded;
      case 'youtube_board':
        return Icons.play_circle_fill_rounded;
      case 'canva_board':
        return Icons.palette_rounded;
      case 'student_connect':
        return Icons.wifi_tethering_rounded;
      case 'settings':
        return Icons.tune_rounded;

      // 기타/유틸리티
      case 'file_explorer':
        return Icons.folder_open_rounded;
      case 'timetable':
        return Icons.calendar_view_week_rounded;
      case 'bst_cloud':
        return Icons.cloud_done_rounded;
      case 'textbookpro':
      case 'textbook_pro':
      case 'tbp':
        return Icons.menu_book_rounded;
      case 'plugin_store':
        return Icons.extension_rounded;
      case 'app_drawer':
        return Icons.apps_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  VoidCallback _getToolOnTap(String id) {
    switch (id) {
      // 단순 도구 (Simple Tools)
      case 'timer':
        return _openTimer;
      case 'calculator':
        return _openCalculator;
      case 'picker':
        return _openRandomPicker;
            case 'school_calendar':
        return _openSchoolCalendarDialog;
      case 'notepad':
        return _openNotepad;
      case 'send_message_teacher':
        return _openSendMessageToTeacherDialog;

      // 판서 관련 (Annotation Tools)
      case 'unified_pen':
        return _openUnifiedPenDialog;
      case 'whiteboard':
        return _openWhiteboard;
      case 'document_board':
        return _openDocumentBoard;
      case 'website_board':
        return _openWebsiteBoard;
      case 'youtube_board':
        return _openYoutubeBoard;
      case 'canva_board':
        return _openCanvaBoard;
      case 'ppt_board':
        return _openPptOverlay;
      case 'pdf_board':
        return _openPdfBoard;
      case 'student_connect':
        return _openStudentConnect;
      case 'settings':
        return _openSettingsWizard;

      // 기타/유틸리티
      case 'file_explorer':
        return _openFileExplorer;
      case 'timetable':
        return _openWeeklyTimetable;
      case 'bst_cloud':
        return _openBstCloud;
      case 'textbookpro':
      case 'textbook_pro':
        return _openTextbookProModal;
      case 'plugin_store':
        return _openPluginStore;
      case 'app_drawer':
        return _openAppDrawer;
      default:
        return () {};
    }
  }

  void _showTbpWebSelectionDialog() {
    final scale = _settings.scaleFactor;
    final cloud = BstCloudService.instance;
    final isCloudActive = cloud.activeToken != null;
    final token = cloud.activeToken ?? '';

    // ── 1. Cloud 미연결 시: 반드시 교사용 Cloud 연결 필요 안내 모달 ──
    if (!isCloudActive) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20 * scale),
            side: const BorderSide(color: Color(0xFF242629)),
          ),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10 * scale),
                ),
                child: Icon(Icons.cloud_off_rounded, color: const Color(0xFF818CF8), size: 24 * scale),
              ),
              SizedBox(width: 12 * scale),
              Text(
                '교사용 Cloud 연결 필요',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18 * scale,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TBP 전자교과서 및 HTMLP 웹교안은 선생님 Cloud에 연결된 상태에서만 작동합니다.',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white70,
                  fontSize: 14 * scale,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 10 * scale),
              Text(
                '교사용 앱의 6자리 OTP 또는 QR로 간편 접속하면 드라이브에 저장된 교과서와 교안(.tbp / .htmlp)을 즉시 불러옵니다.',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white38,
                  fontSize: 12 * scale,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('닫기', style: GoogleFonts.notoSansKr(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _openBstCloud();
              },
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text('☁️ Cloud 간편 연결하기'),
            ),
          ],
        ),
      );
      return;
    }

    // ── 2. Cloud 연결 상태: bst-save 내의 포인터 껍데기 파일(.tbp, .htmlp) 탐색 및 실행 ──
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20 * scale),
          side: const BorderSide(color: Color(0xFF242629)),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF7F5AF0).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10 * scale),
              ),
              child: Icon(Icons.auto_stories_rounded, color: const Color(0xFF00F5D4), size: 24 * scale),
            ),
            SizedBox(width: 12 * scale),
            Text(
              '교사용 Cloud 교과서 & 웹교안 (TBP / HTMLP)',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18 * scale,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520 * scale,
          height: 420 * scale,
          child: FutureBuilder<List<BstCloudFile>>(
            future: Future.wait([
              BstCloudService.instance.fetchFilesBySpecificFolder(accessToken: token, folderName: 'bst-save'),
              BstCloudService.instance.fetchDriveFolderFiles(accessToken: token),
            ]).then((lists) => [...lists[0], ...lists[1]]),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)));
              }
              final allFiles = snapshot.data ?? [];
              final seenIds = <String>{};
              final pointerFiles = allFiles.where((f) {
                if (!seenIds.add(f.id)) return false;
                final name = f.name.toLowerCase();
                return name.endsWith('.tbp') ||
                    name.endsWith('.htmlp') ||
                    name.endsWith('.bsttbp') ||
                    name.endsWith('.canva.bst');
              }).toList();

              if (pointerFiles.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_rounded, size: 48 * scale, color: Colors.white24),
                      SizedBox(height: 12 * scale),
                      Text(
                        'Cloud에 등록된 교과서나 교안(.tbp / .htmlp)이 없습니다',
                        style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 14 * scale, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 6 * scale),
                      Text(
                        '교사용 앱에서 스마트교과서 또는 Canva 교안을 저장해주세요.',
                        style: TextStyle(color: Colors.white38, fontSize: 12 * scale),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: pointerFiles.length,
                separatorBuilder: (_, __) => SizedBox(height: 8 * scale),
                itemBuilder: (context, index) {
                  final file = pointerFiles[index];
                  final lower = file.name.toLowerCase();
                  final isHtmlp = lower.endsWith('.htmlp') || lower.endsWith('.canva.bst');

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12 * scale),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                      leading: Icon(
                        isHtmlp ? Icons.slideshow_rounded : Icons.menu_book_rounded,
                        color: isHtmlp ? const Color(0xFF6366F1) : const Color(0xFF00F5D4),
                      ),
                      title: Text(
                        file.name,
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5 * scale),
                      ),
                      subtitle: Text(
                        isHtmlp ? 'HTMLP 웹교안 포인터' : 'TBP 스마트교과서 포인터',
                        style: TextStyle(color: Colors.white38, fontSize: 11 * scale),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        _pushBoardRoute(
                          TbpViewerRoute(
                            tbpFilePath: 'drive://tbp/${file.id}',
                            title: file.name,
                            scaleFactor: _settings.scaleFactor,
                            mode: isHtmlp ? TbpViewerMode.htmlp : TbpViewerMode.tbp,
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('닫기', style: GoogleFonts.notoSansKr(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _openUnifiedPenDialog() {
    if (kIsWeb) {
      _openWhiteboard();
      return;
    }

    final scale = _settings.scaleFactor;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20 * scale),
          side: const BorderSide(color: Color(0xFF242629)),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF7F5AF0).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10 * scale),
              ),
              child: Icon(Icons.draw_rounded, color: const Color(0xFF7F5AF0), size: 24 * scale),
            ),
            SizedBox(width: 12 * scale),
            Text(
              '판서 모드 선택',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18 * scale,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPenOptionTile(
              scale: scale,
              icon: Icons.brush_rounded,
              color: const Color(0xFF00F5D4),
              title: '기본 판서 띄우기',
              subtitle: '빈 캔버스에서 자유롭게 필기 및 그림판 사용',
              onTap: () {
                Navigator.of(ctx).pop();
                _openWhiteboard();
              },
            ),
            SizedBox(height: 12 * scale),
            if (!kIsWeb) ...[
              _buildPenOptionTile(
                scale: scale,
                icon: Icons.description_rounded,
                color: const Color(0xFFFF8906),
                title: '문서 열고 판서하기',
                subtitle: 'PDF, PPT, HWP 등 수업 문서를 선택하여 판서',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openDocumentBoard();
                },
              ),
              SizedBox(height: 12 * scale),
            ],
            _buildPenOptionTile(
              scale: scale,
              icon: Icons.language_rounded,
              color: const Color(0xFF2CB67D),
              title: '사이트 위에 판서하기',
              subtitle: '웹 브라우저 및 교육 사이트 위에 오버레이 필기',
              onTap: () {
                Navigator.of(ctx).pop();
                _openWebsiteBoard();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '닫기',
              style: GoogleFonts.notoSansKr(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPenOptionTile({
    required double scale,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale)),
        leading: Container(
          padding: EdgeInsets.all(8 * scale),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10 * scale),
          ),
          child: Icon(icon, color: color, size: 20 * scale),
        ),
        title: Text(
          title,
          style: GoogleFonts.notoSansKr(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13 * scale,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.notoSansKr(
            color: Colors.white54,
            fontSize: 11 * scale,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14 * scale),
        onTap: onTap,
      ),
    );
  }

  Future<void> _fetchTimetableBackground() async {
    final settings = _settings;
    if (settings.selectedSchool == null) return;

    final schoolCode = settings.selectedSchool!.code;
    final targetDate = _debugTimeOverride ?? DateTime.now();
    final weekOffset = _getWeekOffset(targetDate, DateTime.now());

    try {
      final rawData = await _comciganService.fetchTimetableRaw(
        schoolCode,
        weekOffset: weekOffset,
      );
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
          _debugTimeOverride = _debugTimeOverride!.add(
            const Duration(seconds: 1),
          );
        });
      } else {
        setState(() {
          _now = DateTime.now();
        });
      }
      _updateLiveSchedule();

      // 급식 투표 스마트 파이프라인 (DB 누수 0, 서버 점유 0KB)
      final now = _debugTimeOverride ?? DateTime.now();
      if (now.second == 0) {
        final nowMinutes = now.hour * 60 + now.minute;
        final endMin = _getLunchEndMinutes();
        final currentSchoolId = _settings.schoolId.isNotEmpty
            ? _settings.schoolId
            : (_settings.selectedSchool?.name ?? 'Demo');
        final voteDate = DateTime(now.year, now.month, now.day);
        final classKey = _settings.classNickname.isNotEmpty
            ? _settings.classNickname
            : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';

        if (nowMinutes == endMin - 5) {
          // 종료 5분 전: 교실 투표 1회 서버 전송 및 보관
          MealVoteService.instance.syncClassVotesToServer(
            schoolId: currentSchoolId,
            date: voteDate,
            classKey: classKey,
          );
        } else if (nowMinutes == endMin - 4) {
          // 종료 4분 전 (1분 뒤): 전교 투표 1회 취합 및 전자칠판 로컬/서버 동기화
          MealVoteService.instance.fetchAndPersistFinalResults(
            schoolId: currentSchoolId,
            date: voteDate,
          );
        }
      }

      // DB 사용량 최적화: 백그라운드 주기적 Firestore 호출(온라인 상태 쓰기, 배너 읽기, 시간표 폴링)을 전면 제거하고
      // 앱 실행 시(또는 설정 수동 저장 시) 1회만 호출하여 일일 DB 할당량 고갈을 원천 차단합니다.

      if (!kIsWeb && Platform.isWindows && _settings.autoSleepEnabled) {
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
            _sleepWarningTimer = Timer.periodic(const Duration(seconds: 1), (
              timer,
            ) {
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
                  side: BorderSide(
                    color: const Color(0xFFEF4565).withOpacity(0.4),
                    width: 2,
                  ),
                ),
                title: Row(
                  children: [
                    const Icon(
                      Icons.power_settings_new_rounded,
                      color: Color(0xFFEF4565),
                      size: 28,
                    ),
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
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFEF4565),
                            ),
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
                actionsPadding: EdgeInsets.only(
                  bottom: 20 * scale,
                  left: 20 * scale,
                  right: 20 * scale,
                ),
                actions: [
                  ElevatedButton(
                    onPressed: _snoozeSleep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4565),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 32 * scale,
                        vertical: 14 * scale,
                      ),
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

    final result = await Navigator.of(
      context,
    ).push<T>(MaterialPageRoute(builder: (context) => page));

    if (!kIsWeb && wasSpecial && Platform.isWindows) {
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

  void _openUpcomingToolDialog(
    String title,
    String description,
    Color accentColor,
  ) {
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
                      Icon(
                        Icons.info_outline_rounded,
                        color: accentColor,
                        size: 18,
                      ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
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

  List<ScannedApp>? _dashboardScannedApps;

  List<LauncherSlot> _getProCustomSlots() {
    final slots = _settings.launcherSlots;
    final List<LauncherSlot> result = [];
    for (int i = 14; i <= 17; i++) {
      if (i < slots.length &&
          slots[i].type == LauncherSlotType.systemApp &&
          slots[i].name.isNotEmpty) {
        result.add(slots[i]);
      }
    }
    if (result.isEmpty) {
      for (final s in slots) {
        if (s.type == LauncherSlotType.systemApp && s.name.isNotEmpty) {
          result.add(s);
          if (result.length >= 4) break;
        }
      }
    }
    return result;
  }

  int _getProSlotIndex(int customIdx) {
    final slots = _settings.launcherSlots;
    int foundCount = 0;
    for (int i = 14; i <= 17; i++) {
      if (i < slots.length &&
          slots[i].type == LauncherSlotType.systemApp &&
          slots[i].name.isNotEmpty) {
        if (foundCount == customIdx) return i;
        foundCount++;
      }
    }
    return (14 + customIdx).clamp(14, 18);
  }

  int _getNextAvailableProSlotIndex() {
    final slots = _settings.launcherSlots;
    for (int i = 14; i <= 17; i++) {
      if (i >= slots.length ||
          slots[i].type == LauncherSlotType.empty ||
          slots[i].name.isEmpty) {
        return i;
      }
    }
    return 14;
  }

  void _showAddUrlAppDialog(int slotIndex) {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://');
    final scale = _settings.scaleFactor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0E17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
        title: Text(
          '🌐 웹 바로가기 추가',
          style: GoogleFonts.notoSansKr(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16 * scale,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '바로가기 이름 (예: Canva, EBS, 유튜브)',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '웹 주소 (URL)',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
            ),
            onPressed: () async {
              final name = titleCtrl.text.trim();
              var url = urlCtrl.text.trim();
              if (name.isEmpty || url.isEmpty) return;
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://$url';
              }

              final updatedSlots = List<LauncherSlot>.from(_settings.launcherSlots);
              while (updatedSlots.length <= slotIndex) {
                updatedSlots.add(LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''));
              }
              updatedSlots[slotIndex] = LauncherSlot(
                type: LauncherSlotType.systemApp,
                name: name,
                id: url,
                iconPath: null,
              );
              final newSettings = _settings.copyWith(launcherSlots: updatedSlots);
              await _storageService.saveSettings(newSettings);
              setState(() {
                _settings = newSettings;
              });

              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text(
              '등록',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _openAppSelectorForSlot(int slotIndex) {
    final scale = _settings.scaleFactor;
    bool isLoading = _dashboardScannedApps == null;
    List<ScannedApp> apps = _dashboardScannedApps ?? [];

    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            if (isLoading) {
              SystemAppScanner.scanInstalledApps().then((scanned) {
                if (context.mounted) {
                  setStateDialog(() {
                    apps = SystemAppScanner.externalAppsOnly(scanned);
                    _dashboardScannedApps = apps;
                    isLoading = false;
                  });
                }
              }).catchError((_) {
                if (context.mounted) {
                  setStateDialog(() {
                    isLoading = false;
                  });
                }
              });
            }

            final filteredApps = apps.where((app) {
              return app.name.toLowerCase().contains(
                    searchQuery.toLowerCase(),
                  ) ||
                  app.appId.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AlertDialog(
                backgroundColor: const Color(0xFF0F0E17).withOpacity(0.9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: const Color(0xFF2EC4B6).withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                titlePadding: EdgeInsets.fromLTRB(
                  24 * scale,
                  20 * scale,
                  20 * scale,
                  12 * scale,
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.apps_rounded,
                          color: Color(0xFF00F5D4),
                        ),
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
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white54,
                        size: 20 * scale,
                      ),
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
                          border: Border.all(
                            color: Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: TextField(
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontSize: 13 * scale,
                          ),
                          decoration: InputDecoration(
                            hintText: '프로그램 이름 검색...',
                            hintStyle: GoogleFonts.notoSansKr(
                              color: Colors.white24,
                              fontSize: 13 * scale,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Colors.white30,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 12 * scale,
                            ),
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
                        child: isLoading
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF00F5D4),
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                    SizedBox(height: 14 * scale),
                                    Text(
                                      '설치된 앱을 불러오는 중입니다...',
                                      style: GoogleFonts.notoSansKr(
                                        color: Colors.white70,
                                        fontSize: 12.5 * scale,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : filteredApps.isEmpty
                                ? Center(
                                    child: Text(
                                      searchQuery.isEmpty
                                          ? (kIsWeb
                                              ? '웹 브라우저에서는 하단의 "웹 주소(URL) 추가"를 이용해 주세요.'
                                              : '검색된 외부 앱이 없습니다.')
                                          : '검색 결과가 없습니다.',
                                      style: GoogleFonts.notoSansKr(
                                        color: Colors.white30,
                                        fontSize: 13 * scale,
                                      ),
                                    ),
                                  )
                            : ListView.separated(
                                physics: const BouncingScrollPhysics(),
                                itemCount: filteredApps.length,
                                separatorBuilder: (_, __) =>
                                    SizedBox(height: 8 * scale),
                                itemBuilder: (context, idx) {
                                  final app = filteredApps[idx];
                                  final hasIcon =
                                      app.iconPath != null &&
                                      app.iconPath!.isNotEmpty &&
                                      File(app.iconPath!).existsSync();

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () async {
                                        // Update the slot!
                                        final updatedSlots =
                                            List<LauncherSlot>.from(
                                              _settings.launcherSlots,
                                            );
                                        while (updatedSlots.length <= slotIndex) {
                                          updatedSlots.add(LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''));
                                        }
                                        updatedSlots[slotIndex] = LauncherSlot(
                                          type: LauncherSlotType.systemApp,
                                          name: app.name,
                                          id: app.appId,
                                          iconPath: app.iconPath,
                                        );

                                        final newSettings = _settings.copyWith(
                                          launcherSlots: updatedSlots,
                                        );
                                        await _storageService.saveSettings(
                                          newSettings,
                                        );
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
                                          color: Colors.white.withOpacity(
                                            0.015,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.03,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // Icon
                                            Container(
                                              width: 32 * scale,
                                              height: 32 * scale,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                  0.02,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      8 * scale,
                                                    ),
                                              ),
                                              child: hasIcon
                                                  ? ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8 * scale,
                                                          ),
                                                      child: Image.file(
                                                        File(app.iconPath!),
                                                        fit: BoxFit.contain,
                                                      ),
                                                    )
                                                  : Icon(
                                                      Icons
                                                          .insert_drive_file_rounded,
                                                      color: Colors.white30,
                                                      size: 16 * scale,
                                                    ),
                                            ),
                                            SizedBox(width: 14 * scale),
                                            // Name and AppId
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    app.name,
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          color: Colors.white
                                                              .withOpacity(0.9),
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 12 * scale,
                                                        ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  SizedBox(height: 2 * scale),
                                                  Text(
                                                    app.appId,
                                                    style: GoogleFonts.outfit(
                                                      color: Colors.white24,
                                                      fontSize: 9 * scale,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                actionsPadding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  20 * scale,
                  16 * scale,
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () {
                      _showAddUrlAppDialog(slotIndex);
                    },
                    icon: const Icon(
                      Icons.link_rounded,
                      color: Color(0xFF38BDF8),
                      size: 16,
                    ),
                    label: Text(
                      '웹 주소(URL) 추가',
                      style: GoogleFonts.notoSansKr(
                        color: const Color(0xFF38BDF8),
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!kIsWeb)
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          final result = await FilePicker.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['exe', 'lnk', 'bat', 'cmd', 'apk'],
                          );
                          if (result != null && result.files.single.path != null) {
                            final filePath = result.files.single.path!;
                            final fileName = p.basenameWithoutExtension(filePath);
                            
                            final updatedSlots = List<LauncherSlot>.from(_settings.launcherSlots);
                            while (updatedSlots.length <= slotIndex) {
                              updatedSlots.add(LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''));
                            }
                            updatedSlots[slotIndex] = LauncherSlot(
                              type: LauncherSlotType.systemApp,
                              name: fileName,
                              id: filePath,
                              iconPath: null,
                            );

                            final newSettings = _settings.copyWith(
                              launcherSlots: updatedSlots,
                            );
                            await _storageService.saveSettings(newSettings);
                            setState(() {
                              _settings = newSettings;
                            });

                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          }
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.folder_open_rounded, color: Color(0xFF00F5D4), size: 16),
                      label: Text(
                        '직접 파일(.exe/.apk/.lnk) 선택',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF00F5D4),
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '닫기',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white54,
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
          title: Text(
            '앱 바로가기 삭제',
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            '해당 슬롯의 바로가기 앱을 삭제하시겠습니까?',
            style: GoogleFonts.notoSansKr(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                '취소',
                style: GoogleFonts.notoSansKr(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                '삭제',
                style: GoogleFonts.notoSansKr(
                  color: const Color(0xFFEF4565),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final updatedSlots = List<LauncherSlot>.from(_settings.launcherSlots);
      while (updatedSlots.length <= slotIndex) {
        updatedSlots.add(LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''));
      }
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
  }

  Future<void> _launchSystemApp(SystemApp app) async {
    final appId = app.appId;
    if (appId.startsWith('http://') || appId.startsWith('https://')) {
      _launchURL(appId);
    } else {
      final success = await SystemAppScanner.launchApp(appId);
      if (!success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${app.name} 앱을 실행할 수 없습니다.')));
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
    final classroomId = _settings.classNickname.isNotEmpty
        ? _settings.classNickname
        : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';

    final period = _currentPeriod;
    final lesson = _currentLesson;
    final isBreakTime = period == null ||
        !period.isClass ||
        period.label.contains('쉬는') ||
        period.label.contains('점심') ||
        period.label.contains('아침') ||
        period.label.contains('방과후');

    // 쉬는시간 및 과목별 판서 연결:
    // 국어시간 판서 -> 다음 국어시간에 판서 들어가면 복원
    // 쉬는시간 판서 -> 쉬는시간에 들어가면 복원
    // Cloud 연동 시 Cloud Drive bst-pen 폴더 자동 실시간 동기화
    final String activeSubject = isBreakTime
        ? '쉬는시간'
        : (lesson != null && lesson.subject.isNotEmpty
            ? lesson.subject
            : (period != null && period.label.isNotEmpty ? period.label : '수업'));

    final teacher = BstCloudService.instance.activeTeacherName ?? lesson?.teacher ?? '선생님';
    final isCloud = BstCloudService.instance.activeToken != null;

    final targetPath = await BoardStorageService.instance.resolveSubjectBoardPath(
      classroomId: classroomId,
      subject: activeSubject,
      isCloud: isCloud,
    );

    _pushBoardRoute(
      BoardestPenView(
        filePath: targetPath,
        scaleFactor: _settings.scaleFactor,
        teacher: teacher,
        subject: activeSubject,
      ),
    );
  }

  /// 교사별 화이트보드 관리 다이얼로그 (Cloud 사용 교사는 제외하고 로컬 저장 교사들만 관리)
  Future<void> _openTeacherWhiteboardManagerDialog() async {
    final s = _settings.scaleFactor;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * s)),
          child: Container(
            width: 720 * s,
            height: 540 * s,
            padding: EdgeInsets.all(24 * s),
            child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
              future: BoardStorageService.instance.listAllLocalTeachersWithBoards(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0)));
                }

                final teacherMap = snapshot.data!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded, color: Color(0xFF00F5D4), size: 22),
                        const SizedBox(width: 10),
                        Text(
                          '교사별 로컬 화이트보드 관리',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontSize: 16 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF242629), height: 20),

                    // 안내 배너
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF242629),
                        borderRadius: BorderRadius.circular(8 * s),
                      ),
                      child: Text(
                        '💡 시간표 기준 교사가 화이트보드를 누르면 해당 교사의 최근 판서가 자동 로드됩니다. (Cloud 연동 교사 제외)',
                        style: TextStyle(color: Colors.white70, fontSize: 11 * s),
                      ),
                    ),
                    SizedBox(height: 12 * s),

                    // 교사별 판서 목록
                    Expanded(
                      child: teacherMap.isEmpty
                          ? Center(
                              child: Text(
                                '로컬에 저장된 교사별 판서가 없습니다.',
                                style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 13 * s),
                              ),
                            )
                          : ListView.builder(
                              itemCount: teacherMap.length,
                              itemBuilder: (context, idx) {
                                final teacher = teacherMap.keys.elementAt(idx);
                                final boards = teacherMap[teacher]!;

                                return Container(
                                  margin: EdgeInsets.only(bottom: 12 * s),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F0E17),
                                    borderRadius: BorderRadius.circular(12 * s),
                                    border: Border.all(color: const Color(0xFF242629)),
                                  ),
                                  child: ExpansionTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFF7F5AF0).withOpacity(0.2),
                                      child: Text(
                                        teacher.isNotEmpty ? teacher[0] : '교',
                                        style: const TextStyle(color: Color(0xFF00F5D4), fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      '$teacher 선생님 (총 ${boards.length}개 판서)',
                                      style: GoogleFonts.notoSansKr(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13 * s,
                                      ),
                                    ),
                                    children: [
                                      ...boards.map((b) {
                                        final fileName = b['fileName'] as String;
                                        final fullPath = b['fullPath'] as String;
                                        final modTime = b['modifiedTime'] as DateTime;
                                        final timeStr = '${modTime.month}/${modTime.day} ${modTime.hour.toString().padLeft(2, '0')}:${modTime.minute.toString().padLeft(2, '0')}';

                                        return ListTile(
                                          dense: true,
                                          title: Text(fileName, style: TextStyle(color: Colors.white, fontSize: 12 * s)),
                                          subtitle: Text('수정시각: $timeStr', style: TextStyle(color: Colors.white54, fontSize: 10 * s)),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF2CB67D),
                                                  padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
                                                ),
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  _pushBoardRoute(
                                                    BoardestPenView(
                                                      filePath: fullPath,
                                                      scaleFactor: _settings.scaleFactor,
                                                      teacher: teacher,
                                                      subject: '판서',
                                                    ),
                                                  );
                                                },
                                                child: const Text('열기', style: TextStyle(color: Colors.white, fontSize: 11)),
                                              ),
                                              SizedBox(width: 6 * s),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                                onPressed: () async {
                                                  await BoardStorageService.instance.deleteBoardByPath(fullPath);
                                                  setModalState(() {});
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
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
        ),
      ),
    );
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

  void _openBstCloud() {
    if (BstCloudService.isCloudFeatureDisabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '클라우드 기능이 일시 비활성화되었습니다. 수업 자료는 USB를 연결하여 이용해 주세요.',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12 * _settings.scaleFactor),
            side: const BorderSide(color: Color(0xFF2EC4B6), width: 1.5),
          ),
          margin: const EdgeInsets.all(20),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => BstCloudModal(scaleFactor: _settings.scaleFactor),
    ).then((_) {
      if (mounted) {
        setState(() {
          _refreshCloudFiles();
        });
      }
    });
  }

  void _openPluginStore() {
    showDialog(
      context: context,
      builder: (context) => PluginStoreView(
        scaleFactor: _settings.scaleFactor,
        onLaunchPlugin: (id, name) {
          setState(() {
            _activePluginId = id;
            _activePluginName = name;
          });
        },
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
    showDialog(context: context, builder: (context) => const NoiseMeterModal());
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
    final String timeText =
        '${(_timerSecondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_timerSecondsElapsed % 60).toString().padLeft(2, '0')}';
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
                    color:
                        (_timerRunning ? accentColor : const Color(0xFFEF4565))
                            .withValues(alpha: 0.025),
                    boxShadow: _timerRunning
                        ? [
                            BoxShadow(
                              color: accentColor.withOpacity(0.04),
                              blurRadius: 150 * scale,
                              spreadRadius: 10 * scale,
                            ),
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
                        color: isZero && isCountdown
                            ? const Color(0xFFEF4565)
                            : accentColor,
                        letterSpacing: 6,
                        shadows: [
                          Shadow(
                            color:
                                (isZero && isCountdown
                                        ? const Color(0xFFEF4565)
                                        : accentColor)
                                    .withOpacity(0.8),
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
                          onPressed: _timerRunning
                              ? _pauseMiniTimer
                              : _startMiniTimer,
                          icon: Icon(
                            _timerRunning
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 28 * scale,
                          ),
                          label: Text(
                            _timerRunning ? '일시정지' : '시작',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 20 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _timerRunning
                                ? Colors.orangeAccent
                                : const Color(0xFF2EC4B6),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 40 * scale,
                              vertical: 18 * scale,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        SizedBox(width: 20 * scale),
                        ElevatedButton.icon(
                          onPressed: _resetMiniTimer,
                          icon: Icon(Icons.replay_rounded, size: 28 * scale),
                          label: Text(
                            '초기화',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 20 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4565),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 40 * scale,
                              vertical: 18 * scale,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 40 * scale),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildBigPresetBtn(
                          '+1분',
                          () => _adjustMiniTimer(60),
                          scale,
                        ),
                        _buildBigPresetBtn(
                          '+3분',
                          () => _adjustMiniTimer(180),
                          scale,
                        ),
                        _buildBigPresetBtn(
                          '+5분',
                          () => _adjustMiniTimer(300),
                          scale,
                        ),
                        _buildBigPresetBtn(
                          '+10분',
                          () => _adjustMiniTimer(600),
                          scale,
                        ),
                        _buildBigPresetBtn(
                          'Clear',
                          () {
                            setState(() {
                              _timerTargetSeconds = 0;
                              _timerSecondsElapsed = 0;
                              _timerRunning = false;
                              _miniTimerInstance?.cancel();
                            });
                          },
                          scale,
                          isClear: true,
                        ),
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
                      icon: Icon(
                        Icons.fullscreen_exit_rounded,
                        color: Colors.white70,
                        size: 36 * scale,
                      ),
                      onPressed: () {
                        setState(() {
                          _timerFullscreen = false;
                        });
                      },
                      tooltip: '전체화면 종료',
                    ),
                    SizedBox(width: 10 * scale),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: const Color(0xFFEF4565),
                        size: 36 * scale,
                      ),
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
              ),
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
                            Icons.timer_rounded,
                            color: accentColor,
                            size: 14 * scale,
                          ),
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
                            icon: Icon(
                              Icons.fullscreen_rounded,
                              color: Colors.white60,
                              size: 14 * scale,
                            ),
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
                            icon: Icon(
                              Icons.close_rounded,
                              color: const Color(0xFFEF4565),
                              size: 14 * scale,
                            ),
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
                              color: isZero && isCountdown
                                  ? const Color(0xFFEF4565)
                                  : accentColor,
                              shadows: [
                                Shadow(
                                  color:
                                      (isZero && isCountdown
                                              ? const Color(0xFFEF4565)
                                              : accentColor)
                                          .withOpacity(0.5),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 6 * scale),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildMiniPresetBtn(
                                '+1m',
                                () => _adjustMiniTimer(60),
                                scale,
                              ),
                              _buildMiniPresetBtn(
                                '+3m',
                                () => _adjustMiniTimer(180),
                                scale,
                              ),
                              _buildMiniPresetBtn(
                                '+5m',
                                () => _adjustMiniTimer(300),
                                scale,
                              ),
                              _buildMiniPresetBtn(
                                'Reset',
                                () {
                                  setState(() {
                                    _timerTargetSeconds = 0;
                                    _timerSecondsElapsed = 0;
                                    _timerRunning = false;
                                    _miniTimerInstance?.cancel();
                                  });
                                },
                                scale,
                                isClear: true,
                              ),
                            ],
                          ),
                          SizedBox(height: 10 * scale),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: _timerRunning
                                    ? _pauseMiniTimer
                                    : _startMiniTimer,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _timerRunning
                                      ? Colors.orangeAccent
                                      : const Color(0xFF2EC4B6),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16 * scale,
                                    vertical: 8 * scale,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  _timerRunning ? '일시정지' : '시작',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 10 * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8 * scale),
                              ElevatedButton(
                                onPressed: _resetMiniTimer,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4565),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16 * scale,
                                    vertical: 8 * scale,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  '초기화',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 10 * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
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

  Widget _buildMiniPresetBtn(
    String label,
    VoidCallback onTap,
    double scale, {
    bool isClear = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 8 * scale,
          vertical: 4 * scale,
        ),
        decoration: BoxDecoration(
          color: isClear
              ? const Color(0xFFEF4565).withOpacity(0.12)
              : const Color(0xFF00F5D4).withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isClear
                ? const Color(0xFFEF4565).withOpacity(0.3)
                : const Color(0xFF00F5D4).withOpacity(0.3),
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

  Widget _buildBigPresetBtn(
    String label,
    VoidCallback onTap,
    double scale, {
    bool isClear = false,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8 * scale),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isClear
              ? const Color(0xFFEF4565).withOpacity(0.15)
              : const Color(0xFF00F5D4).withOpacity(0.1),
          foregroundColor: isClear
              ? const Color(0xFFEF4565)
              : const Color(0xFF00F5D4),
          padding: EdgeInsets.symmetric(
            horizontal: 30 * scale,
            vertical: 14 * scale,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isClear
                  ? const Color(0xFFEF4565).withOpacity(0.4)
                  : const Color(0xFF00F5D4).withOpacity(0.4),
              width: 1.5,
            ),
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

  Widget _buildMiniCalendarWindow(double scale) {
    final accentColor = const Color(0xFF00F5D4);
    final firstDay = DateTime(
      _miniCalendarMonth.year,
      _miniCalendarMonth.month,
      1,
    );
    final lastDay = DateTime(
      _miniCalendarMonth.year,
      _miniCalendarMonth.month + 1,
      0,
    );
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
          if (date.year == day.year &&
              date.month == day.month &&
              date.day == day.day) {
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
                            _showWeeklyTimetableInCalendar
                                ? Icons.view_week_rounded
                                : Icons.calendar_month_rounded,
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
                              _showWeeklyTimetableInCalendar
                                  ? Icons.calendar_month_rounded
                                  : Icons.view_week_rounded,
                              color: accentColor,
                              size: 16 * scale,
                            ),
                            tooltip: _showWeeklyTimetableInCalendar
                                ? '학사달력 보기'
                                : '주간 시간표 보기',
                            onPressed: () {
                              setState(() {
                                _showWeeklyTimetableInCalendar =
                                    !_showWeeklyTimetableInCalendar;
                              });
                            },
                          ),
                          SizedBox(width: 4 * scale),
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                    ...['월', '화', '수', '목', '금'].map(
                                      (dayName) => Expanded(
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
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6 * scale),
                                ...List.generate(7, (periodIdx) {
                                  final period = periodIdx + 1;
                                  return Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 3 * scale,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 26 * scale,
                                          height: 32 * scale,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.04,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
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
                                          final dayLessons = _getLessonsForDay(
                                            weekday,
                                          );
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
                                          final hasLesson =
                                              lesson.subject.isNotEmpty;
                                          return Expanded(
                                            child: Container(
                                              height: 32 * scale,
                                              margin: EdgeInsets.symmetric(
                                                horizontal: 2 * scale,
                                              ),
                                              decoration: BoxDecoration(
                                                color: hasLesson
                                                    ? accentColor.withOpacity(
                                                        0.06,
                                                      )
                                                    : Colors.white.withOpacity(
                                                        0.01,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: hasLesson
                                                      ? accentColor.withOpacity(
                                                          0.15,
                                                        )
                                                      : Colors.white
                                                            .withOpacity(0.03),
                                                  width: 0.8,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: hasLesson
                                                  ? Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          lesson.subject,
                                                          style:
                                                              GoogleFonts.notoSansKr(
                                                                color: Colors
                                                                    .white
                                                                    .withOpacity(
                                                                      0.95,
                                                                    ),
                                                                fontSize:
                                                                    9 * scale,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        if (lesson
                                                            .classroom
                                                            .isNotEmpty)
                                                          Text(
                                                            lesson.classroom,
                                                            style: GoogleFonts.notoSansKr(
                                                              color:
                                                                  const Color(
                                                                    0xFF2CB67D,
                                                                  ).withOpacity(
                                                                    0.8,
                                                                  ),
                                                              fontSize:
                                                                  7 * scale,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        Icons.chevron_left_rounded,
                                        color: Colors.white70,
                                        size: 20 * scale,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _miniCalendarMonth = DateTime(
                                            _miniCalendarMonth.year,
                                            _miniCalendarMonth.month - 1,
                                            1,
                                          );
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
                                      icon: Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.white70,
                                        size: 20 * scale,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _miniCalendarMonth = DateTime(
                                            _miniCalendarMonth.year,
                                            _miniCalendarMonth.month + 1,
                                            1,
                                          );
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8 * scale),
                                Row(
                                  children: weekDays.asMap().entries.map((
                                    entry,
                                  ) {
                                    final idx = entry.key;
                                    final dayName = entry.value;
                                    Color textColor = Colors.white54;
                                    if (idx == 0)
                                      textColor = const Color(0xFFEF4565);
                                    if (idx == 6)
                                      textColor = const Color(0xFF00F5D4);
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
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 7,
                                        childAspectRatio: 1.15,
                                        crossAxisSpacing: 3,
                                        mainAxisSpacing: 3,
                                      ),
                                  itemCount: totalCells,
                                  itemBuilder: (context, index) {
                                    final dayNum = index - startWeekday + 1;
                                    final isCurrentMonth =
                                        dayNum > 0 && dayNum <= daysCount;
                                    if (!isCurrentMonth)
                                      return const SizedBox.shrink();
                                    final cellDate = DateTime(
                                      _miniCalendarMonth.year,
                                      _miniCalendarMonth.month,
                                      dayNum,
                                    );
                                    final dayEvents = getEventsForDay(cellDate);
                                    final hasEvents = dayEvents.isNotEmpty;
                                    final isToday =
                                        DateTime.now().year == cellDate.year &&
                                        DateTime.now().month ==
                                            cellDate.month &&
                                        DateTime.now().day == cellDate.day;
                                    final weekdayIdx = index % 7;
                                    Color dayColor = Colors.white;
                                    if (weekdayIdx == 0)
                                      dayColor = const Color(0xFFEF4565);
                                    if (weekdayIdx == 6)
                                      dayColor = const Color(0xFF00F5D4);
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: isToday
                                            ? const Color(
                                                0xFF2EC4B6,
                                              ).withOpacity(0.18)
                                            : Colors.white.withOpacity(0.02),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isToday
                                              ? const Color(0xFF2EC4B6)
                                              : Colors.white.withOpacity(0.04),
                                          width: isToday ? 1.2 : 1,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$dayNum',
                                            style: GoogleFonts.outfit(
                                              color: isToday
                                                  ? Colors.white
                                                  : dayColor.withOpacity(0.8),
                                              fontSize: 9 * scale,
                                              fontWeight: isToday
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (hasEvents)
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF7F5AF0,
                                                ).withOpacity(0.85),
                                                borderRadius:
                                                    BorderRadius.circular(3),
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
                            Icons.apps_rounded,
                            color: accentColor,
                            size: 14 * scale,
                          ),
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
                            icon: Icon(
                              Icons.close_rounded,
                              color: const Color(0xFFEF4565),
                              size: 14 * scale,
                            ),
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF00F5D4),
                                ),
                              ),
                            )
                          : StatefulBuilder(
                              builder: (context, setDrawerState) {
                                final allApps =
                                    SystemAppScanner.externalAppsOnly(
                                      _cachedAppsList ?? [],
                                    );
                                final filtered = allApps
                                    .where(
                                      (app) => app.name.toLowerCase().contains(
                                        _appDrawerQuery.toLowerCase(),
                                      ),
                                    )
                                    .toList();

                                return Column(
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        12 * scale,
                                        12 * scale,
                                        12 * scale,
                                        8 * scale,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.04),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.08,
                                            ),
                                          ),
                                        ),
                                        child: TextField(
                                          style: GoogleFonts.notoSansKr(
                                            color: Colors.white,
                                            fontSize: 11 * scale,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: '앱 이름 검색...',
                                            hintStyle: GoogleFonts.notoSansKr(
                                              color: Colors.white38,
                                              fontSize: 11 * scale,
                                            ),
                                            prefixIcon: Icon(
                                              Icons.search_rounded,
                                              color: Colors.white38,
                                              size: 14 * scale,
                                            ),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  vertical: 8 * scale,
                                                ),
                                          ),
                                          controller:
                                              _appDrawerSearchController,
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
                                                style: GoogleFonts.notoSansKr(
                                                  color: Colors.white38,
                                                  fontSize: 12 * scale,
                                                ),
                                              ),
                                            )
                                          : GridView.builder(
                                              padding: EdgeInsets.all(
                                                12 * scale,
                                              ),
                                              gridDelegate:
                                                  SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: 4,
                                                    childAspectRatio: 0.95,
                                                    crossAxisSpacing: 8 * scale,
                                                    mainAxisSpacing: 8 * scale,
                                                  ),
                                              itemCount: filtered.length,
                                              itemBuilder: (context, idx) {
                                                final app = filtered[idx];
                                                final isBoardest = app.appId
                                                    .startsWith('boardest://');
                                                final avatar =
                                                    app.name.length >= 2
                                                    ? app.name.substring(0, 2)
                                                    : app.name;

                                                return Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    onTap: () {
                                                      setState(() {
                                                        _showMiniAppDrawer =
                                                            false;
                                                      });
                                                      if (isBoardest) {
                                                        final toolId = app.appId
                                                            .replaceFirst(
                                                              'boardest://',
                                                              '',
                                                            );
                                                        if (toolId != 'main') {
                                                          _getToolOnTap(
                                                            toolId,
                                                          )();
                                                        }
                                                      } else {
                                                        SystemAppScanner.launchApp(
                                                          app.appId,
                                                        );
                                                      }
                                                    },
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Container(
                                                          width: 32 * scale,
                                                          height: 32 * scale,
                                                          decoration:
                                                              BoxDecoration(
                                                                color: Colors
                                                                    .white
                                                                    .withOpacity(
                                                                      0.05,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                          alignment:
                                                              Alignment.center,
                                                          child:
                                                              app.hasIcon &&
                                                                  app.iconPath !=
                                                                      null
                                                              ? Image.file(
                                                                  File(
                                                                    app.iconPath!,
                                                                  ),
                                                                  key: ValueKey(
                                                                    app.iconPath,
                                                                  ),
                                                                  width:
                                                                      18 *
                                                                      scale,
                                                                  height:
                                                                      18 *
                                                                      scale,
                                                                )
                                                              : Text(
                                                                  avatar,
                                                                  style: GoogleFonts.notoSansKr(
                                                                    color:
                                                                        accentColor,
                                                                    fontSize:
                                                                        9 *
                                                                        scale,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                        ),
                                                        SizedBox(
                                                          height: 4 * scale,
                                                        ),
                                                        Text(
                                                          app.name,
                                                          style:
                                                              GoogleFonts.notoSansKr(
                                                                color: Colors
                                                                    .white70,
                                                                fontSize:
                                                                    8 * scale,
                                                              ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          textAlign:
                                                              TextAlign.center,
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
    showDialog(context: context, builder: (context) => const NotepadModal());
  }

  // ── 교실에서 교사/교무실로 쪽지 발송 다이얼로그 ──
  void _openSendMessageToTeacherDialog() {
    final scale = MediaQuery.of(context).size.width / 1920.0;
    final textCtrl = TextEditingController();
    String target = '교무실 (전체 선생님)';
    final recentTeacher = MealCallService.instance.lastSenderName;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 24 * scale),
          child: Container(
            width: 480 * scale,
            padding: EdgeInsets.all(24 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(20 * scale),
              border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 30,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7F5AF0).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10 * scale),
                      ),
                      child: Icon(Icons.send_rounded, color: const Color(0xFF7F5AF0), size: 24 * scale),
                    ),
                    SizedBox(width: 12 * scale),
                    Text(
                      '선생님께 쪽지 보내기',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                SizedBox(height: 16 * scale),
                Text(
                  '수신 대상',
                  style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12 * scale, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6 * scale),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10 * scale),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: target,
                      dropdownColor: const Color(0xFF242629),
                      isExpanded: true,
                      style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                      items: [
                        '교무실 (전체 선생님)',
                        if (recentTeacher != null && recentTeacher.isNotEmpty) recentTeacher,
                      ].toSet().map((name) {
                        return DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => target = val);
                      },
                    ),
                  ),
                ),
                SizedBox(height: 16 * scale),
                Text(
                  '쪽지 내용',
                  style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12 * scale, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6 * scale),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12 * scale),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: textCtrl,
                    maxLines: 3,
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                    decoration: InputDecoration(
                      hintText: '선생님께 전달할 메시지를 입력하세요...',
                      hintStyle: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * scale),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                SizedBox(height: 24 * scale),
                SizedBox(
                  height: 48 * scale,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7F5AF0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                    ),
                    onPressed: () async {
                      final msg = textCtrl.text.trim();
                      if (msg.isEmpty) return;
                      Navigator.pop(ctx);

                      final clName = _settings.classNickname.isNotEmpty
                          ? _settings.classNickname
                          : '${_settings.selectedGrade}학년 ${_settings.selectedClass}반';
                      final docId = MealCallService.instance.documentId;
                      final sCode = _settings.selectedSchool?.code?.toString() ?? '';
                      final schoolCode = sCode.isNotEmpty
                          ? sCode
                          : (_settings.schoolId.isNotEmpty ? _settings.schoolId : 'ydm');
                      final nowMs = DateTime.now().millisecondsSinceEpoch;
                      final msgId = 'msg_$nowMs';
                      final nowIso = DateTime.now().toIso8601String();

                      try {
                        final rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com';
                        // 1. teacher_inbox에 기록 (모든 교사 앱 실시간 감지)
                        await http.put(
                          Uri.parse('$rtdbBase/teacher_inbox/$schoolCode/messages/$msgId.json'),
                          headers: {"Content-Type": "application/json"},
                          body: json.encode({
                            'messageId': msgId,
                            'targetTeacher': target,
                            'senderClass': clName,
                            'senderDocId': docId,
                            'text': msg,
                            'sentAt': nowIso,
                            'response': null,
                          }),
                        ).timeout(const Duration(seconds: 4));

                        // demo 경로 동기화
                        try {
                          await http.put(
                            Uri.parse('$rtdbBase/teacher_inbox/demo/messages/$msgId.json'),
                            headers: {"Content-Type": "application/json"},
                            body: json.encode({
                              'messageId': msgId,
                              'targetTeacher': target,
                              'senderClass': clName,
                              'senderDocId': docId,
                              'text': msg,
                              'sentAt': nowIso,
                            }),
                          ).timeout(const Duration(seconds: 2));
                        } catch (_) {}

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('🎉 [$target]으로 쪽지가 전송되었습니다!'),
                              backgroundColor: const Color(0xFF7F5AF0),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('쪽지 전송에 실패했습니다. 네트워크를 확인하세요.'),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                        }
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 18 * scale, color: Colors.white),
                        SizedBox(width: 8 * scale),
                        Text('전송하기', style: GoogleFonts.notoSansKr(fontSize: 15 * scale, fontWeight: FontWeight.bold)),
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

  void _openFileExplorer() {
    if (kIsWeb) return;
    if (Platform.isWindows) {
      final defaultPath = Platform.environment['USERPROFILE'] != null
          ? '${Platform.environment['USERPROFILE']}\\Documents'
          : 'C:\\';
      final targetPath = _isUsbConnected && _usbDriveLetter.isNotEmpty
          ? _usbDriveLetter
          : defaultPath;
      Process.run('explorer.exe', [targetPath]);
    }
  }

  Future<void> _openPptBoard() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'pptx', 'ppt', 'tbp', 'bsttbp', 'TBP', 'bstTBP', 'iwb'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!mounted) return;
        final ext = p.extension(path).toLowerCase();

        if (ext == '.tbp' || ext == '.bsttbp') {
          _pushBoardRoute(
            TbpViewerRoute(
              tbpFilePath: path,
              scaleFactor: _settings.scaleFactor,
            ),
          );
          return;
        }

        if (ext == '.pptx' || ext == '.ppt') {
          if (kIsWeb || !Platform.isWindows) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PPT 판서는 Windows에서만 지원됩니다.')),
            );
            return;
          }
          _pushBoardRoute(
            PptOverlayView(
              initialFilePath: path,
              scaleFactor: _settings.scaleFactor,
              fullscreen: widget.pptFullscreen,
            ),
          );
          return;
        }

        if (ext == '.pdf') {
          _pushBoardRoute(
            PdfBoardView(
              initialFilePath: path,
              scaleFactor: _settings.scaleFactor,
            ),
          );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('파일을 열 수 없습니다: $e')));
    }
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
        if (kIsWeb || !Platform.isWindows) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PPT 판서는 Windows에서만 지원됩니다.')),
          );
          return;
        }
        _pushBoardRoute(
          PptOverlayView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
            fullscreen: widget.pptFullscreen,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PPT 파일을 열 수 없습니다: $e')));
    }
  }

  Future<void> _openPdfBoard() async {
    if (kIsWeb) {
      _openBstCloud();
      return;
    }
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!mounted) return;
        _pushBoardRoute(
          PdfBoardView(
            initialFilePath: path,
            scaleFactor: _settings.scaleFactor,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF 파일을 열 수 없습니다: $e')));
    }
  }

  Future<void> _openDocumentBoard() async {
    if (kIsWeb) {
      _openBstCloud();
      return;
    }
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: (!kIsWeb && Platform.isAndroid)
            ? ['pdf']
            : ['pdf', 'pptx', 'ppt', 'iwb'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final ext = path.split('.').last.toLowerCase();
        if (!mounted) return;
        if (ext == 'pdf') {
          _pushBoardRoute(
            PdfBoardView(
              initialFilePath: path,
              scaleFactor: _settings.scaleFactor,
            ),
          );
        } else if (ext == 'pptx' || ext == 'ppt') {
          if (!kIsWeb && Platform.isAndroid) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Android에서는 PPT 판서를 지원하지 않습니다. PDF만 사용해 주세요.'),
              ),
            );
            return;
          }
          _pushBoardRoute(
            PptOverlayView(
              initialFilePath: path,
              scaleFactor: _settings.scaleFactor,
              fullscreen: widget.pptFullscreen,
            ),
          );
        } else {
          _pushBoardRoute(
            BoardestPenView(filePath: path, scaleFactor: _settings.scaleFactor),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('문서를 열 수 없습니다: $e')));
    }
  }

  void _openWebsiteBoard() {
    _pushBoardRoute(WebsiteBoardView(scaleFactor: _settings.scaleFactor));
  }

  void _openYoutubeBoard({String? url, String? filePath}) {
    _pushBoardRoute(
      VideoCollectionBoardView(scaleFactor: _settings.scaleFactor),
    );
  }

  void _openCanvaBoard({String? url, String? filePath}) {
    if (filePath != null && filePath.isNotEmpty) {
      _pushBoardRoute(HtmlPresentView(filePath: filePath, scaleFactor: _settings.scaleFactor));
      return;
    }
    final controller = TextEditingController(text: url ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('프레젠테이션/웹 URL 입력 (.HTMLP)', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: GoogleFonts.notoSansKr(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Canva, Google Slides, 미리캔버스, YouTube, URL...',
            hintStyle: GoogleFonts.notoSansKr(color: Colors.white38),
            enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF7F5AF0)), borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00F5D4), width: 2), borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0)),
            onPressed: () {
              final targetUrl = controller.text.trim();
              Navigator.pop(ctx);
              if (targetUrl.isNotEmpty) {
                _pushBoardRoute(HtmlPresentView(initialUrl: targetUrl, scaleFactor: _settings.scaleFactor));
              }
            },
            child: Text('열기', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}