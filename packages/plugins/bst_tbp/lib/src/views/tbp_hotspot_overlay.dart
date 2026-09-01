import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../services/tbp_download_interceptor.dart';
import '../services/tbp_storage_service.dart';

/// 핫스팟 오버레이 핀 렌더링 & 모달 에디터 위젯
class TbpHotspotOverlay extends StatelessWidget {
  final List<Map<String, dynamic>> hotspots;
  final String tbpFolderPath;
  final String currentDhash;
  final double scaleFactor;
  final bool isTeacherApp;
  final Function(List<Map<String, dynamic>> updatedHotspots)? onHotspotsUpdated;

  const TbpHotspotOverlay({
    super.key,
    required this.hotspots,
    required this.tbpFolderPath,
    required this.currentDhash,
    required this.scaleFactor,
    required this.isTeacherApp,
    this.onHotspotsUpdated,
  });

  static Future<void> showAddHotspotModal(
    BuildContext context,
    double rx,
    double ry,
    String tbpFolderPath,
    String currentDhash,
    List<Map<String, dynamic>> hotspots,
    Function(List<Map<String, dynamic>> updatedHotspots)? onHotspotsUpdated,
  ) async {
    final titleCtrl = TextEditingController();
    final valCtrl = TextEditingController();
    String type = 'url';
    String iconEmoji = '🔗';

    try {
      final res = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          title: Text(
            '✨ 핫스팟 핀 추가',
            style: GoogleFonts.notoSansKr(
              color: const Color(0xFF2EC4B6),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '핫스팟 이름',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF242629),
                value: type,
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'url', child: Text('🌐 외부 웹사이트 URL')),
                  DropdownMenuItem(value: 'pdf', child: Text('📄 PDF 문서')),
                  DropdownMenuItem(value: 'hwp', child: Text('📝 HWP 한글 문서')),
                  DropdownMenuItem(value: 'ppt', child: Text('📊 PPT 발표 자료')),
                  DropdownMenuItem(
                    value: 'vid',
                    child: Text('🎬 동영상 파일 (.mp4)'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setModalState(() {
                      type = v;
                      if (v == 'url')
                        iconEmoji = '🔗';
                      else if (v == 'pdf')
                        iconEmoji = '📄';
                      else if (v == 'hwp')
                        iconEmoji = '📝';
                      else if (v == 'ppt')
                        iconEmoji = '📊';
                      else if (v == 'vid')
                        iconEmoji = '🎬';
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: valCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: type == 'url' ? 'URL 주소' : '파일 경로',
                        labelStyle: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  if (type != 'url')
                    IconButton(
                      icon: const Icon(
                        Icons.folder_open_rounded,
                        color: Color(0xFF2EC4B6),
                      ),
                      onPressed: () async {
                        final pick = await FilePicker.pickFiles();
                        if (pick != null && pick.files.single.path != null) {
                          valCtrl.text = pick.files.single.path!;
                          if (titleCtrl.text.isEmpty) {
                            titleCtrl.text = p.basename(
                              pick.files.single.path!,
                            );
                          }
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2EC4B6),
              ),
              onPressed: () {
                if (valCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, {
                  'id': 'H_${DateTime.now().millisecondsSinceEpoch}',
                  'name': titleCtrl.text.trim().isEmpty
                      ? '핫스팟'
                      : titleCtrl.text.trim(),
                  'type': type,
                  'value': valCtrl.text.trim(),
                  'icon': iconEmoji,
                  'x': rx,
                  'y': ry,
                });
              },
              child: const Text(
                '추가',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

      if (res != null) {
        final updated = List<Map<String, dynamic>>.from(hotspots)..add(res);
        await TbpStorageService.instance.saveHotspots(
          tbpFolderPath,
          currentDhash,
          updated,
        );
        if (onHotspotsUpdated != null) onHotspotsUpdated(updated);
      }
    } finally {
      titleCtrl.dispose();
      valCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = scaleFactor;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            // Prevent pointer bleed through on hotspot pin click or right click
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: isTeacherApp
                ? (details) {
                    final rx = details.localPosition.dx / constraints.maxWidth;
                    final ry = details.localPosition.dy / constraints.maxHeight;
                    showAddHotspotModal(
                      context,
                      rx,
                      ry,
                      tbpFolderPath,
                      currentDhash,
                      hotspots,
                      onHotspotsUpdated,
                    );
                  }
                : null,
            child: Stack(
              children: hotspots.map((hotspot) {
                final rx = (hotspot['x'] as num).toDouble();
                final ry = (hotspot['y'] as num).toDouble();
                final left = rx * constraints.maxWidth;
                final top = ry * constraints.maxHeight;

                return Positioned(
                  left: left - 22 * s,
                  top: top - 22 * s,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown:
                        (
                          _,
                        ) {}, // Block click event passing to underlying webview element
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22 * s),
                          onTap: () async {
                            final val = (hotspot['value'] as String? ?? '')
                                .trim();
                            if (val.isEmpty) return;
                            if (val.startsWith('http://') ||
                                val.startsWith('https://')) {
                              await launchUrl(
                                Uri.parse(val),
                                mode: LaunchMode.externalApplication,
                              );
                            } else {
                              TbpDownloadInterceptor.instance
                                  .openSupportedViewer(
                                    context: context,
                                    filePath: val,
                                    scaleFactor: scaleFactor,
                                  );
                            }
                          },
                          child: Container(
                            width: 44 * s,
                            height: 44 * s,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2EC4B6).withOpacity(0.95),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                hotspot['icon'] ?? '🔗',
                                style: TextStyle(fontSize: 20 * s),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
