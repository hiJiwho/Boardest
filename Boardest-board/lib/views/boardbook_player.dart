import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

import '../widgets/annotation_canvas.dart';
import '../widgets/board_toolbar.dart';
import '../models/board_tools.dart';
import '../services/local_server_service.dart';
import 'pdf_board_view.dart';
import 'ppt_overlay_view.dart';
import 'video_board_view.dart';
import 'hwp_overlay_view.dart';

import '../services/annotation_storage_service.dart';

// Android Webview imports
import 'package:webview_flutter/webview_flutter.dart';
// Windows Webview imports
import 'package:webview_windows/webview_windows.dart';

class BoardBookPlayer extends StatefulWidget {
  final String bbFilePath;
  final double scaleFactor;
  const BoardBookPlayer({
    super.key,
    required this.bbFilePath,
    required this.scaleFactor,
  });

  @override
  State<BoardBookPlayer> createState() => _BoardBookPlayerState();
}

class _BoardBookPlayerState extends State<BoardBookPlayer> {
  bool _loading = true;
  String? _error;
  String _tempPath = '';
  String _lessonTitle = '';
  List<Map<String, dynamic>> _slides = [];
  int _currentIndex = 0;

  // 공통 판서 상태
  late AnnotationController _annotationController;
  Color _penColor = const Color(0xFFEF4565);
  double _strokeWidth = 4.0;
  ToolMode _tool = ToolMode.pen;
  ShapeType _activeShape = ShapeType.line;
  bool _eraseEntireStroke = false;
  double _eraserSize = 30.0;

  String _selectedClassForPen = '전체 반 공용 (통합)';
  final List<String> _classList = [
    '전체 반 공용 (통합)',
    '1학년 1반',
    '1학년 2반',
    '2학년 1반',
    '2학년 2반',
    '3학년 1반',
    '3학년 2반',
  ];

  // 웹 페이지 단위 판서 저장소 (Key: scopeKey, Value: 판서 획들)
  final Map<String, List<AnnotationStroke>> _pageDrawings = {};
  
  // 웹 페이지 단위 핫스팟 저장소 (Key: pageId, Value: 핫스팟 리스트)
  Map<String, List<Map<String, dynamic>>> _pageHotspots = {};
  
  // 현재 활성화된 웹뷰 페이지 식별 ID
  String _currentWebPageId = 'default';

  String _getScopedKey(String pageId) => '[$_selectedClassForPen]_$pageId';

  @override
  void initState() {
    super.initState();
    _annotationController = AnnotationController();
    _loadEraserPrefs();
    _unpackAndLoad();
  }

  Future<void> _loadEraserPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _eraseEntireStroke = prefs.getBool('whiteboard_erase_entire') ?? false;
      _eraserSize = prefs.getDouble('whiteboard_eraser_size') ?? 30.0;
    });
    _syncControllerTooling();
  }

  void _syncControllerTooling() {
    _annotationController.toolMode = _tool;
    _annotationController.activeColor = _penColor;
    _annotationController.activeWidth = _strokeWidth;
    _annotationController.eraseEntireStroke = _eraseEntireStroke;
    _annotationController.eraserSize = _eraserSize;
    _annotationController.activeShape = _activeShape;
  }

  Future<void> _unpackAndLoad() async {
    try {
      final dir = Directory(widget.bbFilePath);
      if (!await dir.exists()) {
        setState(() {
          _error = 'BoardBook 폴더를 찾을 수 없습니다:\n${widget.bbFilePath}';
          _loading = false;
        });
        return;
      }

      _tempPath = widget.bbFilePath;
      final manifestFile = File(p.join(_tempPath, 'manifest.json'));
      if (!manifestFile.existsSync()) {
        setState(() {
          _error = '교안 manifest.json 파일을 찾을 수 없습니다.';
          _loading = false;
        });
        return;
      }

      final manifestContent = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;

      // 이전 핫스팟 및 데이터 로드 (manifest.json 내부에 결합 저장)
      final rawHotspots = manifest['hotspots'] as Map<String, dynamic>? ?? {};
      _pageHotspots = rawHotspots.map((k, v) => MapEntry(k, List<Map<String, dynamic>>.from(v)));

      setState(() {
        _lessonTitle = manifest['title'] ?? 'BoardBook 수업';
        _slides = List<Map<String, dynamic>>.from(manifest['slides'] ?? []);
        _loading = false;
      });

      LocalServerService.instance.activeTextbookDir = _tempPath;

      if (_slides.isNotEmpty) {
        _loadSlide(0);
      }
    } catch (e) {
      setState(() {
        _error = 'BoardBook 패키지를 불러오는 도중 오류가 발생했습니다:\n$e';
        _loading = false;
      });
    }
  }

  void _loadSlide(int index) {
    if (index < 0 || index >= _slides.length) return;

    // 현재 열린 페이지의 판서 세션 백업
    _saveCurrentPageDrawing();

    setState(() {
      _currentIndex = index;
      _annotationController.clear();
      _currentWebPageId = 'slide_$index';
    });

    // 백업된 판서가 있다면 복원
    _restorePageDrawing(_currentWebPageId);
  }

  // 웹뷰 페이지/해시 체인지 인식 시 호출
  void _handleWebPageChanged(String pageId) {
    if (_currentWebPageId == pageId) return;

    // 1. 현재 판서 상태 백업
    _saveCurrentPageDrawing();

    // 2. 캔버스 리셋
    _annotationController.clear();

    setState(() {
      _currentWebPageId = pageId;
    });

    // 3. 복원 진행
    _restorePageDrawing(pageId);
  }

  void _handleWebRightClick(double px, double py) {
    final Size size = MediaQuery.of(context).size;
    final rx = size.width > 0 ? (px / size.width).clamp(0.0, 1.0) : 0.5;
    final ry = size.height > 0 ? (py / size.height).clamp(0.0, 1.0) : 0.5;
    _showCreateHotspotDialog(rx, ry);
  }

  Future<void> _saveManifestData() async {
    try {
      final manifestFile = File(p.join(_tempPath, 'manifest.json'));
      if (!manifestFile.existsSync()) return;

      final manifestContent = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;

      manifest['hotspots'] = _pageHotspots;
      await manifestFile.writeAsString(jsonEncode(manifest));
    } catch (e) {
      debugPrint('[BoardBookPlayer] Save manifest error: $e');
    }
  }

  Future<void> _saveCurrentPageDrawing() async {
    final key = _getScopedKey(_currentWebPageId);
    if (_annotationController.strokes.isNotEmpty) {
      _pageDrawings[key] = List<AnnotationStroke>.from(_annotationController.strokes);
    } else {
      _pageDrawings.remove(key);
    }

    final Map<int, List<AnnotationStroke>> pageAnnotations = {};
    int idx = 0;
    for (final slide in _slides) {
      final slidePageId = 'slide_$idx';
      final scopedKey = '[$_selectedClassForPen]_$slidePageId';
      if (_pageDrawings.containsKey(scopedKey)) {
        pageAnnotations[idx] = _pageDrawings[scopedKey]!;
      }
      idx++;
    }

    await AnnotationStorageService.instance.saveDocumentAnnotations(
      'BOARDBOOK',
      _lessonTitle,
      {
        'title': _lessonTitle,
        'filePath': widget.bbFilePath,
        'className': _selectedClassForPen,
        'totalPages': _slides.length,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      pageAnnotations,
      fullFilePath: widget.bbFilePath,
      className: _selectedClassForPen,
    );
  }

  Future<void> _restorePageDrawing(String pageId) async {
    final key = _getScopedKey(pageId);
    if (!_pageDrawings.containsKey(key)) {
      final loaded = await AnnotationStorageService.instance.loadDocumentAnnotations(
        'BOARDBOOK',
        _lessonTitle,
        fullFilePath: widget.bbFilePath,
        className: _selectedClassForPen,
      );
      int idx = 0;
      for (final slide in _slides) {
        final slidePageId = 'slide_$idx';
        final scopedKey = '[$_selectedClassForPen]_$slidePageId';
        if (loaded.containsKey(idx)) {
          _pageDrawings[scopedKey] = loaded[idx]!;
        }
        idx++;
      }
    }

    if (_pageDrawings.containsKey(key)) {
      for (final stroke in _pageDrawings[key]!) {
        _annotationController.addStroke(stroke);
      }
    }
  }



  // 핫스팟 클릭 시 Boardest 내부 칠판 뷰어로 열기
  void _openHotspotFile(Map<String, dynamic> hotspot) async {
    final filePath = hotspot['path'] as String;
    final ext = p.extension(filePath).toLowerCase();

    if (ext == '.pdf') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfBoardView(
            initialFilePath: filePath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    } else if (ext == '.pptx' || ext == '.ppt') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PptOverlayView(
            initialFilePath: filePath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    } else if (['.mp4', '.mkv', '.avi', '.mov', '.wmv'].contains(ext)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoBoardView(
            filePath: filePath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    } else if (ext == '.hwp') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HwpOverlayView(
            initialFilePath: filePath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    }
  }

  // 핫스팟 우클릭 시 삭제 메뉴
  void _showHotspotDeleteMenu(Map<String, dynamic> hotspot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: const Text('핫스팟 삭제', style: TextStyle(color: Colors.white)),
        content: Text('\'${hotspot['name']}\' 핫스팟 링크를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _pageHotspots[_currentWebPageId]?.remove(hotspot);
      });
      _saveManifestData();
    }
  }

  void _showCreateHotspotDialog(double rx, double ry) async {
    final titleController = TextEditingController();
    final valueController = TextEditingController();
    String type = 'url';
    String iconEmoji = '🔗';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF16161A),
              title: Row(
                children: [
                  const Icon(Icons.add_location_alt_rounded, color: Color(0xFF00F5D4)),
                  const SizedBox(width: 8),
                  Text('핫스팟 링크 추가', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: '핫스팟 이름 (예: 관련 영상)',
                        labelStyle: TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: Color(0xFF242629),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: type,
                      dropdownColor: const Color(0xFF242629),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: '리소스 유형',
                        labelStyle: TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: Color(0xFF242629),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'url', child: Text('🌐 외부 웹사이트 URL')),
                        DropdownMenuItem(value: 'vid', child: Text('🎬 동영상 파일 (.mp4)')),
                        DropdownMenuItem(value: 'pdf', child: Text('📄 문서 파일 (.pdf)')),
                        DropdownMenuItem(value: 'img', child: Text('🖼️ 이미지 파일 (.jpg/.png)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            type = val;
                            if (val == 'url') iconEmoji = '🔗';
                            else if (val == 'vid') iconEmoji = '🎬';
                            else if (val == 'pdf') iconEmoji = '📄';
                            else if (val == 'img') iconEmoji = '🖼️';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: valueController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: type == 'url' ? 'URL 링크 (https://...)' : '파일 경로',
                              labelStyle: const TextStyle(color: Colors.white60),
                              filled: true,
                              fillColor: const Color(0xFF242629),
                            ),
                          ),
                        ),
                        if (type != 'url') ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.folder_open_rounded, color: Color(0xFF00F5D4)),
                            onPressed: () async {
                              final pickerRes = await FilePicker.pickFiles();
                              if (pickerRes != null && pickerRes.files.single.path != null) {
                                valueController.text = pickerRes.files.single.path!;
                                if (titleController.text.isEmpty) {
                                  titleController.text = p.basename(pickerRes.files.single.path!);
                                }
                              }
                            },
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0)),
                  onPressed: () {
                    if (valueController.text.trim().isEmpty) return;
                    Navigator.pop(context, {
                      'id': 'H_${DateTime.now().millisecondsSinceEpoch}',
                      'name': titleController.text.trim().isEmpty ? '핫스팟 링크' : titleController.text.trim(),
                      'type': type,
                      'value': valueController.text.trim(),
                      'icon': iconEmoji,
                      'x': rx,
                      'y': ry,
                    });
                  },
                  child: const Text('생성'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        final list = _pageHotspots[_currentWebPageId] ?? [];
        list.add(result);
        _pageHotspots[_currentWebPageId] = list;
      });
      _saveManifestData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✨ 핫스팟 링크가 추가되었습니다!')),
      );
    }
  }

  @override
  void dispose() {
    _annotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0E17),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4))),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
        body: Center(
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4565), size: 48),
                const SizedBox(height: 16),
                Text('수업 시작 실패', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(_error!, style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('뒤로 가기'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 현재 페이지의 핫스팟 리스트 취득
    final currentHotspots = _pageHotspots[_currentWebPageId] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF16161A),
      body: Stack(
        children: [
          // 1. 슬라이드 메인 컨텐츠 영역 (WebView 포함)
          Positioned.fill(
            child: _buildSlideContent(),
          ),

          // 2. 핫스팟 오버레이 단추 레이어 (좌표 기반 배치)
          if (_slides.isNotEmpty && _slides[_currentIndex]['type'] == 'url')
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: currentHotspots.map((hotspot) {
                      final rx = hotspot['x'] as double;
                      final ry = hotspot['y'] as double;
                      final left = rx * constraints.maxWidth;
                      final top = ry * constraints.maxHeight;

                      return Positioned(
                        left: left - 20 * s,
                        top: top - 20 * s,
                        child: GestureDetector(
                          onTap: () => _openHotspotFile(hotspot),
                          onSecondaryTap: () => _showHotspotDeleteMenu(hotspot),
                          child: Tooltip(
                            message: hotspot['name'],
                            child: Container(
                              width: 40 * s,
                              height: 40 * s,
                              decoration: BoxDecoration(
                                color: const Color(0xFF7F5AF0).withOpacity(0.95),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  )
                                ],
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.file_present_rounded,
                                  color: Colors.white,
                                  size: 20 * s,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),

          // 3. 슬라이드 판서 레이어
          Positioned.fill(
            child: AnnotationCanvas(
              controller: _annotationController,
              enabled: _tool == ToolMode.pen || _tool == ToolMode.eraser || _tool == ToolMode.select || _tool == ToolMode.shape,
              onRightClick: (pos) => _handleWebRightClick(pos.dx, pos.dy),
            ),
          ),

          // 4. 상단 바 (수업 제목 및 닫기)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 16 * s),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$_lessonTitle - [${_currentIndex + 1}/${_slides.length}] ${_slides[_currentIndex]['title']}',
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 2 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(10 * s),
                      border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.5)),
                    ),
                    child: DropdownButton<String>(
                      dropdownColor: const Color(0xFF242629),
                      value: _selectedClassForPen,
                      underline: const SizedBox(),
                      style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      items: _classList.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedClassForPen) {
                          _saveCurrentPageDrawing();
                          _annotationController.clear();
                          setState(() {
                            _selectedClassForPen = val;
                          });
                          _restorePageDrawing(_currentWebPageId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('🏫 [$val] 판서 데이터로 전환되었습니다.')),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5. 우측 슬라이드 스위처
          Positioned(
            right: 16 * s,
            top: 80 * s,
            bottom: 120 * s,
            child: Container(
              width: 72 * s,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: ListView.builder(
                itemCount: _slides.length,
                itemBuilder: (context, idx) {
                  final isSelected = idx == _currentIndex;
                  final type = _slides[idx]['type'];
                  IconData icon;
                  if (type == 'whiteboard') icon = Icons.draw_rounded;
                  else icon = Icons.language_rounded;

                  return GestureDetector(
                    onTap: () => _loadSlide(idx),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      height: 52 * s,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00F5D4).withOpacity(0.15) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.08), width: 1.5),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, color: isSelected ? const Color(0xFF00F5D4) : Colors.white60, size: 18 * s),
                            const SizedBox(height: 2),
                            Text('${idx + 1}', style: TextStyle(color: isSelected ? const Color(0xFF00F5D4) : Colors.white38, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 6. 하단 칠판 툴바
          Positioned(
            bottom: 16 * s,
            left: 16 * s,
            right: 16 * s,
            child: Center(
              child: _buildFloatingToolbar(s),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlideContent() {
    if (_slides.isEmpty) return const SizedBox.shrink();

    final slide = _slides[_currentIndex];
    final type = slide['type'];
    final value = slide['value'];

    if (type == 'whiteboard') {
      return Container(
        color: const Color(0xFF1E1E24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.draw_rounded, color: Colors.white.withOpacity(0.05), size: 120),
              Text('자유 판서 영역', style: GoogleFonts.notoSansKr(color: Colors.white24, fontSize: 18)),
            ],
          ),
        ),
      );
    } else if (type == 'url') {
      String targetUrl = value;
      if (!targetUrl.startsWith('http')) {
        targetUrl = 'http://localhost:7777/textbooks/$targetUrl';
      }
      return _buildWebviewLayer(targetUrl);
    }

    return Center(child: Text('알 수 없는 슬라이드 형식: $type', style: const TextStyle(color: Colors.white30)));
  }

  Widget _buildWebviewLayer(String url) {
    if (Platform.isWindows) {
      return _WindowsWebviewWidget(
        url: url,
        onPageChanged: _handleWebPageChanged,
        onRightClick: _handleWebRightClick,
      );
    } else {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'BoardestChannel',
          onMessageReceived: (JavaScriptMessage msg) {
            try {
              final data = jsonDecode(msg.message);
              final type = data['type'];
              if (type == 'rightClick') {
                _handleWebRightClick(data['x'], data['y']);
              } else if (type == 'pageChanged') {
                _handleWebPageChanged(data['pageId']);
              }
            } catch (_) {}
          },
        )
        ..loadRequest(Uri.parse(url));

      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            controller.runJavaScript('''
              let lastPageId = "";
              function getPageDhash() {
                let raw = (window.location.href + '_' + (document.body ? document.body.innerText.substring(0, 150) : '')).replace(/\\s+/g, '');
                let hash = 0;
                for (let i = 0; i < raw.length; i++) {
                  hash = ((hash << 5) - hash) + raw.charCodeAt(i);
                  hash |= 0;
                }
                return 'dhash_' + Math.abs(hash);
              }

              function checkPage() {
                let pageId = window.location.hash || window.location.search || document.title;
                let pageNumEl = document.querySelector('.page-num, .pageNum, #pageNo, .page_num, [class*="page"]');
                if (pageNumEl && pageNumEl.innerText) {
                  pageId = pageNumEl.innerText.trim();
                }
                if (!pageId || pageId === '') {
                  pageId = getPageDhash();
                }
                if (pageId && pageId !== lastPageId) {
                  lastPageId = pageId;
                  BoardestChannel.postMessage(JSON.stringify({
                    type: 'pageChanged',
                    pageId: pageId
                  }));
                }
              }
              
              if (!window.__boardestDhashInjected) {
                window.__boardestDhashInjected = true;
                setInterval(checkPage, 500);
                window.addEventListener('hashchange', checkPage);
                window.addEventListener('click', () => setTimeout(checkPage, 300));

                window.addEventListener('contextmenu', function(e) {
                  e.preventDefault();
                  BoardestChannel.postMessage(JSON.stringify({
                    type: 'rightClick',
                    x: e.clientX,
                    y: e.clientY
                  }));
                });
              }
            ''');
          },
        ),
      );
      return WebViewWidget(controller: controller);
    }
  }

  Widget _buildFloatingToolbar(double scale) {
    return BoardDockToolbar(
      scale: scale,
      tool: _tool,
      onPrev: _currentIndex > 0 ? () => _loadSlide(_currentIndex - 1) : null,
      onNext: _currentIndex < _slides.length - 1 ? () => _loadSlide(_currentIndex + 1) : null,
      pageLabel: '${_currentIndex + 1} / ${_slides.length}',
      onToolChanged: (mode) {
        setState(() {
          _tool = mode;
        });
        _syncControllerTooling();
      },
      strokeWidth: _strokeWidth,
      onStrokeWidthChanged: (w) {
        setState(() {
          _strokeWidth = w;
          _tool = ToolMode.pen;
        });
        _syncControllerTooling();
      },
      penColor: _penColor,
      onColorChanged: (c) {
        setState(() {
          _penColor = c;
          _tool = ToolMode.pen;
        });
        _syncControllerTooling();
      },
      activeShape: _activeShape,
      onShapeChanged: (shape) {
        setState(() {
          _activeShape = shape;
          _tool = ToolMode.shape;
        });
        _syncControllerTooling();
      },
      onUndo: _annotationController.undo,
      onClear: () => setState(() => _annotationController.clear()),
      onClose: () => Navigator.pop(context),
      eraseEntireStroke: _eraseEntireStroke,
      onEraseEntireStrokeChanged: (val) async {
        setState(() => _eraseEntireStroke = val);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('whiteboard_erase_entire', val);
        _syncControllerTooling();
      },
      eraserSize: _eraserSize,
      onEraserSizeChanged: (val) async {
        setState(() => _eraserSize = val);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('whiteboard_eraser_size', val);
        _syncControllerTooling();
      },
    );
  }
}

// Windows WebView2 감싸기 래퍼
class _WindowsWebviewWidget extends StatefulWidget {
  final String url;
  final Function(String pageId) onPageChanged;
  final Function(double x, double y) onRightClick;

  const _WindowsWebviewWidget({
    required this.url,
    required this.onPageChanged,
    required this.onRightClick,
  });

  @override
  State<_WindowsWebviewWidget> createState() => _WindowsWebviewWidgetState();
}

class _WindowsWebviewWidgetState extends State<_WindowsWebviewWidget> {
  final WebviewController _controller = WebviewController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    try {
      await _controller.initialize();
      
      _controller.webMessage.listen((msg) {
        if (msg is Map<String, dynamic>) {
          final type = msg['type'];
          if (type == 'rightClick') {
            widget.onRightClick(msg['x'] as double, msg['y'] as double);
          } else if (type == 'pageChanged') {
            widget.onPageChanged(msg['pageId'] as String);
          }
        }
      });

      _controller.url.listen((_) {
        _injectDhashScript();
      });

      await _controller.loadUrl(widget.url);
      setState(() => _initialized = true);
    } catch (_) {}
  }

  void _injectDhashScript() {
    _controller.executeScript('''
      let lastPageId = "";
      function getPageDhash() {
        let raw = (window.location.href + '_' + (document.body ? document.body.innerText.substring(0, 150) : '')).replace(/\\s+/g, '');
        let hash = 0;
        for (let i = 0; i < raw.length; i++) {
          hash = ((hash << 5) - hash) + raw.charCodeAt(i);
          hash |= 0;
        }
        return 'dhash_' + Math.abs(hash);
      }

      function checkPage() {
        let pageId = window.location.hash || window.location.search || document.title;
        let pageNumEl = document.querySelector('.page-num, .pageNum, #pageNo, .page_num, [class*="page"]');
        if (pageNumEl && pageNumEl.innerText) {
          pageId = pageNumEl.innerText.trim();
        }
        if (!pageId || pageId === '') {
          pageId = getPageDhash();
        }
        if (pageId && pageId !== lastPageId) {
          lastPageId = pageId;
          window.chrome?.webview?.postMessage({
            type: 'pageChanged',
            pageId: pageId
          });
        }
      }
      
      if (!window.__boardestDhashInjected) {
        window.__boardestDhashInjected = true;
        setInterval(checkPage, 500);
        window.addEventListener('hashchange', checkPage);
        window.addEventListener('click', () => setTimeout(checkPage, 200));

        window.addEventListener('contextmenu', function(e) {
          e.preventDefault();
          window.chrome?.webview?.postMessage({
            type: 'rightClick',
            x: e.clientX,
            y: e.clientY
          });
        });
      }
    ''');
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)));
    }
    return Webview(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
