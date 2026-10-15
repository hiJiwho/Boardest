import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';
import '../../models/app_settings.dart' show LauncherSlot, LauncherSlotType;

enum BstToolType {
  pen,
  timer,
  random,
  calculator,
  web,
  pdf,
  cloud,
  settings,
}

class BstToolsDock extends StatelessWidget {
  final bool isPro;
  final bool isWindows;
  final ValueChanged<BstToolType>? onToolTap;
  final VoidCallback? onAddAppTap;
  final VoidCallback? onMinimizeTap;
  final VoidCallback? onCloseTap;
  final List<LauncherSlot>? customSlots;
  final ValueChanged<LauncherSlot>? onLaunchApp;
  final ValueChanged<int>? onRemoveApp;
  final ValueChanged<int>? onAddAppToSlot;

  const BstToolsDock({
    super.key,
    this.isPro = false,
    this.isWindows = false,
    this.onToolTap,
    this.onAddAppTap,
    this.onMinimizeTap,
    this.onCloseTap,
    this.customSlots,
    this.onLaunchApp,
    this.onRemoveApp,
    this.onAddAppToSlot,
  });

  Widget _buildToolButton({
    required String icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 52,
        height: 48,
        decoration: BoxDecoration(
          color: isPrimary
              ? const Color(0xFF00F5D4)
              : Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isPrimary
                ? const Color(0xFF00F5D4)
                : Colors.white.withOpacity(0.08),
          ),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: const Color(0xFF00F5D4).withOpacity(0.3),
                    blurRadius: 10,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              icon,
              style: TextStyle(
                fontSize: 17,
                color: isPrimary ? Colors.black : Colors.white,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: isPrimary ? Colors.black : const Color(0xFFCBD5E1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 기본 도구 목록
    final baseTools = [
      {'type': BstToolType.pen, 'icon': '🖊️', 'label': '판서', 'primary': true},
      {'type': BstToolType.timer, 'icon': '⏱️', 'label': '타이머', 'primary': false},
      {'type': BstToolType.random, 'icon': '🎲', 'label': '추첨', 'primary': false},
      {'type': BstToolType.calculator, 'icon': '🧮', 'label': '계산기', 'primary': false},
      {'type': BstToolType.web, 'icon': '🌐', 'label': '웹', 'primary': false},
      {'type': BstToolType.pdf, 'icon': '📄', 'label': 'PDF', 'primary': false},
      {'type': BstToolType.cloud, 'icon': '☁️', 'label': 'Cloud', 'primary': false},
      {'type': BstToolType.settings, 'icon': '⚙️', 'label': '설정', 'primary': false},
    ];

    if (!isPro) {
      // 1. Web 버전: 6열 x 1행 (웹, PDF 제외 6개 도구 한 줄 배치)
      final webTools = [
        {'type': BstToolType.pen, 'icon': '🖊️', 'label': '판서', 'primary': true},
        {'type': BstToolType.timer, 'icon': '⏱️', 'label': '타이머', 'primary': false},
        {'type': BstToolType.random, 'icon': '🎲', 'label': '추첨', 'primary': false},
        {'type': BstToolType.calculator, 'icon': '🧮', 'label': '계산기', 'primary': false},
        {'type': BstToolType.cloud, 'icon': '☁️', 'label': 'Cloud', 'primary': false},
        {'type': BstToolType.settings, 'icon': '⚙️', 'label': '설정', 'primary': false},
      ];

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('🧰', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                const Text(
                  '수업 도구함',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'WEB 6×1',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const crossAxisCount = 6;
                  const rowCount = 1;
                  const spacing = 8.0;
                  final itemWidth = (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;
                  final itemHeight = constraints.maxHeight;
                  final ratio = (itemWidth / (itemHeight > 0 ? itemHeight : itemWidth)).clamp(0.5, 4.0);

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: ratio,
                    ),
                    itemCount: webTools.length,
                    itemBuilder: (context, index) {
                      final item = webTools[index];
                      final isPrimary = item['primary'] as bool;
                      return _buildToolGridCard(
                        icon: item['icon'] as String,
                        label: item['label'] as String,
                        isPrimary: isPrimary,
                        onTap: () => onToolTap?.call(item['type'] as BstToolType),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // 2. Windows / Android PRO 모드: 6열 x 2행 (총 12 슬롯 도구함)
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 상단 바
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('🧰', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              const Text(
                '수업 & 시스템 도구함',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '6×2 PRO',
                  style: TextStyle(
                    color: Color(0xFF00F5D4),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (isWindows) ...[
                InkWell(
                  onTap: onMinimizeTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 26,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text('─', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onCloseTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 26,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text('✕', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // 6열 x 2행 = 12칸 그리드
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const crossAxisCount = 6;
                const rowCount = 2;
                const spacing = 6.0;
                final itemWidth = (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;
                final itemHeight = (constraints.maxHeight - (spacing * (rowCount - 1))) / rowCount;
                final ratio = (itemWidth / (itemHeight > 0 ? itemHeight : itemWidth)).clamp(0.5, 4.0);

                final customApps = customSlots
                        ?.where((s) => s.type == LauncherSlotType.systemApp && s.name.isNotEmpty)
                        .toList() ??
                    [];

                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: ratio,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    if (index < baseTools.length) {
                      // 0~7: 8개 기본 도구
                      final tool = baseTools[index];
                      return _buildToolGridCard(
                        icon: tool['icon'] as String,
                        label: tool['label'] as String,
                        isPrimary: tool['primary'] as bool,
                        onTap: () => onToolTap?.call(tool['type'] as BstToolType),
                      );
                    } else if (index == 11 && isWindows) {
                      // 마지막 슬롯: 윈도우 전용 종료/닫기 버튼
                      return _buildSystemAppCard(
                        icon: '🚪',
                        label: '앱 닫기',
                        onTap: onCloseTap ?? () {},
                      );
                    } else {
                      // 8, 9, 10 (비윈도우는 11 포함): 등록된 앱 또는 앱 추가 슬롯
                      final customIdx = index - baseTools.length;
                      if (customIdx < customApps.length) {
                        final slot = customApps[customIdx];
                        return _buildCustomAppCard(
                          slot: slot,
                          onTap: () => onLaunchApp?.call(slot),
                          onLongPress: () => onRemoveApp?.call(customIdx),
                        );
                      } else if (customIdx == customApps.length) {
                        return _buildAddAppCard(
                          onTap: () {
                            if (onAddAppToSlot != null) {
                              onAddAppToSlot!(customIdx);
                            } else {
                              onAddAppTap?.call();
                            }
                          },
                        );
                      } else {
                        return _buildEmptySlotCard(
                          onTap: () {
                            if (onAddAppToSlot != null) {
                              onAddAppToSlot!(customIdx);
                            } else {
                              onAddAppTap?.call();
                            }
                          },
                        );
                      }
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomAppCard({
    required LauncherSlot slot,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final hasIcon = slot.iconPath != null &&
        slot.iconPath!.isNotEmpty &&
        File(slot.iconPath!).existsSync();
    final isUrl = slot.id.startsWith('http://') || slot.id.startsWith('https://');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF00F5D4).withOpacity(0.35),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasIcon)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(slot.iconPath!),
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                ),
              )
            else if (isUrl)
              const Text('🌐', style: TextStyle(fontSize: 17))
            else
              const Text('🚀', style: TextStyle(fontSize: 17)),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                slot.name,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolGridCard({
    required String icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: isPrimary
              ? const Color(0xFF00F5D4)
              : Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isPrimary
                ? const Color(0xFF00F5D4)
                : Colors.white.withOpacity(0.08),
          ),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: const Color(0xFF00F5D4).withOpacity(0.3),
                    blurRadius: 8,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              icon,
              style: TextStyle(
                fontSize: 18,
                color: isPrimary ? Colors.black : Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: isPrimary ? Colors.black : const Color(0xFFCBD5E1),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemAppCard({
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.025),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.65),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddAppCard({VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap ?? onAddAppTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF00F5D4).withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF00F5D4).withOpacity(0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('➕', style: TextStyle(fontSize: 16)),
            SizedBox(height: 2),
            Text(
              '앱 추가',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF00F5D4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySlotCard({VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.01),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Center(
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
