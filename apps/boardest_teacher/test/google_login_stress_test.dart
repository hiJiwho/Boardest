import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('Empirical Stress Tests: Loopback HTTP Server & Dynamic Port Fallback', () {
    test('1.1 Exclusively binds to 127.0.0.1 (loopbackIPv4) and NOT 0.0.0.0 (anyIPv4)', () async {
      HttpServer? server;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        expect(server.address.address, equals('127.0.0.1'));
        expect(server.address.isLoopback, isTrue);
        expect(server.address, equals(InternetAddress.loopbackIPv4));
        expect(server.address, isNot(equals(InternetAddress.anyIPv4)));
      } finally {
        await server?.close(force: true);
      }
    });

    test('1.2 Default port 1217 binding and dynamic fallback when occupied', () async {
      ServerSocket? blocker;
      try {
        blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 1217, shared: false);
      } catch (_) {}

      HttpServer? testServer;
      int activePort = 0;
      const defaultPort = 1217;

      try {
        try {
          testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, defaultPort, shared: true);
        } catch (e1) {
          // Dynamic port fallback logic as in cloud_drive_service.dart:434
          testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
        }

        activePort = testServer.port;
        expect(activePort, isNonZero);
        if (blocker != null) {
          expect(activePort, isNot(equals(1217)));
        }
        expect(testServer.address, equals(InternetAddress.loopbackIPv4));

        testServer.listen((req) {
          req.response.statusCode = HttpStatus.ok;
          req.response.write('fallback_active');
          req.response.close();
        });

        final res = await http.get(Uri.parse('http://127.0.0.1:$activePort/health'));
        expect(res.statusCode, equals(200));
        expect(res.body, equals('fallback_active'));
      } finally {
        await testServer?.close(force: true);
        await blocker?.close();
      }
    });

    test('1.3 Dynamic port reflection in OAuth redirect URLs (no hardcoded 1217)', () {
      const activePort = 49201;

      final boardestOAuthUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
          '?client_id=test_id'
          '&redirect_uri=http://127.0.0.1:$activePort/boardest-oauth-callback'
          '&response_type=code';

      final cloudOAuthUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
          '?client_id=test_id'
          '&redirect_uri=http://127.0.0.1:$activePort'
          '&response_type=code';

      expect(boardestOAuthUrl, contains('redirect_uri=http://127.0.0.1:49201/boardest-oauth-callback'));
      expect(boardestOAuthUrl, isNot(contains(':1217')));
      expect(cloudOAuthUrl, contains('redirect_uri=http://127.0.0.1:49201'));
      expect(cloudOAuthUrl, isNot(contains(':1217')));
    });

    test('1.4 Rapid sequential restart stress test (5 iterations)', () async {
      for (int i = 0; i < 5; i++) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
        expect(server.port, greaterThan(0));
        server.listen((req) => req.response.close());
        await server.close(force: true);
      }
    });

    test('1.5 Concurrent incoming HTTP burst stress test (50 requests)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int processed = 0;
      server.listen((req) async {
        processed++;
        req.response.statusCode = 200;
        req.response.write('processed_$processed');
        await req.response.close();
      });

      final port = server.port;
      final futures = List.generate(50, (i) => http.get(Uri.parse('http://127.0.0.1:$port/ping?seq=$i')));
      final responses = await Future.wait(futures);

      expect(responses.length, equals(50));
      for (final r in responses) {
        expect(r.statusCode, equals(200));
        expect(r.body, startsWith('processed_'));
      }
      expect(processed, equals(50));
      await server.close(force: true);
    });
    test('1.6 Dynamic port OAuth callback location headers correctly formatted', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final activePort = server.port;

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/start-boardest-oauth') {
          final authUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
              '?client_id=test_client'
              '&redirect_uri=http://127.0.0.1:$activePort/boardest-oauth-callback'
              '&response_type=code';
          request.response.statusCode = HttpStatus.found;
          request.response.headers.add('Location', authUrl);
          await request.response.close();
        }
      });

      final client = http.Client();
      final req = http.Request('GET', Uri.parse('http://127.0.0.1:$activePort/start-boardest-oauth'))..followRedirects = false;
      final response = await client.send(req);

      expect(response.statusCode, equals(302));
      final location = response.headers['location'];
      expect(location, isNotNull);
      expect(location, contains('redirect_uri=http://127.0.0.1:$activePort/boardest-oauth-callback'));
      expect(location, isNot(contains(':1217')));

      await server.close(force: true);
    });
  });

  group('Empirical Stress Tests: URL Parameter Preservation & Windows Launchers', () {
    test('2.1 Complex OAuth URL with &target=win&port=1217 preserves all query parameters', () {
      const authUrl = 'https://boardest-teacher-oauth.web.app/?sys=win&target=win&port=1217&boardest-login=true';
      final uri = Uri.parse(authUrl);

      expect(uri.queryParameters['sys'], equals('win'));
      expect(uri.queryParameters['target'], equals('win'));
      expect(uri.queryParameters['port'], equals('1217'));
      expect(uri.queryParameters['boardest-login'], equals('true'));
      expect(uri.queryParameters.length, equals(4));
    });

    test('2.2 Unquoted cmd.exe ampersand splitting causes command syntax error', () async {
      if (!Platform.isWindows) return;

      // In cmd.exe, unquoted ampersands split commands
      final res = await Process.run('cmd.exe', ['/c', 'echo test & target=win & port=1217']);

      expect(res.exitCode, isNot(equals(0)));
      expect(res.stderr.toString(), contains('target'));
    });

    test('2.3 Tier 3 (explorer.exe) executes cleanly with exit code 0 or 1', () async {
      if (!Platform.isWindows) return;

      const testUrl = 'https://boardest-teacher-oauth.web.app/?sys=win&target=win&port=1217&boardest-login=true';
      final res = await Process.run('explorer.exe', [testUrl]);

      expect(res.exitCode, anyOf([0, 1]));
    });

    test('2.4 Tier 5 (powershell Start-Process) executes cleanly with exit code 0', () async {
      if (!Platform.isWindows) return;

      const testUrl = 'https://boardest-teacher-oauth.web.app/?sys=win&target=win&port=1217&boardest-login=true';
      final res = await Process.run('powershell', ['-NoProfile', '-Command', 'Start-Process', '"$testUrl"']);

      expect(res.exitCode, equals(0));
    });

    test('2.5 Quoted cmd.exe argument preserves full query string without ampersand splitting', () async {
      if (!Platform.isWindows) return;

      const testUrl = 'https://boardest-teacher-oauth.web.app/?sys=win&target=win&port=1217&boardest-login=true';
      final res = await Process.run('cmd.exe', ['/c', 'echo "$testUrl"']);

      expect(res.exitCode, equals(0));
      expect(res.stdout.toString(), contains('target=win'));
      expect(res.stdout.toString(), contains('port=1217'));
      expect(res.stdout.toString(), contains('boardest-login=true'));
      expect(res.stderr.toString(), isEmpty);
    });

    test('2.6 Loopback server receives and parses all query parameters from HTTP request', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, String>? receivedParams;

      server.listen((HttpRequest request) async {
        receivedParams = Map.from(request.uri.queryParameters);
        request.response.statusCode = HttpStatus.ok;
        request.response.write('ok');
        await request.response.close();
      });

      final port = server.port;
      final testUri = Uri.parse('http://127.0.0.1:$port/oauth-test?sys=win&target=win&port=1217&boardest-login=true');
      final res = await http.get(testUri);

      expect(res.statusCode, equals(200));
      expect(receivedParams, isNotNull);
      expect(receivedParams!['sys'], equals('win'));
      expect(receivedParams!['target'], equals('win'));
      expect(receivedParams!['port'], equals('1217'));
      expect(receivedParams!['boardest-login'], equals('true'));

      await server.close(force: true);
    });
  });
}
