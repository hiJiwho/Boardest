import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfBoardView extends StatefulWidget {
  final String filePath;
  final int initialPage;
  final void Function(int page, int total)? onPageChanged;
  final Widget Function(BuildContext context, int page, Size pageSize)? overlayBuilder;

  const PdfBoardView({
    super.key,
    required this.filePath,
    this.initialPage = 0,
    this.onPageChanged,
    this.overlayBuilder,
  });

  @override
  State<PdfBoardView> createState() => _PdfBoardViewState();
}

class _PdfBoardViewState extends State<PdfBoardView> {
  PdfDocument? _pdfDocument;
  int _currentPage = 0;
  int _totalPages = 1;
  bool _isLoading = false;
  String? _loadError;

  final Map<int, Uint8List?> _cachedPages = {};
  final Map<int, Size> _cachedPageSizes = {};

  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _loadPdf();
  }

  @override
  void dispose() {
    _pdfDocument?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final doc = await PdfDocument.openFile(widget.filePath);
      setState(() {
        _pdfDocument = doc;
        _totalPages = doc.pages.length;
      });
      await _preRenderPage(_currentPage);
    } catch (e) {
      setState(() {
        _loadError = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _preRenderPage(int index) async {
    if (_pdfDocument == null || index < 0 || index >= _totalPages) return;
    if (_cachedPages.containsKey(index)) return;

    try {
      final page = _pdfDocument!.pages[index];
      const targetW = 1600.0;
      final targetH = targetW * page.height / page.width;
      final pageImage = await page.render(fullWidth: targetW, fullHeight: targetH);
      
      if (pageImage == null) return;
      
      final img = await pageImage.createImage();
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      pageImage.dispose();
      img.dispose();
      
      if (byteData != null && mounted) {
        setState(() {
          _cachedPages[index] = byteData.buffer.asUint8List();
          _cachedPageSizes[index] = Size(page.width, page.height);
        });
      }
    } catch (e) {
      debugPrint('PDF render error: $e');
    }
  }

  void changePage(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _totalPages) return;
    setState(() {
      _currentPage = targetIndex;
      _transformationController.value = Matrix4.identity();
    });
    _preRenderPage(_currentPage);
    widget.onPageChanged?.call(_currentPage, _totalPages);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Center(child: Text('Error: $_loadError'));
    }
    if (_isLoading || _pdfDocument == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final bytes = _cachedPages[_currentPage];
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final pageSize = _cachedPageSizes[_currentPage] ?? const Size(800, 1131);
    final aspect = pageSize.width / pageSize.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewW = constraints.maxWidth;
        final double viewH = constraints.maxHeight;

        double finalH = viewH;
        double finalW = finalH * aspect;
        if (finalW > viewW) {
          finalW = viewW;
          finalH = finalW / aspect;
        }

        return Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6.0,
                transformationController: _transformationController,
                child: SizedBox(
                  width: finalW,
                  height: finalH,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(bytes, fit: BoxFit.fill),
                      if (widget.overlayBuilder != null)
                        widget.overlayBuilder!(context, _currentPage, pageSize),
                    ],
                  ),
                ),
              ),
            ),
            // 좌우 페이지 이동 버튼
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.black54),
                  onPressed: () => changePage(_currentPage - 1),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.black54),
                  onPressed: () => changePage(_currentPage + 1),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
