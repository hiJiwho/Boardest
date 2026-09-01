import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/bst_save_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/youtube_embed_service.dart';

/// Boardest-Teacher 클린 유튜브 (수업 플리 관리 & 전자칠판 송출 컨트롤러)
class YoutubeBoardView extends StatefulWidget {
  final double scaleFactor;
  final String? initialUrl;
  final String? filePath; // .YT 플리 파일
  final VoidCallback? onBack;

  const YoutubeBoardView({
    super.key,
    required this.scaleFactor,
    this.initialUrl,
    this.filePath,
    this.onBack,
  });

  @override
  State<YoutubeBoardView> createState() => _YoutubeBoardViewState();
}

class YtPlaylistItem {
  String title;
  String url;
  int? startSeconds;
  int? endSeconds;

  YtPlaylistItem({
    required this.title,
    required this.url,
    this.startSeconds,
    this.endSeconds,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    if (startSeconds != null) 'startSeconds': startSeconds,
    if (endSeconds != null) 'endSeconds': endSeconds,
  };

  factory YtPlaylistItem.fromJson(Map<String, dynamic> json) {
    return YtPlaylistItem(
      title: json['title'] ?? '유튜브 영상',
      url: json['url'] ?? '',
      startSeconds: json['startSeconds'] as int?,
      endSeconds: json['endSeconds'] as int?,
    );
  }
}

class _YoutubeBoardViewState extends State<YoutubeBoardView> {
  late final TextEditingController _urlController;
  late final TextEditingController _playlistTitleController;

  WebviewController? _winWebviewController;
  WebViewController? _androidWebController;

  bool _isWebviewInitialized = false;
  String _playlistTitle = '오늘의 수업 플리 (Playlist)';
  List<YtPlaylistItem> _playlist = [];
  int _currentIndex = 0;
  bool _showPlaylistDrawer = true;

  void _loadWebviewUrl(String targetUrl) {
    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.loadUrl(targetUrl);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.loadRequest(Uri.parse(targetUrl));
    }
  }

  static const String _defaultUrl = 'https://www.youtube.com';

  static const String _cleanYoutubeCss = '''
    #related, #secondary, ytd-browse[page-subtype="home"],
    .ytp-ce-element, .ytd-compact-autoplay-toggle,
    .video-ads, .ytp-ad-module, .ytp-ad-overlay-container,
    ytd-banner-promo-renderer, ytd-statement-banner-renderer {
      display: none !important;
    }
  ''';

  @override
  void initState() {
    super.initState();
    String targetUrl = widget.initialUrl ?? _defaultUrl;
    _playlistTitleController = TextEditingController(text: _playlistTitle);

    // .YT JSON 파일인 경우 파싱 (단일 영상 및 플리 목록)
    if (widget.filePath != null && widget.filePath!.isNotEmpty) {
      try {
        final file = File(widget.filePath!);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          final data = jsonDecode(content);
          if (data['title'] != null) {
            _playlistTitle = data['title'];
            _playlistTitleController.text = _playlistTitle;
          }
          if (data['playlist'] != null && data['playlist'] is List) {
            _playlist = (data['playlist'] as List)
                .map((e) => YtPlaylistItem.fromJson(e))
                .toList();
            if (_playlist.isNotEmpty) {
              targetUrl = _playlist[0].url;
            }
          } else if (data['url'] != null) {
            _playlist.add(
              YtPlaylistItem(title: _playlistTitle, url: data['url']),
            );
            targetUrl = data['url'];
          }
        }
      } catch (e) {
        debugPrint('[YoutubeBoardView] .YT JSON parse error: $e');
      }
    }

    if (_playlist.isEmpty) {
      _playlist.add(YtPlaylistItem(title: '기본 수업 영상', url: targetUrl));
    }

    _urlController = TextEditingController(text: targetUrl);

    if (Platform.isWindows) {
      _initWindowsWebview();
    } else if (Platform.isAndroid) {
      _initAndroidWebview();
    }
  }

  Future<void> _initWindowsWebview() async {
    try {
      _winWebviewController = WebviewController();
      await _winWebviewController!.initialize();
      _winWebviewController!.url.listen((url) {
        if (mounted) {
          _urlController.text = url;
          _injectCleanCssWindows();
        }
      });
      await _winWebviewController!.loadUrl(_urlController.text);
      if (mounted) setState(() => _isWebviewInitialized = true);
    } catch (e) {
      debugPrint('[YoutubeBoardView] Init error: $e');
    }
  }

  void _injectCleanCssWindows() {
    if (_winWebviewController == null) return;
    final js =
        '''
      (function() {
        var style = document.getElementById('bst-yt-clean-style');
        if (!style) {
          style = document.createElement('style');
          style.id = 'bst-yt-clean-style';
          style.innerHTML = `$_cleanYoutubeCss`;
          document.head.appendChild(style);
        }
      })();
    ''';
    _winWebviewController!.executeScript(js);
  }

  void _initAndroidWebview() {
    _androidWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _urlController.text = url);
              _androidWebController?.runJavaScript('''
                var style = document.createElement('style');
                style.innerHTML = `$_cleanYoutubeCss`;
                document.head.appendChild(style);
              ''');
            }
          },
          onNavigationRequest: (NavigationRequest req) {
            final u = req.url.toLowerCase();
            if (u.contains('doubleclick.net') ||
                u.contains('googlesyndication')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_urlController.text));
    setState(() => _isWebviewInitialized = true);
  }

  void _playPlaylistItem(int index) {
    if (index < 0 || index >= _playlist.length) return;
    final embedUrl = YouTubeEmbedService.convertToEmbedUrl(
      _playlist[index].url,
    );
    setState(() {
      _currentIndex = index;
      _urlController.text = embedUrl;
    });

    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.loadUrl(embedUrl);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.loadRequest(Uri.parse(embedUrl));
    }
  }

  bool _isDownloadingMp4 = false;
  double _downloadProgress = 0.0;
  String _downloadStatusText = '';

  Future<void> _autoDownloadMp4(String rawUrl) async {
    final targetUrl = rawUrl.trim();
    if (targetUrl.isEmpty || _isDownloadingMp4) return;

    setState(() {
      _isDownloadingMp4 = true;
      _downloadProgress = 0.05;
      _downloadStatusText = '🔍 유튜브 MP4 다운로드 시작…';
    });

    final file = await YouTubeEmbedService.downloadVideoDirectly(
      targetUrl,
      onProgress: (prog, status) {
        if (mounted) {
          setState(() {
            _downloadProgress = prog;
            _downloadStatusText = status;
          });
        }
      },
    );

    if (file != null && mounted) {
      final fileUri = Uri.file(file.path).toString();
      final filename = p.basename(file.path);
      setState(() {
        _playlist.add(YtPlaylistItem(title: '🎬 $filename', url: fileUri));
        _currentIndex = _playlist.length - 1;
        _urlController.text = fileUri;
        _isDownloadingMp4 = false;
        _downloadProgress = 1.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🎉 [$filename] MP4 비디오가 로컬 보관함에 자동 저장되었습니다!')),
      );
      _loadWebviewUrl(fileUri);
    } else {
      if (mounted) {
        setState(() {
          _isDownloadingMp4 = false;
        });
        // 스트림 직접 추출 실패 시 일반 임베드 뷰어로 재생 폴백
        final embedUrl = YouTubeEmbedService.convertToEmbedUrl(targetUrl);
        _loadWebviewUrl(embedUrl);
      }
    }
  }

  /// 수업 비디오 컷 편집 모달 (시작/종료 초 지정)
  void _showYtCutEditorModal(int index) {
    if (index < 0 || index >= _playlist.length) return;
    final item = _playlist[index];
    final startCtrl = TextEditingController(
      text: item.startSeconds?.toString() ?? '0',
    );
    final endCtrl = TextEditingController(
      text: item.endSeconds?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Row(
          children: [
            const Icon(Icons.content_cut_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(
              '✂️ [${item.title}] 컷 편집 구간',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '시작 재생 시각 (초)',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: endCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '종료 재생 시각 (초, 비워두면 끝까지)',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                item.startSeconds = null;
                item.endSeconds = null;
              });
              Navigator.pop(ctx);
            },
            child: const Text('초기화', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              final startS = int.tryParse(startCtrl.text.trim());
              final endS = int.tryParse(endCtrl.text.trim());
              setState(() {
                item.startSeconds = startS;
                item.endSeconds = endS;
              });
              final embed = YouTubeEmbedService.convertToEmbedUrl(
                item.url,
                startSeconds: startS,
                endSeconds: endS,
              );
              _loadWebviewUrl(embed);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '✂️ 컷 구간 설정 저장됨 (${startS ?? 0}초 ~ ${endS != null ? '$endS초' : '끝'})',
                  ),
                ),
              );
            },
            child: const Text(
              '적용하기',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 전체 플리를 .YT JSON 파일로 저장
  void _savePlaylistAsYtFile() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text(
          '▶️ .YT 플리 파일로 내보내기',
          style: GoogleFonts.notoSansKr(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _playlistTitleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '수업 플리 제목',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '플리 포함 영상: ${_playlist.length}개',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2EC4B6),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.usb_rounded, size: 16),
            label: const Text('USB 저장'),
            onPressed: () => _executeYtSave(ctx, 'usb'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.computer_rounded, size: 16),
            label: const Text('로컬 저장'),
            onPressed: () => _executeYtSave(ctx, 'local'),
          ),
          if (CloudDriveService.instance.isLoggedIn)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7F5AF0),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.cloud_upload_rounded, size: 16),
              label: const Text('Cloud 업로드'),
              onPressed: () => _executeYtSave(ctx, 'cloud'),
            ),
        ],
      ),
    );
  }

  Future<void> _executeYtSave(BuildContext ctx, String targetLocation) async {
    final title = _playlistTitleController.text.trim();
    final jsonObj = {
      'title': title,
      'playlist': _playlist.map((e) => e.toJson()).toList(),
      'createdAt': DateTime.now().toIso8601String(),
      'type': 'clean_youtube_playlist',
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonObj);
    Navigator.pop(ctx);

    if (targetLocation == 'cloud') {
      final ok = await CloudDriveService.instance.uploadTextFileToDrive(
        '$title.yt',
        jsonStr,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: ok ? const Color(0xFF7F5AF0) : Colors.redAccent,
            content: Text(
              ok ? '☁️ [$title.yt] 플리가 BST Cloud에 업로드되었습니다!' : 'Cloud 업로드 실패',
            ),
          ),
        );
      }
      return;
    }

    String? savePath;
    if (targetLocation == 'usb') {
      try {
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          'Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=2" | Select-Object -ExpandProperty DeviceID',
        ]);
        if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
          final drive = '${res.stdout.toString().trim().substring(0, 1)}:\\';
          savePath = p.join(drive, '$title.yt');
        }
      } catch (_) {}
    }

    if (savePath == null || savePath.isEmpty) {
      try {
        savePath = await FilePicker.saveFile(
          dialogTitle: '▶️ .YT 플리 파일 저장',
          fileName: '$title.yt',
          type: FileType.custom,
          allowedExtensions: ['yt'],
        );
      } catch (_) {}
    }

    if (savePath == null || savePath.isEmpty) {
      final boardDir = await BstSaveService.instance.directoryFor(
        BstSaveService.subBoard,
      );
      savePath = p.join(boardDir.path, '$title.yt');
    }

    try {
      final file = File(savePath);
      await file.writeAsString(jsonStr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2EC4B6),
            content: Text('▶️ [$title.yt] 플리 파일이 저장되었습니다! ($savePath)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('플리 저장 실패: $e')));
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _playlistTitleController.dispose();
    _winWebviewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: SafeArea(
        child: Column(
          children: [
            // Top Teacher Command Bar
            Container(
              height: 54 * scale,
              padding: EdgeInsets.symmetric(horizontal: 12 * scale),
              color: const Color(0xFF16161A),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const Icon(
                    Icons.playlist_play_rounded,
                    color: Colors.redAccent,
                    size: 28,
                  ),
                  SizedBox(width: 8 * scale),
                  Text(
                    '수업 비디오 다운로드 관리자',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15 * scale,
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  // URL 입력창
                  Expanded(
                    child: Container(
                      height: 38 * scale,
                      decoration: BoxDecoration(
                        color: const Color(0xFF242629),
                        borderRadius: BorderRadius.circular(20 * scale),
                        border: Border.all(
                          color: Colors.redAccent.withOpacity(0.4),
                        ),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 14 * scale),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            size: 16,
                            color: Colors.white54,
                          ),
                          SizedBox(width: 8 * scale),
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13 * scale,
                              ),
                              onSubmitted: (url) => _autoDownloadMp4(url),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: '유튜브 URL 입력 시 자동으로 MP4 비디오 다운로드…',
                                hintStyle: TextStyle(color: Colors.white38),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.file_download_rounded,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            tooltip: '유튜브 영상을 MP4로 다운로드 및 저장',
                            onPressed: () =>
                                _autoDownloadMp4(_urlController.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 12 * scale),

                  IconButton(
                    icon: const Icon(
                      Icons.save_alt_rounded,
                      color: Colors.redAccent,
                    ),
                    tooltip: '.YT 플리 파일 저장',
                    onPressed: _savePlaylistAsYtFile,
                  ),
                  IconButton(
                    icon: Icon(
                      _showPlaylistDrawer
                          ? Icons.view_sidebar_rounded
                          : Icons.view_sidebar_outlined,
                      color: Colors.white70,
                    ),
                    tooltip: '플리 리스트 토글',
                    onPressed: () => setState(
                      () => _showPlaylistDrawer = !_showPlaylistDrawer,
                    ),
                  ),
                ],
              ),
            ),

            if (_isDownloadingMp4)
              Container(
                margin: EdgeInsets.symmetric(
                  horizontal: 16 * scale,
                  vertical: 4 * scale,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: 12 * scale,
                  vertical: 6 * scale,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8 * scale),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _downloadStatusText,
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${(_downloadProgress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4 * scale),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: Colors.white12,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              ),

            // Main Body: Sidebar (Playlist) + WebView
            Expanded(
              child: Row(
                children: [
                  // 좌측 수업 플리 목록 사이드바
                  if (_showPlaylistDrawer)
                    Container(
                      width: 260 * scale,
                      color: const Color(0xFF131418),
                      padding: EdgeInsets.all(12 * scale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.queue_music_rounded,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              SizedBox(width: 6 * scale),
                              Expanded(
                                child: Text(
                                  _playlistTitleController.text,
                                  style: GoogleFonts.notoSansKr(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13 * scale,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 16),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _playlist.length,
                              itemBuilder: (ctx, idx) {
                                final isSelected = idx == _currentIndex;
                                return Card(
                                  color: isSelected
                                      ? Colors.redAccent.withOpacity(0.2)
                                      : const Color(0xFF1F2128),
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      8 * scale,
                                    ),
                                    side: BorderSide(
                                      color: isSelected
                                          ? Colors.redAccent
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 12 * scale,
                                      backgroundColor: isSelected
                                          ? Colors.redAccent
                                          : Colors.white12,
                                      child: Text(
                                        '${idx + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      _playlist[idx].title,
                                      style: GoogleFonts.notoSansKr(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 12 * scale,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.content_cut_rounded,
                                            color:
                                                (_playlist[idx].startSeconds !=
                                                        null ||
                                                    _playlist[idx].endSeconds !=
                                                        null)
                                                ? Colors.amber
                                                : Colors.white54,
                                            size: 16,
                                          ),
                                          tooltip: '구간 컷 편집 (시작/종료 초)',
                                          onPressed: () =>
                                              _showYtCutEditorModal(idx),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline_rounded,
                                            color: Colors.white30,
                                            size: 16,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _playlist.removeAt(idx);
                                              if (_currentIndex >=
                                                  _playlist.length) {
                                                _currentIndex =
                                                    _playlist.isEmpty
                                                    ? 0
                                                    : _playlist.length - 1;
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    onTap: () => _playPlaylistItem(idx),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 우측 유튜브 뷰포트
                  Expanded(child: _buildWebView()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    if (Platform.isWindows &&
        _isWebviewInitialized &&
        _winWebviewController != null) {
      return Webview(_winWebviewController!);
    } else if (Platform.isAndroid && _androidWebController != null) {
      return WebViewWidget(controller: _androidWebController!);
    } else {
      return Center(
        child: Text(
          '▶️ 클린 유튜브 엔진 로딩 중…',
          style: GoogleFonts.notoSansKr(color: Colors.white38),
        ),
      );
    }
  }
}
