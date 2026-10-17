import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../services/tbp/tbp_download_interceptor.dart';
import '../../services/tbp/tbp_storage_service.dart';

/// 핫스팟 오버레이 핀 렌더링 & 우클릭 모달 에디터 위젯
class TbpHotspotOverlay extends StatelessWidget {
  final List<Map<String, dynamic>> hotspots;
  final String tbpFolderPath;
  final String currentDhash;
  final double scaleFactor;
  final bool isTeacherApp;
  final Function(List<Map<String, dynamic>> updatedHotspots)? onHotspotsUpdated;
  final void Function(Map<String, dynamic> spot)? onTriggerHotspot;

  const TbpHotspotOverlay({
    super.key,
    required this.hotspots,
    required this.tbpFolderPath,
    required this.currentDhash,
    required this.scaleFactor,
    this.isTeacherApp = true,
    this.onHotspotsUpdated,
    this.onTriggerHotspot,
  });

  static Map<String, dynamic> _typeMeta(String type) {
    switch (type) {
      case 'url':
        return {'label': '🌐 외부 웹사이트 URL', 'emoji': '🔗', 'color': 0xFF0084FF, 'icon': Icons.language_rounded, 'hint': 'https://...'};
      case 'pdf':
      case 'doc':
        return {'label': '📄 문서 자료 (PDF/HWP/PPT)', 'emoji': '📄', 'color': 0xFFFF595E, 'icon': Icons.description_rounded, 'hint': '문서 파일 경로 또는 우측 폴더 아이콘 클릭'};
      case 'hwp':
        return {'label': '📝 HWP 한글 문서', 'emoji': '📝', 'color': 0xFF38BDF8, 'icon': Icons.article_rounded, 'hint': 'HWP 파일 경로 또는 우측 폴더 아이콘 클릭'};
      case 'ppt':
        return {'label': '📊 PPT 발표 자료', 'emoji': '📊', 'color': 0xFFFF9F1C, 'icon': Icons.slideshow_rounded, 'hint': 'PPT 파일 경로 또는 우측 폴더 아이콘 클릭'};
      case 'vid':
      case 'video':
        return {'label': '🎬 동영상 (MP4 / YouTube)', 'emoji': '🎬', 'color': 0xFFFF007F, 'icon': Icons.play_circle_fill_rounded, 'hint': '동영상 파일 경로 또는 YouTube 링크'};
      case 'image':
        return {'label': '🖼️ 이미지 팝업 (확대 보기)', 'emoji': '🖼️', 'color': 0xFF9B5DE5, 'icon': Icons.image_rounded, 'hint': '이미지 파일 경로 또는 이미지 URL'};
      case 'memo':
        return {'label': '📌 텍스트 메모 / 판서 팁', 'emoji': '📌', 'color': 0xFFFEE440, 'icon': Icons.sticky_note_2_rounded, 'hint': '클릭 시 표시할 수업 핵심 질문/메모 입력'};
      case 'timer':
        return {'label': '⏱️ 활동 타이머 (초 단위)', 'emoji': '⏱️', 'color': 0xFF00F5D4, 'icon': Icons.timer_rounded, 'hint': '타이머 시간(초) 입력 — 예: 180 (3분)'};
      case 'audio':
        return {'label': '🔊 오디오 / 듣기 음원', 'emoji': '🔊', 'color': 0xFFFF9F1C, 'icon': Icons.volume_up_rounded, 'hint': '오디오 파일 경로 또는 음원 URL'};
      case 'page':
        return {'label': '📖 교과서 페이지 이동', 'emoji': '📖', 'color': 0xFF2EC4B6, 'icon': Icons.menu_book_rounded, 'hint': '이동할 페이지 번호 또는 URL'};
      default:
        return {'label': '🔗 웹 링크', 'emoji': '🔗', 'color': 0xFF2EC4B6, 'icon': Icons.link_rounded, 'hint': 'https://...'};
    }
  }

  /// 우클릭 또는 상단 버튼으로 새 핫스팟 핀 추가 / 기존 핫스팟 수정 모달
  static Future<void> showAddHotspotModal(
    BuildContext context,
    double rx,
    double ry,
    String tbpFolderPath,
    String currentDhash,
    List<Map<String, dynamic>> hotspots,
    Function(List<Map<String, dynamic>> updatedHotspots)? onHotspotsUpdated, {
    Map<String, dynamic>? existingSpot,
  }) async {
    final isEdit = existingSpot != null;
    final titleCtrl = TextEditingController(
      text: (existingSpot?['title'] ?? existingSpot?['name'] ?? '').toString(),
    );
    final valCtrl = TextEditingController(
      text: (existingSpot?['value'] ?? '').toString(),
    );
    String type = (existingSpot?['type'] ?? 'url').toString();
    if (type == 'vid') type = 'video';

    const supportedTypes = [
      'url',
      'doc',
      'pdf',
      'hwp',
      'ppt',
      'video',
      'image',
      'memo',
      'timer',
      'audio',
      'page',
    ];
    if (!supportedTypes.contains(type)) {
      type = 'url';
    }

    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final meta = _typeMeta(type);
          final needsFilePicker = type == 'doc' ||
              type == 'pdf' ||
              type == 'hwp' ||
              type == 'ppt' ||
              type == 'video' ||
              type == 'image' ||
              type == 'audio';

          return AlertDialog(
            backgroundColor: const Color(0xFF16161A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Color(meta['color'] as int).withOpacity(0.5), width: 1.5),
            ),
            title: Row(
              children: [
                Text(meta['emoji'] as String, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isEdit ? '핫스팟 핀 편집' : '✨ 우클릭 핫스팟 핀 추가',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'X ${(rx * 100).toStringAsFixed(0)}% · Y ${(ry * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        labelText: '핫스팟 표시 제목 (교과서 화면 위 뱃지 이름)',
                        hintText: '예: 탐구 영상 보기 / 활동지 PDF / 3분 모둠 토의',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12.5),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF242629),
                      value: type,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        labelText: '핫스팟 동작 유형',
                        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12.5),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'url', child: Text('🌐 외부 웹사이트 URL')),
                        DropdownMenuItem(value: 'doc', child: Text('📄 통합 문서 (PDF/HWP/PPT)')),
                        DropdownMenuItem(value: 'pdf', child: Text('📕 PDF 문서 자료')),
                        DropdownMenuItem(value: 'hwp', child: Text('📝 HWP 한글 문서')),
                        DropdownMenuItem(value: 'ppt', child: Text('📊 PPT 발표 자료')),
                        DropdownMenuItem(value: 'video', child: Text('🎬 동영상 (MP4 / YouTube)')),
                        DropdownMenuItem(value: 'image', child: Text('🖼️ 이미지 팝업 (확대 보기)')),
                        DropdownMenuItem(value: 'memo', child: Text('📌 텍스트 메모 / 판서 팁')),
                        DropdownMenuItem(value: 'timer', child: Text('⏱️ 활동 타이머 (초 단위)')),
                        DropdownMenuItem(value: 'audio', child: Text('🔊 오디오 / 듣기 음원')),
                        DropdownMenuItem(value: 'page', child: Text('📖 교과서 페이지 이동')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() {
                            type = v;
                            if (v == 'timer' && valCtrl.text.trim().isEmpty) {
                              valCtrl.text = '180';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: valCtrl,
                            maxLines: type == 'memo' ? 3 : 1,
                            style: const TextStyle(color: Colors.white, fontSize: 13.5),
                            decoration: InputDecoration(
                              labelText: meta['hint'] as String,
                              labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.04),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        if (needsFilePicker) ...[
                          const SizedBox(width: 8),
                          Tooltip(
                            message: '내 PC에서 파일 선택',
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2EC4B6).withOpacity(0.18),
                                foregroundColor: const Color(0xFF2EC4B6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.folder_open_rounded, size: 18),
                              label: const Text('파일 선택', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final pick = await FilePicker.pickFiles();
                                if (pick != null && pick.files.isNotEmpty) {
                                  final single = pick.files.single;
                                  final path = single.path ?? single.name;
                                  valCtrl.text = path;
                                  if (titleCtrl.text.trim().isEmpty) {
                                    titleCtrl.text = p.basenameWithoutExtension(path);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (isEdit)
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, {'__delete__': true}),
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4565), size: 18),
                  label: const Text('삭제', style: TextStyle(color: Color(0xFFEF4565), fontWeight: FontWeight.bold)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EC4B6),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  var rawVal = valCtrl.text.trim();
                  if (rawVal.isEmpty && type == 'timer') {
                    rawVal = '180';
                  }
                  if (rawVal.isEmpty) return;
                  if (type == 'url' &&
                      !rawVal.startsWith('http://') &&
                      !rawVal.startsWith('https://')) {
                    rawVal = 'https://$rawVal';
                  }
                  final chosenMeta = _typeMeta(type);
                  final spotTitle = titleCtrl.text.trim().isEmpty
                      ? (chosenMeta['label'] as String).replaceAll(RegExp(r'^[^\s]+\s'), '')
                      : titleCtrl.text.trim();
                  Navigator.pop(ctx, {
                    'id': existingSpot?['id'] ?? 'H_${DateTime.now().millisecondsSinceEpoch}',
                    'name': spotTitle,
                    'title': spotTitle,
                    'type': type,
                    'value': rawVal,
                    'icon': chosenMeta['emoji'],
                    'color': chosenMeta['color'],
                    'x': rx,
                    'y': ry,
                  });
                },
                icon: Icon(isEdit ? Icons.check_rounded : Icons.add_location_alt_rounded, size: 18),
                label: Text(
                  isEdit ? '저장' : '핫스팟 꽂기',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (res != null) {
      final updated = List<Map<String, dynamic>>.from(hotspots);
      if (res['__delete__'] == true && existingSpot != null) {
        updated.removeWhere((h) => h['id'] == existingSpot['id']);
      } else if (isEdit) {
        final idx = updated.indexWhere((h) => h['id'] == existingSpot['id']);
        if (idx >= 0) {
          updated[idx] = res;
        } else {
          updated.add(res);
        }
      } else {
        updated.add(res);
      }
      await TbpStorageService.instance.saveHotspots(
        tbpFolderPath,
        currentDhash,
        updated,
      );
      if (onHotspotsUpdated != null) onHotspotsUpdated(updated);
    }
  }

  void _defaultExecuteSpot(BuildContext context, Map<String, dynamic> hotspot) async {
    if (onTriggerHotspot != null) {
      onTriggerHotspot!(hotspot);
      return;
    }
    final val = (hotspot['value'] as String? ?? '').trim();
    if (val.isEmpty) return;
    if (val.startsWith('http://') || val.startsWith('https://')) {
      await launchUrl(
        Uri.parse(val),
        mode: LaunchMode.externalApplication,
      );
    } else {
      TbpDownloadInterceptor.instance.openSupportedViewer(
        context: context,
        filePath: val,
        scaleFactor: scaleFactor,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = scaleFactor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 0 ? constraints.maxWidth : MediaQuery.of(context).size.width;
        final height = constraints.maxHeight > 0 ? constraints.maxHeight : MediaQuery.of(context).size.height;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: hotspots.map((hotspot) {
                final rx = ((hotspot['x'] as num?)?.toDouble() ?? 0.5).clamp(0.02, 0.98);
                final ry = ((hotspot['y'] as num?)?.toDouble() ?? 0.5).clamp(0.02, 0.98);
                final left = rx * width;
                final top = ry * height;
                final type = (hotspot['type'] ?? 'url').toString();
                final meta = _typeMeta(type);
                final colorVal = (hotspot['color'] as int?) ?? (meta['color'] as int);
                final spotColor = Color(colorVal);
                final label = (hotspot['title'] ?? hotspot['name'] ?? '핫스팟').toString();
                final emoji = (hotspot['icon'] ?? meta['emoji'] ?? '🔗').toString();

                return Positioned(
                  left: (left - 22 * s).clamp(4.0, (width - 160 * s).clamp(4.0, double.infinity)),
                  top: (top - 20 * s).clamp(4.0, (height - 48 * s).clamp(4.0, double.infinity)),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {},
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _defaultExecuteSpot(context, hotspot),
                        onSecondaryTap: () {
                          showAddHotspotModal(
                            context,
                            rx,
                            ry,
                            tbpFolderPath,
                            currentDhash,
                            hotspots,
                            onHotspotsUpdated,
                            existingSpot: hotspot,
                          );
                        },
                        onLongPress: () {
                          showAddHotspotModal(
                            context,
                            rx,
                            ry,
                            tbpFolderPath,
                            currentDhash,
                            hotspots,
                            onHotspotsUpdated,
                            existingSpot: hotspot,
                          );
                        },
                        child: Tooltip(
                          message: '$label (클릭: 실행 / 우클릭·길게누르기: 편집·삭제)',
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16161A).withOpacity(0.92),
                              borderRadius: BorderRadius.circular(22 * s),
                              border: Border.all(color: spotColor, width: 2 * s),
                              boxShadow: [
                                BoxShadow(
                                  color: spotColor.withOpacity(0.45),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 24 * s,
                                  height: 24 * s,
                                  decoration: BoxDecoration(
                                    color: spotColor.withOpacity(0.22),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(emoji, style: TextStyle(fontSize: 13 * s)),
                                ),
                                SizedBox(width: 6 * s),
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: 130 * s),
                                  child: Text(
                                    label,
                                    style: GoogleFonts.notoSansKr(
                                      color: Colors.white,
                                      fontSize: 12 * s,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
    );
  }
}
