import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

/// 교사 노트북(Electron) ↔ 전자칠판 Flutter 간 LAN 통신 서비스
/// 
/// - 포트: 7777 (AppConfig.lanServerPort)
/// - 인증 없음 (Zero-configuration 연결)
class LocalServerService {
  static final LocalServerService instance = LocalServerService._();
  String activeTextbookDir = '';
  LocalServerService._();

  HttpServer? _server;
  String _serverIp = '';
  bool _isRunning = false;

  // 현재 상태 콜백 (dashboard_view가 제공)
  Map<String, dynamic> Function()? onStatusRequest;
  // 명령 수신 콜백
  void Function(String command, Map<String, dynamic> params)? onCommandReceived;
  // 파일 수신 콜백
  void Function(String filePath)? onFileReceived;

  String get serverIp => _serverIp;
  bool get isRunning => _isRunning;
  String get serverUrl => 'http://$_serverIp:${AppConfig.lanServerPort}';

  /// 서버 시작
  Future<bool> start() async {
    if (_isRunning) return true;

    try {
      // LAN IP 취득
      _serverIp = await _getLanIpAddress();
      if (_serverIp.isEmpty) {
        debugPrint('[LocalServer] LAN IP를 찾을 수 없습니다.');
        return false;
      }

      // 라우터 설정
      final router = Router();

      // 엔드포인트 바인딩
      router.get('/ping', _handlePing);
      router.get('/status', (Request req) => _handleStatus(req));
      router.get('/timetable', (Request req) => _handleTimetable(req));
      router.post('/command', (Request req) => _handleCommand(req));
      router.get('/info', (Request req) => _handleInfo(req));
      router.post('/upload', (Request req) => _handleUpload(req));
      router.get('/textbooks/<filepath|.*>', (Request req, String filepath) async {
        final decodedPath = Uri.decodeComponent(filepath);
        if (activeTextbookDir.isEmpty) return Response.notFound('No active textbook directory.');
        final file = File(p.join(activeTextbookDir, decodedPath));
        if (!await file.exists()) {
          return Response.notFound('Textbook asset not found: $decodedPath');
        }
        
        final bytes = await file.readAsBytes();
        String contentType = 'application/octet-stream';
        final ext = p.extension(file.path).toLowerCase();
        if (ext == '.html' || ext == '.htm') contentType = 'text/html; charset=utf-8';
        else if (ext == '.js') contentType = 'application/javascript; charset=utf-8';
        else if (ext == '.css') contentType = 'text/css; charset=utf-8';
        else if (ext == '.png') contentType = 'image/png';
        else if (ext == '.jpg' || ext == '.jpeg') contentType = 'image/jpeg';
        else if (ext == '.gif') contentType = 'image/gif';
        else if (ext == '.svg') contentType = 'image/svg+xml';
        else if (ext == '.json') contentType = 'application/json';
        else if (ext == '.mp4') contentType = 'video/mp4';
        else if (ext == '.webm') contentType = 'video/webm';
        else if (ext == '.mp3') contentType = 'audio/mpeg';
        else if (ext == '.wav') contentType = 'audio/wav';
        else if (ext == '.woff') contentType = 'font/woff';
        else if (ext == '.woff2') contentType = 'font/woff2';
        else if (ext == '.ttf') contentType = 'font/ttf';
        
        return Response.ok(bytes, headers: {
          'Content-Type': contentType,
          'Access-Control-Allow-Origin': '*',
        });
      });

      router.get('/plugins/<filepath|.*>', (Request req, String filepath) async {
        final decodedPath = Uri.decodeComponent(filepath);
        final appDir = await getApplicationSupportDirectory();
        final file = File(p.join(appDir.path, 'plugins', decodedPath));
        if (!await file.exists()) {
          return Response.notFound('Plugin asset not found: $decodedPath');
        }
        
        final bytes = await file.readAsBytes();
        String contentType = 'application/octet-stream';
        final ext = p.extension(file.path).toLowerCase();
        if (ext == '.html' || ext == '.htm') contentType = 'text/html; charset=utf-8';
        else if (ext == '.js') contentType = 'application/javascript; charset=utf-8';
        else if (ext == '.css') contentType = 'text/css; charset=utf-8';
        else if (ext == '.png') contentType = 'image/png';
        else if (ext == '.jpg' || ext == '.jpeg') contentType = 'image/jpeg';
        else if (ext == '.gif') contentType = 'image/gif';
        else if (ext == '.svg') contentType = 'image/svg+xml';
        else if (ext == '.json') contentType = 'application/json';
        
        return Response.ok(bytes, headers: {
          'Content-Type': contentType,
          'Access-Control-Allow-Origin': '*',
        });
      });

      final handler = Pipeline()
          .addMiddleware(_corsMiddleware())
          .addHandler(router.call);

      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        AppConfig.lanServerPort,
      );

      _isRunning = true;
      debugPrint('[LocalServer] 서버 시작됨: $serverUrl');
      return true;
    } catch (e) {
      debugPrint('[LocalServer] 서버 시작 실패: $e');
      return false;
    }
  }

  /// 서버 종료
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    debugPrint('[LocalServer] 서버 종료됨');
  }

  // ──────────────────────────── 핸들러 ────────────────────────────

  Response _handlePing(Request request) {
    return Response.ok(
      json.encode({'status': 'ok', 'service': 'Boardest'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleStatus(Request request) {
    final statusData = onStatusRequest?.call() ?? {};
    return Response.ok(
      json.encode(statusData),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleTimetable(Request request) {
    final statusData = onStatusRequest?.call() ?? {};
    final timetable = statusData['timetable'] ?? {};
    return Response.ok(
      json.encode(timetable),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _handleCommand(Request request) async {
    try {
      final body = await request.readAsString();
      final data = json.decode(body) as Map<String, dynamic>;
      final command = data['command'] as String? ?? '';
      final params = data['params'] as Map<String, dynamic>? ?? {};

      if (command.isEmpty) {
        return Response.badRequest(
          body: json.encode({'error': '커맨드가 비어있습니다.'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      onCommandReceived?.call(command, params);

      return Response.ok(
        json.encode({'status': 'ok', 'command': command}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: json.encode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Response _handleInfo(Request request) {
    final statusData = onStatusRequest?.call() ?? {};
    final info = {
      'ip': _serverIp,
      'port': AppConfig.lanServerPort,
      'schoolName': statusData['schoolName'] ?? '',
      'grade': statusData['grade'] ?? 0,
      'classNum': statusData['classNum'] ?? 0,
      'version': '1.0.0',
    };
    return Response.ok(
      json.encode(info),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// 바이너리 파일 업로드 수신 핸들러 (X-File-Name 헤더로 파일명 획득)
  Future<Response> _handleUpload(Request request) async {
    try {
      final rawFileName = request.headers['X-File-Name'] ?? 'uploaded_file.bin';
      final fileName = Uri.decodeComponent(rawFileName);
      
      // Request body 전체를 바이너리로 수집
      final bytes = await request.read().fold<List<int>>([], (list, element) => list..addAll(element));

      if (bytes.isEmpty) {
        return Response.badRequest(
          body: json.encode({'error': '전송된 파일 데이터가 없습니다.'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 시스템 임시 디렉토리에 파일 저장
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);

      debugPrint('[LocalServer] 파일 업로드 완료: ${tempFile.path}');

      if (onFileReceived != null) {
        onFileReceived!(tempFile.path);
      }

      return Response.ok(
        json.encode({
          'status': 'ok',
          'message': '파일 수신 및 저장 완료',
          'filePath': tempFile.path,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: json.encode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // ──────────────────────────── 미들웨어 ────────────────────────────

  /// CORS 허용 (Electron renderer도 접근 가능하도록)
  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await handler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  static const Map<String, String> _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-File-Name',
  };

  // ──────────────────────────── 유틸리티 ────────────────────────────

  /// LAN IP 주소 취득 (가상 어댑터 필터링 및 Wi-Fi/물리 어댑터 우선)
  Future<String> _getLanIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // 1순위: 가상 어댑터가 아닌 실제 물리 어댑터 중 사설 IP 탐색
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('virtual') ||
            name.contains('vbox') ||
            name.contains('vmnet') ||
            name.contains('wsl') ||
            name.contains('docker') ||
            name.contains('host-only') ||
            name.contains('pseudo') ||
            name.contains('hyper-v')) {
          continue;
        }

        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
            return ip;
          }
        }
      }

      // 2순위: 가상 어댑터 중에서라도 사설 IP가 매칭되면 반환
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
            return ip;
          }
        }
      }

      // 3순위: 그 외 첫 번째 주소
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('[LocalServer] IP 취득 실패: $e');
    }
    return '';
  }
}

/// 지원되는 커맨드 목록
class BoardCommand {
  static const String mealCall = 'meal_call';
  static const String showMessage = 'show_message';
  static const String openTool = 'open_tool';
  static const String nextSlide = 'next_slide';
  static const String prevSlide = 'prev_slide';
  static const String startTimer = 'start_timer';
  static const String stopTimer = 'stop_timer';
  static const String setBrightness = 'set_brightness';
}
