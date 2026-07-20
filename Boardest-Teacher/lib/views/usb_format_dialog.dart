import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/usb_format_service.dart';

/// USB 형식 선택 다이얼로그
/// Plus / Pro / Ultra 중 하나를 선택하면 UsbFormatService.applyFormat을 호출합니다.
class UsbFormatDialog extends StatefulWidget {
  final String usbRoot;
  final double scaleFactor;

  const UsbFormatDialog({
    super.key,
    required this.usbRoot,
    this.scaleFactor = 1.0,
  });

  @override
  State<UsbFormatDialog> createState() => _UsbFormatDialogState();
}

class _UsbFormatDialogState extends State<UsbFormatDialog> {
  String _currentType = 'Plus';
  String _selectedType = 'Plus';
  bool _isLoading = true;
  bool _isApplying = false;
  String? _statusMessage;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _dialogBg => _isDark ? const Color(0xFF16161A) : Colors.white;
  Color get _borderColor => _isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withOpacity(0.08);
  Color get _textColor => _isDark ? Colors.white : Colors.black87;
  Color get _textColor70 => _isDark ? Colors.white70 : Colors.black87;
  Color get _textColor54 => _isDark ? Colors.white54 : Colors.black54;
  Color get _textColor38 => _isDark ? Colors.white30 : Colors.black38;
  Color get _textColor24 => _isDark ? Colors.white24 : Colors.black26;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await UsbFormatService.readCurrentType(widget.usbRoot);
    if (mounted) {
      setState(() {
        _currentType = t;
        _selectedType = t;
        _isLoading = false;
      });
    }
  }

  Future<void> _apply() async {
    if (_selectedType == _currentType) {
      Navigator.of(context).pop();
      return;
    }

    // Ultra에서 다른 타입으로 변경 시 경고
    if (_currentType == 'Ultra' && _selectedType != 'Ultra') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('⚠️ Ultra 해제 주의',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            'Ultra 모드를 해제하면 /bst 폴더가 /bst-old로 이름이 바뀌고 숨김이 해제됩니다.\n\n'
            '저장된 수업 자료는 삭제되지 않지만 Boardest Ultra 보안 접근 방식이 해제됩니다.\n\n'
            '계속하시겠습니까?',
            style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('계속', style: GoogleFonts.notoSansKr(color: const Color(0xFFEF4565))),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isApplying = true);
    try {
      await UsbFormatService.applyFormat(widget.usbRoot, _selectedType);
      if (mounted) {
        setState(() {
          _currentType = _selectedType;
          _isApplying = false;
          _statusMessage = '✅ $_selectedType 형식으로 설정되었습니다.';
        });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop(_selectedType);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApplying = false;
          _statusMessage = '❌ 오류: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480 * s,
        padding: EdgeInsets.all(28 * s),
        decoration: BoxDecoration(
          color: _dialogBg,
          borderRadius: BorderRadius.circular(24 * s),
          border: Border.all(color: _borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2EC4B6).withValues(alpha: 0.08),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF2EC4B6)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2EC4B6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12 * s),
                        ),
                        child: Icon(Icons.usb_rounded, color: const Color(0xFF2EC4B6), size: 22 * s),
                      ),
                      SizedBox(width: 12 * s),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'USB 형식 지정',
                            style: GoogleFonts.notoSansKr(
                              color: _textColor,
                              fontSize: 18 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '현재: Boardest-$_currentType',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF2EC4B6),
                              fontSize: 11 * s,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 24 * s),

                  // 형식 선택 카드들
                  ..._buildTypeCards(s),

                  SizedBox(height: 20 * s),

                  // 상태 메시지
                  if (_statusMessage != null) ...[
                    Container(
                      padding: EdgeInsets.all(10 * s),
                      decoration: BoxDecoration(
                        color: _isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8 * s),
                      ),
                      child: Text(
                        _statusMessage!,
                        style: GoogleFonts.notoSansKr(color: _textColor70, fontSize: 12 * s),
                      ),
                    ),
                    SizedBox(height: 12 * s),
                  ],

                  // 버튼 행
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isApplying ? null : () => Navigator.of(context).pop(),
                        child: Text('취소',
                            style: GoogleFonts.notoSansKr(color: _textColor38, fontSize: 14 * s)),
                      ),
                      SizedBox(width: 8 * s),
                      _isApplying
                          ? SizedBox(
                              width: 24 * s,
                              height: 24 * s,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF2EC4B6),
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _apply,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2EC4B6),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10 * s)),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 20 * s, vertical: 10 * s),
                              ),
                              child: Text('적용',
                                  style: GoogleFonts.notoSansKr(
                                      fontWeight: FontWeight.bold, fontSize: 14 * s)),
                            ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildTypeCards(double s) {
    final types = [
      _UsbTypeInfo(
        id: 'Plus',
        emoji: '🟢',
        label: 'Boardest-Plus',
        subtitle: '일반 USB — 포맷 없음',
        desc: 'USB 내부의 모든 폴더/파일을 자유롭게 탐색합니다.\n'
            'BoardestUSB.json을 만들지 않아 완전히 일반 USB 상태를 유지합니다.',
        accentColor: const Color(0xFF2EC4B6),
        warningText: null,
      ),
      _UsbTypeInfo(
        id: 'Pro',
        emoji: '🔵',
        label: 'Boardest-Pro',
        subtitle: '교안 매칭 — 루트에 숨김 JSON 생성',
        desc: '현재 수업 시간표의 반에 매핑된 특정 폴더만 노출합니다.\n'
            '루트에 숨김 BoardestUSB.json 및 반별 폴더들이 자동 생성됩니다.',
        accentColor: const Color(0xFF7F5AF0),
        warningText: null,
      ),
    ];

    return types.map((info) {
      final isSelected = _selectedType == info.id;
      return GestureDetector(
        onTap: () => setState(() => _selectedType = info.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.only(bottom: 10 * s),
          padding: EdgeInsets.all(14 * s),
          decoration: BoxDecoration(
            color: isSelected
                ? info.accentColor.withValues(alpha: 0.10)
                : (_isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withOpacity(0.02)),
            borderRadius: BorderRadius.circular(14 * s),
            border: Border.all(
              color: isSelected
                  ? info.accentColor.withValues(alpha: 0.6)
                  : _borderColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Radio indicator
              Container(
                width: 18 * s,
                height: 18 * s,
                margin: EdgeInsets.only(top: 2 * s),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? info.accentColor : _textColor24,
                    width: 2,
                  ),
                  color: isSelected ? info.accentColor : Colors.transparent,
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 10 * s, color: _isDark ? Colors.black : Colors.white)
                    : null,
              ),
              SizedBox(width: 12 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(info.emoji, style: TextStyle(fontSize: 14 * s)),
                        SizedBox(width: 6 * s),
                        Text(
                          info.label,
                          style: GoogleFonts.notoSansKr(
                            color: isSelected ? _textColor : _textColor70,
                            fontSize: 14 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2 * s),
                    Text(
                      info.subtitle,
                      style: GoogleFonts.notoSansKr(
                        color: isSelected
                            ? info.accentColor
                            : _textColor38,
                        fontSize: 11 * s,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6 * s),
                    Text(
                      info.desc,
                      style: GoogleFonts.notoSansKr(
                        color: _textColor54,
                        fontSize: 11 * s,
                        height: 1.5,
                      ),
                    ),
                    if (info.warningText != null && _currentType == info.id) ...[
                      SizedBox(height: 6 * s),
                      Text(
                        info.warningText!,
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFFEF4565).withValues(alpha: 0.8),
                          fontSize: 10 * s,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

class _UsbTypeInfo {
  final String id;
  final String emoji;
  final String label;
  final String subtitle;
  final String desc;
  final Color accentColor;
  final String? warningText;

  const _UsbTypeInfo({
    required this.id,
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.desc,
    required this.accentColor,
    this.warningText,
  });
}
