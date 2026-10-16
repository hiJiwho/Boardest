import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/bst_cloud_service.dart';
import 'components/bst_cloud_auth_modal.dart';
import 'tools/teacher_creation_tools_view.dart';
import 'tools/teacher_usage_tools_view.dart';

export 'tools/teacher_creation_tools_view.dart';
export 'tools/teacher_usage_tools_view.dart';

/// 교사도구 통합 뷰
/// - [사용 (수업 진행 도구)]: 판서 칠판, 타이머 & 스톱워치, 계산기, 주사위 & 랜덤 뽑기
/// - [제작 (수업 저작 도구)]: TBP 스마트교과서 폴더 제작, Canva 수업 디자인 등록, 판서 노트(.bstpen) 제작 & Cloud 업로드
class BoardestToolsView extends StatefulWidget {
  final bool initialCreationMode;
  final int initialTabIndex;

  const BoardestToolsView({
    super.key,
    this.initialCreationMode = false,
    this.initialTabIndex = 0,
  });

  @override
  State<BoardestToolsView> createState() => _BoardestToolsViewState();
}

class _BoardestToolsViewState extends State<BoardestToolsView> {
  late bool _isCreationMode; // false: 수업 사용 도구, true: 수업 제작 도구
  int _usageTabIndex = 0; // 0: 판서 칠판, 1: 타이머, 2: 계산기, 3: 주사위/뽑기
  int _creationTabIndex = 0; // 0: TBP 교과서 폴더 제작, 1: Canva 디자인 등록, 2: 판서 노트 & 자료 업로드

  @override
  void initState() {
    super.initState();
    _isCreationMode = widget.initialCreationMode;
    if (_isCreationMode) {
      _creationTabIndex = widget.initialTabIndex.clamp(0, 2);
    } else {
      _usageTabIndex = widget.initialTabIndex.clamp(0, 3);
    }
  }

  Future<void> _openCloudModal() async {
    if (BstCloudService.instance.activeToken != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${BstCloudService.instance.activeTeacherName ?? "선생님"} Cloud가 이미 연결되어 있습니다.'),
          backgroundColor: const Color(0xFF10B981),
          action: SnackBarAction(
            label: '연결 해제',
            textColor: Colors.white,
            onPressed: () {
              BstCloudService.instance.disconnect();
              setState(() {});
            },
          ),
        ),
      );
      return;
    }

    await BstCloudAuthModal.show(
      context,
      schoolName: 'Boardest Tools',
      gradeClass: '교사 도구함',
      onUnlocked: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D11),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopHeader(),
            Expanded(
              child: _isCreationMode
                  ? TeacherCreationToolsView(
                      activeTabIndex: _creationTabIndex,
                      onRequestCloudConnect: _openCloudModal,
                    )
                  : TeacherUsageToolsView(
                      activeTabIndex: _usageTabIndex,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D141C),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isCreationMode
                    ? const [Color(0xFF7F5AF0), Color(0xFF00C4CC)]
                    : const [Color(0xFF00F5D4), Color(0xFF2EC4B6)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _isCreationMode ? 'CREATE' : 'USE',
              style: GoogleFonts.outfit(
                color: _isCreationMode ? Colors.white : const Color(0xFF080D11),
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Boardest',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(width: 4),
          Text(
            '교사도구',
            style: GoogleFonts.notoSansKr(
              color: _isCreationMode ? const Color(0xFF7F5AF0) : const Color(0xFF00F5D4),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 16),

          // [사용] vs [제작] 모드 스위처
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF080D11),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModeToggleChip(
                  label: '수업 사용',
                  icon: Icons.play_lesson_rounded,
                  selected: !_isCreationMode,
                  activeColor: const Color(0xFF00F5D4),
                  onTap: () => setState(() => _isCreationMode = false),
                ),
                const SizedBox(width: 4),
                _buildModeToggleChip(
                  label: '교안 제작',
                  icon: Icons.auto_fix_high_rounded,
                  selected: _isCreationMode,
                  activeColor: const Color(0xFF7F5AF0),
                  onTap: () => setState(() => _isCreationMode = true),
                ),
              ],
            ),
          ),

          const SizedBox(width: 18),

          // 세부 도구 탭 목록
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _isCreationMode
                    ? [
                        _buildTabButton(
                          index: 0,
                          currentIndex: _creationTabIndex,
                          icon: Icons.auto_stories_rounded,
                          title: 'TBP 교과서 제작',
                          accentColor: const Color(0xFF7F5AF0),
                          onTap: () => setState(() => _creationTabIndex = 0),
                        ),
                        const SizedBox(width: 8),
                        _buildTabButton(
                          index: 1,
                          currentIndex: _creationTabIndex,
                          icon: Icons.palette_rounded,
                          title: 'Canva 교안 등록',
                          accentColor: const Color(0xFF00C4CC),
                          onTap: () => setState(() => _creationTabIndex = 1),
                        ),
                        const SizedBox(width: 8),
                        _buildTabButton(
                          index: 2,
                          currentIndex: _creationTabIndex,
                          icon: Icons.draw_rounded,
                          title: '판서 노트 & 자료 업로드',
                          accentColor: const Color(0xFF00F5D4),
                          onTap: () => setState(() => _creationTabIndex = 2),
                        ),
                      ]
                    : [
                        _buildTabButton(
                          index: 0,
                          currentIndex: _usageTabIndex,
                          icon: Icons.brush_rounded,
                          title: '판서 칠판',
                          accentColor: const Color(0xFF00F5D4),
                          onTap: () => setState(() => _usageTabIndex = 0),
                        ),
                        const SizedBox(width: 8),
                        _buildTabButton(
                          index: 1,
                          currentIndex: _usageTabIndex,
                          icon: Icons.timer_outlined,
                          title: '타이머 & 스톱워치',
                          accentColor: const Color(0xFF00F5D4),
                          onTap: () => setState(() => _usageTabIndex = 1),
                        ),
                        const SizedBox(width: 8),
                        _buildTabButton(
                          index: 2,
                          currentIndex: _usageTabIndex,
                          icon: Icons.calculate_outlined,
                          title: '계산기',
                          accentColor: const Color(0xFF00F5D4),
                          onTap: () => setState(() => _usageTabIndex = 2),
                        ),
                        const SizedBox(width: 8),
                        _buildTabButton(
                          index: 3,
                          currentIndex: _usageTabIndex,
                          icon: Icons.casino_outlined,
                          title: '주사위 & 뽑기',
                          accentColor: const Color(0xFF00F5D4),
                          onTap: () => setState(() => _usageTabIndex = 3),
                        ),
                      ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: BstCloudService.instance.activeToken != null
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : const Color(0xFF00F5D4).withValues(alpha: 0.15),
              foregroundColor: BstCloudService.instance.activeToken != null
                  ? const Color(0xFF10B981)
                  : const Color(0xFF00F5D4),
              side: BorderSide(
                color: BstCloudService.instance.activeToken != null
                    ? const Color(0xFF10B981)
                    : const Color(0xFF00F5D4),
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: _openCloudModal,
            icon: Icon(
              BstCloudService.instance.activeToken != null
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_rounded,
              size: 18,
            ),
            label: Text(
              BstCloudService.instance.activeToken != null
                  ? '${BstCloudService.instance.activeTeacherName ?? '선생님'} Cloud 연결됨'
                  : 'Cloud 연동',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggleChip({
    required String label,
    required IconData icon,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final isDarkText = activeColor == const Color(0xFF00F5D4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? (isDarkText ? const Color(0xFF080D11) : Colors.white) : Colors.white54,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                color: selected ? (isDarkText ? const Color(0xFF080D11) : Colors.white) : Colors.white60,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required int currentIndex,
    required IconData icon,
    required String title,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final isSelected = currentIndex == index;
    final isDarkText = accentColor == const Color(0xFF00F5D4) || accentColor == const Color(0xFF00C4CC);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentColor : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? accentColor : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? (isDarkText ? const Color(0xFF080D11) : Colors.white) : const Color(0xFF94A1B2),
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                color: isSelected ? (isDarkText ? const Color(0xFF080D11) : Colors.white) : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
