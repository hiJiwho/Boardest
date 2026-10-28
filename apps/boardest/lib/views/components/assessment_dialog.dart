import 'package:flutter/material.dart';
import '../../models/assessment_item.dart';
import '../../services/assessment_service.dart';

/// 교실 전자칠판 & 교사용 수행평가 / 과제 등록 및 확인 다이얼로그
class AssessmentDialog extends StatefulWidget {
  final String schoolCode;
  final int grade;
  final int classNum;
  final bool isTeacher;

  const AssessmentDialog({
    super.key,
    required this.schoolCode,
    required this.grade,
    required this.classNum,
    this.isTeacher = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String schoolCode,
    required int grade,
    required int classNum,
    bool isTeacher = false,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AssessmentDialog(
        schoolCode: schoolCode,
        grade: grade,
        classNum: classNum,
        isTeacher: isTeacher,
      ),
    );
  }

  @override
  State<AssessmentDialog> createState() => _AssessmentDialogState();
}

class _AssessmentDialogState extends State<AssessmentDialog> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await AssessmentService.instance.loadAssessments(
      schoolCode: widget.schoolCode,
      grade: widget.grade,
      classNum: widget.classNum,
    );
    if (mounted) setState(() => _isLoading = false);
  }

  void _showAddDialog() {
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController(text: '공통');
    final descCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    String selectedType = '수행평가';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E222D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.assignment_add, color: Color(0xFF00F5D4)),
                const SizedBox(width: 8),
                Text(
                  widget.isTeacher ? '수행평가 / 과제 등록 (선생님)' : '수행평가 / 과제 등록 (학생)',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: subjectCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '과목명 (예: 국어, 수학, 영어, 과학)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '수행평가 / 과제 제목',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '세부 내용 / 준비물',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('마감일: ', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setDlgState(() => selectedDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 16, color: Color(0xFF00F5D4)),
                          label: Text(
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Color(0xFF00F5D4), fontWeight: FontWeight.bold),
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소', style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5D4),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty) return;
                  final item = AssessmentItem(
                    id: 'as_${DateTime.now().millisecondsSinceEpoch}',
                    schoolCode: widget.schoolCode,
                    grade: widget.grade,
                    classNum: widget.classNum,
                    subject: subjectCtrl.text.trim().isEmpty ? '공통' : subjectCtrl.text.trim(),
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    dueDate: selectedDate,
                    type: selectedType,
                    authorRole: widget.isTeacher ? 'teacher' : 'student',
                    authorName: widget.isTeacher ? '선생님' : '${widget.grade}-${widget.classNum} 학생',
                    createdAt: DateTime.now(),
                  );
                  Navigator.pop(ctx);
                  await AssessmentService.instance.addAssessment(
                    schoolCode: widget.schoolCode,
                    item: item,
                  );
                  if (mounted) setState(() {});
                },
                child: const Text('등록하기', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF14171F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white12)),
      child: Container(
        width: 580,
        height: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF00F5D4), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '수행평가 & 과제 캘린더 (${widget.grade}학년 ${widget.classNum > 0 ? "${widget.classNum}반" : "전체"})',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '교사와 학생 모두 자유롭게 등록하고 실시간 D-Day로 마감일을 확인하세요.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 28),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
                  : ValueListenableBuilder<List<AssessmentItem>>(
                      valueListenable: AssessmentService.instance.assessmentsNotifier,
                      builder: (ctx, items, _) {
                        if (items.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisSize.min,
                              children: [
                                Icon(Icons.task_alt_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
                                const SizedBox(height: 12),
                                const Text(
                                  '등록된 수행평가나 과제가 없습니다.',
                                  style: TextStyle(color: Colors.white54, fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '아래 [+ 등록하기] 버튼을 눌러 새 수행평가를 추가해보세요!',
                                  style: TextStyle(color: Colors.white30, fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final it = items[idx];
                            final isUrgent = it.dDay >= 0 && it.dDay <= 3;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isUrgent ? const Color(0xFFFF6B6B).withOpacity(0.6) : Colors.white10,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isUrgent
                                          ? const Color(0xFFFF6B6B).withOpacity(0.2)
                                          : const Color(0xFF00F5D4).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      it.dDayString,
                                      style: TextStyle(
                                        color: isUrgent ? const Color(0xFFFF6B6B) : const Color(0xFF00F5D4),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      it.subject,
                                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          it.title,
                                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                        ),
                                        if (it.description.isNotEmpty)
                                          Text(
                                            it.description,
                                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${it.dueDate.month}/${it.dueDate.day} 마감',
                                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white38),
                                    onPressed: () async {
                                      await AssessmentService.instance.deleteAssessment(
                                        schoolCode: widget.schoolCode,
                                        grade: widget.grade,
                                        itemId: it.id,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                  label: const Text('새로고침', style: TextStyle(color: Colors.white70)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add, size: 18, color: Colors.black),
                  label: const Text('수행평가 등록', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
