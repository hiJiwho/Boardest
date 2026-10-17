import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../models/board_tools.dart';
import '../../services/tbp/tbp_download_interceptor.dart';
import '../../services/tbp/tbp_storage_service.dart';

/// 핫스팟 종류 (8종)
enum HotspotType {
  url, // 🌐 웹 링크
  doc, // 📄 문서 (PDF/HWP/PPT)
  video, // 🎬 동영상
  image, // 🖼️ 이미지
  memo, // 📝 메모
  timer, // ⏱️ 타이머
  audio, // 🔊 오디오
}

extension HotspotTypeExt on HotspotType {
  String get emoji {
    switch (this) {
      case HotspotType.url:
        return '🌐';
      case HotspotType.doc:
        return '📄';
      case HotspotType.video:
        return '🎬';
      case HotspotType.image:
        return '🖼️';
      case HotspotType.memo:
        return '📝';
      case HotspotType.timer:
        return '⏱️';
      case HotspotType.audio:
        return '🔊';
    }
  }

  String get label {
    switch (this) {
      case HotspotType.url:
        return '웹 링크';
      case HotspotType.doc:
        return '문서 (PDF/HWP/PPT)';
      case HotspotType.video:
        return '동영상';
      case HotspotType.image:
        return '이미지 팝업';
      case HotspotType.memo:
        return '메모';
      case HotspotType.timer:
        return '타이머';
      case HotspotType.audio:
        return '오디오';
    }
  }

  String get hint {
    switch (this) {
      case HotspotType.url:
        return 'https://...';
      case HotspotType.doc:
        return 'PDF/HWP/PPT 파일 경로 또는 우측 파일 선택';
      case HotspotType.video:
        return 'MP4 파일 경로 또는 YouTube 링크';
      case HotspotType.image:
        return '이미지 파일 경로 또는 URL';
      case HotspotType.memo:
        return '클릭 시 표시할 수업 핵심 질문/메모 입력';
      case HotspotType.timer:
        return '타이머 시간(초) — 예: 180 (3분)';
      case HotspotType.audio:
        return '오디오 파일 경로 또는 음원 URL';
    }
  }

  Color get color {
    switch (this) {
      case HotspotType.url:
        return const Color(0xFF2EC4B6);
      case HotspotType.doc:
        return const Color(0xFF7F5AF0);
      case HotspotType.video:
        return const Color(0xFFFF6B6B);
      case HotspotType.image:
        return const Color(0xFF06D6A0);
      case HotspotType.memo:
        return const Color(0xFFFFD166);
      case HotspotType.timer:
        return const Color(0xFFFF8906);
      case HotspotType.audio:
        return const Color(0xFF118AB2);
    }
  }

  static HotspotType fromString(String? s) {
    switch (s) {
      case 'url':
        return HotspotType.url;
      case 'doc':
      case 'pdf':
      case 'hwp':
      case 'ppt':
        return HotspotType.doc;
      case 'video':
      case 'vid':
        return HotspotType.video;
      case 'image':
        return HotspotType.image;
      case 'memo':
        return HotspotType.memo;
      case 'timer':
        return HotspotType.timer;
      case 'audio':
        return HotspotType.audio;
      default:
        return HotspotType.url;
    }
  }
}

/// 핫스팟 오버레이 (8종 핫스팟 + 우클릭 생성/편집 + Pen/Touch/Smart 모드 대응)
class TbpHotspotOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> hotspots;
  final String tbpFolderPath;
  final String currentDhash;
  final double scaleFactor;
  final TbpInputMode inputMode;
  final bool longPressActive;
  final Function(List<Map<String, dynamic>> updatedHotspots)? onHotspotsUpdated;

  const TbpHotspotOverlay({
    super.key,
    required this.hotspots,
    required this.tbpFolderPath,
    required this.currentDhash,
    required this.scaleFactor,
    required this.inputMode,
    required this.longPressActive,
    this.onHotspotsUpdated,
  });

  /// 우클릭 또는 상단 버튼으로 핫스팟 핀 추가 / 편집 모달
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
    HotspotType selectedType = HotspotTypeExt.fromString(existingSpot?['type']?.toString());

    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final needsFilePicker = selectedType == HotspotType.doc ||
              selectedType == HotspotType.video ||
              selectedType == HotspotType.image ||
              selectedType == HotspotType.audio;

          return AlertDialog(
            backgroundColor: const Color(0xFF16161A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: selectedType.color.withValues(alpha: 0.55), width: 1.5),
            ),
            title: Row(
              children: [
                Text(selectedType.emoji, style: const TextStyle(fontSize: 20)),
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
                    color: Colors.white.withValues(alpha: 0.06),
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
                        labelText: '핫스팟 표시 제목',
                        hintText: '예: 탐구 영상 보기 / 활동지 PDF / 3분 모둠 토의',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12.5),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<HotspotType>(
                      dropdownColor: const Color(0xFF242629),
                      initialValue: selectedType,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        labelText: '핫스팟 동작 유형 (8종)',
                        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12.5),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: HotspotType.values
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text('${t.emoji} ${t.label}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() {
                            selectedType = v;
                            if (v == HotspotType.timer && valCtrl.text.trim().isEmpty) {
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
                            maxLines: selectedType == HotspotType.memo ? 3 : 1,
                            style: const TextStyle(color: Colors.white, fontSize: 13.5),
                            decoration: InputDecoration(
                              labelText: selectedType.hint,
                              labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        if (needsFilePicker) ...[
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedType.color.withValues(alpha: 0.18),
                              foregroundColor: selectedType.color,
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
                  if (rawVal.isEmpty && selectedType == HotspotType.timer) {
                    rawVal = '180';
                  }
                  if (rawVal.isEmpty) return;
                  if (selectedType == HotspotType.url &&
                      !rawVal.startsWith('http://') &&
                      !rawVal.startsWith('https://')) {
                    rawVal = 'https://$rawVal';
                  }
                  final spotTitle = titleCtrl.text.trim().isEmpty
                      ? selectedType.label
                      : titleCtrl.text.trim();
                  Navigator.pop(ctx, {
                    'id': existingSpot?['id'] ?? 'H_${DateTime.now().millisecondsSinceEpoch}',
                    'name': spotTitle,
                    'title': spotTitle,
                    'type': selectedType.name,
                    'value': rawVal,
                    'icon': selectedType.emoji,
                    'color': selectedType.color.toARGB32(),
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

  @override
  State<TbpHotspotOverlay> createState() => _TbpHotspotOverlayState();
}

class _TbpHotspotOverlayState extends State<TbpHotspotOverlay> {
  // 타이머 상태
  int? _timerSeconds;
  Timer? _activeTimer;
  int _remaining = 0;

  @override
  void dispose() {
    _activeTimer?.cancel();
    super.dispose();
  }

  bool _isHotspotInteractable(Map<String, dynamic> hotspot) {
    switch (widget.inputMode) {
      case TbpInputMode.pen:
        return false;
      case TbpInputMode.touch:
      case TbpInputMode.smart:
        return true;
    }
  }

  Future<void> _activateHotspot(
    BuildContext context,
    Map<String, dynamic> hotspot,
  ) async {
    final type = HotspotTypeExt.fromString(hotspot['type'] as String?);
    final value = (hotspot['value'] as String? ?? '').trim();

    switch (type) {
      case HotspotType.url:
        if (value.isNotEmpty) {
          final urlStr = (value.startsWith('http://') || value.startsWith('https://'))
              ? value
              : 'https://$value';
          await launchUrl(
            Uri.parse(urlStr),
            mode: LaunchMode.externalApplication,
          );
        }
        break;

      case HotspotType.doc:
      case HotspotType.video:
      case HotspotType.audio:
        if (value.startsWith('http://') || value.startsWith('https://')) {
          await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
        } else {
          TbpDownloadInterceptor.instance.openSupportedViewer(
            context: context,
            filePath: value,
            scaleFactor: widget.scaleFactor,
          );
        }
        break;

      case HotspotType.image:
        _showImagePopup(context, value);
        break;

      case HotspotType.memo:
        _showMemoPopup(context, (hotspot['title'] ?? hotspot['name'] ?? '메모').toString(), value);
        break;

      case HotspotType.timer:
        final secs = int.tryParse(value) ?? 60;
        _startTimer(context, secs);
        break;
    }
  }

  void _showImagePopup(BuildContext context, String filePath) {
    final isNetwork = filePath.startsWith('http://') || filePath.startsWith('https://');
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isNetwork
                  ? Image.network(filePath, fit: BoxFit.contain)
                  : (File(filePath).existsSync()
                      ? Image.file(File(filePath), fit: BoxFit.contain)
                      : const Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 80,
                        )),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemoPopup(BuildContext context, String title, String memoText) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Text('📝 ', style: TextStyle(fontSize: 20)),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          memoText,
          style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '닫기',
              style: GoogleFonts.notoSansKr(color: const Color(0xFF7F5AF0)),
            ),
          ),
        ],
      ),
    );
  }

  void _startTimer(BuildContext context, int seconds) {
    _activeTimer?.cancel();
    _remaining = seconds;

    _activeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 0) {
        t.cancel();
        if (mounted) setState(() {});
      } else {
        _remaining--;
        if (mounted) setState(() {});
      }
    });

    if (mounted) setState(() => _timerSeconds = seconds);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 0 ? constraints.maxWidth : MediaQuery.of(context).size.width;
        final height = constraints.maxHeight > 0 ? constraints.maxHeight : MediaQuery.of(context).size.height;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: (details) {
            final rx = (details.localPosition.dx / width).clamp(0.02, 0.98);
            final ry = (details.localPosition.dy / height).clamp(0.02, 0.98);
            TbpHotspotOverlay.showAddHotspotModal(
              context,
              rx,
              ry,
              widget.tbpFolderPath,
              widget.currentDhash,
              widget.hotspots,
              widget.onHotspotsUpdated,
            );
          },
          child: SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // ── 타이머 오버레이 (활성 시) ──────────────────
                if (_activeTimer != null && _timerSeconds != null)
                  Positioned(
                    bottom: 30 * s,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24 * s,
                          vertical: 12 * s,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(40 * s),
                          border: Border.all(
                            color: const Color(0xFFFF8906),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('⏱️ ', style: TextStyle(fontSize: 22 * s)),
                            Text(
                              '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}',
                              style: GoogleFonts.notoSansKr(
                                color: _remaining <= 10
                                    ? const Color(0xFFFF6B6B)
                                    : Colors.white,
                                fontSize: 28 * s,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 12 * s),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                              ),
                              onPressed: () {
                                _activeTimer?.cancel();
                                setState(() {
                                  _activeTimer = null;
                                  _timerSeconds = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── 핫스팟 핀들 ─────────────────────────────────
                ...widget.hotspots.map((hotspot) {
                  final rx = ((hotspot['x'] as num?)?.toDouble() ?? 0.5).clamp(0.02, 0.98);
                  final ry = ((hotspot['y'] as num?)?.toDouble() ?? 0.5).clamp(0.02, 0.98);
                  final left = rx * width;
                  final top = ry * height;
                  final type = HotspotTypeExt.fromString(
                    hotspot['type'] as String?,
                  );
                  final interactable = _isHotspotInteractable(hotspot);
                  final label = (hotspot['title'] ?? hotspot['name'] ?? type.label).toString();
                  final emoji = (hotspot['icon'] as String?) ?? type.emoji;

                  return Positioned(
                    left: (left - 22 * s).clamp(4.0, (width - 160 * s).clamp(4.0, double.infinity)),
                    top: (top - 20 * s).clamp(4.0, (height - 48 * s).clamp(4.0, double.infinity)),
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) {},
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: interactable
                              ? () => _activateHotspot(context, hotspot)
                              : null,
                          onSecondaryTap: () {
                            TbpHotspotOverlay.showAddHotspotModal(
                              context,
                              rx,
                              ry,
                              widget.tbpFolderPath,
                              widget.currentDhash,
                              widget.hotspots,
                              widget.onHotspotsUpdated,
                              existingSpot: hotspot,
                            );
                          },
                          onLongPress: () {
                            TbpHotspotOverlay.showAddHotspotModal(
                              context,
                              rx,
                              ry,
                              widget.tbpFolderPath,
                              widget.currentDhash,
                              widget.hotspots,
                              widget.onHotspotsUpdated,
                              existingSpot: hotspot,
                            );
                          },
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: interactable ? 1.0 : 0.5,
                            child: Tooltip(
                              message: '$label (클릭: 실행 / 우클릭·길게누르기: 편집·삭제)',
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF16161A).withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(22 * s),
                                  border: Border.all(
                                    color: interactable ? type.color : Colors.white38,
                                    width: 2 * s,
                                  ),
                                  boxShadow: interactable
                                      ? [
                                          BoxShadow(
                                            color: type.color.withValues(alpha: 0.45),
                                            blurRadius: 12,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : const [],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 24 * s,
                                      height: 24 * s,
                                      decoration: BoxDecoration(
                                        color: type.color.withValues(alpha: 0.22),
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
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
