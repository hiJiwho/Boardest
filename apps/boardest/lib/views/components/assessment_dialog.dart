import 'package:flutter/material.dart';
import '../../models/assessment_item.dart';
import '../../services/assessment_service.dart';

/// 교실 전자칠판 & 교사용 수행평가 / 과제 등록, 확인, 수정 다이얼로그 (v5.3.4)
class AssessmentDialog extends StatefulWidget {
  final String schoolCode;
  final int grade;
  final int classNum;
  final bool isTeacher;
  final bool initialShowAdd;
  final AssessmentItem? initialItem;

  const AssessmentDialog({
    super.key,
    required this.schoolCode,
    required this.grade,
    required this.classNum,
    this.isTeacher = false,
    this.initialShowAdd = false,
    this.initialItem,
  });

  static Future<void> show(
    BuildContext context, {
    required String schoolCode,
    required int grade,
    required int classNum,
    bool isTeacher = false,
    bool initialShowAdd = false,
    AssessmentItem? initialItem,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AssessmentDialog(
        schoolCode: schoolCode,
        grade: grade,
        classNum: classNum,
        isTeacher: isTeacher,
        initialShowAdd: initialShowAdd,
        initialItem: initialItem,
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
    if (widget.initialShowAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddOrEditDialog();
      });
    } else if (widget.initialItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDetailModal(widget.initialItem!);
      });
    }
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

  void _showAddOrEditDialog({AssessmentItem? editItem}) {
    final titleCtrl = TextEditingController(text: editItem?.title ?? '');
    final subjectCtrl = TextEditingController(text: editItem?.subject ?? '국어');
    final descCtrl = TextEditingController(text: editItem?.description ?? '');
    final rangeCtrl = TextEditingController(text: editItem?.range ?? '');
    final precautionsCtrl = TextEditingController(text: editItem?.precautions ?? '');
    final roundCtrl = TextEditingController(text: (editItem?.round ?? 1).toString());
    final periodCtrl = TextEditingController(text: (editItem?.period ?? 1).toString());
    DateTime selectedDate = editItem?.dueDate ?? DateTime.now().add(const Duration(days: 7));
    String selectedType = editItem?.type ?? '수행평가';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isEdit = editItem != null;
          return AlertDialog(
            backgroundColor: const Color(0xFF1E222D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(isEdit ? Icons.edit_note_rounded : Icons.assignment_add, color: const Color(0xFF00F5D4)),
                const SizedBox(width: 8),
                Text(
                  isEdit ? '수행평가 내용 수정' : (widget.isTeacher ? '수행평가 등록 (교사)' : '수행평가 등록 (학생)'),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: subjectCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '과목명 (예: 국어, 수학)',
                              labelStyle: TextStyle(color: Colors.white70),
                              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: roundCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '회차 (예: 1차, 2차)',
                              labelStyle: TextStyle(color: Colors.white70),
                              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: periodCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '교시 (예: 2교시)',
                              labelStyle: TextStyle(color: Colors.white70),
                              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '수행평가 / 과제 제목',
                        labelStyle: TextStyle(color: Colors.white70),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: rangeCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '수행 범위 (예: 교과서 45~52쪽, 유인물 1~3번)',
                        labelStyle: TextStyle(color: Colors.white70),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '세부 내용 / 평가 기준',
                        labelStyle: TextStyle(color: Colors.white70),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: precautionsCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '주의사항 (예: 계산기 지참, 부정행위 금지)',
                        labelStyle: TextStyle(color: Colors.white70),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('실시/마감일: ', style: TextStyle(color: Colors.white70, fontSize: 14)),
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
                    id: editItem?.id ?? 'as_${DateTime.now().millisecondsSinceEpoch}',
                    schoolCode: widget.schoolCode,
                    grade: widget.grade,
                    classNum: widget.classNum,
                    subject: subjectCtrl.text.trim().isEmpty ? '공통' : subjectCtrl.text.trim(),
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    range: rangeCtrl.text.trim(),
                    precautions: precautionsCtrl.text.trim(),
                    round: int.tryParse(roundCtrl.text.trim()) ?? 1,
                    period: int.tryParse(periodCtrl.text.trim()) ?? 1,
                    dueDate: selectedDate,
                    type: selectedType,
                    authorRole: editItem?.authorRole ?? (widget.isTeacher ? 'teacher' : 'student'),
                    authorName: editItem?.authorName ?? (widget.isTeacher ? '선생님' : '${widget.grade}-${widget.classNum} 학생'),
                    createdAt: editItem?.createdAt ?? DateTime.now(),
                  );
                  Navigator.pop(ctx);
                  await AssessmentService.instance.addAssessment(
                    schoolCode: widget.schoolCode,
                    item: item,
                  );
                  if (mounted) setState(() {});
                },
                child: Text(isEdit ? '수정 완료' : '등록하기', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDetailModal(AssessmentItem it) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181C26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(it.subject, style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                it.title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('일시', '${it.scheduleDisplay} (${it.dDayString})', highlight: true),
              if (it.round > 0) _detailRow('회차', '${it.round}차 수행평가'),
              if (it.range.isNotEmpty) _detailRow('수행 범위', it.range),
              if (it.description.isNotEmpty) _detailRow('세부 내용', it.description),
              if (it.precautions.isNotEmpty) _detailRow('주의사항', it.precautions, isWarning: true),
              _detailRow('작성자', '${it.authorName} (${it.authorRole == 'teacher' ? '교사' : '학생'})'),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showAddOrEditDialog(editItem: it);
            },
            icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF00F5D4)),
            label: const Text('수정', style: TextStyle(color: Color(0xFF00F5D4))),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await AssessmentService.instance.deleteAssessment(
                schoolCode: widget.schoolCode,
                grade: widget.grade,
                itemId: it.id,
              );
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFFF6B6B)),
            label: const Text('삭제', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool highlight = false, bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isWarning
                    ? const Color(0xFFFFB703)
                    : (highlight ? const Color(0xFF00F5D4) : Colors.white),
                fontSize: 13,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF14171F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white12)),
      child: Container(
        width: 620,
        height: 540,
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
                        '항목을 누르면 수행 범위, 세부 내용, 주의사항을 확인 및 수정할 수 있습니다.',
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
                              mainAxisSize: MainAxisSize.min,
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
                            return InkWell(
                              onTap: () => _showDetailModal(it),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
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
                                          if (it.range.isNotEmpty || it.description.isNotEmpty)
                                            Text(
                                              it.range.isNotEmpty ? '범위: ${it.range}' : it.description,
                                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    // [실시 날짜/교시] 먼저, [D-Day 뱃지] 뒤로 (순서 변경!)
                                    Text(
                                      it.scheduleDisplay,
                                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 10),
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
                                  ],
                                ),
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
                  onPressed: () => _showAddOrEditDialog(),
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
