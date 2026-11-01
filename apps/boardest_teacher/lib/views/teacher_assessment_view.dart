import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';
import 'package:file_picker/file_picker.dart';
import '../models/assessment_item.dart';
import '../models/lesson.dart';
import '../models/school_notice.dart';
import '../services/assessment_service.dart';
import '../services/comcigan_service.dart';
import '../services/school_notice_service.dart';

/// 교사용 스마트 수행평가 관리 및 다중 공지 화면
class TeacherAssessmentView extends StatefulWidget {
  final String schoolCode;
  final String teacherName;
  final TimetableResult? timetableResult;
  final VoidCallback? onBack;

  const TeacherAssessmentView({
    super.key,
    required this.schoolCode,
    required this.teacherName,
    this.timetableResult,
    this.onBack,
  });

  @override
  State<TeacherAssessmentView> createState() => _TeacherAssessmentViewState();
}

class _TeacherAssessmentViewState extends State<TeacherAssessmentView> {
  int _selectedGrade = 1;
  int _selectedClassFilter = 0; // 0: 학년 전체, 1~12: 각 반 필터
  Map<int, Set<int>> _installedClasses = {
    1: <int>{},
    2: <int>{},
    3: <int>{},
  };
  int _mainSubTab = 0; // 0: 수행평가 다중 공지, 1: 학교 행사 광고판 관리
  bool _isLoading = true;
  bool _isLoadingNotices = false;
  String _searchQuery = '';

  TextStyle _ts(double size, {FontWeight w = FontWeight.w700, Color c = Colors.white, double? h}) {
    return TextStyle(
      fontFamily: 'SiwonhanSeolreim',
      fontSize: size,
      fontWeight: w,
      color: c,
      height: h,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAssessments();
    _loadNotices();
  }

  @override
  void dispose() {
    AssessmentService.instance.stopStreaming();
    super.dispose();
  }

  Future<void> _loadAssessments() async {
    setState(() => _isLoading = true);
    final installedFuture = AssessmentService.instance.fetchInstalledClasses(widget.schoolCode);
    final loadFuture = AssessmentService.instance.loadAssessments(
      schoolCode: widget.schoolCode,
      grade: _selectedGrade,
      classNum: _selectedClassFilter,
    );
    final installedMap = await installedFuture;
    await loadFuture;
    AssessmentService.instance.startStreaming(
      schoolCode: widget.schoolCode,
      grade: _selectedGrade,
      classNum: _selectedClassFilter,
    );
    if (mounted) {
      setState(() {
        _installedClasses = installedMap;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNotices() async {
    setState(() => _isLoadingNotices = true);
    await SchoolNoticeService.instance.loadNotices(schoolCode: widget.schoolCode);
    if (mounted) setState(() => _isLoadingNotices = false);
  }

  Widget _buildSubTabButton({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSel = _mainSubTab == index;
    return InkWell(
      onTap: () {
        setState(() => _mainSubTab = index);
        if (index == 1) _loadNotices();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF00F5D4) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSel ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: _ts(
                13.5,
                w: FontWeight.w800,
                c: isSel ? Colors.black : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F131D),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단 헤더 및 액션 버튼들 ──
          Row(
            children: [
              if (widget.onBack != null) ...[
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                  tooltip: '대시보드로 돌아가기',
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                _mainSubTab == 0 ? Icons.assignment_turned_in_rounded : Icons.campaign_rounded,
                color: const Color(0xFF00F5D4),
                size: 28,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mainSubTab == 0 ? '수행평가 다중 공지 & 학사 관리' : '학교 행사 광고판 관리 (교실·학생 연동)',
                    style: _ts(22, w: FontWeight.w900),
                  ),
                  Text('${widget.schoolCode} · ${widget.teacherName} 선생님', style: _ts(12.5, c: Colors.white54)),
                ],
              ),
              const SizedBox(width: 24),
              // 서브탭 전환 버튼
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSubTabButton(
                      index: 0,
                      label: '수행평가 다중 공지',
                      icon: Icons.assignment_turned_in_rounded,
                    ),
                    const SizedBox(width: 4),
                    _buildSubTabButton(
                      index: 1,
                      label: '학교 행사 광고판',
                      icon: Icons.campaign_rounded,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_mainSubTab == 0) ...[
                // 인쇄 3종 내보내기 버튼
                OutlinedButton.icon(
                  onPressed: () => _showExportPrintDialog(),
                  icon: const Icon(Icons.print_rounded, size: 16, color: Color(0xFF00F5D4)),
                  label: Text('인쇄 3종 내보내기', style: _ts(13.5, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00F5D4), width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 12),
                // 스마트 다중 공지 버튼
                ElevatedButton.icon(
                  onPressed: () => _showSmartMultiNoticeDialog(),
                  icon: const Icon(Icons.add_task_rounded, size: 18, color: Colors.black),
                  label: Text('스마트 다중 공지 ➕', style: _ts(14.5, w: FontWeight.w900, c: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _loadNotices,
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF00F5D4)),
                  label: Text('새로고침', style: _ts(13.5, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00F5D4), width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showAddSchoolNoticeDialog(),
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 18, color: Colors.black),
                  label: Text('새 행사 광고 등록 (PNG 업로드) ➕', style: _ts(14.5, w: FontWeight.w900, c: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          if (_mainSubTab == 0) ...[
            // ── 학년 탭 및 검색 바 ──
            Row(
              children: [
                for (int g in [1, 2, 3]) ...[
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedGrade = g;
                        _selectedClassFilter = 0;
                      });
                      _loadAssessments();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedGrade == g ? const Color(0xFF00F5D4).withOpacity(0.2) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedGrade == g ? const Color(0xFF00F5D4) : Colors.white12,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        '$g학년',
                        style: _ts(
                          14,
                          w: FontWeight.w800,
                          c: _selectedGrade == g ? const Color(0xFF00F5D4) : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loadAssessments,
                  icon: const Icon(Icons.refresh_rounded, size: 15, color: Color(0xFF00F5D4)),
                  label: Text('새로고침', style: _ts(12.5, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 240,
                  height: 38,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '과목명 또는 제목 검색...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── 1반 ~ 12반 학급 선택 바 (설치 안 된 반 비활성화) ──
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() => _selectedClassFilter = 0);
                      AssessmentService.instance.updateFilter(
                        grade: _selectedGrade,
                        classNum: 0,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedClassFilter == 0
                            ? const Color(0xFF00F5D4)
                            : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedClassFilter == 0 ? const Color(0xFF00F5D4) : Colors.white12,
                        ),
                      ),
                      child: Text(
                        '전체 학급',
                        style: _ts(
                          12.5,
                          w: FontWeight.w800,
                          c: _selectedClassFilter == 0 ? Colors.black : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (int c = 1; c <= 12; c++) ...[
                    Builder(
                      builder: (_) {
                        final isInstalled = (_installedClasses[_selectedGrade] ?? const <int>{}).contains(c);
                        final isSelected = _selectedClassFilter == c;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Opacity(
                            opacity: isSelected ? 1.0 : (isInstalled ? 1.0 : 0.8),
                            child: InkWell(
                              onTap: () {
                                setState(() => _selectedClassFilter = c);
                                AssessmentService.instance.updateFilter(
                                  grade: _selectedGrade,
                                  classNum: c,
                                );
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF00F5D4)
                                      : (isInstalled
                                          ? Colors.white.withOpacity(0.07)
                                          : Colors.white.withOpacity(0.03)),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF00F5D4)
                                        : (isInstalled
                                            ? const Color(0xFF00F5D4).withOpacity(0.35)
                                            : Colors.amber.withOpacity(0.25)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isInstalled ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                      size: 12,
                                      color: isSelected
                                          ? Colors.black
                                          : (isInstalled ? const Color(0xFF00F5D4) : Colors.amberAccent),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isInstalled ? '$c반' : '$c반(미설치)',
                                      style: _ts(
                                        12,
                                        w: FontWeight.w800,
                                        c: isSelected
                                            ? Colors.black
                                            : (isInstalled ? Colors.white : Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 수행평가 목록 ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
                  : ValueListenableBuilder<List<AssessmentItem>>(
                      valueListenable: AssessmentService.instance.assessmentsNotifier,
                      builder: (context, items, _) {
                        var filtered = items.where((it) {
                          if (it.grade != _selectedGrade && it.grade != 0) return false;
                          if (_selectedClassFilter > 0 &&
                              it.classNum != 0 &&
                              it.classNum != _selectedClassFilter) {
                            return false;
                          }
                          if (_searchQuery.isNotEmpty) {
                            final q = _searchQuery.toLowerCase();
                            return it.subject.toLowerCase().contains(q) || it.title.toLowerCase().contains(q);
                          }
                          return true;
                        }).toList();

                        if (filtered.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.assignment_outlined, size: 54, color: Colors.white24),
                                const SizedBox(height: 12),
                                Text('$_selectedGrade학년에 등록된 수행평가 일정이 없습니다.', style: _ts(16, c: Colors.white54)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _showSmartMultiNoticeDialog(),
                                  icon: const Icon(Icons.add, size: 16, color: Colors.black),
                                  label: Text('첫 수행평가 공지 작성하기', style: _ts(13.5, w: FontWeight.w800, c: Colors.black)),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4)),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final it = filtered[idx];
                            return _buildAssessmentCard(it);
                          },
                        );
                      },
                    ),
            ),
          ] else ...[
            // ── 학교 행사 광고판 관리 화면 ──
            Expanded(
              child: _buildSchoolNoticeManagementContent(),
            ),
          ],
        ],
      ),
    );
  }

  /// 수행평가 카드 위젯
  Widget _buildAssessmentCard(AssessmentItem it) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 1. [과목]
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
                ),
                child: Text(it.subject, style: _ts(13, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
              ),
              const SizedBox(width: 8),
              if (it.round > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${it.round}차', style: _ts(12, w: FontWeight.w700, c: Colors.white70)),
                ),
              const SizedBox(width: 10),
              // 2. [제목]
              Expanded(
                child: Text(it.title, style: _ts(16, w: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              // 3. [실시 날짜/교시] (피드백: 일시 먼저!)
              Text(it.scheduleDisplay, style: _ts(13, c: Colors.white70, w: FontWeight.w600)),
              const SizedBox(width: 8),
              // 4. [D-Day 뱃지] (피드백: D-Day 뒤로!)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: it.dday.contains('+')
                      ? Colors.grey.withOpacity(0.2)
                      : (it.dday == 'D-Day' || it.dday == 'D-1'
                          ? Colors.redAccent.withOpacity(0.25)
                          : Colors.amber.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: it.dday == 'D-Day' || it.dday == 'D-1'
                        ? Colors.redAccent
                        : Colors.amber.withOpacity(0.6),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  it.dday,
                  style: _ts(
                    11.5,
                    w: FontWeight.w900,
                    c: it.dday == 'D-Day' || it.dday == 'D-1' ? Colors.redAccent : Colors.amberAccent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 대상 반 표기
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F5AF0).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  it.classNum == 0 ? '${it.grade}학년 전체' : '${it.grade}-${it.classNum}반',
                  style: _ts(12, w: FontWeight.w800, c: const Color(0xFFB8A2FF)),
                ),
              ),
              const SizedBox(width: 12),
              // 삭제 버튼
              IconButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E222D),
                      title: const Text('수행평가 삭제', style: TextStyle(color: Colors.white)),
                      content: Text('\'${it.title}\' 공지를 삭제하시겠습니까?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B)),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('삭제', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await AssessmentService.instance.deleteAssessment(
                      schoolCode: widget.schoolCode,
                      grade: it.grade,
                      itemId: it.id,
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFFF6B6B)),
                tooltip: '공지 삭제',
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 수행 범위 및 세부 내용
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (it.range.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('수행 범위: ', style: _ts(12.5, c: Colors.white54)),
                    Text(it.range, style: _ts(12.5, w: FontWeight.w700, c: Colors.white)),
                  ],
                ),
              if (it.description.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('세부 내용: ', style: _ts(12.5, c: Colors.white54)),
                    Text(it.description, style: _ts(12.5, c: Colors.white70)),
                  ],
                ),
              if (it.precautions.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFFD166)),
                    const SizedBox(width: 4),
                    Text('주의사항: ', style: _ts(12.5, c: const Color(0xFFFFD166))),
                    Text(it.precautions, style: _ts(12.5, c: Colors.white)),
                  ],
                ),
              if (it.points > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('배점: ', style: _ts(12.5, c: Colors.white54)),
                    Text('${it.points}점', style: _ts(12.5, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 스마트 다중 공지 다이얼로그 (동료 교사 시간표 병합 + 주간 달력 시각화) ──
  void _showSmartMultiNoticeDialog() {
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController(text: '수학');
    final descCtrl = TextEditingController();
    final rangeCtrl = TextEditingController();
    final precautionsCtrl = TextEditingController();
    final roundCtrl = TextEditingController(text: '1');
    final periodCtrl = TextEditingController(text: '2');
    final pointsCtrl = TextEditingController(text: '20');
    final colleagueCtrl = TextEditingController();

    int selectedGrade = _selectedGrade;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    // 대상 학급 선택 상태: 설치 학급이 있으면 설치 학급 우선, 없으면 1~12반 전체 폴백 (Lockout 원천 차단)
    final initialInstalled = _installedClasses[selectedGrade] ?? const <int>{};
    final Set<int> selectedClasses = initialInstalled.isNotEmpty
        ? Set<int>.from(initialInstalled)
        : Set<int>.from(List.generate(12, (i) => i + 1));
    bool refreshedInstalled = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          if (!refreshedInstalled) {
            refreshedInstalled = true;
            AssessmentService.instance.fetchInstalledClasses(widget.schoolCode).then((map) {
              if (!mounted) return;
              setState(() => _installedClasses = map);
              setDlgState(() {
                final inst = map[selectedGrade] ?? const <int>{};
                if (selectedClasses.isEmpty) {
                  if (inst.isNotEmpty) {
                    selectedClasses.addAll(inst);
                  } else {
                    selectedClasses.addAll(List.generate(12, (i) => i + 1));
                  }
                }
              });
            });
          }
          final installedForGrade = _installedClasses[selectedGrade] ?? const <int>{};
          // 동료 교사 시간표 병합 계산
          final colleagueName = colleagueCtrl.text.trim();
          final List<Lesson> relevantLessons = [];
          if (widget.timetableResult != null) {
            for (final lesson in widget.timetableResult!.lessons) {
              if (lesson.grade != selectedGrade) continue;
              final isMe = lesson.teacher == widget.teacherName;
              final isColleague = colleagueName.isNotEmpty &&
                  (lesson.teacher == colleagueName || lesson.teacher.contains(colleagueName));
              if (isMe || isColleague) {
                relevantLessons.add(lesson);
              }
            }
          }

          // 주간 수업 집중 요일 분석 (월~금 중 수업이 몇 개나 걸쳐 있는지)
          final Map<int, List<Lesson>> weekdayLessons = {1: [], 2: [], 3: [], 4: [], 5: []};
          for (final l in relevantLessons) {
            if (weekdayLessons.containsKey(l.weekday)) {
              weekdayLessons[l.weekday]!.add(l);
            }
          }
          final activeDaysCount = weekdayLessons.values.where((list) => list.isNotEmpty).length;

          return AlertDialog(
            backgroundColor: const Color(0xFF161A24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00F5D4), size: 24),
                const SizedBox(width: 8),
                Text('스마트 수행평가 다중 공지', style: _ts(19, w: FontWeight.w900)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                ),
              ],
            ),
            content: SizedBox(
              width: 820,
              height: 600,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 학년 및 과목 / 회차
                    Row(
                      children: [
                        // 학년 선택
                        for (int g in [1, 2, 3]) ...[
                          ChoiceChip(
                            label: Text('$g학년'),
                            selected: selectedGrade == g,
                            selectedColor: const Color(0xFF00F5D4),
                            onSelected: (val) {
                              if (val) {
                                setDlgState(() {
                                  selectedGrade = g;
                                  final inst = _installedClasses[g] ?? const <int>{};
                                  selectedClasses.clear();
                                  if (inst.isNotEmpty) {
                                    selectedClasses.addAll(inst);
                                  } else {
                                    selectedClasses.addAll(List.generate(12, (i) => i + 1));
                                  }
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: subjectCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '과목명',
                              labelStyle: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: roundCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '회차 (예: 1차)',
                              labelStyle: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: periodCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '실시 교시',
                              labelStyle: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: pointsCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '배점 (점)',
                              labelStyle: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 제목
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '수행평가 제목 (예: 이차방정식 활용 서술형 평가)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 수행 범위
                    TextField(
                      controller: rangeCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '수행 범위 (예: 교과서 82p ~ 115p, 학습지 1~4호)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 세부 내용 & 주의사항
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: descCtrl,
                            maxLines: 2,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '세부 내용 및 평가 방식',
                              labelStyle: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: precautionsCtrl,
                            maxLines: 2,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '주의사항 및 준비물 (예: 계산기 지참 불가)',
                              labelStyle: TextStyle(color: Colors.amberAccent),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── 공지 대상 학급 선택 (1~12반 전체 표시 및 선택 가능) ──
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('대상 학급 선택 (1~12반): ', style: _ts(14, w: FontWeight.w800)),
                            const SizedBox(width: 8),
                            ActionChip(
                              label: Text(
                                selectedClasses.length == 12
                                    ? '전체 해제'
                                    : (installedForGrade.isNotEmpty
                                        ? (selectedClasses.length == installedForGrade.length &&
                                                selectedClasses.containsAll(installedForGrade)
                                            ? '1~12반 전체 선택'
                                            : '설치 학급 선택 (${installedForGrade.length}개 반)')
                                        : '1~12반 전체 선택'),
                              ),
                              onPressed: () {
                                setDlgState(() {
                                  if (selectedClasses.length == 12) {
                                    selectedClasses.clear();
                                  } else if (installedForGrade.isNotEmpty &&
                                      (selectedClasses.length != installedForGrade.length ||
                                          !selectedClasses.containsAll(installedForGrade))) {
                                    selectedClasses
                                      ..clear()
                                      ..addAll(installedForGrade);
                                  } else {
                                    selectedClasses
                                      ..clear()
                                      ..addAll(List.generate(12, (i) => i + 1));
                                  }
                                });
                              },
                            ),
                            if (installedForGrade.isNotEmpty && selectedClasses.length != 12) ...[
                              const SizedBox(width: 8),
                              ActionChip(
                                label: const Text('1~12반 모두 선택'),
                                onPressed: () {
                                  setDlgState(() {
                                    selectedClasses
                                      ..clear()
                                      ..addAll(List.generate(12, (i) => i + 1));
                                  });
                                },
                              ),
                            ],
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                installedForGrade.isEmpty
                                    ? '※ 설치 학급 정보 확인 전이므로 1~12반 전체에 자유롭게 공지 가능합니다.'
                                    : '※ 미설치 학급도 선택 가능하며, 해당 교실에서 앱 실행 시 자동 동기화됩니다.',
                                style: _ts(11.5, c: Colors.white54),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (int c = 1; c <= 12; c++)
                              Builder(
                                builder: (_) {
                                  final isInstalled = installedForGrade.contains(c);
                                  final isSel = selectedClasses.contains(c);
                                  return FilterChip(
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!isInstalled) ...[
                                          Icon(
                                            Icons.info_outline_rounded,
                                            size: 13,
                                            color: isSel ? Colors.black87 : Colors.amberAccent,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          isInstalled ? '$c반' : '$c반(미설치)',
                                          style: TextStyle(
                                            color: isSel
                                                ? Colors.black
                                                : (isInstalled ? Colors.white : Colors.white70),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    selected: isSel,
                                    selectedColor: isInstalled
                                        ? const Color(0xFF00F5D4)
                                        : const Color(0xFFFFD166),
                                    backgroundColor: isInstalled
                                        ? Colors.white.withOpacity(0.08)
                                        : Colors.white.withOpacity(0.04),
                                    side: BorderSide(
                                      color: isSel
                                          ? (isInstalled ? const Color(0xFF00F5D4) : const Color(0xFFFFD166))
                                          : (isInstalled ? Colors.white12 : Colors.amber.withOpacity(0.3)),
                                      width: 1,
                                    ),
                                    checkmarkColor: Colors.black,
                                    onSelected: (val) {
                                      setDlgState(() {
                                        if (val) {
                                          selectedClasses.add(c);
                                        } else {
                                          selectedClasses.remove(c);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                        if (selectedClasses.any((c) => !installedForGrade.contains(c))) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.info_outline_rounded, size: 14, color: Colors.amberAccent),
                                const SizedBox(width: 6),
                                Text(
                                  '안내: 미설치 학급(${selectedClasses.where((c) => !installedForGrade.contains(c)).map((c) => '$c반').join(', ')})도 공지 등록되며, 교실 앱 실행 시 즉시 반영됩니다.',
                                  style: _ts(11.5, c: Colors.amberAccent),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── 동료 교사 시간표 병합 & 추천 배너 (피드백 반영) ──
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2536),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.people_alt_rounded, size: 20, color: Color(0xFF00F5D4)),
                              const SizedBox(width: 8),
                              Text('동료 교사 시간표 연동 (일정 최적화)', style: _ts(14.5, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
                              const Spacer(),
                              SizedBox(
                                width: 220,
                                height: 36,
                                child: TextField(
                                  controller: colleagueCtrl,
                                  onChanged: (_) => setDlgState(() {}),
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: '동료 교사명 (예: 김윤리)',
                                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                                    filled: true,
                                    fillColor: Colors.black26,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (colleagueName.isNotEmpty && relevantLessons.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00F5D4).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lightbulb_rounded, color: Color(0xFF00F5D4), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '💡 추천: ${widget.teacherName} 쌤과 $colleagueName 쌤의 수업을 합산하면, 전 학급 수행평가가 ${activeDaysCount}일 안에 집중 완료됩니다!',
                                      style: _ts(13, w: FontWeight.w800, c: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),

                          // ── 주간 시간표 그리드 시각화 (피드백 반영: 주간 달력으로 어떻게 몰리는지 표시) ──
                          Text('📅 주간 시간표 수업 집중도 시각화', style: _ts(13.5, w: FontWeight.w800)),
                          const SizedBox(height: 8),
                          _buildWeeklyTimetableGrid(relevantLessons, colleagueName),
                          const SizedBox(height: 10),

                          // 실시 날짜 선택 및 [다음 주로 미루기 ⏩] 버튼
                          Row(
                            children: [
                              Text('실시 예정일: ', style: _ts(13, c: Colors.white70)),
                              TextButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: selectedDate,
                                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) {
                                    setDlgState(() => selectedDate = picked);
                                  }
                                },
                                icon: const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF00F5D4)),
                                label: Text(
                                  '${selectedDate.year}년 ${selectedDate.month}월 ${selectedDate.day}일 (날짜 변경)',
                                  style: _ts(13.5, w: FontWeight.w800, c: const Color(0xFF00F5D4)),
                                ),
                              ),
                              const Spacer(),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setDlgState(() {
                                    selectedDate = selectedDate.add(const Duration(days: 7));
                                  });
                                },
                                icon: const Icon(Icons.fast_forward_rounded, size: 16, color: Colors.black),
                                label: Text('다음 주로 미루기 ⏩', style: _ts(12.5, w: FontWeight.w800, c: Colors.black)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFD166),
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('수행평가 제목을 입력해주세요.')),
                    );
                    return;
                  }
                  if (selectedClasses.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('공지할 학급을 1개 이상 선택해주세요.')),
                    );
                    return;
                  }
                  final targetList = selectedClasses.toList()..sort();
                  final baseItem = AssessmentItem(
                    id: '',
                    schoolCode: widget.schoolCode,
                    grade: selectedGrade,
                    classNum: 0,
                    subject: subjectCtrl.text.trim().isEmpty ? '과목' : subjectCtrl.text.trim(),
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    range: rangeCtrl.text.trim(),
                    precautions: precautionsCtrl.text.trim(),
                    round: int.tryParse(roundCtrl.text.trim()) ?? 1,
                    period: int.tryParse(periodCtrl.text.trim()) ?? 2,
                    points: int.tryParse(pointsCtrl.text.trim()) ?? 20,
                    dueDate: selectedDate,
                    type: '수행평가',
                    authorRole: 'teacher',
                    authorName: widget.teacherName,
                    createdAt: DateTime.now(),
                  );

                  Navigator.pop(ctx);
                  if (_selectedGrade != selectedGrade) {
                    setState(() {
                      _selectedGrade = selectedGrade;
                      _selectedClassFilter = 0;
                    });
                  }
                  await AssessmentService.instance.addMultiClassAssessment(
                    schoolCode: widget.schoolCode,
                    baseItem: baseItem,
                    targetClasses: targetList,
                  );
                  await _loadAssessments();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$selectedGrade학년 ${targetList.map((c) => '$c반').join(', ')} (${targetList.length}개 학급)에 수행평가가 공지되었습니다!',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFF00F5D4),
                    ),
                  );
                },
                icon: const Icon(Icons.send_rounded, size: 16, color: Colors.black),
                label: Text('선택 학급(${selectedClasses.length}개 반) 즉시 공지 등록', style: _ts(14, w: FontWeight.w900, c: Colors.black)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 주간 시간표 그리드 시각화 (월~금, 1~7교시)
  Widget _buildWeeklyTimetableGrid(List<Lesson> lessons, String colleagueName) {
    const days = ['월', '화', '수', '목', '금'];
    return Table(
      border: TableBorder.all(color: Colors.white12, width: 1.0),
      children: [
        // 요일 헤더
        TableRow(
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06)),
          children: [
            Center(child: Padding(padding: const EdgeInsets.all(4), child: Text('교시', style: _ts(11, c: Colors.white54)))),
            for (final d in days)
              Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(d, style: _ts(11.5, w: FontWeight.w800)))),
          ],
        ),
        // 1~6교시 행
        for (int p = 1; p <= 6; p++)
          TableRow(
            children: [
              Center(child: Padding(padding: const EdgeInsets.all(4), child: Text('$p', style: _ts(11, c: Colors.white54)))),
              for (int w = 1; w <= 5; w++)
                Builder(
                  builder: (_) {
                    final matching = lessons.where((l) => l.weekday == w && l.classTime == p).toList();
                    if (matching.isEmpty) {
                      return const SizedBox(height: 24);
                    }
                    return Container(
                      padding: const EdgeInsets.all(2),
                      color: const Color(0xFF00F5D4).withOpacity(0.12),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 2,
                        children: matching.map((l) {
                          final isMe = l.teacher == widget.teacherName;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF00F5D4) : Colors.amber,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${l.grade}-${l.classNum}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }

  // ── 3-Way 인쇄 / 내보내기 모달 ──
  void _showExportPrintDialog() {
    final items = AssessmentService.instance.assessments;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.print_rounded, color: Color(0xFF00F5D4), size: 24),
            const SizedBox(width: 8),
            Text('수행평가 3종 인쇄 / 내보내기', style: _ts(18, w: FontWeight.w900)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. 표준 학사 일정표 (Excel / CSV)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.table_chart_rounded, color: Colors.greenAccent),
                ),
                title: Text('1. 표준 학사 일정표 (Excel / CSV)', style: _ts(14.5, w: FontWeight.w800)),
                subtitle: const Text('NEIS 규격 호환 CSV 클립보드 복사 (Excel 바로 열기 지원)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: ElevatedButton(
                  onPressed: () {
                    final csv = _generateCsv(items);
                    Clipboard.setData(ClipboardData(text: csv));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Excel용 CSV 데이터가 클립보드에 복사되었습니다. (Ctrl+V로 붙여넣기 가능)')),
                    );
                  },
                  child: const Text('복사'),
                ),
              ),
              const Divider(color: Colors.white12),

              // 2. A4 1장 전 학급 요약본 (인쇄용)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF7F5AF0).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.newspaper_rounded, color: Color(0xFFB8A2FF)),
                ),
                title: Text('2. A4 1장 전 학급 요약본', style: _ts(14.5, w: FontWeight.w800)),
                subtitle: const Text('교무실 게시용 전 학급 수행평가 한눈에 보기 표', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: ElevatedButton(
                  onPressed: () {
                    final text = _generateSummaryText(items);
                    Clipboard.setData(ClipboardData(text: text));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('A4 요약본 서식이 클립보드에 복사되었습니다.')),
                    );
                  },
                  child: const Text('복사'),
                ),
              ),
              const Divider(color: Colors.white12),

              // 3. 반별 안내장 (학생 배부용)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF00F5D4).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.description_rounded, color: Color(0xFF00F5D4)),
                ),
                title: Text('3. 반별 안내장 (학생 배부용)', style: _ts(14.5, w: FontWeight.w800)),
                subtitle: const Text('학급 알림판 및 가정통신문 첨부용 서식', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: ElevatedButton(
                  onPressed: () {
                    final text = _generateClassNoticeText(items);
                    Clipboard.setData(ClipboardData(text: text));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('반별 안내장 서식이 클립보드에 복사되었습니다.')),
                    );
                  },
                  child: const Text('복사'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  String _generateCsv(List<AssessmentItem> items) {
    final sb = StringBuffer();
    sb.writeln('\uFEFF학년,학급,과목,회차,교시,제목,실시일,배점,수행범위,주의사항');
    for (final it in items) {
      final cName = it.classNum == 0 ? '전체' : '${it.classNum}반';
      sb.writeln('${it.grade},$cName,"${it.subject}","${it.round}차","${it.period}교시","${it.title}","${it.dueDate.year}-${it.dueDate.month}-${it.dueDate.day}",${it.points},"${it.range}","${it.precautions}"');
    }
    return sb.toString();
  }

  String _generateSummaryText(List<AssessmentItem> items) {
    final sb = StringBuffer();
    sb.writeln('========================================');
    sb.writeln('  [ ${widget.schoolCode} ] 수행평가 학사 일정 요약표');
    sb.writeln('  담당 교사: ${widget.teacherName}');
    sb.writeln('========================================\n');
    for (final it in items) {
      final cName = it.classNum == 0 ? '전 학급' : '${it.grade}-${it.classNum}반';
      sb.writeln('▶ [${it.subject}] ${it.title} (${it.round}차)');
      sb.writeln('  - 대상: $cName | 일시: ${it.scheduleDisplay}');
      sb.writeln('  - 범위: ${it.range}');
      sb.writeln('  - 배점: ${it.points}점 | 주의사항: ${it.precautions}\n');
    }
    return sb.toString();
  }

  String _generateClassNoticeText(List<AssessmentItem> items) {
    final sb = StringBuffer();
    sb.writeln('📢 [학급 공지사항] 이번 주 수행평가 안내');
    sb.writeln('----------------------------------------');
    for (final it in items) {
      sb.writeln('• 과목: ${it.subject} (${it.title})');
      sb.writeln('  일시: ${it.scheduleDisplay}');
      sb.writeln('  범위: ${it.range}');
      if (it.precautions.isNotEmpty) {
        sb.writeln('  주의사항: ${it.precautions}');
      }
      sb.writeln('');
    }
    sb.writeln('※ 준비물을 반드시 확인하고 성실하게 임해 주시기 바랍니다.');
    return sb.toString();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 학교 행사 및 공지 광고판 관리 화면 (교실 및 학생 앱 연동) ──
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSchoolNoticeManagementContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 안내 배너
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF161E2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00F5D4), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '전자칠판(Boardest Class) & 학생 웹(Boardest Student) 실시간 연동 광고판',
                      style: _ts(14.5, w: FontWeight.bold, c: const Color(0xFF00F5D4)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '등록된 행사 포스터(사진+제목)는 교실 화면 우측에 30초마다 자동 회전 표출되며, 학생 앱에서도 확인 가능합니다. 완료된 행사는 48시간 후 자동 삭제됩니다.',
                      style: _ts(12.5, c: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 공지 목록
        Expanded(
          child: _isLoadingNotices
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
              : ValueListenableBuilder<List<SchoolNotice>>(
                  valueListenable: SchoolNoticeService.instance.noticesNotifier,
                  builder: (context, notices, _) {
                    if (notices.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.campaign_outlined, size: 64, color: Colors.white24),
                            const SizedBox(height: 14),
                            Text('현재 등록된 학교 행사 광고판이 없습니다.', style: _ts(16, c: Colors.white54)),
                            const SizedBox(height: 8),
                            Text('교내 포스터나 행사 안내 사진을 등록하면 교실 전자칠판에 자동 송출됩니다.', style: _ts(13, c: Colors.white38)),
                            const SizedBox(height: 18),
                            ElevatedButton.icon(
                              onPressed: () => _showAddSchoolNoticeDialog(),
                              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18, color: Colors.black),
                              label: Text('첫 행사 광고 등록하기', style: _ts(14, w: FontWeight.w800, c: Colors.black)),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4)),
                            ),
                          ],
                        ),
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 20),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 380,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: notices.length,
                      itemBuilder: (context, idx) {
                        final notice = notices[idx];
                        return _buildNoticeCard(notice);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNoticeCard(SchoolNotice notice) {
    String dDayStr = '';
    bool isExpired = false;
    if (notice.endDate != null && notice.endDate!.isNotEmpty) {
      final ed = DateTime.tryParse(notice.endDate!);
      if (ed != null) {
        final now = DateTime.now();
        final diff = ed.difference(DateTime(now.year, now.month, now.day)).inDays;
        if (diff > 0) {
          dDayStr = 'D-$diff';
        } else if (diff == 0) {
          dDayStr = 'D-Day 오늘마감';
        } else {
          dDayStr = '마감됨 (48h 내 자동삭제)';
          isExpired = true;
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141926),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpired ? Colors.redAccent.withOpacity(0.4) : const Color(0xFF00F5D4).withOpacity(0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 포스터 이미지 영역
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildNoticeImage(notice.imageUrl),
                // 상단 배지
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.campaign_rounded, size: 14, color: Color(0xFF00F5D4)),
                        const SizedBox(width: 4),
                        Text('교내 행사 광고', style: _ts(11, w: FontWeight.bold, c: Colors.white)),
                      ],
                    ),
                  ),
                ),
                if (dDayStr.isNotEmpty)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isExpired ? Colors.red.shade900 : const Color(0xFF00F5D4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        dDayStr,
                        style: _ts(11, w: FontWeight.w900, c: isExpired ? Colors.white : Colors.black),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 정보 및 삭제 바
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: _ts(15, w: FontWeight.w900, c: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_rounded, size: 13, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      notice.teacherName.isNotEmpty ? '${notice.teacherName} 선생님' : '담당 교사',
                      style: _ts(12, c: Colors.white60),
                    ),
                    const Spacer(),
                    if (notice.endDate != null && notice.endDate!.isNotEmpty)
                      Text(
                        '종료: ${notice.endDate}',
                        style: _ts(12, c: Colors.white54),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _confirmDeleteNotice(notice),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                      label: Text('삭제하기', style: _ts(12.5, w: FontWeight.w700, c: Colors.redAccent)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        backgroundColor: Colors.red.withOpacity(0.08),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteNotice(SchoolNotice notice) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161924),
        title: Text('행사 광고판 삭제', style: _ts(18, w: FontWeight.w900)),
        content: Text(
          '\'${notice.title}\' 행사 광고를 삭제하시겠습니까?\n삭제 즉시 교실 전자칠판 및 학생 앱에서도 내려갑니다.',
          style: _ts(14, c: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: _ts(14, c: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('삭제', style: _ts(14, w: FontWeight.bold, c: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true) {
      final success = await SchoolNoticeService.instance.deleteNotice(
        schoolCode: widget.schoolCode,
        noticeId: notice.id,
      );
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('행사 광고판이 삭제되었습니다.'),
              backgroundColor: Colors.black87,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('삭제에 실패했습니다. 네트워크를 확인해 주세요.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _showAddSchoolNoticeDialog() {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final teacherCtrl = TextEditingController(text: widget.teacherName);
    DateTime selectedEndDate = DateTime.now().add(const Duration(days: 7));
    String selectedFileName = '';
    String previewUrl = '';
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141926),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: const Color(0xFF00F5D4).withOpacity(0.3), width: 1.2),
              ),
              title: Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: Color(0xFF00F5D4), size: 24),
                  const SizedBox(width: 8),
                  Text('새 학교 행사 · 광고판 등록', style: _ts(18, w: FontWeight.w900)),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '교실 전자칠판(30초 회전)과 학생 앱에 송출될 포스터(사진+제목)를 등록합니다.',
                        style: _ts(12.5, c: Colors.white60),
                      ),
                      const SizedBox(height: 16),

                      // 포스터 파일 선택 버튼 및 미리보기
                      Text('포스터 사진 (PNG / JPG / WEBP)', style: _ts(13, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final res = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
                                withData: true,
                              );
                              if (res != null && res.files.isNotEmpty) {
                                final f = res.files.first;
                                Uint8List? bytes = f.bytes;
                                if (bytes == null && f.path != null) {
                                  try {
                                    bytes = await File(f.path!).readAsBytes();
                                  } catch (_) {}
                                }
                                if (bytes != null) {
                                  final ext = (f.extension ?? 'png').toLowerCase();
                                  final mime = (ext == 'jpg' || ext == 'jpeg')
                                      ? 'image/jpeg'
                                      : (ext == 'webp' ? 'image/webp' : 'image/png');
                                  final b64 = base64Encode(bytes);
                                  setDState(() {
                                    selectedFileName = f.name;
                                    previewUrl = 'data:$mime;base64,$b64';
                                    urlCtrl.text = previewUrl;
                                  });
                                }
                              }
                            },
                            icon: const Icon(Icons.folder_open_rounded, size: 16, color: Colors.black),
                            label: Text('컴퓨터에서 PNG 선택', style: _ts(13, w: FontWeight.w800, c: Colors.black)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedFileName.isNotEmpty ? selectedFileName : (previewUrl.isNotEmpty ? '이미지 준비됨' : '선택된 파일 없음'),
                              style: _ts(12, c: selectedFileName.isNotEmpty ? const Color(0xFF00F5D4) : Colors.white38),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 미리보기 컨테이너
                      if (previewUrl.isNotEmpty) ...[
                        Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildNoticeImage(previewUrl),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 또는 웹 이미지 URL 직접 입력
                      TextField(
                        controller: urlCtrl,
                        onChanged: (val) {
                          setDState(() {
                            previewUrl = val.trim();
                          });
                        },
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: '또는 이미지 URL 직접 입력 (선택)',
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                          hintText: 'https://...',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 행사 제목 입력 (필수)
                      Text('행사 및 공지 제목 (필수)', style: _ts(13, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                      const SizedBox(height: 6),
                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '예: 2026학년도 교내 봄 축제 부스 참가 신청 안내',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 마감일 및 담당 교사
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('행사 마감일 (48h 후 자동 삭제)', style: _ts(12.5, w: FontWeight.w700, c: Colors.white70)),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final d = await showDatePicker(
                                      context: dialogCtx,
                                      initialDate: selectedEndDate,
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (d != null) {
                                      setDState(() => selectedEndDate = d);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF00F5D4)),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${selectedEndDate.year}-${selectedEndDate.month.toString().padLeft(2, '0')}-${selectedEndDate.day.toString().padLeft(2, '0')}',
                                          style: _ts(13, w: FontWeight.bold, c: const Color(0xFF00F5D4)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('담당 교사명', style: _ts(12.5, w: FontWeight.w700, c: Colors.white70)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: teacherCtrl,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.05),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: Text('취소', style: _ts(14, c: Colors.white54)),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          final img = previewUrl.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('행사 제목을 입력해 주세요.')),
                            );
                            return;
                          }
                          if (img.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('포스터 사진(PNG/JPG)을 선택하거나 이미지 URL을 입력해 주세요.')),
                            );
                            return;
                          }

                          setDState(() => isSubmitting = true);
                          final id = 'notice_${DateTime.now().millisecondsSinceEpoch}';
                          final notice = SchoolNotice(
                            id: id,
                            title: title,
                            imageUrl: img,
                            teacherName: teacherCtrl.text.trim().isNotEmpty ? teacherCtrl.text.trim() : widget.teacherName,
                            endDate: '${selectedEndDate.year}-${selectedEndDate.month.toString().padLeft(2, '0')}-${selectedEndDate.day.toString().padLeft(2, '0')}',
                            createdAt: DateTime.now(),
                          );

                          final success = await SchoolNoticeService.instance.addNotice(
                            schoolCode: widget.schoolCode,
                            notice: notice,
                          );

                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }

                          if (mounted) {
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('🎉 \'${notice.title}\' 행사 광고가 교실 및 학생 화면에 등록되었습니다!'),
                                  backgroundColor: const Color(0xFF00B4D8),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('등록에 실패했습니다. Firebase 연결 상태를 확인해 주세요.'),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.cloud_upload_rounded, size: 18, color: Colors.black),
                  label: Text('광고판 등록 및 송출 🚀', style: _ts(14, w: FontWeight.w900, c: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNoticeImage(String imageUrl) {
    if (imageUrl.startsWith('data:image')) {
      try {
        final commaIdx = imageUrl.indexOf(',');
        final base64Str = commaIdx != -1 ? imageUrl.substring(commaIdx + 1) : imageUrl;
        final bytes = base64Decode(base64Str);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildNoticeImageFallback(),
        );
      } catch (_) {}
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildNoticeImageFallback(),
    );
  }

  Widget _buildNoticeImageFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E2638), Color(0xFF101420)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.campaign_rounded, color: Color(0xFF00F5D4), size: 36),
            const SizedBox(height: 6),
            Text('학교 행사 포스터', style: _ts(13, w: FontWeight.bold, c: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
