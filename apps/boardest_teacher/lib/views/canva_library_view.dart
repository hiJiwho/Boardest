import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'dart:ui';
import '../services/app_paths.dart';
import '../services/canva_oauth_service.dart';
class CanvaLibraryView extends StatefulWidget {
  final double scaleFactor;

  const CanvaLibraryView({super.key, this.scaleFactor = 1.0});

  @override
  State<CanvaLibraryView> createState() => _CanvaLibraryViewState();
}

class _CanvaLibraryViewState extends State<CanvaLibraryView> {
  bool _isLoading = true;
  List<Map<String, String>> _designs = [];

  @override
  void initState() {
    super.initState();
    _fetchCanvaDesigns();
  }

  Future<void> _fetchCanvaDesigns() async {
    final token = CanvaOAuthService.instance.accessToken;
    if (token != null && token.isNotEmpty) {
      final designs = await CanvaOAuthService.instance.fetchUserDesigns();
      if (mounted) {
        setState(() {
          _designs = designs.map((d) => {
            'id': d.id,
            'title': d.title,
            'thumbnail': d.thumbnailUrl ?? 'https://images.unsplash.com/photo-1614730321146-b6fa6a46bcb4?q=80&w=600&auto=format&fit=crop',
            'embedUrl': d.embedUrl,
          }).toList();
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _designs = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveDesignAsBstCanva(Map<String, String> design) async {
    try {
      final bstDir = Directory(p.join(AppPaths.dataRootSync, 'CanvaDesigns'));
      if (!bstDir.existsSync()) {
        bstDir.createSync(recursive: true);
      }

      final safeTitle = design['title']!.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      final file = File(p.join(bstDir.path, '$safeTitle.bstcanva'));

      final jsonStr = jsonEncode({
        'id': design['id'],
        'title': design['title'],
        'embedUrl': design['embedUrl'],
        'thumbnail': design['thumbnail'],
        'savedAt': DateTime.now().toIso8601String(),
      });

      await file.writeAsString(jsonStr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ $safeTitle 파일이 저장되었습니다. USB나 드라이브에서 열 수 있습니다.',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF00C4CC),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(24 * scale),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24 * scale),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: const Color(0xFF131418).withOpacity(0.75),
              borderRadius: BorderRadius.circular(24 * scale),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 40,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Column(
              children: [
                // Glassmorphic Header
                Container(
                  height: 70 * scale,
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF00C4CC).withOpacity(0.2),
                        const Color(0xFF7D2AE8).withOpacity(0.2),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8 * scale),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C4CC).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12 * scale),
                        ),
                        child: Icon(
                          Icons.auto_awesome_mosaic_rounded,
                          color: const Color(0xFF00C4CC),
                          size: 24 * scale,
                        ),
                      ),
                      SizedBox(width: 16 * scale),
                      Text(
                        'Canva 내 디자인 불러오기',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _fetchCanvaDesigns,
                        icon: Icon(Icons.refresh_rounded, size: 16 * scale),
                        label: const Text('새로고침'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12 * scale),
                          ),
                        ),
                      ),
                      SizedBox(width: 12 * scale),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 24 * scale,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Body
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(
                                color: Color(0xFF00C4CC),
                              ),
                              SizedBox(height: 20 * scale),
                              Text(
                                'Canva 디자인을 불러오는 중입니다...',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white70,
                                  fontSize: 14 * scale,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: EdgeInsets.all(24 * scale),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 16 / 12,
                                crossAxisSpacing: 24 * scale,
                                mainAxisSpacing: 24 * scale,
                              ),
                          itemCount: _designs.length,
                          itemBuilder: (context, index) {
                            final design = _designs[index];
                            return _buildDesignCard(design, scale);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesignCard(Map<String, String> design, double scale) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1D24).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(16 * scale),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    design['thumbnail']!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.image,
                        color: Colors.white24,
                        size: 50,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12 * scale,
                    left: 12 * scale,
                    right: 12 * scale,
                    child: Text(
                      design['title']!,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(12 * scale),
            child: ElevatedButton.icon(
              onPressed: () => _saveDesignAsBstCanva(design),
              icon: Icon(Icons.download_rounded, size: 16 * scale),
              label: Text(
                '수업 자료로 저장 (.bstCanva)',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7D2AE8),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12 * scale),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10 * scale),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
