import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/board_tools.dart';

/// 기본 칠판(Whiteboard)과 100% 동일한 GoodNotes 플로팅 스타일을 자랑하는 프리미엄 통합 캡슐 툴바
class BoardDockToolbar extends StatefulWidget {
  final double scale;
  final ToolMode tool;
  final ValueChanged<ToolMode> onToolChanged;
  
  final double strokeWidth;
  final ValueChanged<double> onStrokeWidthChanged;
  
  final Color penColor;
  final ValueChanged<Color> onColorChanged;
  
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String? pageLabel;
  final VoidCallback? onPageLabelTap;
  
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onClear;
  final VoidCallback? onClose;

  // Advanced Eraser Options
  final bool? eraseEntireStroke;
  final ValueChanged<bool>? onEraseEntireStrokeChanged;
  final double? eraserSize;
  final ValueChanged<double>? onEraserSizeChanged;

  // URL search options
  final bool showUrlSearch;
  final String urlValue;
  final ValueChanged<String>? onUrlSubmitted;
  final VoidCallback? onUrlRefresh;

  const BoardDockToolbar({
    super.key,
    required this.scale,
    required this.tool,
    required this.onToolChanged,
    required this.strokeWidth,
    required this.onStrokeWidthChanged,
    required this.penColor,
    required this.onColorChanged,
    this.onPrev,
    this.onNext,
    this.pageLabel,
    this.onPageLabelTap,
    this.onUndo,
    this.onRedo,
    this.onClear,
    this.onClose,
    this.eraseEntireStroke,
    this.onEraseEntireStrokeChanged,
    this.eraserSize,
    this.onEraserSizeChanged,
    this.showUrlSearch = false,
    this.urlValue = '',
    this.onUrlSubmitted,
    this.onUrlRefresh,
  });

  @override
  State<BoardDockToolbar> createState() => _BoardDockToolbarState();
}

class _BoardDockToolbarState extends State<BoardDockToolbar> {
  bool _isPenDetailsOpen = false;
  bool _isEraserDetailsOpen = false;
  bool _isUrlSearchOpen = false;
  late TextEditingController _urlInputCtrl;

  @override
  void initState() {
    super.initState();
    _urlInputCtrl = TextEditingController(text: widget.urlValue);
  }

  @override
  void didUpdateWidget(covariant BoardDockToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.urlValue != oldWidget.urlValue) {
      _urlInputCtrl.text = widget.urlValue;
    }
  }

  @override
  void dispose() {
    _urlInputCtrl.dispose();
    super.dispose();
  }

  static const _colors = [
    Colors.white,
    Colors.black,
    Color(0xFFEF4565), // 빨강
    Color(0xFFFFD60A), // 노랑
    Color(0xFF00F5D4), // 민트
    Color(0xFF3DA9FC), // 파랑
    Color(0xFF2CB67D), // 초록
    Colors.orange,
    Colors.purple,
  ];

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Pen Details Card Pop-up
        if (_isPenDetailsOpen && widget.tool == ToolMode.pen) ...[
          _buildPenDetailsCard(scale),
          const SizedBox(height: 8),
        ],

        // 2. Eraser details card Pop-up
        if (_isEraserDetailsOpen && widget.tool == ToolMode.eraser) ...[
          _buildEraserDetailsCard(scale),
          const SizedBox(height: 8),
        ],

        // 2.5 URL Search Details Card Pop-up
        if (_isUrlSearchOpen && widget.showUrlSearch) ...[
          _buildUrlSearchDetailsCard(scale),
          const SizedBox(height: 8),
        ],

        // 3. GoodNotes Styled Main Capsule Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF13171F).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 삼선 메뉴 아이콘 형태의 닫기/종료 버튼
              if (widget.onClose != null)
                IconButton(
                  tooltip: '종료',
                  icon: const Icon(Icons.power_settings_new_rounded, color: Color(0xFFFF6464)),
                  onPressed: widget.onClose,
                ),

              // Page indicators (이전 / pageLabel / 다음)
              if (widget.onPrev != null || widget.onNext != null || widget.pageLabel != null) ...[
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                  onPressed: widget.onPrev,
                ),
                if (widget.pageLabel != null)
                  GestureDetector(
                    onTap: widget.onPageLabelTap,
                    child: Text(
                      widget.pageLabel!,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 13 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                  onPressed: widget.onNext,
                ),
                _buildSeparator(),
              ],

              // 1. Pen Tool (Double click to open details)
              _buildToolDockBtn(
                Icons.edit_rounded,
                '펜 도구',
                ToolMode.pen,
                () {
                  if (widget.tool == ToolMode.pen) {
                    setState(() {
                      _isPenDetailsOpen = !_isPenDetailsOpen;
                      _isEraserDetailsOpen = false;
                      _isUrlSearchOpen = false;
                    });
                  } else {
                    widget.onToolChanged(ToolMode.pen);
                    setState(() {
                      _isPenDetailsOpen = false;
                      _isEraserDetailsOpen = false;
                      _isUrlSearchOpen = false;
                    });
                  }
                },
                scale,
              ),

              // 2. Eraser Tool
              _buildToolDockBtn(
                Icons.auto_fix_high_rounded,
                '지우개 도구',
                ToolMode.eraser,
                () {
                  if (widget.tool == ToolMode.eraser) {
                    setState(() {
                      _isEraserDetailsOpen = !_isEraserDetailsOpen;
                      _isPenDetailsOpen = false;
                      _isUrlSearchOpen = false;
                    });
                  } else {
                    widget.onToolChanged(ToolMode.eraser);
                    setState(() {
                      _isPenDetailsOpen = false;
                      _isEraserDetailsOpen = false;
                      _isUrlSearchOpen = false;
                    });
                  }
                },
                scale,
              ),

              // 3. Lasso select tool
              _buildToolDockBtn(
                Icons.select_all_rounded,
                '올가미 도구',
                ToolMode.select,
                () {
                  widget.onToolChanged(ToolMode.select);
                  setState(() {
                    _isPenDetailsOpen = false;
                    _isEraserDetailsOpen = false;
                    _isUrlSearchOpen = false;
                  });
                },
                scale,
              ),

              // 4. Pan Tool (조작/이동)
              _buildToolDockBtn(
                Icons.pan_tool_rounded,
                '조작 및 이동 도구',
                ToolMode.pointer,
                () {
                  widget.onToolChanged(ToolMode.pointer);
                  setState(() {
                    _isPenDetailsOpen = false;
                    _isEraserDetailsOpen = false;
                    _isUrlSearchOpen = false;
                  });
                },
                scale,
              ),

              // 4.5 URL Search Tool (돋보기)
              if (widget.showUrlSearch)
                Tooltip(
                  message: '사이트 검색/이동',
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isUrlSearchOpen = !_isUrlSearchOpen;
                        _isPenDetailsOpen = false;
                        _isEraserDetailsOpen = false;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isUrlSearchOpen ? const Color(0xFF00F5D4).withOpacity(0.18) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _isUrlSearchOpen ? const Color(0xFF00F5D4) : Colors.transparent),
                      ),
                      child: Icon(Icons.search_rounded, color: _isUrlSearchOpen ? const Color(0xFF00F5D4) : Colors.white70, size: 18 * scale),
                    ),
                  ),
                ),

              _buildSeparator(),

              // Undo / Redo
              IconButton(
                icon: const Icon(Icons.undo_rounded, color: Colors.white70),
                onPressed: widget.onUndo,
              ),
              if (widget.onRedo != null)
                IconButton(
                  icon: const Icon(Icons.redo_rounded, color: Colors.white70),
                  onPressed: widget.onRedo,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeparator() {
    return Container(
      width: 1,
      height: 20,
      color: Colors.white12,
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildToolDockBtn(IconData icon, String tooltip, ToolMode mode, VoidCallback onTap, double scale) {
    final active = widget.tool == mode;
    final activeColor = const Color(0xFF00F5D4);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active ? activeColor.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? activeColor : Colors.transparent),
          ),
          child: Icon(icon, color: active ? activeColor : Colors.white70, size: 18 * scale),
        ),
      ),
    );
  }

  Widget _buildPenDetailsCard(double scale) {
    return Card(
      color: const Color(0xFF13171F).withOpacity(0.96),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      child: Container(
        width: 240 * scale,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '펜 색상 & 굵기 설정',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11 * scale, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _colors.map((c) {
                final active = widget.penColor.value == c.value;
                return GestureDetector(
                  onTap: () {
                    widget.onColorChanged(c);
                    if (widget.tool != ToolMode.pen) {
                      widget.onToolChanged(ToolMode.pen);
                    }
                  },
                  child: Container(
                    width: 22 * scale,
                    height: 22 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c,
                      border: Border.all(color: active ? Colors.white : Colors.white24, width: active ? 2 : 1),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.line_weight_rounded, color: Colors.white60, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    min: 1.0,
                    max: 20.0,
                    value: widget.strokeWidth.clamp(1.0, 20.0),
                    activeColor: const Color(0xFF00F5D4),
                    onChanged: widget.onStrokeWidthChanged,
                  ),
                ),
                Text(
                  '${widget.strokeWidth.toStringAsFixed(0)}px',
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10 * scale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEraserDetailsCard(double scale) {
    final eraseEntire = widget.eraseEntireStroke ?? false;
    final eraserSize = widget.eraserSize ?? 30.0;

    return Card(
      color: const Color(0xFF13171F).withOpacity(0.96),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.16)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_fix_high_rounded, color: Colors.tealAccent, size: 16),
            const SizedBox(width: 8),
            Text(
              '지우개 종류:',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 10 * scale, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: !eraseEntire ? const Color(0xFF00F5D4).withOpacity(0.2) : Colors.transparent,
                foregroundColor: !eraseEntire ? const Color(0xFF00F5D4) : Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('부분 지우개', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
              onPressed: () {
                widget.onEraseEntireStrokeChanged?.call(false);
              },
            ),
            const SizedBox(width: 6),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: eraseEntire ? const Color(0xFF00F5D4).withOpacity(0.2) : Colors.transparent,
                foregroundColor: eraseEntire ? const Color(0xFF00F5D4) : Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('획 지우개', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
              onPressed: () {
                widget.onEraseEntireStrokeChanged?.call(true);
              },
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: Colors.white24),
            const SizedBox(width: 12),
            Text(
              '크기:',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 10 * scale, fontWeight: FontWeight.bold),
            ),
            SizedBox(
              width: 100 * scale,
              child: Slider(
                value: eraserSize.clamp(5.0, 100.0),
                min: 5.0,
                max: 100.0,
                activeColor: const Color(0xFF00F5D4),
                onChanged: (val) {
                  widget.onEraserSizeChanged?.call(val);
                },
              ),
            ),
            if (widget.onClear != null) ...[
              const SizedBox(width: 12),
              Container(width: 1, height: 16, color: Colors.white24),
              const SizedBox(width: 12),
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4565).withOpacity(0.15),
                  foregroundColor: const Color(0xFFEF4565),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 12),
                label: Text(
                  '초기화',
                  style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  widget.onClear!();
                  setState(() {
                    _isEraserDetailsOpen = false;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUrlSearchDetailsCard(double scale) {
    return Card(
      color: const Color(0xFF13171F).withOpacity(0.96),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.16)),
      ),
      child: Container(
        width: 320 * scale,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.language_rounded, color: Color(0xFF00F5D4), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 32 * scale,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: TextField(
                  controller: _urlInputCtrl,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 12 * scale),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'https://주소 입력',
                    hintStyle: TextStyle(color: Colors.white30),
                  ),
                  onSubmitted: (url) {
                    widget.onUrlSubmitted?.call(url);
                    setState(() {
                      _isUrlSearchOpen = false;
                    });
                  },
                ),
              ),
            ),
            if (widget.onUrlRefresh != null) ...[
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.refresh_rounded, color: Colors.white70, size: 18 * scale),
                onPressed: widget.onUrlRefresh,
              ),
            ],
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4).withOpacity(0.15),
                foregroundColor: const Color(0xFF00F5D4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                '이동',
                style: GoogleFonts.notoSansKr(fontSize: 10.5 * scale, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                widget.onUrlSubmitted?.call(_urlInputCtrl.text);
                setState(() {
                  _isUrlSearchOpen = false;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
