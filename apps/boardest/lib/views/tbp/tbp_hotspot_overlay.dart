import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/board_tools.dart';
import '../../services/tbp/tbp_download_interceptor.dart';

/// 핫스팟 종류 (8종)
enum HotspotType {
  url, // 🌐 웹 링크
  doc, // 📄 문서 (PDF/HWP/PPT)
  video, // 🎬 동영상
  image, // 🖼️ 이미지
  memo, // 📝 메모
  timer, // ⏱️ 타이머
  audio, // 🔊 오디오
  page, // 🔗 TBP 내 페이지 이동
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
      case HotspotType.page:
        return '🔗';
    }
  }

  String get label {
    switch (this) {
      case HotspotType.url:
        return '웹 링크';
      case HotspotType.doc:
        return '문서';
      case HotspotType.video:
        return '동영상';
      case HotspotType.image:
        return '이미지';
      case HotspotType.memo:
        return '메모';
      case HotspotType.timer:
        return '타이머';
      case HotspotType.audio:
        return '오디오';
      case HotspotType.page:
        return '페이지 이동';
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
      case HotspotType.page:
        return const Color(0xFFEF476F);
    }
  }

  static HotspotType fromString(String? s) {
    switch (s) {
      case 'url':
        return HotspotType.url;
      case 'doc':
        return HotspotType.doc;
      case 'video':
        return HotspotType.video;
      case 'image':
        return HotspotType.image;
      case 'memo':
        return HotspotType.memo;
      case 'timer':
        return HotspotType.timer;
      case 'audio':
        return HotspotType.audio;
      case 'page':
        return HotspotType.page;
      default:
        return HotspotType.url;
    }
  }
}

/// 핫스팟 오버레이 (8종 핫스팟 + Pen/Touch/Smart 모드 대응)
class TbpHotspotOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> hotspots;
  final String tbpFolderPath;
  final String currentDhash;
  final double scaleFactor;
  final TbpInputMode inputMode;
  final bool longPressActive;

  const TbpHotspotOverlay({
    super.key,
    required this.hotspots,
    required this.tbpFolderPath,
    required this.currentDhash,
    required this.scaleFactor,
    required this.inputMode,
    required this.longPressActive,
  });

  @override
  State<TbpHotspotOverlay> createState() => _TbpHotspotOverlayState();
}

class _TbpHotspotOverlayState extends State<TbpHotspotOverlay> {
  // 타이머 상태
  int? _timerSeconds;
  Timer? _activeTimer;
  int _remaining = 0;
  OverlayEntry? _timerOverlay;

  @override
  void dispose() {
    _activeTimer?.cancel();
    _timerOverlay?.remove();
    super.dispose();
  }

  bool _isHotspotInteractable(Map<String, dynamic> hotspot) {
    switch (widget.inputMode) {
      case TbpInputMode.pen:
        return false; // Pen 모드: 핫스팟도 완전히 비활성
      case TbpInputMode.touch:
        return true; // Touch 모드: 핫스팟 항상 활성
      case TbpInputMode.smart:
        return true; // Smart 모드: 꾹 누를 때만 핫스팟 활성 -> 항상 활성
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
        if (value.startsWith('http')) {
          await launchUrl(
            Uri.parse(value),
            mode: LaunchMode.externalApplication,
          );
        }
        break;

      case HotspotType.doc:
      case HotspotType.video:
      case HotspotType.audio:
        TbpDownloadInterceptor.instance.openSupportedViewer(
          context: context,
          filePath: value,
          scaleFactor: widget.scaleFactor,
        );
        break;

      case HotspotType.image:
        _showImagePopup(context, value);
        break;

      case HotspotType.memo:
        _showMemoPopup(context, value);
        break;

      case HotspotType.timer:
        final secs = int.tryParse(value) ?? 60;
        _startTimer(context, secs);
        break;

      case HotspotType.page:
        // 페이지 이동은 상위 위젯에 콜백으로 처리 (dHash 이동)
        debugPrint('[Hotspot] Page jump to dHash: $value');
        break;
    }
  }

  void _showImagePopup(BuildContext context, String filePath) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: File(filePath).existsSync()
                  ? Image.file(File(filePath), fit: BoxFit.contain)
                  : const Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 80,
                    ),
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

  void _showMemoPopup(BuildContext context, String memoText) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Text('📝 ', style: TextStyle(fontSize: 20)),
            Text(
              '메모',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          memoText,
          style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 14),
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
        return Stack(
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
                      color: const Color(0xFF16161A).withOpacity(0.95),
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
              final rx = (hotspot['x'] as num).toDouble();
              final ry = (hotspot['y'] as num).toDouble();
              final left = rx * constraints.maxWidth;
              final top = ry * constraints.maxHeight;
              final type = HotspotTypeExt.fromString(
                hotspot['type'] as String?,
              );
              final interactable = _isHotspotInteractable(hotspot);

              return Positioned(
                left: left - 22 * s,
                top: top - 22 * s,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown:
                      (
                        _,
                      ) {}, // Block click event passing to underlying webview element
                  child: GestureDetector(
                    onTap: interactable
                        ? () => _activateHotspot(context, hotspot)
                        : null,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: interactable ? 1.0 : 0.45,
                      child: Container(
                        width: 44 * s,
                        height: 44 * s,
                        decoration: BoxDecoration(
                          color: type.color.withOpacity(0.92),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: interactable ? Colors.white : Colors.white38,
                            width: 2.5,
                          ),
                          boxShadow: interactable
                              ? [
                                  BoxShadow(
                                    color: type.color.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : const [],
                        ),
                        child: Center(
                          child: Text(
                            hotspot['icon'] as String? ?? type.emoji,
                            style: TextStyle(fontSize: 20 * s),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
