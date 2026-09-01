import 'dart:io';

class LoopbackLoginService {
  HttpServer? _server;
  final int port = 1217;

  bool get isRunning => _server != null;

  Future<void> startServer(Function(String code, String state) onCallback) async {
    try {
      stopServer();
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      print('Listening on localhost:$port');

      _server?.listen((HttpRequest request) {
        if (request.uri.path == '/callback') {
          final code = request.uri.queryParameters['code'];
          final state = request.uri.queryParameters['state'];

          if (code != null && state != null) {
            onCallback(code, state);
            request.response
              ..statusCode = HttpStatus.ok
              ..write('Authentication successful! You can close this window.')
              ..close();
            
            stopServer();
          } else {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('Missing code or state.')
              ..close();
          }
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not found')
            ..close();
        }
      });
    } catch (e) {
      print('Failed to start loopback server: $e');
    }
  }

  void stopServer() {
    _server?.close(force: true);
    _server = null;
    print('Loopback server stopped');
  }
}
