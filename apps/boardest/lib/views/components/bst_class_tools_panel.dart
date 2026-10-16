import 'package:flutter/material.dart';
import '../boardest_tools_view.dart';
import 'bst_tools_dock.dart';

/// 교사 도구 패널 ([사용] / [제작] 분리 지원)
class BstClassToolsPanel extends StatefulWidget {
  final bool isPro;
  final bool isWindows;
  final ValueChanged<BstToolType>? onToolTap;
  final VoidCallback? onAddAppTap;
  final List<dynamic>? customSlots;

  const BstClassToolsPanel({
    super.key,
    this.isPro = false,
    this.isWindows = false,
    this.onToolTap,
    this.onAddAppTap,
    this.customSlots,
  });

  @override
  State<BstClassToolsPanel> createState() => _BstClassToolsPanelState();
}

class _BstClassToolsPanelState extends State<BstClassToolsPanel> {
  bool _isCreationTab = false; // false: 사용 도구, true: 제작 도구

  void _openCreationStudio(BuildContext context, int tabIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardestToolsView(
          initialCreationMode: true,
          initialTabIndex: tabIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1) [사용 (수업 진행)] 3*2 6대 도구
    final usageTools = [
      {
        'type': BstToolType.pen,
        'name': '판서',
        'sub': '판서 도구',
        'icon': Icons.edit_rounded,
        'color': const Color(0xFF00F5D4),
      },
      {
        'type': BstToolType.timer,
        'name': '타이머',
        'sub': '스톱워치',
        'icon': Icons.timer_outlined,
        'color': const Color(0xFFFFB703),
      },
      {
        'type': BstToolType.random,
        'name': '추첨',
        'sub': '자리 / 번호',
        'icon': Icons.casino_outlined,
        'color': const Color(0xFFA78BFA),
      },
      {
        'type': BstToolType.calculator,
        'name': '계산기',
        'sub': '공학 / 일반',
        'icon': Icons.calculate_outlined,
        'color': const Color(0xFF38BDF8),
      },
      {
        'type': BstToolType.cloud,
        'name': '클라우드',
        'sub': '교안 · PDF',
        'icon': Icons.cloud_outlined,
        'color': const Color(0xFF34D399),
      },
      {
        'type': BstToolType.settings,
        'name': '설정',
        'sub': '환경 설정',
        'icon': Icons.settings_outlined,
        'color': const Color(0xFF94A3B8),
      },
    ];

    // 2) [제작 (수업 저작)] 도구
    final creationTools = [
      {
        'creationIndex': 0,
        'name': 'TBP 제작',
        'sub': '폴더형 교과서',
        'icon': Icons.auto_stories_rounded,
        'color': const Color(0xFF7F5AF0),
      },
      {
        'creationIndex': 1,
        'name': 'Canva 등록',
        'sub': '슬라이드 결합',
        'icon': Icons.palette_rounded,
        'color': const Color(0xFF00C4CC),
      },
      {
        'creationIndex': 2,
        'name': '판서 노트',
        'sub': '.bstpen 저작',
        'icon': Icons.draw_rounded,
        'color': const Color(0xFF00F5D4),
      },
      {
        'creationIndex': 2,
        'name': '자료 업로드',
        'sub': 'Cloud 교안함',
        'icon': Icons.cloud_upload_rounded,
        'color': const Color(0xFF38BDF8),
      },
      {
        'type': BstToolType.cloud,
        'name': '교안 열기',
        'sub': 'Cloud 탐색기',
        'icon': Icons.folder_shared_rounded,
        'color': const Color(0xFF34D399),
      },
      {
        'type': BstToolType.settings,
        'name': '설정',
        'sub': '환경 설정',
        'icon': Icons.settings_outlined,
        'color': const Color(0xFF94A3B8),
      },
    ];

    final activeTools = _isCreationTab ? creationTools : usageTools;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 헤더: 교사 도구 타이틀 + [사용 / 제작] 탭 전환
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (_isCreationTab ? const Color(0xFF7F5AF0) : const Color(0xFF00F5D4)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isCreationTab ? Icons.auto_fix_high_rounded : Icons.widgets_rounded,
                    color: _isCreationTab ? const Color(0xFF7F5AF0) : const Color(0xFF00F5D4),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '교사 도구',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF050811),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMiniModeTab(
                        label: '사용',
                        selected: !_isCreationTab,
                        activeColor: const Color(0xFF00F5D4),
                        onTap: () => setState(() => _isCreationTab = false),
                      ),
                      _buildMiniModeTab(
                        label: '제작',
                        selected: _isCreationTab,
                        activeColor: const Color(0xFF7F5AF0),
                        onTap: () => setState(() => _isCreationTab = true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. 도구 2:3 (2열 3행) 그리드
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const crossAxisCount = 2;
                  const rowCount = 3;
                  const spacing = 8.0;
                  final itemWidth = (constraints.maxWidth - spacing) / crossAxisCount;
                  final itemHeight = (constraints.maxHeight - (spacing * (rowCount - 1))) / rowCount;
                  final ratio = (itemWidth / (itemHeight > 0 ? itemHeight : itemWidth)).clamp(0.5, 3.0);

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: ratio,
                    ),
                    itemCount: activeTools.length,
                    itemBuilder: (context, index) {
                      final tool = activeTools[index];
                      final type = tool['type'] as BstToolType?;
                      final creationIdx = tool['creationIndex'] as int?;
                      final name = tool['name'] as String;
                      final sub = tool['sub'] as String;
                      final icon = tool['icon'] as IconData;
                      final color = tool['color'] as Color;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (creationIdx != null) {
                              _openCreationStudio(context, creationIdx);
                            } else if (type != null) {
                              widget.onToolTap?.call(type);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.035),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: color.withValues(alpha: 0.25),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(icon, color: color, size: 22),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  sub,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // 3. 하단 앱/플러그인 추가 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: InkWell(
              onTap: widget.onAddAppTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 15,
                      color: widget.isPro ? const Color(0xFF00F5D4) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isPro ? '앱 / 도구 추가 (PRO)' : '앱 등록 (설정)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: widget.isPro ? const Color(0xFF00F5D4) : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniModeTab({
    required String label,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final isDarkText = activeColor == const Color(0xFF00F5D4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? (isDarkText ? const Color(0xFF050811) : Colors.white) : const Color(0xFF94A3B8),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
