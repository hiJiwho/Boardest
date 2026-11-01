import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/tbp_metadata.dart';
import '../../models/board_tools.dart';
import '../../services/tbp/tbp_storage_service.dart';
import '../../services/tbp/tbp_dhash_engine.dart';
import '../../services/tbp/tbp_download_interceptor.dart';
import '../../widgets/annotation_canvas.dart';
import '../../helpers/iframe_view_helper.dart';
import 'tbp_hotspot_overlay.dart';

enum TbpViewerMode { tbp, htmlp }

/// TextBook Plus (TBP) 단일 스마트교과서 뷰어
/// - hijiwho/boardbook 동일 구조 dHash 페이지 추적 및 판서 자동 교체
/// - Windows: webview_windows, Android: webview_flutter
/// - Pen / Touch / Smart 3모드 입력 시스템
class TbpViewerRoute extends StatefulWidget {
  final String? tbpFilePath;
  final String? filePath;
  final String? initialUrl;
  final String? embedUrl;
  final String? title;
  final double scaleFactor;
  final TbpViewerMode mode;

  const TbpViewerRoute({
    super.key,
    this.tbpFilePath,
    this.filePath,
    this.initialUrl,
    this.embedUrl,
    this.title,
    this.scaleFactor = 1.0,
    this.mode = TbpViewerMode.tbp,
  });

  @override
  State<TbpViewerRoute> createState() => _TbpViewerRouteState();
}

class _TbpViewerRouteState extends State<TbpViewerRoute> {
  TbpMetadata? _metadata;
  Map<String, dynamic>? _infoJson;
  String _tbpFolderPath = '';
  bool _isLoading = true;
  String? _errorMessage;

  String _currentDhash = 'default';
  List<Map<String, dynamic>> _currentHotspots = [];

  late final TbpDhashEngine _dhashEngine;

  final WebviewController _winWebview = WebviewController();
  late final WebViewController _androidWebview;
  bool _winWebviewInitialized = false;

  // ─── 입력 모드 ──────────────────────────────────────────
  TbpInputMode _inputMode = TbpInputMode.pen;

  String _selectedClass = '기본';
  List<String> _availableClasses = ['기본', '1반', '2반', '3반'];

  // 0ms 즉시 복원 인메모리 판서 캐시 (키: '$classId::$dHash')
  final Map<String, List<AnnotationStroke>> _pageStrokesMemory = {};

  // 1536px 네이티브 벡터 선명도 줌 팩터 관리
  double _lastAppliedZoom = -1.0;
  double _lastContainerWidth = 0.0;

  void _applyNativeZoom(double width) {
    if (kIsWeb || !Platform.isWindows || !_winWebviewInitialized || width <= 0) return;
    _lastContainerWidth = width;
    final targetZoom = width / 1536.0;
    if ((_lastAppliedZoom - targetZoom).abs() > 0.005) {
      _lastAppliedZoom = targetZoom;
      _winWebview.setZoomFactor(targetZoom);
    }
  }

  // ─── 판서 ───────────────────────────────────────────────
  final AnnotationController _annotationController = AnnotationController();
  ToolMode _tool = ToolMode.pen;
  Color _penColor = const Color(0xFF00F5D4);
  double _strokeWidth = 4.0;
  bool _eraseEntireStroke = false;
  double _eraserSize = 30.0;
  bool _showPenSettings = false;
  bool _isHighlighter = false;
  bool _isToolbarCollapsed = false;
  bool _isLaser = false;
  Offset? _laserPosition;
  Timer? _laserFadeTimer;
  String _pageFeedback = '';
  Timer? _feedbackTimer;

  // ─── Smart 모드 꾹 누르기 상태 ──────────────────────────
  bool _longPressActive = false;
  final Duration _longPressDuration = const Duration(milliseconds: 500);
  Timer? _longPressTimer;

  final FocusNode _keyboardFocus = FocusNode();

  bool _isSwitchingPage = false;
  String _targetUrl = '';
  String _resolvedTitle = '';

  void _onStrokesChanged() {
    if (_isSwitchingPage) return;
    final memKey = '$_selectedClass::$_currentDhash';
    final snapshot = List<AnnotationStroke>.from(_annotationController.strokes);
    _pageStrokesMemory[memKey] = snapshot;
    if (_tbpFolderPath.isNotEmpty && _currentDhash.isNotEmpty) {
      unawaited(
        TbpStorageService.instance.savePenStrokes(
          _tbpFolderPath,
          _currentDhash,
          snapshot,
          classId: _selectedClass,
        ),
      );
    }
  }

  Future<void> _loadAvailableClasses() async {
    if (_tbpFolderPath.isNotEmpty) {
      final list = await TbpStorageService.instance.getAvailableClasses(_tbpFolderPath);
      if (mounted) {
        setState(() {
          final merged = <String>{'기본', ..._availableClasses, ...list};
          _availableClasses = merged.toList();
          if (!_availableClasses.contains(_selectedClass) && _availableClasses.isNotEmpty) {
            _selectedClass = _availableClasses.first;
          }
        });
      }
    }
  }

  Future<void> _switchClass(String newClass) async {
    if (_selectedClass == newClass) return;
    _isSwitchingPage = true;
    try {
      final oldKey = '$_selectedClass::$_currentDhash';
      final currentStrokes = List<AnnotationStroke>.from(_annotationController.strokes);
      _pageStrokesMemory[oldKey] = currentStrokes;
      if (_tbpFolderPath.isNotEmpty && _currentDhash.isNotEmpty) {
        unawaited(
          TbpStorageService.instance.savePenStrokes(
            _tbpFolderPath,
            _currentDhash,
            currentStrokes,
            classId: _selectedClass,
          ),
        );
      }
      setState(() {
        _selectedClass = newClass;
        if (!_availableClasses.contains(newClass)) {
          _availableClasses.add(newClass);
        }
      });
      final newKey = '$newClass::$_currentDhash';
      List<AnnotationStroke> strokes;
      if (_pageStrokesMemory.containsKey(newKey)) {
        strokes = List<AnnotationStroke>.from(_pageStrokesMemory[newKey]!);
      } else {
        strokes = await TbpStorageService.instance.loadPenStrokes(
          _tbpFolderPath,
          _currentDhash,
          classId: newClass,
        );
        _pageStrokesMemory[newKey] = List<AnnotationStroke>.from(strokes);
      }
      if (mounted) {
        _annotationController.setStrokes(strokes);
        _showFeedback('🏫 [$newClass] 학급 판서로 전환 (핫스팟 유지)');
      }
    } finally {
      _isSwitchingPage = false;
    }
  }

  Widget _buildClassSelector(double s) {
    final activeVal = _availableClasses.contains(_selectedClass)
        ? _selectedClass
        : (_availableClasses.isNotEmpty ? _availableClasses.first : '기본');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF24262E),
        borderRadius: BorderRadius.circular(8 * s),
        border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: activeVal,
          dropdownColor: const Color(0xFF16161A),
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00F5D4), size: 18),
          style: GoogleFonts.notoSansKr(
            color: const Color(0xFF00F5D4),
            fontSize: 12 * s,
            fontWeight: FontWeight.bold,
          ),
          onChanged: (val) {
            if (val == '__new__') {
              _promptNewClass();
            } else if (val != null) {
              _switchClass(val);
            }
          },
          items: [
            ..._availableClasses.map((c) => DropdownMenuItem(
              value: c,
              child: Text('🏫 $c'),
            )),
            const DropdownMenuItem(
              value: '__new__',
              child: Text('➕ 새 학급 추가...', style: TextStyle(color: Color(0xFFFFD166))),
            ),
          ],
        ),
      ),
    );
  }

  void _promptNewClass() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text('새 학급 추가', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '예: 4반, 특별반',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4)),
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                _switchClass(text);
              }
            },
            child: const Text('추가', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAvailableClasses();
    if (!kIsWeb && Platform.isWindows) {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    _resolvedTitle = widget.title ?? '스마트교과서';
    _annotationController.activeColor = _penColor;
    _annotationController.activeWidth = _strokeWidth;
    _annotationController.toolMode = _tool;
    _annotationController.eraseEntireStroke = _eraseEntireStroke;
    _annotationController.eraserSize = _eraserSize;
    _annotationController.addListener(_onStrokesChanged);
    _dhashEngine = TbpDhashEngine(
      onDhashChanged: _onDhashDetected,
      onWebContextMenu: (rx, ry) {
        if (!mounted || widget.mode == TbpViewerMode.htmlp) return;
        TbpHotspotOverlay.showAddHotspotModal(
          context,
          rx.clamp(0.05, 0.92),
          ry.clamp(0.08, 0.88),
          _tbpFolderPath,
          _currentDhash,
          _currentHotspots,
          (updated) {
            if (!mounted) return;
            setState(() {
              _currentHotspots = updated;
            });
          },
        );
      },
      onNavigationRequested: (isNext) => _navigatePage(isNext),
    );
    _loadPackageOrUrl();
  }

  /// URL 포맷팅 (Canva, Google Slides, MiriCanvas 등 임베드 주소 자동 변환)
  static String formatPresentUrl(String rawInput) {
    var url = rawInput.trim();
    if (url.isEmpty) return 'https://docs.google.com/presentation';

    if (url.contains('<iframe') || url.contains('src=')) {
      final srcMatch = RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false).firstMatch(url);
      if (srcMatch != null && srcMatch.group(1) != null) {
        url = srcMatch.group(1)!.trim();
      }
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final segs = uri?.pathSegments.where((e) => e.isNotEmpty).toList() ?? const <String>[];

    // Canva
    if (host.contains('canva.com')) {
      final di = segs.indexOf('design');
      if (di >= 0 && segs.length >= di + 3) {
        final id = segs[di + 1];
        final token = segs[di + 2];
        return 'https://www.canva.com/design/$id/$token/view?embed';
      }
      if (di >= 0 && segs.length == di + 2) {
        return 'https://www.canva.com/design/${segs[di + 1]}/view?embed';
      }
      if (!url.contains('embed')) {
        return url.contains('?') ? '$url&embed' : '$url?embed';
      }
      return url;
    }

    // Google Slides / Docs
    if (host.contains('docs.google.com')) {
      if (url.contains('/presentation/d/')) {
        if (url.contains('/embed') || url.contains('/pubembed')) return url;
        final m = RegExp(r'/presentation/d/([a-zA-Z0-9_-]+)').firstMatch(url);
        if (m != null) {
          return 'https://docs.google.com/presentation/d/${m.group(1)}/embed?start=false&loop=false&delayms=3000';
        }
      }
      if (url.contains('/document/d/') && url.contains('/edit')) {
        return url.replaceAll(RegExp(r'/edit.*$'), '/preview');
      }
      return url;
    }

    // MiriCanvas
    if (host.contains('miricanvas.com')) {
      final vi = segs.indexOf('v');
      if (vi >= 0 && segs.length > vi + 1) {
        final docId = segs[vi + 1];
        return 'https://www.miricanvas.com/v/$docId?mode=presentation';
      }
      return url;
    }

    return url;
  }

  Future<void> _loadPackageOrUrl() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'TBP 전자교과서는 보안 및 고성능 엔진 구동을 위해 Windows/Android 전용 앱에서만 지원됩니다.\n웹 브라우저에서는 지원되지 않습니다.';
        });
      }
      return;
    }
    try {
      final rawPath = (widget.tbpFilePath ?? widget.filePath ?? widget.initialUrl ?? widget.embedUrl ?? '').trim();

      // 1. 직접 웹 URL 또는 iframe 인 경우
      if (rawPath.startsWith('http://') || rawPath.startsWith('https://') || rawPath.contains('<iframe')) {
        _targetUrl = formatPresentUrl(rawPath);
        final safeKey = _targetUrl.replaceAll(RegExp(r'[^\w-]'), '_');
        final folderId = 'tbp_${safeKey.length > 32 ? safeKey.substring(0, 32) : safeKey}';
        
        _tbpFolderPath = await TbpStorageService.instance.registerCreatedTbpProject(
          meta: {
            'title': _resolvedTitle,
            'folderId': folderId,
            'webUrl': _targetUrl,
            'scopeKey': 'TBP',
            'createdAt': DateTime.now().toIso8601String(),
          },
          localDirPath: kIsWeb ? 'web://tbp/$folderId' : null,
        );

        final initialHotspots = await TbpStorageService.instance.loadHotspots(_tbpFolderPath, _currentDhash);
        final initialStrokes = await TbpStorageService.instance.loadPenStrokes(_tbpFolderPath, _currentDhash);
        _currentHotspots = initialHotspots;
        _annotationController.setStrokes(initialStrokes);

        await _setupWebview(_targetUrl);
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. TBP 패키지 파일 또는 Cloud TBP 폴더인 경우
      final meta = await TbpStorageService.instance.loadTbpFile(rawPath);
      if (meta == null) {
        // 로컬 파일에서 JSON 내용 읽기 재시도
        if (!kIsWeb && rawPath.isNotEmpty && File(rawPath).existsSync()) {
          try {
            final content = await File(rawPath).readAsString();
            final parsed = jsonDecode(content);
            if (parsed is Map<String, dynamic>) {
              final directUrl = (parsed['webUrl'] ?? parsed['url'] ?? parsed['embedUrl'] ?? '').toString();
              if (directUrl.isNotEmpty) {
                _targetUrl = formatPresentUrl(directUrl);
                await _setupWebview(_targetUrl);
                if (mounted) setState(() => _isLoading = false);
                return;
              }
            }
          } catch (_) {}
        }

        setState(() {
          _errorMessage = 'TBP/HTMLP 데이터를 로드할 수 없습니다: $rawPath';
          _isLoading = false;
        });
        return;
      }

      _metadata = meta;
      if (meta.title.isNotEmpty && widget.title == null) {
        _resolvedTitle = meta.title;
      }
      _tbpFolderPath = TbpStorageService.instance.getTbpFolderPath(
        rawPath,
        meta.folderId,
      );
      _infoJson = await TbpStorageService.instance.loadInfoJson(_tbpFolderPath);

      var targetUrl = (_infoJson?['webUrl'] ?? _infoJson?['targetUrl'] ?? _infoJson?['url'] ?? _infoJson?['embedUrl'] ?? '').toString().trim();
      if (targetUrl.isEmpty && !kIsWeb && rawPath.isNotEmpty && File(rawPath).existsSync()) {
        try {
          final parsed = jsonDecode(await File(rawPath).readAsString());
          if (parsed is Map) {
            targetUrl = (parsed['webUrl'] ?? parsed['targetUrl'] ?? parsed['url'] ?? parsed['embedUrl'] ?? '').toString().trim();
          }
        } catch (_) {}
      }
      if (targetUrl.isEmpty) {
        setState(() {
          _errorMessage = 'TBP 폴더 내 webUrl 설정이 올바르지 않습니다.';
          _isLoading = false;
        });
        return;
      }

      await _loadAvailableClasses();
      _dhashEngine.registerKnownHashes(
        await TbpStorageService.instance.getKnownPageHashes(_tbpFolderPath),
      );
      final initialHotspots = await TbpStorageService.instance.loadHotspots(
        _tbpFolderPath,
        _currentDhash,
      );
      final initialStrokes = await TbpStorageService.instance.loadPenStrokes(
        _tbpFolderPath,
        _currentDhash,
        classId: _selectedClass,
      );
      _currentHotspots = initialHotspots;
      _isSwitchingPage = true;
      _annotationController.setStrokes(initialStrokes);
      _isSwitchingPage = false;

      _targetUrl = formatPresentUrl(targetUrl);
      await _setupWebview(_targetUrl);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'TBP/HTMLP 패키지 로딩 중 오류: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _setupWebview(String url) async {
    if (kIsWeb) {
      return;
    } else if (Platform.isWindows) {
      await _initWindowsWebview(url);
    } else {
      _initAndroidWebview(url);
    }
    _dhashEngine.startTracker(
      _winWebviewInitialized ? _winWebview : null,
      Platform.isWindows ? null : _androidWebview,
    );
  }

  Future<void> _initWindowsWebview(String url) async {
    try {
      await _winWebview.initialize();
      await _winWebview.setBackgroundColor(Colors.transparent);
      await _winWebview.loadUrl(url);

      _winWebview.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) {
          if (_lastContainerWidth > 0) {
            _applyNativeZoom(_lastContainerWidth);
          }
          _dhashEngine.requestHashNow();
          Future.delayed(const Duration(milliseconds: 50), () => _dhashEngine.requestHashNow());
          Future.delayed(const Duration(milliseconds: 600), () => _dhashEngine.requestHashNow());
          Future.delayed(const Duration(milliseconds: 1500), () => _dhashEngine.requestHashNow());
        }
      });

      _winWebview.webMessage.listen((message) {
        try {
          _dhashEngine.onDhashMessage(message);
          final data = jsonDecode(message);
          if (data['type'] == 'downloadRequest' && widget.mode == TbpViewerMode.tbp) {
            TbpDownloadInterceptor.instance.handleDownload(
              context: context,
              tbpFolderPath: _tbpFolderPath,
              currentDhash: _currentDhash,
              downloadUrl: data['url'],
              filename: data['filename'],
              scaleFactor: widget.scaleFactor,
            );
          }
        } catch (_) {}
      });

      if (mounted) setState(() => _winWebviewInitialized = true);
    } catch (e) {
      debugPrint('[TbpViewer] Windows webview init error: $e');
    }
  }

  void _initAndroidWebview(String url) {
    _androidWebview = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TbpChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          try {
            _dhashEngine.onDhashMessage(msg.message);
            final data = jsonDecode(msg.message);
            if (data['type'] == 'downloadRequest' && widget.mode == TbpViewerMode.tbp) {
              TbpDownloadInterceptor.instance.handleDownload(
                context: context,
                tbpFolderPath: _tbpFolderPath,
                currentDhash: _currentDhash,
                downloadUrl: data['url'],
                filename: data['filename'],
                scaleFactor: widget.scaleFactor,
              );
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          _dhashEngine.requestHashNow();
          Future.delayed(const Duration(milliseconds: 600), () => _dhashEngine.requestHashNow());
          Future.delayed(const Duration(milliseconds: 1500), () => _dhashEngine.requestHashNow());
        },
      ))
      ..loadRequest(Uri.parse(url));
  }

  Future<void> _onDhashDetected(String dHash) async {
    if (_currentDhash == dHash) return;
    _isSwitchingPage = true;
    try {
      final prevHash = _currentDhash;
      final prevStrokes = List<AnnotationStroke>.from(_annotationController.strokes);

      // 0. 현재 메모리에 이전 페이지 스트로크 즉시 백업
      if (prevHash.isNotEmpty) {
        _pageStrokesMemory['$_selectedClass::$prevHash'] = prevStrokes;
      }

      // 1. 이전 페이지 판서 자동 저장 (Auto-Save)
      if (_tbpFolderPath.isNotEmpty && prevHash.isNotEmpty && prevHash != 'default') {
        TbpStorageService.instance.savePenStrokes(
          _tbpFolderPath,
          prevHash,
          prevStrokes,
          classId: _selectedClass,
        ).catchError((e) {
          debugPrint('[TbpViewer] Auto-save error: $e');
        });
      }

      _currentDhash = dHash;

      // 0ms 즉각 복원: 인메모리 캐시에 이미 새 페이지 스트로크가 있으면 즉시 화면 반영
      final memKey = '$_selectedClass::$dHash';
      if (_pageStrokesMemory.containsKey(memKey)) {
        final cached = _pageStrokesMemory[memKey]!;
        if (mounted) {
          _annotationController.setStrokes(cached);
        }
      }

      // 2. 새 페이지의 핫스팟 및 판서 스트로크 자동 로드
      final hotspots = await TbpStorageService.instance.loadHotspots(
        _tbpFolderPath,
        dHash,
      );
      
      var strokes = _pageStrokesMemory[memKey];
      if (strokes == null) {
        strokes = await TbpStorageService.instance.loadPenStrokes(
          _tbpFolderPath,
          dHash,
          classId: _selectedClass,
        );
        _pageStrokesMemory[memKey] = strokes;
      }

      // 초기 로딩 중('default') 작성한 판서가 있으면 첫 실제 페이지 해시로 이관
      if (prevHash == 'default' && prevStrokes.isNotEmpty && strokes.isEmpty) {
        strokes = prevStrokes;
        _pageStrokesMemory[memKey] = strokes;
        await TbpStorageService.instance.savePenStrokes(
          _tbpFolderPath,
          dHash,
          strokes,
          classId: _selectedClass,
        );
      }

      if (mounted) {
        setState(() => _currentHotspots = hotspots);
        _annotationController.setStrokes(strokes);
      }
    } finally {
      _isSwitchingPage = false;
    }
  }

  void _showFeedback(String msg) {
    _feedbackTimer?.cancel();
    if (mounted) setState(() => _pageFeedback = msg);
    _feedbackTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _pageFeedback = '');
    });
  }

  DateTime? _lastNavigateTime;

  void _navigatePage(bool isNext) {
    final now = DateTime.now();
    if (_lastNavigateTime != null && now.difference(_lastNavigateTime!).inMilliseconds < 350) {
      return; // 350ms 디바운스로 2페이지 연속 넘어감 차단
    }
    _lastNavigateTime = now;
    _dhashEngine.navigatePage(isNext: isNext);
    _showFeedback(isNext ? '다음 슬라이드 ▶' : '◀ 이전 슬라이드');
  }

  Future<void> _saveCurrentBoard() async {
    if (_tbpFolderPath.isNotEmpty && _currentDhash.isNotEmpty) {
      await TbpStorageService.instance.savePenStrokes(
        _tbpFolderPath,
        _currentDhash,
        _annotationController.strokes,
        classId: _selectedClass,
      );
      _showFeedback('💾 판서가 저장되었습니다');
    }
  }

  bool get _isAnnotationEnabled {
    if (_isLaser) return false;
    switch (_inputMode) {
      case TbpInputMode.pen:
        return true;
      case TbpInputMode.touch:
        return false;
      case TbpInputMode.smart:
        return !_longPressActive;
    }
  }

  void _onSmartPointerDown(PointerEvent e) {
    if (_inputMode != TbpInputMode.smart) return;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (mounted) setState(() => _longPressActive = true);
    });
  }

  void _onSmartPointerUp(PointerEvent e) {
    _longPressTimer?.cancel();
    if (_longPressActive) {
      if (mounted) setState(() => _longPressActive = false);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCtrl = HardwareKeyboard.instance.isControlPressed;
      if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
        setState(() => _annotationController.undo());
        _showFeedback('↩️ 실행 취소');
        return KeyEventResult.handled;
      }
      if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyS) {
        _saveCurrentBoard();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.pageDown ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        _navigatePage(true);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.pageUp ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _navigatePage(false);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyP) {
        setState(() {
          _isLaser = false;
          _isHighlighter = false;
          _tool = ToolMode.pen;
          _annotationController.toolMode = ToolMode.pen;
          _annotationController.activeColor = _penColor;
          _annotationController.activeWidth = _strokeWidth;
        });
        _showFeedback('✏️ 일반 펜 (P)');
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyH) {
        setState(() {
          _isLaser = false;
          _isHighlighter = true;
          _tool = ToolMode.pen;
          _annotationController.toolMode = ToolMode.pen;
          _annotationController.activeColor = _penColor.withOpacity(0.35);
          _annotationController.activeWidth = 24.0;
        });
        _showFeedback('🖍️ 형광펜 (H)');
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyL) {
        setState(() {
          _isLaser = !_isLaser;
          if (_isLaser) {
            _tool = ToolMode.pointer;
            _annotationController.toolMode = ToolMode.pointer;
            _showFeedback('🔴 레이저 포인터 활성화 (L)');
          } else {
            _tool = ToolMode.pen;
            _annotationController.toolMode = ToolMode.pen;
            _showFeedback('✏️ 일반 펜 복귀');
          }
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyE) {
        setState(() {
          _isLaser = false;
          _tool = ToolMode.eraser;
          _annotationController.toolMode = ToolMode.eraser;
        });
        _showFeedback('🧹 지우개 (E)');
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.slash ||
          event.logicalKey == LogicalKeyboardKey.f1) {
        _showShortcutsDialog();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Timer? _touchDhashTimer;

  void _onPointerMove(PointerMoveEvent event) {
    if (_isLaser) {
      setState(() {
        _laserPosition = event.position;
      });
      _laserFadeTimer?.cancel();
      _laserFadeTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _laserPosition = null);
      });
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_isLaser) {
      setState(() {
        _laserPosition = event.position;
      });
    }
    _onSmartPointerDown(event);
    _touchDhashTimer?.cancel();
    _touchDhashTimer = Timer(const Duration(milliseconds: 1000), () {
      _dhashEngine.requestHashNow();
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isLaser) {
      _laserFadeTimer?.cancel();
      _laserFadeTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _laserPosition = null);
      });
    }
    _onSmartPointerUp(event);
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _touchDhashTimer?.cancel();
    _dhashEngine.dispose();
    if (_winWebviewInitialized) {
      try {
        _winWebview.dispose();
      } catch (_) {}
    }
    _annotationController.removeListener(_onStrokesChanged);
    _annotationController.dispose();
    _longPressTimer?.cancel();
    _keyboardFocus.dispose();
    if (!kIsWeb && Platform.isWindows) {
      windowManager.setTitleBarStyle(TitleBarStyle.normal);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0E17),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFEF4565),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('뒤로 가기'),
              ),
            ],
          ),
        ),
      );
    }

    final webviewWidget = kIsWeb
        ? getIframeViewWidget('tbp-web-iframe-${_targetUrl.hashCode}', _targetUrl)
        : (Platform.isWindows
            ? (_winWebviewInitialized
                ? Webview(_winWebview)
                : const SizedBox.shrink())
            : WebViewWidget(controller: _androidWebview));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: (_) => _onSmartPointerUp(const PointerUpEvent()),
        child: Focus(
          focusNode: _keyboardFocus,
          onKeyEvent: _onKeyEvent,
          autofocus: true,
          child: Stack(
            children: [
              // ── 16:9 컨테이너 (WebView + 판서 + 핫스팟) ──
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _applyNativeZoom(constraints.maxWidth);
                      });
                      return Stack(
                        children: [
                          // ── WebView 레이어 ──────────────────────────────
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: _isAnnotationEnabled,
                              child: webviewWidget,
                            ),
                          ),

                          // ── 판서 오버레이 ───────────────────────────────
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: !_isAnnotationEnabled,
                              child: Container(
                                color: Colors.transparent,
                                child: AnnotationCanvas(
                                  controller: _annotationController,
                                  enabled:
                                      _isAnnotationEnabled &&
                                      _tool != ToolMode.pointer,
                                ),
                              ),
                            ),
                          ),

                          // ── 핫스팟 오버레이 (TBP 모드일 때만 활성) ─────
                          if (widget.mode == TbpViewerMode.tbp)
                            Positioned.fill(
                              child: TbpHotspotOverlay(
                                hotspots: _currentHotspots,
                                tbpFolderPath: _tbpFolderPath,
                                currentDhash: _currentDhash,
                                scaleFactor: widget.scaleFactor,
                                inputMode: _inputMode,
                                longPressActive: _longPressActive,
                                onHotspotsUpdated: (updated) {
                                  setState(() {
                                    _currentHotspots = updated;
                                  });
                                },
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // ── 상단 컨트롤 바 ─────────────────────────────
              Positioned(
                top: 12 * s,
                left: 16 * s,
                right: 16 * s,
                child: _buildControlBar(s),
              ),

              // ── 레이저 포인터 발광 스포트라이트 오버레이 ─────────
              if (_isLaser && _laserPosition != null)
                Positioned(
                  left: _laserPosition!.dx - 12,
                  top: _laserPosition!.dy - 12,
                  child: IgnorePointer(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF2A6D),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF2A6D).withOpacity(0.85),
                            blurRadius: 18,
                            spreadRadius: 6,
                          ),
                          const BoxShadow(
                            color: Colors.white,
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── 전용 좌우 페이지 넘김 터치 버튼 (전자칠판 터치 친화형) ──
              Positioned(
                left: 8 * s,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _navigatePage(false),
                      borderRadius: BorderRadius.circular(20 * s),
                      hoverColor: const Color(0xFF00F5D4).withOpacity(0.2),
                      child: Container(
                        width: 44 * s,
                        height: 74 * s,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A).withOpacity(0.72),
                          borderRadius: BorderRadius.circular(16 * s),
                          border: Border.all(color: Colors.white24, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(Icons.chevron_left_rounded, color: Colors.white, size: 36 * s),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: (_isAnnotationEnabled || _isLaser || _isToolbarCollapsed) ? 80 * s : 8 * s,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _navigatePage(true),
                      borderRadius: BorderRadius.circular(20 * s),
                      hoverColor: const Color(0xFF00F5D4).withOpacity(0.2),
                      child: Container(
                        width: 44 * s,
                        height: 74 * s,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A).withOpacity(0.72),
                          borderRadius: BorderRadius.circular(16 * s),
                          border: Border.all(color: Colors.white24, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(Icons.chevron_right_rounded, color: Colors.white, size: 36 * s),
                      ),
                    ),
                  ),
                ),
              ),

              // ── 우측 플로팅 펜 툴바 (세로형) ─────────────────────────
              if (_isAnnotationEnabled || _isLaser || _isToolbarCollapsed)
                Positioned(
                  right: 16 * s,
                  top: 90 * s,
                  bottom: 90 * s,
                  child: Center(
                    child: _buildFloatingPenBar(s),
                  ),
                ),

              // ── 페이지 넘김 / 상태 안내 토스트 ──────────────────────
              if (_pageFeedback.isNotEmpty)
                Positioned(
                  bottom: 30 * s,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 9 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(20 * s),
                        border: Border.all(color: const Color(0xFF00F5D4), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00F5D4).withOpacity(0.2),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Text(
                        _pageFeedback,
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13 * s,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar(double s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── 좌측: 뒤로 + 제목 ───────────────────────────────
        _controlContainer(
          s,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () async {
                  if (_tbpFolderPath.isNotEmpty && _currentDhash.isNotEmpty) {
                    await TbpStorageService.instance.savePenStrokes(
                      _tbpFolderPath,
                      _currentDhash,
                      List<AnnotationStroke>.from(_annotationController.strokes),
                      classId: _selectedClass,
                    );
                  }
                  if (mounted) Navigator.pop(context);
                },
                tooltip: '뒤로',
              ),
              SizedBox(width: 6 * s),
              Text(
                '📖 $_resolvedTitle',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14 * s,
                ),
              ),
              SizedBox(width: 8 * s),
              _buildClassSelector(s),
            ],
          ),
        ),

        // ── 중앙: 페이지 이동 + 핫스팟 (TBP 전용) ─────────────
        _controlContainer(
          s,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.navigate_before_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                tooltip: '이전 페이지 (← ArrowLeft / PgUp)',
                onPressed: () => _navigatePage(false),
              ),
              IconButton(
                icon: const Icon(
                  Icons.navigate_next_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                tooltip: '다음 페이지 (→ ArrowRight / PgDn)',
                onPressed: () => _navigatePage(true),
              ),
              if (widget.mode == TbpViewerMode.tbp) ...[
                SizedBox(width: 8 * s),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                  label: Text(
                    '+ 핫스팟',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2EC4B6),
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
                  ),
                  onPressed: () {
                    final offsetCount = _currentHotspots.length;
                    final rx = (0.2 + (offsetCount % 5) * 0.14).clamp(0.1, 0.88);
                    final ry = (0.22 + (offsetCount ~/ 5) * 0.14).clamp(0.15, 0.82);
                    TbpHotspotOverlay.showAddHotspotModal(
                      context,
                      rx,
                      ry,
                      _tbpFolderPath,
                      _currentDhash,
                      _currentHotspots,
                      (updated) {
                        setState(() {
                          _currentHotspots = updated;
                        });
                      },
                    );
                  },
                ),
              ],
            ],
          ),
        ),

        // ── 우측: 입력 모드 토글 (Pen 기본 / Touch) ──────────
        _controlContainer(
          s,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modeButton(s, TbpInputMode.pen, '✏️', 'Pen\n(기본)'),
              SizedBox(width: 4 * s),
              _modeButton(s, TbpInputMode.touch, '👆', 'Touch\n(통과)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingPenBar(double s) {
    if (_isToolbarCollapsed) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16161A).withOpacity(0.94),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IconButton(
          icon: Icon(Icons.palette_rounded, color: const Color(0xFF00F5D4), size: 22 * s),
          tooltip: '판서 도구 펼치기',
          onPressed: () => setState(() => _isToolbarCollapsed = false),
        ),
      );
    }

    final colors = [
      const Color(0xFF00F5D4), // Mint
      const Color(0xFFFFD166), // Yellow
      const Color(0xFFEF4565), // Red
      const Color(0xFF7F5AF0), // Violet
      Colors.white,
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withOpacity(0.94),
        borderRadius: BorderRadius.circular(24 * s),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 접기 토글
          IconButton(
            icon: Icon(Icons.keyboard_arrow_right_rounded, color: Colors.white54, size: 20 * s),
            tooltip: '도구함 접기',
            onPressed: () => setState(() => _isToolbarCollapsed = true),
          ),
          Container(
            margin: EdgeInsets.symmetric(vertical: 3 * s),
            width: 20 * s,
            height: 1,
            color: Colors.white12,
          ),
          // 1. 일반 펜
          IconButton(
            icon: Icon(Icons.edit_rounded, color: (_tool == ToolMode.pen && !_isHighlighter) ? _penColor : Colors.white54, size: 20 * s),
            tooltip: '펜 (일반)',
            onPressed: () {
              setState(() {
                _isHighlighter = false;
                _tool = ToolMode.pen;
                _annotationController.toolMode = ToolMode.pen;
                _annotationController.activeColor = _penColor;
                _annotationController.activeWidth = _strokeWidth;
              });
            },
          ),
          // 2. 형광펜 (반투명 하이라이터)
          IconButton(
            icon: Icon(Icons.border_color_rounded, color: (_tool == ToolMode.pen && _isHighlighter) ? const Color(0xFFFFD166) : Colors.white54, size: 19 * s),
            tooltip: '형광펜 (반투명)',
            onPressed: () {
              setState(() {
                _isLaser = false;
                _isHighlighter = true;
                _tool = ToolMode.pen;
                _annotationController.toolMode = ToolMode.pen;
                _annotationController.activeColor = _penColor.withOpacity(0.35);
                _annotationController.activeWidth = 24.0;
              });
            },
          ),
          // 2.5 레이저 포인터
          IconButton(
            icon: Icon(Icons.flare_rounded, color: _isLaser ? const Color(0xFFFF2A6D) : Colors.white54, size: 19 * s),
            tooltip: '레이저 포인터 (L)',
            onPressed: () {
              setState(() {
                _isLaser = !_isLaser;
                if (_isLaser) {
                  _tool = ToolMode.pointer;
                  _annotationController.toolMode = ToolMode.pointer;
                  _showFeedback('🔴 레이저 포인터 활성화');
                } else {
                  _tool = ToolMode.pen;
                  _annotationController.toolMode = ToolMode.pen;
                  _showFeedback('✏️ 일반 펜 복귀');
                }
              });
            },
          ),
          SizedBox(height: 3 * s),
          ...colors.map((c) => GestureDetector(
            onTap: () {
              setState(() {
                _penColor = c;
                _annotationController.activeColor = _isHighlighter ? c.withOpacity(0.35) : c;
                _tool = ToolMode.pen;
                _annotationController.toolMode = ToolMode.pen;
              });
            },
            child: Container(
              margin: EdgeInsets.symmetric(vertical: 3.5 * s),
              width: 18 * s,
              height: 18 * s,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _penColor == c ? Colors.white : Colors.transparent,
                  width: 2.2,
                ),
              ),
            ),
          )),
          Container(
            margin: EdgeInsets.symmetric(vertical: 6 * s),
            width: 20 * s,
            height: 1,
            color: Colors.white24,
          ),
          // 3. 실행 취소 (Undo)
          IconButton(
            icon: Icon(Icons.undo_rounded, color: Colors.white, size: 20 * s),
            tooltip: '실행 취소 (Ctrl+Z)',
            onPressed: () {
              setState(() => _annotationController.undo());
              _showFeedback('↩️ 실행 취소');
            },
          ),
          // 4. 지우개
          IconButton(
            icon: Icon(Icons.cleaning_services_rounded, color: _tool == ToolMode.eraser ? const Color(0xFFFF8906) : Colors.white54, size: 20 * s),
            tooltip: '지우개',
            onPressed: () {
              setState(() {
                _tool = ToolMode.eraser;
                _annotationController.toolMode = ToolMode.eraser;
              });
            },
          ),
          // 5. 모두 지우기
          IconButton(
            icon: Icon(Icons.delete_sweep_rounded, color: Colors.white54, size: 20 * s),
            tooltip: '모두 지우기',
            onPressed: () {
              setState(() {
                _annotationController.clear();
              });
              _showFeedback('🗑️ 판서 초기화');
            },
          ),
          Container(
            margin: EdgeInsets.symmetric(vertical: 6 * s),
            width: 20 * s,
            height: 1,
            color: Colors.white24,
          ),
          // 6. 판서 즉시 저장
          IconButton(
            icon: Icon(Icons.save_rounded, color: const Color(0xFF00F5D4), size: 20 * s),
            tooltip: '판서 저장 (Ctrl+S)',
            onPressed: _saveCurrentBoard,
          ),
          Container(
            margin: EdgeInsets.symmetric(vertical: 4 * s),
            width: 20 * s,
            height: 1,
            color: Colors.white12,
          ),
          // 7. 단축키 안내
          IconButton(
            icon: Icon(Icons.help_outline_rounded, color: Colors.white54, size: 18 * s),
            tooltip: '단축키 및 조작 안내 (?)',
            onPressed: _showShortcutsDialog,
          ),
        ],
      ),
    );
  }

  void _showShortcutsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00F5D4), width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.keyboard_rounded, color: Color(0xFF00F5D4), size: 24),
            const SizedBox(width: 8),
            Text(
              'TBP 프레젠테이션 단축키 안내',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShortcutRow('PgDn / → / 스페이스', '다음 슬라이드/페이지'),
            _buildShortcutRow('PgUp / ← / 백스페이스', '이전 슬라이드/페이지'),
            _buildShortcutRow('Ctrl + Z', '판서 실행 취소 (Undo)'),
            _buildShortcutRow('Ctrl + S', '판서 즉시 저장'),
            _buildShortcutRow('P', '일반 펜 모드 전환'),
            _buildShortcutRow('H', '형광펜 모드 전환'),
            _buildShortcutRow('L', '레이저 포인터 토글'),
            _buildShortcutRow('E', '지우개 모드 전환'),
            _buildShortcutRow('? / F1', '단축키 안내 보기'),
          ],
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

  Widget _buildShortcutRow(String keys, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              keys,
              style: GoogleFonts.outfit(
                color: const Color(0xFF00F5D4),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            desc,
            style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _controlContainer(double s, Widget child) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withOpacity(0.92),
        borderRadius: BorderRadius.circular(12 * s),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: child,
    );
  }

  Widget _modeButton(double s, TbpInputMode mode, String emoji, String label) {
    final isActive = _inputMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _inputMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF7F5AF0).withOpacity(0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8 * s),
          border: Border.all(
            color: isActive ? const Color(0xFF7F5AF0) : Colors.white24,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TextStyle(fontSize: 16 * s)),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                color: isActive ? Colors.white : Colors.white54,
                fontSize: 9 * s,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
