import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../widgets/usb_explorer.dart';
import '../services/storage_service.dart';

enum UsbType {
  just,
  lite,
  bst,
}

class UsbExplorerPanel extends StatefulWidget {
  final String drivePath;
  final double scaleFactor;
  final void Function(String)? onFileOpen;

  const UsbExplorerPanel({
    super.key,
    required this.drivePath,
    this.scaleFactor = 1.0,
    this.onFileOpen,
  });

  @override
  State<UsbExplorerPanel> createState() => _UsbExplorerPanelState();
}

class _UsbExplorerPanelState extends State<UsbExplorerPanel> {
  UsbType _type = UsbType.just;
  late String _resolvedDrivePath;

  @override
  void initState() {
    super.initState();
    _resolvedDrivePath = widget.drivePath;
    _resolveUsbType();
  }

  @override
  void didUpdateWidget(UsbExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drivePath != widget.drivePath) {
      _resolvedDrivePath = widget.drivePath;
      _resolveUsbType();
    }
  }

  void _resolveUsbType() async {
    final jsonFile = File('${widget.drivePath}BoardestUSB.json');
    if (jsonFile.existsSync()) {
      try {
        final content = jsonFile.readAsStringSync();
        final config = jsonDecode(content);
        final t = config['type'];
        if (t == 'Lite') {
          final settings = await StorageService().getSettings();
          final classNickname = settings.classNickname;
          String resolvedPath = widget.drivePath;
          if (classNickname != null && classNickname.isNotEmpty) {
            final liteSettings = config['lite_settings'] as Map<String, dynamic>? ?? {};
            final relativePath = liteSettings[classNickname] as String?;
            if (relativePath != null && relativePath.isNotEmpty) {
              final mappedPath = p.join(widget.drivePath, relativePath);
              if (Directory(mappedPath).existsSync()) {
                resolvedPath = mappedPath;
              }
            }
          }
          if (mounted) {
            setState(() {
              _type = UsbType.lite;
              _resolvedDrivePath = resolvedPath;
            });
          }
          return;
        } else if (t == 'Bst') {
          if (mounted) {
            setState(() {
              _type = UsbType.bst;
              _resolvedDrivePath = widget.drivePath;
            });
          }
          return;
        }
      } catch (e) {
        // Fallback to just
      }
    }
    if (mounted) {
      setState(() {
        _type = UsbType.just;
        _resolvedDrivePath = widget.drivePath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Default to Just-USB mode
    Widget content = UsbExplorer(
      drivePath: _resolvedDrivePath,
      scaleFactor: widget.scaleFactor,
      onFileOpen: widget.onFileOpen,
    );

    String headerText = 'USB 탐색기 (Boardest-Plus)';

    if (_type == UsbType.lite) {
      headerText = '매칭 교안 (Boardest-Pro)';
      content = UsbExplorer(
        drivePath: _resolvedDrivePath,
        scaleFactor: widget.scaleFactor,
        onFileOpen: widget.onFileOpen,
      );
    } else if (_type == UsbType.bst) {
      headerText = '수업 자료 (Boardest-Ultra)';
      // Boardest-USB uses /bst/PDF or PPT
      final bstPath = '${widget.drivePath}bst';
      content = UsbExplorer(
        drivePath: Directory(bstPath).existsSync() ? bstPath : widget.drivePath,
        scaleFactor: widget.scaleFactor,
        onFileOpen: widget.onFileOpen,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4 * widget.scaleFactor, vertical: 4 * widget.scaleFactor),
          child: Row(
            children: [
              Container(
                width: 4 * widget.scaleFactor,
                height: 12 * widget.scaleFactor,
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F5D4).withOpacity(0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ],
                ),
              ),
              SizedBox(width: 6 * widget.scaleFactor),
              Text(
                headerText,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12 * widget.scaleFactor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(width: 4 * widget.scaleFactor),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00F5D4).withOpacity(0.3),
                        const Color(0xFF00F5D4).withOpacity(0.01)
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 6 * widget.scaleFactor),
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.015),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: content,
          ),
        ),
      ],
    );
  }
}
