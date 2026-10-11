import 'dart:async';
import 'package:flutter/material.dart';

class BstAppHeader extends StatefulWidget {
  final String appName;
  final String schoolName;
  final String gradeClass;
  final bool isWindows;
  final VoidCallback? onLogoTap;
  final VoidCallback? onMinimizeTap;
  final VoidCallback? onCloseTap;
  final bool isCloudActive;
  final VoidCallback? onCloudTap;
  final bool isSpecialRoom;
  final String? specialSubjectName;

  const BstAppHeader({
    super.key,
    this.appName = 'Class',
    this.schoolName = '보데스트 중학교',
    this.gradeClass = '1학년 7반',
    this.isWindows = false,
    this.onLogoTap,
    this.onMinimizeTap,
    this.onCloseTap,
    this.isCloudActive = false,
    this.onCloudTap,
    this.isSpecialRoom = false,
    this.specialSubjectName,
  });

  @override
  State<BstAppHeader> createState() => _BstAppHeaderState();
}

class _BstAppHeaderState extends State<BstAppHeader> {
  bool _showWindowControls = false;
  Timer? _revertTimer;

  void _triggerWindowControls() {
    if (!widget.isWindows) return;
    setState(() {
      _showWindowControls = true;
    });
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showWindowControls = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schoolAndClass = [
      if (widget.schoolName.trim().isNotEmpty) widget.schoolName.trim(),
      if (widget.gradeClass.trim().isNotEmpty) widget.gradeClass.trim(),
    ].join(' ');

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B101B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // 1. 로고 영역 (Windows에서는 클릭 시 5초간 최소화/닫기 버튼으로 전환)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _showWindowControls && widget.isWindows
                ? Row(
                    key: const ValueKey('win_controls'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 최소화 버튼
                      Tooltip(
                        message: '최소화',
                        child: InkWell(
                          onTap: () {
                            widget.onMinimizeTap?.call();
                            _revertTimer?.cancel();
                            if (mounted) setState(() => _showWindowControls = false);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDBC40).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFDBC40).withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.remove_rounded, color: Color(0xFFFDBC40), size: 16),
                                SizedBox(width: 4),
                                Text(
                                  '최소화',
                                  style: TextStyle(color: Color(0xFFFDBC40), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 닫기 버튼
                      Tooltip(
                        message: '프로그램 종료',
                        child: InkWell(
                          onTap: () {
                            widget.onCloseTap?.call();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFC5753).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFC5753).withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.close_rounded, color: Color(0xFFFC5753), size: 16),
                                SizedBox(width: 4),
                                Text(
                                  '닫기',
                                  style: TextStyle(color: Color(0xFFFC5753), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : InkWell(
                    key: const ValueKey('logo_default'),
                    onTap: () {
                      if (widget.isWindows) {
                        _triggerWindowControls();
                      } else {
                        widget.onLogoTap?.call();
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/icons/logo.png',
                              width: 28,
                              height: 28,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00F5D4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Text('⚡', style: TextStyle(fontSize: 16)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'BOARDEST ${widget.appName}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          const SizedBox(width: 12),

          // 2. 전용 교실일 때는 교과명 뱃지 최우선 강조, 일반 교실일 때는 학교 & 학급 뱃지
          if (widget.isSpecialRoom) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7F5AF0), Color(0xFF6366F1)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7F5AF0).withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎨', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                    widget.specialSubjectName?.isNotEmpty == true
                        ? '${widget.specialSubjectName} 전용교실'
                        : '교과 전용교실',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.schoolName.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.schoolName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ] else if (schoolAndClass.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏫', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 5),
                  Text(
                    schoolAndClass,
                    style: const TextStyle(
                      color: Color(0xFF00F5D4),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // 3. 우측 상태 안내 (by jiwho 및 클라우드 상태)
          if (widget.isCloudActive)
            InkWell(
              onTap: widget.onCloudTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F5AF0).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF7F5AF0).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done_rounded, color: Color(0xFF00F5D4), size: 14),
                    SizedBox(width: 5),
                    Text(
                      'Cloud 연결됨',
                      style: TextStyle(color: Color(0xFF00F5D4), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(width: 10),

          const Text(
            'by jiwho',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
