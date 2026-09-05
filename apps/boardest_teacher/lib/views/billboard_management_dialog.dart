import 'dart:convert';
import 'package:universal_io/io.dart' as universal_io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../config/app_config.dart';

class BillboardItem {
  final String title;
  final String imageUrl;
  final String startDate;
  final String endDate;
  final int priority;
  final String teacherName;
  final String createdAt;

  BillboardItem({
    required this.title,
    required this.imageUrl,
    required this.startDate,
    required this.endDate,
    this.priority = 1,
    this.teacherName = '',
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> toFirestoreMap() {
    return {
      'mapValue': {
        'fields': {
          'title': {'stringValue': title},
          'imageUrl': {'stringValue': imageUrl},
          'startDate': {'stringValue': startDate},
          'endDate': {'stringValue': endDate},
          'priority': {'integerValue': priority.toString()},
          'teacherName': {'stringValue': teacherName},
          'createdAt': {'stringValue': createdAt},
        }
      }
    };
  }

  factory BillboardItem.fromFirestoreMap(Map<String, dynamic> map) {
    final fields = (map['mapValue']?['fields'] as Map<String, dynamic>?) ?? map;
    return BillboardItem(
      title: fields['title']?['stringValue']?.toString() ?? '',
      imageUrl: fields['imageUrl']?['stringValue']?.toString() ?? '',
      startDate: fields['startDate']?['stringValue']?.toString() ?? '',
      endDate: fields['endDate']?['stringValue']?.toString() ?? '',
      priority: int.tryParse(fields['priority']?['integerValue']?.toString() ?? '1') ?? 1,
      teacherName: fields['teacherName']?['stringValue']?.toString() ?? '',
      createdAt: fields['createdAt']?['stringValue']?.toString() ?? '',
    );
  }
}

class BillboardManagementDialog extends StatefulWidget {
  final double scaleFactor;
  final String schoolId;
  final String teacherName;

  const BillboardManagementDialog({
    super.key,
    this.scaleFactor = 1.0,
    required this.schoolId,
    required this.teacherName,
  });

  @override
  State<BillboardManagementDialog> createState() => _BillboardManagementDialogState();
}

class _BillboardManagementDialogState extends State<BillboardManagementDialog> {
  bool _isLoading = true;
  bool _isSaving = false;
  String _effectiveSchoolId = 'ydm';
  List<BillboardItem> _announcements = [];

  // New announcement form fields
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  String _selectedImageDataUrl = '';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 14));
  final int _priority = 1;
  bool _isUrlMode = false;

  @override
  void initState() {
    super.initState();
    _resolveSchoolId();
    _fetchAnnouncements();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _resolveSchoolId() {
    String id = widget.schoolId.trim().toLowerCase();
    if (id.isEmpty || id == 'my' || id.contains('양동') || id == '44134') {
      id = 'ydm';
    }
    _effectiveSchoolId = id;
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchAnnouncements() async {
    setState(() => _isLoading = true);
    try {
      var url = '${AppConfig.firestoreBase}/control_configs/$_effectiveSchoolId?key=${AppConfig.firebaseApiKey}';
      var res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));

      if (res.statusCode != 200 && _effectiveSchoolId != 'ydm') {
        _effectiveSchoolId = 'ydm';
        url = '${AppConfig.firestoreBase}/control_configs/$_effectiveSchoolId?key=${AppConfig.firebaseApiKey}';
        res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fields = data['fields'] as Map<String, dynamic>?;
        final announcementsField = fields?['announcements'];
        final values = announcementsField?['arrayValue']?['values'] as List<dynamic>? ?? [];

        final items = values
            .map((v) => BillboardItem.fromFirestoreMap(v as Map<String, dynamic>))
            .where((item) => item.imageUrl.isNotEmpty)
            .toList();

        if (mounted) {
          setState(() {
            _announcements = items;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('[BillboardDialog] Fetch error: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLocalImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;

      if (bytes == null && file.path != null) {
        // Desktop native fallback
        final ioFile = universal_io.File(file.path!);
        if (await ioFile.exists()) {
          bytes = await ioFile.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) return;

      // Compress and resize image to fit comfortably in Firestore
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('지원되지 않는 이미지 형식입니다.'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      img.Image processed = decoded;
      // If width > 1200 or height > 800, scale down proportionally
      if (decoded.width > 1200 || decoded.height > 800) {
        processed = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 1200 : null,
          height: decoded.height > decoded.width ? 800 : null,
        );
      }

      // Encode to JPEG at 78% quality
      final jpgBytes = img.encodeJpg(processed, quality: 78);
      final base64String = base64Encode(jpgBytes);
      final dataUri = 'data:image/jpeg;base64,$base64String';

      setState(() {
        _selectedImageDataUrl = dataUri;
        _isUrlMode = false;
        if (_titleController.text.trim().isEmpty) {
          final cleanName = file.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
          _titleController.text = cleanName;
        }
      });
    } catch (e) {
      debugPrint('[BillboardDialog] Pick image error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 불러오기 실패: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _saveAnnouncementsToFirestore(List<BillboardItem> items) async {
    setState(() => _isSaving = true);
    try {
      final firestoreValues = items.map((item) => item.toFirestoreMap()).toList();
      final body = jsonEncode({
        'fields': {
          'announcements': {
            'arrayValue': {
              'values': firestoreValues,
            }
          }
        }
      });

      final url = '${AppConfig.firestoreBase}/control_configs/$_effectiveSchoolId?updateMask.fieldPaths=announcements&key=${AppConfig.firebaseApiKey}';
      final res = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        setState(() {
          _announcements = items;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 전자칠판 광고판에 공지가 성공적으로 반영되었습니다!'),
              backgroundColor: Color(0xFF2EC4B6),
            ),
          );
        }
        return;
      } else {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[BillboardDialog] Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('광고판 저장 실패: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleAddNewAnnouncement() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공지 제목을 입력해주세요.'), backgroundColor: Colors.amber),
      );
      return;
    }

    String finalImageUrl = '';
    if (_isUrlMode) {
      finalImageUrl = _urlController.text.trim();
    } else {
      finalImageUrl = _selectedImageDataUrl.trim();
    }

    if (finalImageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('광고판에 표시할 사진/이미지를 선택하거나 URL을 입력해주세요.'), backgroundColor: Colors.amber),
      );
      return;
    }

    final newItem = BillboardItem(
      title: title,
      imageUrl: finalImageUrl,
      startDate: _formatDate(_startDate),
      endDate: _formatDate(_endDate),
      priority: _priority,
      teacherName: widget.teacherName.isNotEmpty ? widget.teacherName : '교사',
    );

    final updated = List<BillboardItem>.from(_announcements)..insert(0, newItem);
    await _saveAnnouncementsToFirestore(updated);

    // Reset form
    setState(() {
      _titleController.clear();
      _urlController.clear();
      _selectedImageDataUrl = '';
    });
  }

  Future<void> _handleDeleteItem(int index) async {
    final item = _announcements[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: const Text('공지 삭제', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('\'${item.title}\' 공지를 광고판에서 삭제하시겠습니까?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final updated = List<BillboardItem>.from(_announcements)..removeAt(index);
      await _saveAnnouncementsToFirestore(updated);
    }
  }

  Widget _buildImagePreviewWidget(String urlOrData) {
    if (urlOrData.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_rounded, color: Colors.white38, size: 32),
              SizedBox(height: 6),
              Text('사진을 업로드하거나 URL을 입력하세요', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    if (urlOrData.startsWith('data:image')) {
      try {
        final comma = urlOrData.indexOf(',');
        final b64 = comma != -1 ? urlOrData.substring(comma + 1) : urlOrData;
        final bytes = base64Decode(b64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            bytes,
            height: 140,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        urlOrData,
        height: 140,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 140,
          color: Colors.redAccent.withOpacity(0.1),
          child: const Center(
            child: Text('⚠️ 이미지 미리보기를 불러올 수 없습니다.', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final primaryColor = const Color(0xFF00F5D4);

    return Dialog(
      backgroundColor: const Color(0xFF101015),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: primaryColor.withOpacity(0.4), width: 1.5),
      ),
      child: Container(
        width: 780 * s,
        height: 660 * s,
        padding: EdgeInsets.all(20 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.campaign_rounded, color: primaryColor, size: 22 * s),
                ),
                SizedBox(width: 12 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '전자칠판 광고판 / 교내 공지 관리',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 17 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '교실 전자칠판 대시보드 우측 상단 롤링 광고판에 즉시 실시간 노출됩니다 (학교 ID: $_effectiveSchoolId)',
                        style: TextStyle(color: Colors.white54, fontSize: 11 * s),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _fetchAnnouncements,
                  tooltip: '새로고침',
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white60),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '닫기',
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),

            // Content Area (Split: Left Form, Right List)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left: Add New Announcement
                  Expanded(
                    flex: 46,
                    child: Container(
                      padding: EdgeInsets.all(14 * s),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.025),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF2EC4B6), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  '새 광고 / 공지 등록',
                                  style: GoogleFonts.notoSansKr(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13 * s,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12 * s),

                            // Title input
                            TextField(
                              controller: _titleController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: '공지 제목',
                                labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                                hintText: '예: 학교 축제 안내 / 학부모 총회',
                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.04),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor)),
                              ),
                            ),
                            SizedBox(height: 10 * s),

                            // Image Selection Mode Tab
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => setState(() => _isUrlMode = false),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      decoration: BoxDecoration(
                                        color: !_isUrlMode ? primaryColor.withOpacity(0.18) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: !_isUrlMode ? primaryColor : Colors.white10),
                                      ),
                                      child: Center(
                                        child: Text('📁 사진 파일 선택', style: TextStyle(color: !_isUrlMode ? primaryColor : Colors.white60, fontSize: 11 * s, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => setState(() => _isUrlMode = true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _isUrlMode ? primaryColor.withOpacity(0.18) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: _isUrlMode ? primaryColor : Colors.white10),
                                      ),
                                      child: Center(
                                        child: Text('🔗 이미지 URL 입력', style: TextStyle(color: _isUrlMode ? primaryColor : Colors.white60, fontSize: 11 * s, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8 * s),

                            // File Pick or URL Input
                            if (!_isUrlMode) ...[
                              ElevatedButton.icon(
                                onPressed: _pickLocalImage,
                                icon: const Icon(Icons.photo_library_rounded, size: 16, color: Colors.black),
                                label: const Text('내 PC에서 사진 선택', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  minimumSize: const Size.fromHeight(36),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ] else ...[
                              TextField(
                                controller: _urlController,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: '이미지 직접 링크 (https://...)',
                                  labelStyle: const TextStyle(color: Colors.white60, fontSize: 11),
                                  hintText: 'https://example.com/banner.png',
                                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.04),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor)),
                                ),
                              ),
                            ],
                            SizedBox(height: 10 * s),

                            // Image Preview
                            _buildImagePreviewWidget(_isUrlMode ? _urlController.text.trim() : _selectedImageDataUrl),
                            SizedBox(height: 10 * s),

                            // Date Range Picker
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _startDate,
                                        firstDate: DateTime(2025),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) setState(() => _startDate = picked);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('시작일', style: TextStyle(color: Colors.white38, fontSize: 9)),
                                          Text(_formatDate(_startDate), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _endDate,
                                        firstDate: DateTime(2025),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) setState(() => _endDate = picked);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('종료일', style: TextStyle(color: Colors.white38, fontSize: 9)),
                                          Text(_formatDate(_endDate), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12 * s),

                            // Submit Button
                            ElevatedButton.icon(
                              onPressed: _isSaving ? null : _handleAddNewAnnouncement,
                              icon: _isSaving
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : const Icon(Icons.cloud_upload_rounded, color: Colors.black, size: 18),
                              label: Text(
                                _isSaving ? '광고판 반영 중...' : '광고판에 바로 게시하기',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2EC4B6),
                                minimumSize: const Size.fromHeight(40),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 14 * s),

                  // Right: Currently Registered Announcements List
                  Expanded(
                    flex: 54,
                    child: Container(
                      padding: EdgeInsets.all(14 * s),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.025),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.view_carousel_rounded, color: Color(0xFF00F5D4), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                '현재 등록된 광고판 목록 (${_announcements.length}개)',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13 * s,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
                                : _announcements.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.inbox_rounded, color: Colors.white24, size: 36),
                                            const SizedBox(height: 8),
                                            Text('등록된 공지가 없습니다.', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12)),
                                            const SizedBox(height: 4),
                                            const Text('좌측 양식에서 사진을 올려 전자칠판에 띄워보세요!', style: TextStyle(color: Colors.white30, fontSize: 11)),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: _announcements.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                                        itemBuilder: (context, idx) {
                                          final item = _announcements[idx];
                                          return Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.03),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.white.withOpacity(0.06)),
                                            ),
                                            child: Row(
                                              children: [
                                                // Thumbnail
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: SizedBox(
                                                    width: 64,
                                                    height: 44,
                                                    child: item.imageUrl.startsWith('data:image')
                                                        ? Builder(
                                                            builder: (_) {
                                                              try {
                                                                final comma = item.imageUrl.indexOf(',');
                                                                final b64 = comma != -1 ? item.imageUrl.substring(comma + 1) : item.imageUrl;
                                                                return Image.memory(base64Decode(b64), fit: BoxFit.cover);
                                                              } catch (_) {
                                                                return const Icon(Icons.image_not_supported_rounded, color: Colors.white30);
                                                              }
                                                            },
                                                          )
                                                        : Image.network(
                                                            item.imageUrl,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white30),
                                                          ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),

                                                // Info
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        item.title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '기간: ${item.startDate.isNotEmpty ? item.startDate : "-"} ~ ${item.endDate.isNotEmpty ? item.endDate : "-"}',
                                                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                                                      ),
                                                      Text(
                                                        '작성자: ${item.teacherName.isNotEmpty ? item.teacherName : "선생님"}',
                                                        style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 9.5),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // Delete button
                                                IconButton(
                                                  onPressed: _isSaving ? null : () => _handleDeleteItem(idx),
                                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                  tooltip: '삭제',
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
