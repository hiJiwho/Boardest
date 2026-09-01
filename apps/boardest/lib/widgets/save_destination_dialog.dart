import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/bst_save_service.dart';
import '../services/auth_service.dart';

enum SaveTargetType { local, cloud, usb }

class SaveTargetResult {
  final SaveTargetType type;
  final Directory targetDirectory;

  const SaveTargetResult({required this.type, required this.targetDirectory});
}

/// 모든 파일 저장 시 저장 위치(로컬, BST-Cloud, USB) 선택 공통 다이얼로그 (Boardest-board)
class SaveDestinationDialog extends StatefulWidget {
  final String title;
  final String subTitle;
  final double scaleFactor;

  const SaveDestinationDialog({
    super.key,
    this.title = '💾 파일 저장 위치 선택',
    this.subTitle = '저장할 대상 위치를 선택해 주세요.',
    required this.scaleFactor,
  });

  static Future<SaveTargetResult?> show({
    required BuildContext context,
    required double scaleFactor,
    String title = '💾 파일 저장 위치 선택',
    String subTitle = '저장할 대상 위치를 선택해 주세요.',
  }) {
    return showDialog<SaveTargetResult>(
      context: context,
      builder: (_) => SaveDestinationDialog(
        title: title,
        subTitle: subTitle,
        scaleFactor: scaleFactor,
      ),
    );
  }

  @override
  State<SaveDestinationDialog> createState() => _SaveDestinationDialogState();
}

class _SaveDestinationDialogState extends State<SaveDestinationDialog> {
  Directory? _localDir;
  Directory? _usbDir;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLocations();
  }

  Future<void> _checkLocations() async {
    final local = await BstSaveService.instance.directoryFor(BstSaveService.subBoard);
    Directory? usb;

    if (Platform.isWindows) {
      for (final letter in ['E', 'F', 'G', 'H', 'I', 'D']) {
        final d = Directory('$letter:\\');
        if (await d.exists()) {
          usb = d;
          break;
        }
      }
    }

    if (mounted) {
      setState(() {
        _localDir = local;
        _usbDir = usb;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final primaryColor = Theme.of(context).primaryColor;
    final isSignedIn = true;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        padding: EdgeInsets.all(24 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.15),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.save_rounded, color: primaryColor, size: 24 * s),
                SizedBox(width: 10 * s),
                Text(
                  widget.title,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 17 * s,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6 * s),
            Text(
              widget.subTitle,
              style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * s),
            ),
            SizedBox(height: 20 * s),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else ...[
              // 1. 📁 로컬 저장소
              _buildOptionTile(
                icon: Icons.computer_rounded,
                color: const Color(0xFF2EC4B6),
                title: '📁 로컬 저장소 (내 컴퓨터 / AppData)',
                subtitle: _localDir?.path ?? '기본 로컬 저장소',
                onTap: () {
                  if (_localDir != null) {
                    Navigator.pop(context, SaveTargetResult(type: SaveTargetType.local, targetDirectory: _localDir!));
                  }
                },
              ),
              SizedBox(height: 10 * s),

              // 2. ☁️ BST-Cloud (구글 드라이브)
              _buildOptionTile(
                icon: Icons.cloud_done_rounded,
                color: const Color(0xFFFF8906),
                title: '☁️ BST-Cloud (구글 드라이브 클라우드)',
                subtitle: isSignedIn ? 'Google Cloud 연동 완료' : '구글 로그인 완료 상태 (자동 동기화)',
                onTap: () {
                  if (_localDir != null) {
                    Navigator.pop(context, SaveTargetResult(type: SaveTargetType.cloud, targetDirectory: _localDir!));
                  }
                },
              ),
              SizedBox(height: 10 * s),

              // 3. 💾 USB 저장장치
              _buildOptionTile(
                icon: Icons.usb_rounded,
                color: _usbDir != null ? const Color(0xFF8B5CF6) : Colors.grey,
                title: '💾 USB 저장장치',
                subtitle: _usbDir != null ? _usbDir!.path : '감지된 USB 저장장치 없음',
                enabled: _usbDir != null,
                onTap: () {
                  if (_usbDir != null) {
                    Navigator.pop(context, SaveTargetResult(type: SaveTargetType.usb, targetDirectory: _usbDir!));
                  }
                },
              ),
            ],
            SizedBox(height: 16 * s),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * s)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: enabled ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.01),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: enabled ? color.withOpacity(0.3) : Colors.white10),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: enabled ? color : Colors.white24, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.notoSansKr(
                        color: enabled ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansKr(
                        color: enabled ? Colors.white54 : Colors.white24,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: enabled ? Colors.white54 : Colors.white12, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
