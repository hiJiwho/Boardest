import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'pdf_board_view.dart';

/// Boardest .BST 파일 뷰어 라우트
/// - .BST 파일을 로드하여 해당 PDF 및 필기 데이터(.IWB)를 PdfBoardView에 readOnly 모드로 결합하여 표시합니다.
class BstViewerRoute extends StatefulWidget {
  final String bstPath;
  final double scaleFactor;

  const BstViewerRoute({
    super.key,
    required this.bstPath,
    required this.scaleFactor,
  });

  @override
  State<BstViewerRoute> createState() => _BstViewerRouteState();
}

class _BstViewerRouteState extends State<BstViewerRoute> {
  bool _loading = true;
  String? _error;
  String? _pdfPath;
  String? _iwbPath;

  @override
  void initState() {
    super.initState();
    _loadBst();
  }

  Future<void> _loadBst() async {
    try {
      final file = File(widget.bstPath);
      if (!await file.exists()) {
        setState(() {
          _error = '파일을 찾을 수 없습니다:\n${widget.bstPath}';
          _loading = false;
        });
        return;
      }

      final content = await file.readAsString();
      final parsed = jsonDecode(content) as Map<String, dynamic>;

      final usbPath = parsed['usbPath'] as String? ?? '';
      final fileName = parsed['fileName'] as String? ?? '';
      final className = parsed['className'] as String? ?? '일반';

      if (usbPath.isEmpty || fileName.isEmpty) {
        setState(() {
          _error = 'BST 파일 구조가 잘못되었습니다.';
          _loading = false;
        });
        return;
      }

      // 절대 경로 조합
      final pdfPath = p.join(usbPath, 'bst', 'PDF', fileName);
      final iwbPath = p.join(usbPath, 'bst', 'JSON', '[$className]$fileName.IWB');

      if (!File(pdfPath).existsSync()) {
        setState(() {
          _error = '원본 PDF 교안을 찾을 수 없습니다:\n$pdfPath\n\nUSB 연결 상태를 확인해 주세요.';
          _loading = false;
        });
        return;
      }

      setState(() {
        _pdfPath = pdfPath;
        _iwbPath = iwbPath;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'BST 파일을 읽는 중 오류가 발생했습니다:\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  '수업 자료를 열 수 없습니다',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => exit(0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4565),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text('종료', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PdfBoardView(
      initialFilePath: _pdfPath!,
      forcedIwbPath: _iwbPath!,
      scaleFactor: widget.scaleFactor,
    );
  }
}
