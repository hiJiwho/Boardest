import 'dart:convert';
import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/board_tools.dart';
import '../widgets/annotation_canvas.dart';
import '../widgets/board_toolbar.dart';
import '../services/annotation_storage_service.dart';
import '../services/usb_session_service.dart';
import '../services/bst_cloud_service.dart';
import '../services/storage_service.dart';

/// GoodNotes / Samsung Notes 스타일의 프리미엄 인앱 PDF + 판서 통합 뷰
class PdfBoardView extends StatefulWidget {
  final String initialFilePath;
  final Uint8List? pdfData;
  final double scaleFactor;
  final String? usbSessionId;
  final int initialPage;
  final void Function(String filePath, int page, int total)? onPageChanged;
  final void Function(String filePath)? onLastPageNext;
  final bool readOnly;
  final String? forcedIwbPath;
  final String? classCode;

  const PdfBoardView({
    super.key,
    required this.initialFilePath,
    this.pdfData,
    required this.scaleFactor,
    this.usbSessionId,
    this.initialPage = 0,
    this.onPageChanged,
    this.onLastPageNext,
    this.readOnly = false,
    this.forcedIwbPath,
    this.classCode,
  });

  @override
  State<PdfBoardView> createState() => _PdfBoardViewState();
}

class _PdfBoardViewState extends State<PdfBoardView>
    with TickerProviderStateMixin {
  int _currentPage = 0;
  int _totalPages = 1;
  String _fileName = '불러온 교안 없음';
  String? _pdfFilePath;

  PdfDocument? _pdfDocument;
  final Map<int, Uint8List?> _cachedPages = {};
  final Map<int, Uint8List?> _cachedThumbnails = {};
  final Map<int, Size> _cachedPageSizes = {};
  bool _isLoading = false;

  String _selectedClassForPen = '';

  bool _isSidebarOpen = true;
  final Map<int, List<AnnotationStroke>> _pageAnnotations = {};
  final Map<int, AnnotationController> _pageControllers = {};

  Color _penColor = const Color(0xFFEF4565);
  double _strokeWidth = 4.0;
  ToolMode _tool = ToolMode.pen;
  ShapeType _activeShape = ShapeType.line;
  bool _isPenDetailsOpen = false;
  bool _eraseEntireStroke = false;
  double _eraserSize = 30.0;
  String? _loadError;

  final Color _backgroundColor = const Color(0xFF161920);
  Timer? _autoSaveTimer;

  // 화면 크기 피팅 스타일 (true = 화면 세로 맞춤(한눈에 보기), false = 가로 맞춤(스크롤 가능))
  bool _fitToHeight = true;
  final ScrollController _scrollController = ScrollController();
  final TransformationController _transformationController =
      TransformationController();
  double _fitWidthScale = 1.0;

  void _setZoom(double targetScale) {
    targetScale = targetScale.clamp(0.5, 6.0);
    final matrix = _transformationController.value.clone();
    matrix[0] = targetScale;
    matrix[5] = targetScale;
    _transformationController.value = matrix;
  }

  @override
  void initState() {
    super.initState();
    _loadEraserPrefs();
    if (widget.initialFilePath.isNotEmpty || widget.pdfData != null) {
      _loadPdf(widget.initialFilePath, bytes: widget.pdfData);
    }
  }

  Future<void> _loadEraserPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _eraseEntireStroke = prefs.getBool('whiteboard_erase_entire') ?? false;
      _eraserSize = prefs.getDouble('whiteboard_eraser_size') ?? 30.0;
    });
  }

  void _syncControllerTooling(AnnotationController ctrl) {
    ctrl.toolMode = _tool;
    ctrl.activeColor = _penColor;
    ctrl.activeWidth = _strokeWidth;
    ctrl.eraseEntireStroke = _eraseEntireStroke;
    ctrl.eraserSize = _eraserSize;
    ctrl.activeShape = _activeShape;
  }

  void _syncAllControllers() {
    for (final ctrl in _pageControllers.values) {
      _syncControllerTooling(ctrl);
    }
  }

  void _setTool(ToolMode mode) {
    setState(() {
      _tool = mode;
      _isPenDetailsOpen = false;
    });
    _syncAllControllers();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (widget.usbSessionId != null && _pdfFilePath != null) {
      UsbSessionService.instance.updateFileState(
        widget.usbSessionId!,
        _pdfFilePath!,
        _currentPage,
        _totalPages,
      );
    }
    _pdfDocument?.dispose();
    _scrollController.dispose();
    _transformationController.dispose();
    for (final ctrl in _pageControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPdf(String filePath, {Uint8List? bytes}) async {
    final fileName = filePath.split(RegExp(r'[\\/]')).last;
    final s = await StorageService().getSettings();
    setState(() {
      _selectedClassForPen = '${s.selectedGrade}학년 ${s.selectedClass}반';
      _isLoading = true;
      _loadError = null;
      _pdfFilePath = filePath;
      _fileName = fileName.isNotEmpty ? fileName : '교안 문서';
      _cachedPages.clear();
      _cachedThumbnails.clear();
      _cachedPageSizes.clear();
      _pageAnnotations.clear();
      for (final ctrl in _pageControllers.values) {
        ctrl.dispose();
      }
      _pageControllers.clear();
      _currentPage = 0;
    });

    try {
      PdfDocument doc;
      if (bytes != null) {
        doc = await PdfDocument.openData(bytes);
      } else if (kIsWeb) {
        if (BstCloudService.webMemoryFiles.containsKey(filePath)) {
          doc = await PdfDocument.openData(BstCloudService.webMemoryFiles[filePath]!);
        } else if (filePath.startsWith('http://') || filePath.startsWith('https://') || filePath.startsWith('blob:')) {
          doc = await PdfDocument.openUri(Uri.parse(filePath));
        } else {
          doc = await PdfDocument.openUri(Uri.parse(filePath));
        }
      } else {
        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception('파일을 찾을 수 없습니다.');
        }
        try {
          doc = await PdfDocument.openFile(filePath);
        } catch (_) {
          doc = await PdfDocument.openData(await file.readAsBytes());
        }
      }

      if (doc.pages.isEmpty) {
        throw Exception('PDF 페이지가 없습니다.');
      }

      Map<int, List<AnnotationStroke>> loadedAnnotations = {};

      // 1. Cloud 'bst-pen'에서 본인 학급 전용 .file.pen 다운로드 및 복원 시도
      final token = BstCloudService.instance.activeToken;
      final effectiveClassCode = widget.classCode ?? _selectedClassForPen;
      if (token != null && token.isNotEmpty) {
        final cloudBytes = await BstCloudService.instance.fetchFilePenBytes(
          originalFileName: _fileName,
          accessToken: token,
          classCode: effectiveClassCode.isNotEmpty ? effectiveClassCode : null,
        );
        if (cloudBytes != null && cloudBytes.isNotEmpty) {
          try {
            final jsonMap = json.decode(utf8.decode(cloudBytes)) as Map<String, dynamic>;
            final pages = jsonMap['pages'] as Map<String, dynamic>? ?? {};
            pages.forEach((pageKey, strokeList) {
              final pIdx = int.tryParse(pageKey);
              if (pIdx != null && strokeList is List) {
                loadedAnnotations[pIdx] = strokeList
                    .map<AnnotationStroke>((item) => AnnotationStroke.fromJson(item as Map<String, dynamic>))
                    .toList();
              }
            });
            debugPrint('[PdfBoardView] Loaded ${loadedAnnotations.length} pages of annotations from Cloud (.file.pen)');
          } catch (e) {
            debugPrint('[PdfBoardView] Cloud annotation decode error: $e');
          }
        }
      }

      // 2. Web LocalStorage 복원 시도
      if (loadedAnnotations.isEmpty && kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final rawJson = prefs.getString('web_pdf_pen_$_fileName');
        if (rawJson != null && rawJson.isNotEmpty) {
          try {
            final jsonMap = json.decode(rawJson) as Map<String, dynamic>;
            final pages = jsonMap['pages'] as Map<String, dynamic>? ?? {};
            pages.forEach((pageKey, strokeList) {
              final pIdx = int.tryParse(pageKey);
              if (pIdx != null && strokeList is List) {
                loadedAnnotations[pIdx] = strokeList
                    .map<AnnotationStroke>((item) => AnnotationStroke.fromJson(item as Map<String, dynamic>))
                    .toList();
              }
            });
          } catch (_) {}
        }
      }

      // 3. Desktop 로컬 스토리지 복원
      if (loadedAnnotations.isEmpty && !kIsWeb) {
        loadedAnnotations = await AnnotationStorageService.instance
            .loadDocumentAnnotations(
              'PDF',
              _fileName,
              fullFilePath: filePath,
              className: _selectedClassForPen,
              forcedFile: widget.forcedIwbPath != null
                  ? File(widget.forcedIwbPath!)
                  : null,
            );
      }

      final metadata = await AnnotationStorageService.instance
          .loadDocumentMetadata('PDF', _fileName, fullFilePath: filePath);
      int startPage = widget.initialPage;
      if (metadata != null && metadata['lastPage'] != null) {
        startPage = metadata['lastPage'] as int;
      } else {
        final prefs = await SharedPreferences.getInstance();
        final savedPage = prefs.getInt('pdf_page_$filePath');
        if (savedPage != null) {
          startPage = savedPage;
        }
      }
      startPage = startPage.clamp(0, doc.pages.length - 1);

      if (mounted) {
        setState(() {
          _pdfDocument = doc;
          _totalPages = doc.pages.length;
          _pageAnnotations.addAll(loadedAnnotations);
          _currentPage = startPage;
        });
      }

      await _preRenderPage(_currentPage);

      // 주변 페이지 미리 렌더링 (백그라운드 캐싱)
      _preRenderSiblings();

      // Save/sync initial status
      await _saveAllAnnotations();

      if (widget.usbSessionId != null) {
        _autoSaveTimer?.cancel();
        _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          if (_pdfFilePath != null) {
            UsbSessionService.instance.updateFileState(
              widget.usbSessionId!,
              _pdfFilePath!,
              _currentPage,
              _totalPages,
            );
          }
        });
        widget.onPageChanged?.call(filePath, _currentPage, _totalPages);
      }
    } catch (e, st) {
      debugPrint('PDF load error: $e\n$st');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _pdfFilePath = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF 로딩 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _preRenderSiblings() {
    if (_pdfDocument == null) return;
    for (int offset = 1; offset <= 3; offset++) {
      final nextIdx = _currentPage + offset;
      if (nextIdx < _totalPages) {
        _preRenderPage(nextIdx);
      }
      final prevIdx = _currentPage - offset;
      if (prevIdx >= 0) {
        _preRenderPage(prevIdx);
      }
    }
  }

  Future<void> _preRenderPage(int index) async {
    if (_pdfDocument == null || index < 0 || index >= _totalPages) return;
    if (_cachedPages.containsKey(index)) return;

    try {
      final page = _pdfDocument!.pages[index];

      // 고화질 메인 뷰 렌더링
      const targetW = 1600.0;
      final targetH = targetW * page.height / page.width;
      final pageImage = await page.render(
        fullWidth: targetW,
        fullHeight: targetH,
      );
      if (pageImage == null) return;

      final img = await pageImage.createImage();
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      pageImage.dispose();
      img.dispose();

      // 저화질 사이드바 썸네일 렌더링
      const thumbW = 160.0;
      final thumbH = thumbW * page.height / page.width;
      final thumbImage = await page.render(
        fullWidth: thumbW,
        fullHeight: thumbH,
      );
      Uint8List? thumbBytes;
      if (thumbImage != null) {
        final tImg = await thumbImage.createImage();
        final tData = await tImg.toByteData(format: ui.ImageByteFormat.png);
        thumbImage.dispose();
        tImg.dispose();
        if (tData != null) {
          thumbBytes = tData.buffer.asUint8List();
        }
      }

      if (byteData != null && mounted) {
        setState(() {
          _cachedPages[index] = byteData.buffer.asUint8List();
          _cachedThumbnails[index] = thumbBytes;
          _cachedPageSizes[index] = Size(page.width, page.height);
        });
      }
    } catch (e) {
      debugPrint('PDF page render $index: $e');
    }
  }

  void _changePage(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _totalPages) {
      if (targetIndex >= _totalPages && _pdfFilePath != null) {
        Navigator.pop(context, true);
      }
      return;
    }

    setState(() {
      _currentPage = targetIndex;
      _transformationController.value = Matrix4.identity();
    });

    // Save PDF page locally in SharedPreferences
    if (_pdfFilePath != null) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('pdf_page_$_pdfFilePath', targetIndex);
        if (targetIndex >= _totalPages - 1) {
          prefs.setBool('pdf_completed_$_pdfFilePath', true);
        }
      });
      unawaited(_saveAllAnnotations());
    }

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }

    _preRenderPage(_currentPage);
    _preRenderSiblings();

    if (widget.usbSessionId != null && _pdfFilePath != null) {
      UsbSessionService.instance.updateFileState(
        widget.usbSessionId!,
        _pdfFilePath!,
        _currentPage,
        _totalPages,
      );
      widget.onPageChanged?.call(_pdfFilePath!, _currentPage, _totalPages);
    }
  }

  Future<void> _pickPdfFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb,
    );
    if (result != null) {
      if (kIsWeb && result.files.single.bytes != null) {
        await _loadPdf(result.files.single.name, bytes: result.files.single.bytes);
      } else if (result.files.single.path != null) {
        await _loadPdf(result.files.single.path!);
      }
    }
  }

  Future<void> _saveAllAnnotations() async {
    if (_pdfFilePath == null && _fileName.isEmpty) return;

    final Map<int, List<Map<String, dynamic>>> serializable = {};
    _pageAnnotations.forEach((pageIdx, strokes) {
      serializable[pageIdx] = strokes.map<Map<String, dynamic>>((s) => s.toJson()).toList();
    });

    final payload = json.encode({
      'version': 2,
      'type': 'pdf_pen',
      'fileName': _fileName,
      'lastPage': _currentPage,
      'totalPages': _totalPages,
      'pages': serializable.map((k, v) => MapEntry(k.toString(), v)),
      'updatedAt': DateTime.now().toIso8601String(),
    });

    // 1. Cloud 'bst-pen' 폴더에 본인 학급 전용 .file.pen 백업 동기화
    final token = BstCloudService.instance.activeToken;
    final effectiveClassCode = widget.classCode ?? _selectedClassForPen;
    if (token != null && token.isNotEmpty) {
      final cloudPenName = effectiveClassCode.isNotEmpty
          ? '${effectiveClassCode}_$_fileName.file.pen'
          : '$_fileName.file.pen';
      unawaited(
        BstCloudService.instance.uploadPenBytesDirectly(
          fileName: cloudPenName,
          bytes: Uint8List.fromList(utf8.encode(payload)),
          targetFolderName: 'bst-pen',
        ),
      );
    }

    // 2. Web LocalStorage 영구 보관
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('web_pdf_pen_$_fileName', payload);
      await prefs.setInt('pdf_page_$_fileName', _currentPage);
      debugPrint('[PdfBoardView] Saved PDF annotations to web storage for $_fileName');
      return;
    }

    // 3. Desktop 로컬 저장
    final metadata = {
      'filePath': _pdfFilePath,
      'fileName': _fileName,
      'type': 'pdf',
      'lastPage': _currentPage,
      'totalPages': _totalPages,
      'lastOpened': DateTime.now().toIso8601String(),
    };
    await AnnotationStorageService.instance.saveDocumentAnnotations(
      'PDF',
      _fileName,
      metadata,
      _pageAnnotations,
      fullFilePath: _pdfFilePath,
      className: _selectedClassForPen,
    );
  }

    void _clearCanvas() {
    final activeCtrl = _pageControllers[_currentPage];
    if (activeCtrl != null) {
      activeCtrl.clear();
      setState(() {
        _pageAnnotations[_currentPage] = [];
      });
      unawaited(_saveAllAnnotations());
    }
  }

  void _undoActivePage() {
    final activeCtrl = _pageControllers[_currentPage];
    if (activeCtrl != null) {
      activeCtrl.undo();
    }
  }

  AnnotationController _getOrCreateController(int pageIndex) {
    return _pageControllers.putIfAbsent(pageIndex, () {
      final ctrl = AnnotationController();
      _syncControllerTooling(ctrl);

      // Load pre-loaded strokes if any
      final existingStrokes = _pageAnnotations[pageIndex];
      if (existingStrokes != null && existingStrokes.isNotEmpty) {
        ctrl.strokes.addAll(existingStrokes);
      }

      ctrl.addListener(() {
        final strokes = List<AnnotationStroke>.from(ctrl.strokes);
        _pageAnnotations[pageIndex] = strokes;
        unawaited(_saveAllAnnotations());
        // 사이드바 상태 업데이트용
        if (mounted) setState(() {});
      });
      return ctrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Row(
        children: [
          // 사이드바 (페이지 리스트 및 썸네일)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Container(
              width: _isSidebarOpen ? 210 * scale : 0.0,
              child: _isSidebarOpen
                  ? _buildSidebar(scale)
                  : const SizedBox.shrink(),
            ),
          ),
          // 메인 뷰포트
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildPdfSinglePageView(scale)),

                // 반 선택 Selector Top Bar
                Positioned(
                  top: 12 * scale,
                  left: 16 * scale,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12 * scale,
                      vertical: 4 * scale,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12 * scale),
                      border: Border.all(
                        color: const Color(0xFF2EC4B6).withOpacity(0.5),
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.class_rounded,
                          color: Color(0xFF2EC4B6),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedClassForPen.isNotEmpty ? _selectedClassForPen : '현재 학급',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 최하단 툴바 독
                Positioned(
                  bottom: 16 * scale,
                  left: 16 * scale,
                  right: 16 * scale,
                  child: Center(child: _buildDock(scale)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfSinglePageView(double scale) {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(
              'PDF를 불러오지 못했습니다',
              style: GoogleFonts.notoSansKr(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _pickPdfFile, child: const Text('다시 선택')),
          ],
        ),
      );
    }

    if (_pdfFilePath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.picture_as_pdf_rounded,
              size: 64 * scale,
              color: Colors.white12,
            ),
            const SizedBox(height: 16),
            Text(
              'PDF 교안을 불러오세요',
              style: GoogleFonts.notoSansKr(
                color: Colors.white30,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _pickPdfFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: Colors.black87,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: Text(
                'PDF 파일 선택',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
      );
    }

    final bytes = _cachedPages[_currentPage];
    if (bytes == null) {
      _preRenderPage(_currentPage);
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
      );
    }

    final pageSize = _cachedPageSizes[_currentPage] ?? const Size(800, 1131);
    final aspect = pageSize.width / pageSize.height;
    final ctrl = _getOrCreateController(_currentPage);

    // 플랫 드로잉 영역 크기 계산
    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewW = constraints.maxWidth;
        final double viewH = constraints.maxHeight;

        // 패딩 계산 (하단 툴바가 가리지 않는 선에서 최대 공간 제공)
        final double availW = viewW - 24 * scale;
        final double availH = viewH - 96 * scale;

        double finalH = availH;
        double finalW = finalH * aspect;
        if (finalW > availW) {
          finalW = availW;
          finalH = finalW / aspect;
        }

        if (finalW > 0) {
          _fitWidthScale = availW / finalW;
        }

        final isPointerMode = widget.readOnly || _tool == ToolMode.pointer;

        final mainCanvas = Material(
          elevation: 12,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          child: SizedBox(
            width: finalW,
            height: finalH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(bytes, fit: BoxFit.fill),
                AnnotationCanvas(
                  controller: ctrl,
                  enabled:
                      !widget.readOnly &&
                      (_tool == ToolMode.pen ||
                          _tool == ToolMode.eraser ||
                          _tool == ToolMode.select),
                ),
              ],
            ),
          ),
        );

        return Center(
          child: Padding(
            padding: EdgeInsets.only(top: 24 * scale, bottom: 64 * scale),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6.0,
              panEnabled: isPointerMode,
              scaleEnabled: isPointerMode,
              transformationController: _transformationController,
              clipBehavior: Clip.none,
              child: mainCanvas,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar(double scale) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1116),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.04), width: 1.0),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 10 * scale,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  color: Color(0xFF00F5D4),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '페이지 정보',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13 * scale,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _totalPages,
              itemBuilder: (context, i) {
                final isSelected = _currentPage == i;
                final thumbBytes = _cachedThumbnails[i];
                final hasAnnotation =
                    _pageAnnotations[i] != null &&
                    _pageAnnotations[i]!.isNotEmpty;

                return GestureDetector(
                  onTap: () => _changePage(i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00F5D4).withOpacity(0.06)
                          : Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF00F5D4).withOpacity(0.5)
                            : Colors.white.withOpacity(0.04),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 썸네일 박스
                          AspectRatio(
                            aspectRatio: 0.707, // A4 표준 비율
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2129),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.06),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: thumbBytes != null
                                  ? Image.memory(thumbBytes, fit: BoxFit.fill)
                                  : Center(
                                      child: Icon(
                                        Icons.image,
                                        color: Colors.white10,
                                        size: 24 * scale,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${i + 1} 쪽',
                                style: GoogleFonts.outfit(
                                  color: isSelected
                                      ? const Color(0xFF00F5D4)
                                      : Colors.white54,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 11 * scale,
                                ),
                              ),
                              if (hasAnnotation)
                                Icon(
                                  Icons.gesture_rounded,
                                  color: const Color(
                                    0xFF00F5D4,
                                  ).withOpacity(0.7),
                                  size: 13 * scale,
                                ),
                            ],
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
  }

  Widget _buildDock(double scale) {
    final zoomControls = Container(
      margin: EdgeInsets.only(left: 12 * scale),
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 8 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF13171F).withOpacity(0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '축소',
            icon: Icon(
              Icons.zoom_out_rounded,
              color: Colors.white70,
              size: 20 * scale,
            ),
            onPressed: () {
              double currentScale = _transformationController.value
                  .getMaxScaleOnAxis();
              _setZoom(currentScale - 0.25);
            },
            constraints: const BoxConstraints(),
            padding: EdgeInsets.symmetric(horizontal: 6 * scale),
          ),
          ValueListenableBuilder<Matrix4>(
            valueListenable: _transformationController,
            builder: (context, matrix, child) {
              final percent = (matrix.getMaxScaleOnAxis() * 100).toInt();
              return GestureDetector(
                onTap: () {
                  _transformationController.value = Matrix4.identity();
                },
                child: Container(
                  width: 48 * scale,
                  alignment: Alignment.center,
                  child: Text(
                    '$percent%',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '확대',
            icon: Icon(
              Icons.zoom_in_rounded,
              color: Colors.white70,
              size: 20 * scale,
            ),
            onPressed: () {
              double currentScale = _transformationController.value
                  .getMaxScaleOnAxis();
              _setZoom(currentScale + 0.25);
            },
            constraints: const BoxConstraints(),
            padding: EdgeInsets.symmetric(horizontal: 6 * scale),
          ),
          Container(
            width: 1,
            height: 20 * scale,
            color: Colors.white12,
            margin: EdgeInsets.symmetric(horizontal: 4 * scale),
          ),
          IconButton(
            tooltip: '폭 맞추기',
            icon: Icon(
              Icons.swap_horiz_rounded,
              color: Colors.white70,
              size: 20 * scale,
            ),
            onPressed: () => _setZoom(_fitWidthScale),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.symmetric(horizontal: 6 * scale),
          ),
          if (!widget.readOnly) ...[
            Container(
              width: 1,
              height: 20 * scale,
              color: Colors.white12,
              margin: EdgeInsets.symmetric(horizontal: 4 * scale),
            ),
            IconButton(
              tooltip: _tool == ToolMode.pointer
                  ? '현재: 조작/이동 (펜으로 전환)'
                  : '현재: 펜/판서 (조작으로 전환)',
              icon: Icon(
                _tool == ToolMode.pointer
                    ? Icons.pan_tool_rounded
                    : Icons.edit_rounded,
                color: const Color(0xFF00F5D4),
                size: 20 * scale,
              ),
              onPressed: () {
                if (_tool == ToolMode.pointer) {
                  _setTool(ToolMode.pen);
                } else {
                  _setTool(ToolMode.pointer);
                }
              },
              constraints: const BoxConstraints(),
              padding: EdgeInsets.symmetric(horizontal: 6 * scale),
            ),
          ],
        ],
      ),
    );

    if (widget.readOnly) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            height: 52 * scale,
            padding: EdgeInsets.symmetric(horizontal: 16 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16 * scale),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10 * scale,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _currentPage > 0 ? Colors.white : Colors.white24,
                    size: 18 * scale,
                  ),
                  onPressed: _currentPage > 0
                      ? () => _changePage(_currentPage - 1)
                      : null,
                ),
                SizedBox(width: 8 * scale),
                Text(
                  '${_currentPage + 1} / $_totalPages 쪽',
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 8 * scale),
                IconButton(
                  icon: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _currentPage < _totalPages - 1
                        ? Colors.white
                        : Colors.white24,
                    size: 18 * scale,
                  ),
                  onPressed: _currentPage < _totalPages - 1
                      ? () => _changePage(_currentPage + 1)
                      : null,
                ),
                SizedBox(width: 12 * scale),
                Container(
                  width: 1.5,
                  height: 20 * scale,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                SizedBox(width: 12 * scale),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: const Color(0xFFEF4565),
                    size: 18 * scale,
                  ),
                  label: Text(
                    '닫기',
                    style: GoogleFonts.notoSansKr(
                      color: const Color(0xFFEF4565),
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                    backgroundColor: const Color(
                      0xFFEF4565,
                    ).withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8 * scale),
                    ),
                  ),
                ),
              ],
            ),
          ),
          zoomControls,
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        BoardDockToolbar(
          scale: scale,
          tool: _tool,
          onToolChanged: _setTool,
          strokeWidth: _strokeWidth,
          onStrokeWidthChanged: (w) {
            setState(() {
              _strokeWidth = w;
              _tool = ToolMode.pen;
            });
            _syncAllControllers();
          },
          penColor: _penColor,
          onColorChanged: (c) {
            setState(() {
              _penColor = c;
              _tool = ToolMode.pen;
            });
            _syncAllControllers();
          },
          activeShape: _activeShape,
          onShapeChanged: (shape) {
            setState(() {
              _activeShape = shape;
              _tool = ToolMode.shape;
            });
            _syncAllControllers();
          },
          onPrev: _currentPage > 0 ? () => _changePage(_currentPage - 1) : null,
          onNext: _currentPage < _totalPages - 1
              ? () => _changePage(_currentPage + 1)
              : null,
          pageLabel: '${_currentPage + 1} / $_totalPages 쪽 (이동)',
          onPageLabelTap: () =>
              setState(() => _isSidebarOpen = !_isSidebarOpen),
          onUndo: _undoActivePage,
          onClear: _clearCanvas,
          onClose: () => Navigator.pop(context),
          eraseEntireStroke: _eraseEntireStroke,
          onEraseEntireStrokeChanged: (val) async {
            setState(() => _eraseEntireStroke = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('whiteboard_erase_entire', val);
            _syncAllControllers();
          },
          eraserSize: _eraserSize,
          onEraserSizeChanged: (val) async {
            setState(() => _eraserSize = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('whiteboard_eraser_size', val);
            _syncAllControllers();
          },
        ),
        zoomControls,
      ],
    );
  }
}
