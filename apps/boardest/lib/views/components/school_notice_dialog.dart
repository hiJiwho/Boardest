import 'package:flutter/material.dart';
import '../../models/school_notice.dart';
import '../../services/school_notice_service.dart';

/// 학교 행사 및 공지 광고판 등록/관리 다이얼로그 (사진 + 제목 형식)
class SchoolNoticeDialog extends StatefulWidget {
  final String schoolCode;
  final String teacherName;
  final bool initialShowAdd;

  const SchoolNoticeDialog({
    super.key,
    required this.schoolCode,
    this.teacherName = '',
    this.initialShowAdd = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String schoolCode,
    String teacherName = '',
    bool initialShowAdd = false,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SchoolNoticeDialog(
        schoolCode: schoolCode,
        teacherName: teacherName,
        initialShowAdd: initialShowAdd,
      ),
    );
  }

  @override
  State<SchoolNoticeDialog> createState() => _SchoolNoticeDialogState();
}

class _SchoolNoticeDialogState extends State<SchoolNoticeDialog> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotices();
    if (widget.initialShowAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddNoticeDialog();
      });
    }
  }

  Future<void> _loadNotices() async {
    setState(() => _isLoading = true);
    await SchoolNoticeService.instance.loadNotices(schoolCode: widget.schoolCode);
    if (mounted) setState(() => _isLoading = false);
  }

  void _showAddNoticeDialog() {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final teacherCtrl = TextEditingController(text: widget.teacherName);
    DateTime? selectedEndDate = DateTime.now().add(const Duration(days: 7));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16161A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: const Color(0xFF00F5D4).withOpacity(0.3)),
            ),
            title: Row(
              children: [
                const Icon(Icons.campaign_rounded, color: Color(0xFF00F5D4)),
                const SizedBox(width: 8),
                const Text('학교 행사 · 광고 등록', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('행사 제목 (사진과 함께 크게 노출됩니다)', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '예: 2026 교내 봄 축제 동아리 부스 신청 안내',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('사진 이미지 URL (Firebase Storage 등)', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: urlCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'https://...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('담당자 / 부서', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: teacherCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '예: 학생안전부, 방송반',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('행사 종료일 (종료 48시간 후 자동 삭제):', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                        TextButton.icon(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: selectedEndDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (d != null) {
                              setDlgState(() => selectedEndDate = d);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_rounded, size: 15, color: Color(0xFF00F5D4)),
                          label: Text(
                            selectedEndDate != null
                                ? '${selectedEndDate!.year}-${selectedEndDate!.month.toString().padLeft(2, '0')}-${selectedEndDate!.day.toString().padLeft(2, '0')}'
                                : '날짜 선택',
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
                  final title = titleCtrl.text.trim();
                  final url = urlCtrl.text.trim();
                  if (title.isEmpty || url.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('제목과 사진 URL을 모두 입력해 주세요.')),
                    );
                    return;
                  }

                  final notice = SchoolNotice(
                    id: 'ad_${DateTime.now().millisecondsSinceEpoch}',
                    title: title,
                    imageUrl: url,
                    teacherName: teacherCtrl.text.trim(),
                    endDate: selectedEndDate != null
                        ? '${selectedEndDate!.year}-${selectedEndDate!.month.toString().padLeft(2, '0')}-${selectedEndDate!.day.toString().padLeft(2, '0')}'
                        : null,
                    createdAt: DateTime.now(),
                  );

                  Navigator.pop(ctx);
                  final ok = await SchoolNoticeService.instance.addNotice(
                    schoolCode: widget.schoolCode,
                    notice: notice,
                  );
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ok ? '행사 광고가 성공적으로 등록되었습니다.' : '등록 실패')),
                    );
                  }
                },
                child: const Text('등록 완료', style: TextStyle(fontWeight: FontWeight.bold)),
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
      backgroundColor: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: const Color(0xFF00F5D4).withOpacity(0.3)),
      ),
      child: Container(
        width: 650,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Color(0xFF00F5D4), size: 24),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('학교 행사 & 광고판 관리', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('교실 전자칠판 및 학생 앱에 사진 + 제목으로 노출됩니다', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _showAddNoticeDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('새 행사 등록'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
                  : ValueListenableBuilder<List<SchoolNotice>>(
                      valueListenable: SchoolNoticeService.instance.noticesNotifier,
                      builder: (ctx, notices, _) {
                        if (notices.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_note_rounded, size: 54, color: Colors.white.withOpacity(0.2)),
                                const SizedBox(height: 12),
                                const Text('등록된 학교 행사 및 광고가 없습니다.', style: TextStyle(color: Colors.white54, fontSize: 15)),
                                const SizedBox(height: 6),
                                const Text('상단의 "새 행사 등록" 버튼으로 사진과 제목을 등록하세요.', style: TextStyle(color: Colors.white30, fontSize: 12)),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: notices.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (ctx, idx) {
                            final notice = notices[idx];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF24262E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      notice.imageUrl,
                                      width: 70,
                                      height: 70,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 70,
                                        height: 70,
                                        color: Colors.black38,
                                        child: const Icon(Icons.broken_image_rounded, color: Colors.white24),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          notice.title,
                                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (notice.endDate != null && notice.endDate!.isNotEmpty)
                                              Text('종료: ${notice.endDate}  •  ', style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 12)),
                                            if (notice.teacherName.isNotEmpty)
                                              Text('작성: ${notice.teacherName}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4565)),
                                    tooltip: '삭제',
                                    onPressed: () async {
                                      final ok = await SchoolNoticeService.instance.deleteNotice(
                                        schoolCode: widget.schoolCode,
                                        noticeId: notice.id,
                                      );
                                      if (mounted && ok) {
                                        setState(() {});
                                      }
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
          ],
        ),
      ),
    );
  }
}
