import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cloud_drive_service.dart';
import 'website_board_view.dart';

/// BoardBook Web Textbook Card Model
class WebTextbookCard {
  String id;
  String title;
  String url;
  String grade; // '공통', '1학년', '2학년', '3학년', '4학년', '5학년', '6학년'
  String emoji;

  WebTextbookCard({
    required this.id,
    required this.title,
    required this.url,
    required this.grade,
    required this.emoji,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'grade': grade,
        'emoji': emoji,
      };

  factory WebTextbookCard.fromJson(Map<String, dynamic> json) => WebTextbookCard(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        url: json['url'] ?? '',
        grade: json['grade'] ?? '공통',
        emoji: json['emoji'] ?? '📖',
      );
}

/// BoardBook 스마트 교과서 런처 & dHash 기반 bst-pen 오프라인/온라인 교과서 뷰어
class BoardBookEditor extends StatefulWidget {
  final double scaleFactor;
  final Function(String url, String title)? onOpenUrl;

  const BoardBookEditor({
    super.key,
    required this.scaleFactor,
    this.onOpenUrl,
  });

  @override
  State<BoardBookEditor> createState() => _BoardBookEditorState();
}

class _BoardBookEditorState extends State<BoardBookEditor> {
  final List<WebTextbookCard> _textbooks = [];
  String _selectedGradeFilter = '전체';

  @override
  void initState() {
    super.initState();
    _loadDefaultTextbooks();
  }

  Future<void> _loadDefaultTextbooks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('boardbook_web_textbooks');

    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List list = jsonDecode(jsonStr);
        setState(() {
          _textbooks.clear();
          _textbooks.addAll(list.map((e) => WebTextbookCard.fromJson(e)));
        });
        return;
      } catch (_) {}
    }

    // 기본 등록 디지털 교과서 템플릿
    setState(() {
      _textbooks.addAll([
        WebTextbookCard(
          id: '1',
          title: '초등 국어 3-1',
          url: 'https://dt.kbedu.or.kr/sample_korean3',
          grade: '3학년',
          emoji: '📕',
        ),
        WebTextbookCard(
          id: '2',
          title: '초등 수학 3-1',
          url: 'https://dt.kbedu.or.kr/sample_math3',
          grade: '3학년',
          emoji: '📐',
        ),
        WebTextbookCard(
          id: '3',
          title: '초등 사회 4-1',
          url: 'https://dt.kbedu.or.kr/sample_social4',
          grade: '4학년',
          emoji: '🌏',
        ),
        WebTextbookCard(
          id: '4',
          title: '초등 과학 4-1',
          url: 'https://dt.kbedu.or.kr/sample_science4',
          grade: '4학년',
          emoji: '🧪',
        ),
        WebTextbookCard(
          id: '5',
          title: '디지털 교과서 포털',
          url: 'https://dt.ebs.co.kr',
          grade: '공통',
          emoji: '🏫',
        ),
      ]);
    });
    _saveTextbooks();
  }

  Future<void> _saveTextbooks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_textbooks.map((e) => e.toJson()).toList());
    await prefs.setString('boardbook_web_textbooks', jsonStr);
  }

  void _showAddTextbookDialog([WebTextbookCard? editCard]) {
    final titleCtrl = TextEditingController(text: editCard?.title ?? '');
    final urlCtrl = TextEditingController(text: editCard?.url ?? '');
    final emojiCtrl = TextEditingController(text: editCard?.emoji ?? '📖');
    String gradeVal = editCard?.grade ?? '공통';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text(
          editCard == null ? '✨ 새 디지털 교과서 등록' : '✏️ 교과서 수정',
          style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 50,
                  child: TextField(
                    controller: emojiCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: '이모지', labelStyle: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: '교과서 이름', labelStyle: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: '웹사이트 URL', labelStyle: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF242629),
              value: gradeVal,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: '학년 구분', labelStyle: TextStyle(color: Colors.white70)),
              items: ['공통', '1학년', '2학년', '3학년', '4학년', '5학년', '6학년']
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (val) {
                if (val != null) gradeVal = val;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EC4B6)),
            onPressed: () {
              final title = titleCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (title.isEmpty || url.isEmpty) return;

              setState(() {
                if (editCard == null) {
                  _textbooks.add(WebTextbookCard(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: title,
                    url: url,
                    grade: gradeVal,
                    emoji: emojiCtrl.text.trim().isEmpty ? '📖' : emojiCtrl.text.trim(),
                  ));
                } else {
                  editCard.title = title;
                  editCard.url = url;
                  editCard.grade = gradeVal;
                  editCard.emoji = emojiCtrl.text.trim().isEmpty ? '📖' : emojiCtrl.text.trim();
                }
              });
              _saveTextbooks();
              Navigator.pop(ctx);
            },
            child: const Text('저장', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBbPackage(WebTextbookCard card, {bool toCloud = true, bool toUsb = false}) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final bbDir = Directory('${appDir.path}/BstSave/BOARDBOOK');
      if (!bbDir.existsSync()) bbDir.createSync(recursive: true);

      final sanitizedTitle = card.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '$sanitizedTitle.bb';
      final file = File('${bbDir.path}/$fileName');
      final jsonContent = jsonEncode({
        'id': card.id,
        'title': card.title,
        'url': card.url,
        'grade': card.grade,
        'createdAt': DateTime.now().toIso8601String(),
        'type': 'BOARDBOOK',
      });
      await file.writeAsString(jsonContent, flush: true);

      if (toCloud && CloudDriveService.instance.isLoggedIn) {
        await CloudDriveService.instance.uploadTextFileToDrive(fileName, jsonContent);
      }

      if (toUsb) {
        try {
          final usbDir = Directory('D:\\BoardBook');
          if (!usbDir.existsSync()) usbDir.createSync(recursive: true);
          final usbFile = File('${usbDir.path}/$fileName');
          await usbFile.writeAsString(jsonContent, flush: true);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🎉 [${card.title}.bb] 교과서 패키지가 저장 및 업로드되었습니다!')),
        );
      }
    } catch (e) {
      debugPrint('[BoardBookEditor] .bb export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 저장 중 오류 발생: $e')),
        );
      }
    }
  }

  void _showTextbookSaveOptions(WebTextbookCard card) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('💾 ${card.title} (.bb) 저장 위치 선택', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('기본적으로 AppData에 자동 저장되며, Cloud나 USB로 패키지를 업로드/내보내기할 수 있습니다.', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF2EC4B6)),
              title: const Text('☁️ Bst-cloud 로 .bb 패키지 업로드', style: TextStyle(color: Colors.white)),
              subtitle: const Text('구글 드라이브 클라우드에 복사본 저장 및 연동', style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _exportBbPackage(card, toCloud: true, toUsb: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.usb_rounded, color: Color(0xFF74F8E5)),
              title: const Text('💾 USB / 전자칠판으로 복사본 내보내기', style: TextStyle(color: Colors.white)),
              subtitle: const Text('전자칠판 연결용 USB로 .bb 교과서 패키지 복사', style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _exportBbPackage(card, toCloud: false, toUsb: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openTextbook(WebTextbookCard card) {
    if (widget.onOpenUrl != null) {
      widget.onOpenUrl!(card.url, card.title);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WebsiteBoardView(
            initialUrl: card.url,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final filtered = _selectedGradeFilter == '전체'
        ? _textbooks
        : _textbooks.where((t) => t.grade == _selectedGradeFilter || t.grade == '공통').toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161A),
        elevation: 0,
        title: Text(
          '📚 BoardBook 교과서 런처 & 판서 스마트 뷰어',
          style: GoogleFonts.notoSansKr(
            color: const Color(0xFF2EC4B6),
            fontWeight: FontWeight.bold,
            fontSize: 20 * s,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF2EC4B6)),
            tooltip: '디지털 교과서 추가',
            onPressed: () => _showAddTextbookDialog(),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(20 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [


            // BoardBook Utility Viewers Grid Section
            SizedBox(height: 16 * s),

            // Grid of Textbook Cards
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        '등록된 교과서가 없습니다.\n우측 상단 + 버튼을 눌러 추가해 보세요!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 16 * s),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
                        childAspectRatio: 1.35,
                        crossAxisSpacing: 16 * s,
                        mainAxisSpacing: 16 * s,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, idx) {
                        final card = filtered[idx];
                        return InkWell(
                          onTap: () => _openTextbook(card),
                          onLongPress: () => _showTextbookSaveOptions(card),
                          borderRadius: BorderRadius.circular(16 * s),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF16161A),
                              borderRadius: BorderRadius.circular(16 * s),
                              border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.3), width: 1.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                              ],
                            ),
                            padding: EdgeInsets.all(16 * s),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(card.emoji, style: TextStyle(fontSize: 32 * s)),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2EC4B6).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8 * s),
                                      ),
                                      child: Text(
                                        card.grade,
                                        style: TextStyle(color: const Color(0xFF2EC4B6), fontSize: 12 * s),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  card.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.notoSansKr(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16 * s,
                                  ),
                                ),
                                SizedBox(height: 4 * s),
                                Text(
                                  card.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white38, fontSize: 12 * s),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUtilityChip(String label, Color color) {
    return ActionChip(
      backgroundColor: const Color(0xFF16161A),
      side: BorderSide(color: color.withOpacity(0.5)),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📂 BoardBook 유틸리티 [$label] 실행!')),
        );
      },
    );
  }
}
