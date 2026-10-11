import 'package:flutter/material.dart';
import 'bst_tools_dock.dart';

class BstClassToolsPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // 3*2 기본 6대 도구 (PDF는 Cloud에 통합됨)
    final defaultTools = [
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
          // 1. 헤더: 수업 도구 타이틀
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.widgets_rounded, color: Color(0xFF00F5D4), size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  '수업 도구',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPro
                        ? const Color(0xFF00F5D4).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isPro ? 'PRO' : '3×2',
                    style: TextStyle(
                      color: isPro ? const Color(0xFF00F5D4) : const Color(0xFF94A3B8),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. 도구 2:3 (2열 3행) 그리드 (칸 안에 정확히 맞춤)
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
                itemCount: defaultTools.length,
                itemBuilder: (context, index) {
                  final tool = defaultTools[index];
                  final type = tool['type'] as BstToolType;
                  final name = tool['name'] as String;
                  final sub = tool['sub'] as String;
                  final icon = tool['icon'] as IconData;
                  final color = tool['color'] as Color;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onToolTap?.call(type),
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
              onTap: onAddAppTap,
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
                      color: isPro ? const Color(0xFF00F5D4) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPro ? '앱 / 도구 추가 (PRO)' : '앱 등록 (설정)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isPro ? const Color(0xFF00F5D4) : const Color(0xFF94A3B8),
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
}
