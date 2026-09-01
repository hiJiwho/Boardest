import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

enum SaveTargetType { local, cloud, usb }

class SaveTargetResult {
  final SaveTargetType type;
  final Directory targetDirectory;

  const SaveTargetResult({required this.type, required this.targetDirectory});
}

/// 모든 파일 저장 시 저장 위치(로컬, BST-Cloud, USB) 선택 공통 다이얼로그
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLocations();
  }

  Future<void> _checkLocations() async {
    try {
      _localDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      _localDir = Directory.systemTemp;
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return Dialog(
      backgroundColor: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * s)),
      child: Container(
        padding: EdgeInsets.all(24 * s),
        width: 400 * s,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: GoogleFonts.notoSansKr(
                fontSize: 18 * s,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8 * s),
            Text(
              widget.subTitle,
              style: GoogleFonts.notoSansKr(
                fontSize: 13 * s,
                color: Colors.white70,
              ),
            ),
            SizedBox(height: 20 * s),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFF7F5AF0)),
                title: const Text('로컬 저장소', style: TextStyle(color: Colors.white)),
                onTap: () {
                  if (_localDir != null) {
                    Navigator.pop(
                      context,
                      SaveTargetResult(
                        type: SaveTargetType.local,
                        targetDirectory: _localDir!,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud, color: Color(0xFF2EC4B6)),
                title: const Text('클라우드 저장소', style: TextStyle(color: Colors.white)),
                onTap: () {
                  if (_localDir != null) {
                    Navigator.pop(
                      context,
                      SaveTargetResult(
                        type: SaveTargetType.cloud,
                        targetDirectory: _localDir!,
                      ),
                    );
                  }
                },
              ),
            ],
            SizedBox(height: 12 * s),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소', style: TextStyle(color: Colors.white60)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
