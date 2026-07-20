import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';

class BstPluginMetadata {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String iconEmoji;
  final String downloadUrl;
  final String role; // 'teacher' | 'student' | 'both'

  BstPluginMetadata({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.iconEmoji,
    required this.downloadUrl,
    required this.role,
  });

  factory BstPluginMetadata.fromJson(Map<String, dynamic> json) {
    return BstPluginMetadata(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? 'Unknown',
      iconEmoji: json['iconEmoji'] as String? ?? '🔌',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      role: json['role'] as String? ?? 'both',
    );
  }
}

class PluginStoreView extends StatefulWidget {
  final double scaleFactor;
  final Function(String pluginId, String pluginName) onLaunchPlugin;

  const PluginStoreView({
    super.key,
    required this.onLaunchPlugin,
    this.scaleFactor = 1.0,
  });

  @override
  State<PluginStoreView> createState() => _PluginStoreViewState();
}

class _PluginStoreViewState extends State<PluginStoreView> {
  bool _loadingStore = true;
  List<BstPluginMetadata> _storePlugins = [];
  final Set<String> _installedPluginIds = {};
  final Map<String, double> _downloadProgress = {};
  
  String _selectedRoleFilter = 'all'; // 'all' | 'teacher' | 'student'

  @override
  void initState() {
    super.initState();
    _fetchStoreRegistry();
    _loadInstalledPlugins();
  }

  void _fetchStoreRegistry() async {
    setState(() => _loadingStore = true);
    
    const url = 'https://raw.githubusercontent.com/hiJiwho/bst-store/main/plugins.json';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final List<dynamic> data = json.decode(res.body);
        setState(() {
          _storePlugins = data.map((x) => BstPluginMetadata.fromJson(x)).toList();
        });
      } else {
        _loadFallbackRegistry();
      }
    } catch (_) {
      _loadFallbackRegistry();
    } finally {
      setState(() => _loadingStore = false);
    }
  }

  void _loadFallbackRegistry() {
    setState(() {
      _storePlugins = [
        BstPluginMetadata(
          id: 'com.boardest.stopwatch',
          name: 'M3 다이내믹 스톱워치',
          version: '1.0.1',
          description: '수업 시간 제어 및 랩타임 모션을 지원하는 고디자인 스톱워치',
          author: 'Boardest Team',
          iconEmoji: '⏱️',
          downloadUrl: 'https://raw.githubusercontent.com/hiJiwho/bst-store/main/bundles/stopwatch.bstplus',
          role: 'both',
        ),
        BstPluginMetadata(
          id: 'com.boardest.drawgame',
          name: '마인드맵 추첨판',
          version: '1.0.4',
          description: '모션 룰렛 기반의 반 전체 무작위 번호 추첨도구',
          author: 'DevSchool',
          iconEmoji: '🎡',
          downloadUrl: 'https://raw.githubusercontent.com/hiJiwho/bst-store/main/bundles/drawgame.bstplus',
          role: 'teacher',
        ),
        BstPluginMetadata(
          id: 'com.boardest.noisewatcher',
          name: '데시벨 노이즈 워처',
          version: '1.2.0',
          description: '마이크 감지 모니터링을 통한 실시간 교실 소음 측정기',
          author: 'CreativeLabs',
          iconEmoji: '🔊',
          downloadUrl: 'https://raw.githubusercontent.com/hiJiwho/bst-store/main/bundles/noisewatcher.bstplus',
          role: 'student',
        ),
      ];
    });
  }

  void _loadInstalledPlugins() async {
    final appDir = await getApplicationSupportDirectory();
    final pluginsDir = Directory(p.join(appDir.path, 'plugins'));
    if (!pluginsDir.existsSync()) {
      pluginsDir.createSync(recursive: true);
    }

    final swDir = Directory(p.join(pluginsDir.path, 'com.boardest.stopwatch'));
    if (!swDir.existsSync()) {
      swDir.createSync(recursive: true);
      final indexHtml = File(p.join(swDir.path, 'index.html'));
      indexHtml.writeAsStringSync('''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Stopwatch</title>
  <style>
    body { background: #121214; color: #E2E2E6; font-family: sans-serif; margin: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; }
    .circle { width: 150px; height: 150px; border-radius: 50%; border: 4px solid #27272A; display: flex; align-items: center; justify-content: center; background: #18181B; }
    .time { font-size: 26px; font-weight: bold; color: #00F5D4; }
  </style>
</head>
<body>
  <div class="circle"><div class="time">00:00.00</div></div>
</body>
</html>''');
    }

    final List<String> installed = [];
    final entities = pluginsDir.listSync();
    for (final e in entities) {
      if (e is Directory) {
        installed.add(p.basename(e.path));
      }
    }

    setState(() {
      _installedPluginIds.clear();
      _installedPluginIds.addAll(installed);
    });
  }

  void _installPlugin(BstPluginMetadata plugin) async {
    setState(() => _downloadProgress[plugin.id] = 0.0);
    try {
      final res = await http.get(Uri.parse(plugin.downloadUrl));
      if (res.statusCode != 200) throw Exception('Download failed');

      final archive = ZipDecoder().decodeBytes(res.bodyBytes);
      final appDir = await getApplicationSupportDirectory();
      final destDir = Directory(p.join(appDir.path, 'plugins', plugin.id));
      if (destDir.existsSync()) destDir.deleteSync(recursive: true);
      destDir.createSync(recursive: true);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(p.join(destDir.path, filename));
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(data);
        } else {
          Directory(p.join(destDir.path, filename)).createSync(recursive: true);
        }
      }

      setState(() {
        _downloadProgress.remove(plugin.id);
        _installedPluginIds.add(plugin.id);
      });
    } catch (_) {
      setState(() => _downloadProgress.remove(plugin.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    
    // Filter registry based on category
    final filtered = _storePlugins.where((p) {
      if (_selectedRoleFilter == 'all') return true;
      return p.role == _selectedRoleFilter || p.role == 'both';
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF13171F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.2),
      ),
      child: Container(
        width: 540 * s,
        height: 600 * s,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.extension_rounded, color: const Color(0xFF00F5D4), size: 28 * s),
                    const SizedBox(width: 8),
                    Text(
                      'Boardest Plus 스토어',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18 * s,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Category Filter Tab bar
            Row(
              children: [
                _buildFilterChip('all', '전체 도구', s),
                const SizedBox(width: 8),
                _buildFilterChip('teacher', '교사용 도구 🎓', s),
                const SizedBox(width: 8),
                _buildFilterChip('student', '학생용 도구 🎒', s),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),
            
            Expanded(
              child: _loadingStore
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        final p = filtered[idx];
                        final isInstalled = _installedPluginIds.contains(p.id);
                        final isDownloading = _downloadProgress.containsKey(p.id);

                        return Card(
                          color: Colors.white.withOpacity(0.02),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.white.withOpacity(0.03)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Text(p.iconEmoji, style: TextStyle(fontSize: 26 * s)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Text(p.description, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _buildActionButton(p, isInstalled, isDownloading, s),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, double s) {
    final active = _selectedRoleFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedRoleFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00F5D4).withOpacity(0.15) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? const Color(0xFF00F5D4) : Colors.white10),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            color: active ? const Color(0xFF00F5D4) : Colors.white70,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            fontSize: 11 * s,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BstPluginMetadata p, bool isInstalled, bool isDownloading, double s) {
    if (isDownloading) {
      return SizedBox(
        width: 24 * s,
        height: 24 * s,
        child: const CircularProgressIndicator(color: Color(0xFF00F5D4), strokeWidth: 2),
      );
    }
    if (isInstalled) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4).withOpacity(0.2)),
        onPressed: () {
          Navigator.pop(context);
          widget.onLaunchPlugin(p.id, p.name);
        },
        child: const Text('실행', style: TextStyle(color: Color(0xFF00F5D4))),
      );
    }
    return ElevatedButton(
      onPressed: () => _installPlugin(p),
      child: const Text('설치'),
    );
  }
}
