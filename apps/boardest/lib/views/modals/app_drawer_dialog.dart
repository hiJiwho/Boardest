import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/system_app_scanner.dart';

class AppDrawerDialog extends StatefulWidget {
  final double scale;
  final Function(String toolId)? onLaunchTool;
  const AppDrawerDialog({super.key, required this.scale, this.onLaunchTool});

  @override
  State<AppDrawerDialog> createState() => _AppDrawerDialogState();
}

class _AppDrawerDialogState extends State<AppDrawerDialog> {
  List<ScannedApp> _allApps = [];
  List<ScannedApp> _filteredApps = [];
  bool _loading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final apps = SystemAppScanner.externalAppsOnly(
        await SystemAppScanner.scanInstalledApps(),
      );
      if (mounted) {
        setState(() {
          _allApps = apps;
          _filteredApps = apps;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _filterApps(String query) {
    setState(() {
      _searchQuery = query;
      if (query.trim().isEmpty) {
        _filteredApps = _allApps;
      } else {
        _filteredApps = _allApps
            .where(
              (app) => app.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final double scale = widget.scale;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 60.0 * scale,
        vertical: 40.0 * scale,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0E17).withOpacity(0.85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: EdgeInsets.all(20.0 * scale),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.apps_rounded,
                            color: const Color(0xFF00F5D4),
                            size: 24.0 * scale,
                          ),
                          SizedBox(width: 10.0 * scale),
                          Text(
                            '설치된 앱 목록',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 18.0 * scale,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white60,
                          size: 22.0 * scale,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  SizedBox(height: 15.0 * scale),
                  // Search Box
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filterApps,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 13.0 * scale,
                      ),
                      decoration: InputDecoration(
                        hintText: '앱 이름 검색...',
                        hintStyle: GoogleFonts.notoSansKr(
                          color: Colors.white38,
                          fontSize: 13.0 * scale,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.white38,
                          size: 18.0 * scale,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear_rounded,
                                  color: Colors.white38,
                                  size: 18.0 * scale,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterApps('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 12.0 * scale,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 15.0 * scale),
                  // Grid List
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF00F5D4),
                            ),
                          )
                        : _filteredApps.isEmpty
                        ? Center(
                            child: Text(
                              '검색 결과가 없습니다.',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white38,
                                fontSize: 14.0 * scale,
                              ),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6,
                                  childAspectRatio: 1.1,
                                  crossAxisSpacing: 12.0 * scale,
                                  mainAxisSpacing: 12.0 * scale,
                                ),
                            itemCount: _filteredApps.length,
                            itemBuilder: (context, index) {
                              final app = _filteredApps[index];
                              final colors = [
                                const Color(0xFF2EC4B6),
                                const Color(0xFF00F5D4),
                                const Color(0xFF2CB67D),
                                const Color(0xFFFF007F),
                                const Color(0xFF7F00FF),
                              ];
                              final accentColor =
                                  colors[app.name.codeUnits.first %
                                      colors.length];
                              final avatar = app.name.length >= 2
                                  ? app.name.substring(0, 2)
                                  : app.name;
                              final hasIcon = !kIsWeb &&
                                  app.iconPath != null &&
                                  app.iconPath!.isNotEmpty &&
                                  File(app.iconPath!).existsSync();

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    if (app.appId.startsWith('boardest://')) {
                                      final toolId = app.appId.replaceFirst(
                                        'boardest://',
                                        '',
                                      );
                                      if (toolId != 'main') {
                                        widget.onLaunchTool?.call(toolId);
                                      }
                                      Navigator.of(context).pop();
                                    } else {
                                      SystemAppScanner.launchApp(app.appId);
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.02),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.04),
                                      ),
                                    ),
                                    padding: EdgeInsets.all(8.0 * scale),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: hasIcon
                                              ? 42.0 * scale
                                              : 32.0 * scale,
                                          height: hasIcon
                                              ? 42.0 * scale
                                              : 32.0 * scale,
                                          decoration: BoxDecoration(
                                            color: hasIcon
                                                ? Colors.transparent
                                                : accentColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(
                                              8.0 * scale,
                                            ),
                                            border: hasIcon
                                                ? null
                                                : Border.all(
                                                    color: accentColor
                                                        .withOpacity(0.4),
                                                    width: 1,
                                                  ),
                                          ),
                                          child: hasIcon
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        8.0 * scale,
                                                      ),
                                                  child: Image.file(
                                                    File(app.iconPath!),
                                                    fit: BoxFit.contain,
                                                    width: 42.0 * scale,
                                                    height: 42.0 * scale,
                                                  ),
                                                )
                                              : Center(
                                                  child: Text(
                                                    avatar,
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          fontSize: 10.0 * scale,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: accentColor,
                                                        ),
                                                  ),
                                                ),
                                        ),
                                        SizedBox(height: 6.0 * scale),
                                        Expanded(
                                          child: Text(
                                            app.name,
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 10.0 * scale,
                                              color: Colors.white.withOpacity(
                                                0.8,
                                              ),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
