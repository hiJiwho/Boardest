import 'package:flutter/material.dart';
import 'package:bst_pen/bst_pen.dart';

/// BoardDockToolbar in bst_tbp
class BoardDockToolbar extends StatelessWidget {
  final double scale;
  final ToolMode tool;
  final ValueChanged<ToolMode> onToolChanged;
  final double strokeWidth;
  final ValueChanged<double> onStrokeWidthChanged;
  final Color penColor;
  final ValueChanged<Color> onColorChanged;
  final ShapeType activeShape;
  final ValueChanged<ShapeType>? onShapeChanged;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String? pageLabel;
  final VoidCallback? onPageLabelTap;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onClear;
  final VoidCallback? onClose;

  const BoardDockToolbar({
    super.key,
    required this.scale,
    required this.tool,
    required this.onToolChanged,
    required this.strokeWidth,
    required this.onStrokeWidthChanged,
    required this.penColor,
    required this.onColorChanged,
    this.activeShape = ShapeType.line,
    this.onShapeChanged,
    this.onPrev,
    this.onNext,
    this.pageLabel,
    this.onPageLabelTap,
    this.onUndo,
    this.onRedo,
    this.onClear,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withOpacity(0.95),
        borderRadius: BorderRadius.circular(30 * s),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20 * s,
            offset: Offset(0, 8 * s),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolBtn(
            icon: Icons.pan_tool_alt_rounded,
            isSelected: tool == ToolMode.pointer,
            onTap: () => onToolChanged(ToolMode.pointer),
            scale: s,
          ),
          SizedBox(width: 8 * s),
          _buildToolBtn(
            icon: Icons.edit_rounded,
            isSelected: tool == ToolMode.pen,
            onTap: () => onToolChanged(ToolMode.pen),
            scale: s,
          ),
          SizedBox(width: 8 * s),
          _buildToolBtn(
            icon: Icons.auto_fix_high_rounded,
            isSelected: tool == ToolMode.eraser,
            onTap: () => onToolChanged(ToolMode.eraser),
            scale: s,
          ),
          if (onUndo != null) ...[
            SizedBox(width: 12 * s),
            IconButton(
              icon: Icon(Icons.undo_rounded, color: Colors.white70, size: 20 * s),
              onPressed: onUndo,
            ),
          ],
          if (onRedo != null)
            IconButton(
              icon: Icon(Icons.redo_rounded, color: Colors.white70, size: 20 * s),
              onPressed: onRedo,
            ),
          if (onClear != null)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 20 * s),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }

  Widget _buildToolBtn({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required double scale,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20 * scale),
      child: Container(
        padding: EdgeInsets.all(8 * scale),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7F5AF0) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20 * scale,
          color: isSelected ? Colors.white : Colors.white70,
        ),
      ),
    );
  }
}
