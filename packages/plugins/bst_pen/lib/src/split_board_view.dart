import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'annotation_canvas.dart';
import 'board_tools.dart';

/// 화면 분할 모드
enum SplitMode {
  /// 단일 화면 (1분할)
  single,

  /// 좌우 2분할 (Vertical splitter, horizontal layout)
  twoVertical,

  /// 상하 2분할 (Horizontal splitter, vertical layout)
  twoHorizontal,

  /// 4분할 (2x2 Quad split)
  quad,
}

/// 분할 칠판 단일 패널 데이터
class SplitPaneData {
  final int id;
  String title;
  final AnnotationController controller;
  Color boardBgColor;
  bool isGridPattern;

  SplitPaneData({
    required this.id,
    required this.title,
    required this.controller,
    this.boardBgColor = const Color(0xFF0F172A), // Dark slate
    this.isGridPattern = true,
  });

  void clear() {
    controller.clear();
  }

  void undo() {
    controller.undo();
  }
}

/// 분할 칠판 컨트롤러
class SplitBoardController extends ChangeNotifier {
  SplitMode _splitMode;
  double _splitRatioX;
  double _splitRatioY;
  bool _syncToolsAcrossPanes;
  int _activePaneIndex;

  final List<SplitPaneData> panes;

  SplitBoardController({
    SplitMode initialMode = SplitMode.twoVertical,
    double initialRatioX = 0.5,
    double initialRatioY = 0.5,
    bool syncTools = false,
  })  : _splitMode = initialMode,
        _splitRatioX = initialRatioX.clamp(0.15, 0.85),
        _splitRatioY = initialRatioY.clamp(0.15, 0.85),
        _syncToolsAcrossPanes = syncTools,
        _activePaneIndex = 0,
        panes = List.generate(4, (index) {
          final ctrl = AnnotationController();
          ctrl.toolMode = ToolMode.pen;
          ctrl.activeColor = const Color(0xFF00F5D4);
          ctrl.activeWidth = 4.0;
          return SplitPaneData(
            id: index,
            title: '${index + 1}분할',
            controller: ctrl,
            boardBgColor: index == 0
                ? const Color(0xFF0F172A)
                : index == 1
                    ? const Color(0xFF0B192C)
                    : index == 2
                        ? const Color(0xFF1E293B)
                        : const Color(0xFF131D2E),
          );
        });

  SplitMode get splitMode => _splitMode;
  set splitMode(SplitMode mode) {
    if (_splitMode != mode) {
      _splitMode = mode;
      notifyListeners();
    }
  }

  double get splitRatioX => _splitRatioX;
  set splitRatioX(double ratio) {
    final clamped = ratio.clamp(0.15, 0.85);
    if (_splitRatioX != clamped) {
      _splitRatioX = clamped;
      notifyListeners();
    }
  }

  double get splitRatioY => _splitRatioY;
  set splitRatioY(double ratio) {
    final clamped = ratio.clamp(0.15, 0.85);
    if (_splitRatioY != clamped) {
      _splitRatioY = clamped;
      notifyListeners();
    }
  }

  bool get syncToolsAcrossPanes => _syncToolsAcrossPanes;
  set syncToolsAcrossPanes(bool val) {
    _syncToolsAcrossPanes = val;
    notifyListeners();
  }

  int get activePaneIndex => _activePaneIndex;
  set activePaneIndex(int idx) {
    if (idx >= 0 && idx < panes.length && _activePaneIndex != idx) {
      _activePaneIndex = idx;
      notifyListeners();
    }
  }

  SplitPaneData get activePane => panes[_activePaneIndex.clamp(0, panes.length - 1)];

  /// 1:1 또는 1:1:1:1 균등 분할 리셋
  void resetSplitRatios() {
    _splitRatioX = 0.5;
    _splitRatioY = 0.5;
    notifyListeners();
  }

  /// 모든 분할 패널 일괄 지우기
  void clearAllPanes() {
    for (final p in panes) {
      p.controller.clear();
    }
    notifyListeners();
  }

  /// 펜 색상 변경 (동기화 옵션 반영)
  void setPenColor(Color color, [int? targetPaneIndex]) {
    if (_syncToolsAcrossPanes || targetPaneIndex == null) {
      for (final p in panes) {
        p.controller.activeColor = color;
        p.controller.isEraser = false;
      }
    } else if (targetPaneIndex >= 0 && targetPaneIndex < panes.length) {
      panes[targetPaneIndex].controller.activeColor = color;
      panes[targetPaneIndex].controller.isEraser = false;
    }
    notifyListeners();
  }

  /// 펜 굵기 변경 (동기화 옵션 반영)
  void setPenWidth(double width, [int? targetPaneIndex]) {
    if (_syncToolsAcrossPanes || targetPaneIndex == null) {
      for (final p in panes) {
        p.controller.activeWidth = width;
      }
    } else if (targetPaneIndex >= 0 && targetPaneIndex < panes.length) {
      panes[targetPaneIndex].controller.activeWidth = width;
    }
    notifyListeners();
  }

  /// 지우개 모드 토글
  void setEraserMode(bool isEraser, [int? targetPaneIndex]) {
    if (_syncToolsAcrossPanes || targetPaneIndex == null) {
      for (final p in panes) {
        p.controller.isEraser = isEraser;
      }
    } else if (targetPaneIndex >= 0 && targetPaneIndex < panes.length) {
      panes[targetPaneIndex].controller.isEraser = isEraser;
    }
    notifyListeners();
  }
}

/// Boardest 화면 분할 칠판 뷰 (`SplitBoardView`)
/// 
/// 2-way 좌우 분할, 2-way 상하 분할, 4-way 쿼드 분할을 지원하며,
/// 각 분할 영역 간 터치/펜 좌표 번짐(bleed-through)을 원천 차단하고,
/// 반응형 리사이즈 핸들과 1:1 원클릭 리셋 버튼을 제공합니다.
class SplitBoardView extends StatefulWidget {
  final SplitBoardController? controller;
  final VoidCallback? onClose;
  final bool showHeaderToolbar;
  final double scaleFactor;

  const SplitBoardView({
    super.key,
    this.controller,
    this.onClose,
    this.showHeaderToolbar = true,
    this.scaleFactor = 1.0,
  });

  @override
  State<SplitBoardView> createState() => _SplitBoardViewState();
}

class _SplitBoardViewState extends State<SplitBoardView> {
  late SplitBoardController _ctrl;
  bool _isDraggingDividerX = false;
  bool _isDraggingDividerY = false;
  bool _isDraggingCenter = false;

  final List<Color> _palette = [
    const Color(0xFF00F5D4), // Mint / Teal
    const Color(0xFFFFD166), // Yellow
    const Color(0xFFFF0055), // Red / Pink
    const Color(0xFF00B4D8), // Cyan / Blue
    const Color(0xFFFFFFFF), // White
    const Color(0xFFA78BFA), // Lavender
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? SplitBoardController();
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SplitBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && widget.controller != _ctrl) {
      _ctrl.removeListener(_onControllerChanged);
      _ctrl = widget.controller!;
      _ctrl.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _ctrl.dispose();
    } else {
      _ctrl.removeListener(_onControllerChanged);
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return Container(
      color: const Color(0xFF080D1A),
      child: Column(
        children: [
          // 1. Top Split View Toolbar
          if (widget.showHeaderToolbar) _buildHeaderToolbar(s),

          // 2. Main Partitioned Workspace
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalW = constraints.maxWidth;
                final totalH = constraints.maxHeight;

                if (totalW <= 0 || totalH <= 0) return const SizedBox.shrink();

                switch (_ctrl.splitMode) {
                  case SplitMode.single:
                    return _buildPaneWidget(0, totalW, totalH, s);

                  case SplitMode.twoVertical:
                    return _buildTwoVerticalLayout(totalW, totalH, s);

                  case SplitMode.twoHorizontal:
                    return _buildTwoHorizontalLayout(totalW, totalH, s);

                  case SplitMode.quad:
                    return _buildQuadLayout(totalW, totalH, s);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOP TOOLBAR & CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeaderToolbar(double s) {
    final activePane = _ctrl.activePane;

    return Container(
      height: 54 * s,
      padding: EdgeInsets.symmetric(horizontal: 16 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // App / Tool Title
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8 * s),
                  ),
                  child: Icon(
                    Icons.splitscreen_rounded,
                    color: const Color(0xFF00F5D4),
                    size: 20 * s,
                  ),
                ),
                SizedBox(width: 10 * s),
                Text(
                  '화면 분할 판서 (Split Board)',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),

            SizedBox(width: 20 * s),

            // Split Mode Switcher Segment
            Container(
              padding: EdgeInsets.all(3 * s),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10 * s),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  _buildModeBtn(SplitMode.single, Icons.crop_square_rounded, '단일', s),
                  _buildModeBtn(SplitMode.twoVertical, Icons.view_column_rounded, '좌우 2분할', s),
                  _buildModeBtn(SplitMode.twoHorizontal, Icons.view_agenda_rounded, '상하 2분할', s),
                  _buildModeBtn(SplitMode.quad, Icons.grid_view_rounded, '4분할', s),
                ],
              ),
            ),

            SizedBox(width: 12 * s),

            // 1:1 Reset Button
            if (_ctrl.splitMode != SplitMode.single)
              ElevatedButton.icon(
                onPressed: () => _ctrl.resetSplitRatios(),
                icon: Icon(Icons.restart_alt_rounded, size: 16 * s, color: const Color(0xFF00F5D4)),
                label: Text(
                  '1:1 균등 리셋',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8 * s),
                    side: BorderSide(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
                  ),
                  elevation: 0,
                ),
              ),

            SizedBox(width: 24 * s),

          // Active Pane Tool Controls (Palette & Pen width)
          Row(
            children: [
              // Pen Color Palette
              for (final color in _palette)
                GestureDetector(
                  onTap: () => _ctrl.setPenColor(color, _ctrl.activePaneIndex),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 3 * s),
                    width: 22 * s,
                    height: 22 * s,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: activePane.controller.activeColor == color && !activePane.controller.isEraser
                            ? Colors.white
                            : Colors.transparent,
                        width: 2.5 * s,
                      ),
                      boxShadow: activePane.controller.activeColor == color && !activePane.controller.isEraser
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.6),
                                blurRadius: 6 * s,
                              )
                            ]
                          : null,
                    ),
                  ),
                ),

              SizedBox(width: 8 * s),

              // Eraser Toggle
              IconButton(
                icon: Icon(
                  Icons.auto_fix_normal_rounded,
                  size: 20 * s,
                  color: activePane.controller.isEraser ? const Color(0xFFFFB703) : Colors.white60,
                ),
                tooltip: '지우개 모드',
                onPressed: () => _ctrl.setEraserMode(!activePane.controller.isEraser, _ctrl.activePaneIndex),
              ),

              // Undo Active Pane
              IconButton(
                icon: Icon(Icons.undo_rounded, size: 20 * s, color: Colors.white70),
                tooltip: '현재 분할 실행 취소',
                onPressed: () => activePane.undo(),
              ),

              // Clear Active Pane
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 20 * s, color: const Color(0xFFFF4D4D)),
                tooltip: '현재 분할 지우기',
                onPressed: () => activePane.clear(),
              ),

              // Clear All Panes
              IconButton(
                icon: Icon(Icons.delete_sweep_rounded, size: 22 * s, color: const Color(0xFFFF6B6B)),
                tooltip: '모든 분할 화면 전체 지우기',
                onPressed: () => _ctrl.clearAllPanes(),
              ),

              if (widget.onClose != null) ...[
                SizedBox(width: 8 * s),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 22 * s, color: Colors.white70),
                  tooltip: '닫기',
                  onPressed: widget.onClose,
                ),
              ],
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildModeBtn(SplitMode mode, IconData icon, String label, double s) {
    final isSelected = _ctrl.splitMode == mode;
    return InkWell(
      onTap: () => _ctrl.splitMode = mode,
      borderRadius: BorderRadius.circular(8 * s),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00F5D4) : Colors.transparent,
          borderRadius: BorderRadius.circular(8 * s),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16 * s,
              color: isSelected ? const Color(0xFF080D1A) : Colors.white70,
            ),
            SizedBox(width: 6 * s),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                fontSize: 12 * s,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? const Color(0xFF080D1A) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2-WAY VERTICAL LAYOUT (좌/우 분할)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTwoVerticalLayout(double totalW, double totalH, double s) {
    final dividerW = 12.0 * s;
    final usableW = max(0.0, totalW - dividerW);
    final leftW = usableW * _ctrl.splitRatioX;
    final rightW = usableW * (1.0 - _ctrl.splitRatioX);

    return Stack(
      children: [
        // Left Pane (Pane 0)
        Positioned(
          left: 0,
          top: 0,
          width: leftW,
          height: totalH,
          child: _buildPaneWidget(0, leftW, totalH, s),
        ),

        // Right Pane (Pane 1)
        Positioned(
          left: leftW + dividerW,
          top: 0,
          width: rightW,
          height: totalH,
          child: _buildPaneWidget(1, rightW, totalH, s),
        ),

        // Vertical Resize Handle Divider
        Positioned(
          left: leftW,
          top: 0,
          width: dividerW,
          height: totalH,
          child: _buildVerticalResizeDivider(totalW, totalH, s),
        ),
      ],
    );
  }

  Widget _buildVerticalResizeDivider(double totalW, double totalH, double s) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _isDraggingDividerX = true),
        onHorizontalDragUpdate: (details) {
          final newRatio = _ctrl.splitRatioX + (details.delta.dx / totalW);
          _ctrl.splitRatioX = newRatio;
        },
        onHorizontalDragEnd: (_) => setState(() => _isDraggingDividerX = false),
        onHorizontalDragCancel: () => setState(() => _isDraggingDividerX = false),
        child: Container(
          color: Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Visual Line
              Container(
                width: 3.0 * s,
                height: totalH,
                color: _isDraggingDividerX
                    ? const Color(0xFF00F5D4)
                    : Colors.white.withValues(alpha: 0.15),
              ),

              // Center Grip Pill with Reset Button
              Positioned(
                top: totalH / 2 - 36 * s,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10 * s,
                      height: 48 * s,
                      decoration: BoxDecoration(
                        color: _isDraggingDividerX
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6 * s),
                        border: Border.all(
                          color: const Color(0xFF00F5D4).withValues(alpha: 0.5),
                          width: 1.5 * s,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 4 * s,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 14 * s,
                          color: _isDraggingDividerX ? const Color(0xFF080D1A) : Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 6 * s),
                    // On-Divider 1:1 Reset Button
                    InkWell(
                      onTap: () => _ctrl.resetSplitRatios(),
                      borderRadius: BorderRadius.circular(12 * s),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12 * s),
                          border: Border.all(
                            color: const Color(0xFF00F5D4).withValues(alpha: 0.6),
                            width: 1.2 * s,
                          ),
                        ),
                        child: Text(
                          '1:1',
                          style: GoogleFonts.outfit(
                            fontSize: 10 * s,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF00F5D4),
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2-WAY HORIZONTAL LAYOUT (상/하 분할)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTwoHorizontalLayout(double totalW, double totalH, double s) {
    final dividerH = 12.0 * s;
    final usableH = max(0.0, totalH - dividerH);
    final topH = usableH * _ctrl.splitRatioY;
    final bottomH = usableH * (1.0 - _ctrl.splitRatioY);

    return Stack(
      children: [
        // Top Pane (Pane 0)
        Positioned(
          left: 0,
          top: 0,
          width: totalW,
          height: topH,
          child: _buildPaneWidget(0, totalW, topH, s),
        ),

        // Bottom Pane (Pane 1)
        Positioned(
          left: 0,
          top: topH + dividerH,
          width: totalW,
          height: bottomH,
          child: _buildPaneWidget(1, totalW, bottomH, s),
        ),

        // Horizontal Resize Handle Divider
        Positioned(
          left: 0,
          top: topH,
          width: totalW,
          height: dividerH,
          child: _buildHorizontalResizeDivider(totalW, totalH, s),
        ),
      ],
    );
  }

  Widget _buildHorizontalResizeDivider(double totalW, double totalH, double s) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _isDraggingDividerY = true),
        onVerticalDragUpdate: (details) {
          final newRatio = _ctrl.splitRatioY + (details.delta.dy / totalH);
          _ctrl.splitRatioY = newRatio;
        },
        onVerticalDragEnd: (_) => setState(() => _isDraggingDividerY = false),
        onVerticalDragCancel: () => setState(() => _isDraggingDividerY = false),
        child: Container(
          color: Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Visual Line
              Container(
                width: totalW,
                height: 3.0 * s,
                color: _isDraggingDividerY
                    ? const Color(0xFF00F5D4)
                    : Colors.white.withValues(alpha: 0.15),
              ),

              // Center Grip Pill with Reset Button
              Positioned(
                left: totalW / 2 - 36 * s,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48 * s,
                      height: 10 * s,
                      decoration: BoxDecoration(
                        color: _isDraggingDividerY
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6 * s),
                        border: Border.all(
                          color: const Color(0xFF00F5D4).withValues(alpha: 0.5),
                          width: 1.5 * s,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 4 * s,
                          ),
                        ],
                      ),
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: 1,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 14 * s,
                            color: _isDraggingDividerY ? const Color(0xFF080D1A) : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    // On-Divider 1:1 Reset Button
                    InkWell(
                      onTap: () => _ctrl.resetSplitRatios(),
                      borderRadius: BorderRadius.circular(12 * s),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12 * s),
                          border: Border.all(
                            color: const Color(0xFF00F5D4).withValues(alpha: 0.6),
                            width: 1.2 * s,
                          ),
                        ),
                        child: Text(
                          '1:1',
                          style: GoogleFonts.outfit(
                            fontSize: 10 * s,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF00F5D4),
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4-WAY QUAD LAYOUT (2x2 격자 분할)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuadLayout(double totalW, double totalH, double s) {
    final dividerSize = 12.0 * s;
    final usableW = max(0.0, totalW - dividerSize);
    final usableH = max(0.0, totalH - dividerSize);

    final leftW = usableW * _ctrl.splitRatioX;
    final rightW = usableW * (1.0 - _ctrl.splitRatioX);
    final topH = usableH * _ctrl.splitRatioY;
    final bottomH = usableH * (1.0 - _ctrl.splitRatioY);

    return Stack(
      children: [
        // Pane 0: Top-Left
        Positioned(
          left: 0,
          top: 0,
          width: leftW,
          height: topH,
          child: _buildPaneWidget(0, leftW, topH, s),
        ),

        // Pane 1: Top-Right
        Positioned(
          left: leftW + dividerSize,
          top: 0,
          width: rightW,
          height: topH,
          child: _buildPaneWidget(1, rightW, topH, s),
        ),

        // Pane 2: Bottom-Left
        Positioned(
          left: 0,
          top: topH + dividerSize,
          width: leftW,
          height: bottomH,
          child: _buildPaneWidget(2, leftW, bottomH, s),
        ),

        // Pane 3: Bottom-Right
        Positioned(
          left: leftW + dividerSize,
          top: topH + dividerSize,
          width: rightW,
          height: bottomH,
          child: _buildPaneWidget(3, rightW, bottomH, s),
        ),

        // Vertical Divider
        Positioned(
          left: leftW,
          top: 0,
          width: dividerSize,
          height: totalH,
          child: _buildVerticalResizeDivider(totalW, totalH, s),
        ),

        // Horizontal Divider
        Positioned(
          left: 0,
          top: topH,
          width: totalW,
          height: dividerSize,
          child: _buildHorizontalResizeDivider(totalW, totalH, s),
        ),

        // Center 4-Way Cross Intersection Handle with Reset Button
        Positioned(
          left: leftW - 14 * s,
          top: topH - 14 * s,
          width: 40 * s,
          height: 40 * s,
          child: _buildQuadCenterHandle(totalW, totalH, s),
        ),
      ],
    );
  }

  Widget _buildQuadCenterHandle(double totalW, double totalH, double s) {
    return MouseRegion(
      cursor: SystemMouseCursors.allScroll,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _isDraggingCenter = true),
        onPanUpdate: (details) {
          final newRatioX = _ctrl.splitRatioX + (details.delta.dx / totalW);
          final newRatioY = _ctrl.splitRatioY + (details.delta.dy / totalH);
          _ctrl.splitRatioX = newRatioX;
          _ctrl.splitRatioY = newRatioY;
        },
        onPanEnd: (_) => setState(() => _isDraggingCenter = false),
        onPanCancel: () => setState(() => _isDraggingCenter = false),
        child: Container(
          decoration: BoxDecoration(
            color: _isDraggingCenter ? const Color(0xFF00F5D4) : const Color(0xFF1E293B),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF00F5D4),
              width: 2.0 * s,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 6 * s,
                spreadRadius: 1 * s,
              ),
            ],
          ),
          child: Center(
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.restart_alt_rounded,
                size: 18 * s,
                color: _isDraggingCenter ? const Color(0xFF080D1A) : const Color(0xFF00F5D4),
              ),
              tooltip: '1:1:1:1 균등 분할 리셋',
              onPressed: () => _ctrl.resetSplitRatios(),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INDEPENDENT SPLIT PANE WIDGET (STRICT BOUNDARY CLIPPING & ROUTING)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPaneWidget(int paneIdx, double w, double h, double s) {
    final pane = _ctrl.panes[paneIdx];
    final isActive = _ctrl.activePaneIndex == paneIdx;

    return GestureDetector(
      onTapDown: (_) => _ctrl.activePaneIndex = paneIdx,
      child: Container(
        decoration: BoxDecoration(
          color: pane.boardBgColor,
          border: Border.all(
            color: isActive
                ? const Color(0xFF00F5D4).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.08),
            width: isActive ? 2.0 * s : 1.0,
          ),
        ),
        child: Stack(
          children: [
            // Background Grid Pattern
            if (pane.isGridPattern)
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPatternPainter(
                    dotColor: Colors.white.withValues(alpha: 0.04),
                    spacing: 24.0 * s,
                  ),
                ),
              ),

            // Strict Coordinate Boundary Clipping & Gesture Arena Isolation
            Positioned.fill(
              child: ClipRect(
                child: _IsolatedCanvasGestureLayer(
                  pane: pane,
                  scaleFactor: s,
                  paneSize: Size(w, h),
                ),
              ),
            ),

            // Pane Header Chip (Top-Left of pane)
            Positioned(
              left: 10 * s,
              top: 8 * s,
              child: _buildPaneHeaderChip(pane, isActive, s),
            ),

            // Pane Quick Action Floating Bar (Top-Right of pane)
            Positioned(
              right: 8 * s,
              top: 8 * s,
              child: _buildPaneQuickActions(pane, s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaneHeaderChip(SplitPaneData pane, bool isActive, double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF00F5D4)
            : const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4 * s,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8 * s,
            height: 8 * s,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF080D1A) : const Color(0xFF00F5D4),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6 * s),
          Text(
            pane.title,
            style: GoogleFonts.notoSansKr(
              fontSize: 11 * s,
              fontWeight: FontWeight.w700,
              color: isActive ? const Color(0xFF080D1A) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaneQuickActions(SplitPaneData pane, double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 2 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6 * s),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Background Color Cycle
          InkWell(
            onTap: () {
              setState(() {
                if (pane.boardBgColor == const Color(0xFF0F172A)) {
                  pane.boardBgColor = const Color(0xFF143026); // Classic blackboard green
                } else if (pane.boardBgColor == const Color(0xFF143026)) {
                  pane.boardBgColor = const Color(0xFFF8FAFC); // Clean white
                } else {
                  pane.boardBgColor = const Color(0xFF0F172A); // Dark slate
                }
              });
            },
            borderRadius: BorderRadius.circular(4 * s),
            child: Padding(
              padding: EdgeInsets.all(4 * s),
              child: Icon(Icons.palette_outlined, size: 14 * s, color: Colors.white70),
            ),
          ),
          // Undo
          InkWell(
            onTap: () => pane.undo(),
            borderRadius: BorderRadius.circular(4 * s),
            child: Padding(
              padding: EdgeInsets.all(4 * s),
              child: Icon(Icons.undo_rounded, size: 14 * s, color: Colors.white70),
            ),
          ),
          // Clear
          InkWell(
            onTap: () => pane.clear(),
            borderRadius: BorderRadius.circular(4 * s),
            child: Padding(
              padding: EdgeInsets.all(4 * s),
              child: Icon(Icons.delete_outline_rounded, size: 14 * s, color: const Color(0xFFFF6B6B)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 단일 분할 칠판의 제스처 격리 및 좌표 바운딩 레이어
class _IsolatedCanvasGestureLayer extends StatefulWidget {
  final SplitPaneData pane;
  final double scaleFactor;
  final Size paneSize;

  const _IsolatedCanvasGestureLayer({
    required this.pane,
    required this.scaleFactor,
    required this.paneSize,
  });

  @override
  State<_IsolatedCanvasGestureLayer> createState() => _IsolatedCanvasGestureLayerState();
}

class _IsolatedCanvasGestureLayerState extends State<_IsolatedCanvasGestureLayer> {
  final GlobalKey _paneCanvasKey = GlobalKey();
  List<Offset> _currentPoints = [];
  bool _isDrawing = false;

  /// 격리된 로컬 좌표 산출 및 파티션 경계 바운딩
  Offset _clampAndLocalize(Offset globalPosition) {
    final box = _paneCanvasKey.currentContext?.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(globalPosition) ?? globalPosition;

    // Strict coordinate confinement: bounds to [0, width] and [0, height]
    final clampedX = local.dx.clamp(0.0, widget.paneSize.width);
    final clampedY = local.dy.clamp(0.0, widget.paneSize.height);
    return Offset(clampedX, clampedY);
  }

  void _onPanStart(DragStartDetails details) {
    final p = _clampAndLocalize(details.globalPosition);
    final ctrl = widget.pane.controller;

    if (ctrl.toolMode == ToolMode.eraser) {
      ctrl.eraseAt(p);
      setState(() => _isDrawing = true);
      return;
    }

    setState(() {
      _isDrawing = true;
      _currentPoints = [p];
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final p = _clampAndLocalize(details.globalPosition);
    final ctrl = widget.pane.controller;

    if (ctrl.toolMode == ToolMode.eraser) {
      ctrl.eraseAt(p);
      return;
    }

    setState(() {
      _currentPoints.add(p);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final ctrl = widget.pane.controller;
    if (_isDrawing) {
      if (ctrl.toolMode == ToolMode.pen && _currentPoints.isNotEmpty) {
        final stroke = AnnotationStroke(
          points: List<Offset>.from(_currentPoints),
          color: ctrl.activeColor,
          strokeWidth: ctrl.activeWidth,
        );
        ctrl.addStroke(stroke);
      }
      setState(() {
        _isDrawing = false;
        _currentPoints = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.pane.controller;

    return GestureDetector(
      key: _paneCanvasKey,
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final p = _clampAndLocalize(details.globalPosition);
        if (ctrl.toolMode == ToolMode.pen) {
          final dotStroke = AnnotationStroke(
            points: [p, p + const Offset(0.1, 0.1)],
            color: ctrl.activeColor,
            strokeWidth: ctrl.activeWidth,
          );
          ctrl.addStroke(dotStroke);
        } else if (ctrl.toolMode == ToolMode.eraser) {
          ctrl.eraseAt(p);
        }
      },
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _SplitPanePainter(
              strokes: ctrl.strokes,
              activePoints: _isDrawing ? _currentPoints : null,
              activeColor: ctrl.activeColor,
              activeWidth: ctrl.activeWidth,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

/// 분할 칠판 개별 렌더러
class _SplitPanePainter extends CustomPainter {
  final List<AnnotationStroke> strokes;
  final List<Offset>? activePoints;
  final Color activeColor;
  final double activeWidth;

  _SplitPanePainter({
    required this.strokes,
    this.activePoints,
    required this.activeColor,
    required this.activeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Render finished strokes
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, paint..style = PaintingStyle.fill);
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    // 2. Render active drawing stroke
    if (activePoints != null && activePoints!.isNotEmpty) {
      final activePaint = Paint()
        ..color = activeColor
        ..strokeWidth = activeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (activePoints!.length == 1) {
        canvas.drawCircle(activePoints!.first, activeWidth / 2, activePaint..style = PaintingStyle.fill);
      } else {
        final activePath = Path();
        activePath.moveTo(activePoints!.first.dx, activePoints!.first.dy);
        for (int i = 1; i < activePoints!.length; i++) {
          activePath.lineTo(activePoints![i].dx, activePoints![i].dy);
        }
        canvas.drawPath(activePath, activePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SplitPanePainter oldDelegate) => true;
}

/// 도트 격자 배경 페인터
class _GridPatternPainter extends CustomPainter {
  final Color dotColor;
  final double spacing;

  _GridPatternPainter({
    required this.dotColor,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPatternPainter oldDelegate) => false;
}
