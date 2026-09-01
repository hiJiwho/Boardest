import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

class CanvaOAuthService {
  static const String clientId = 'YOUR_CANVA_CLIENT_ID'; // TODO: Replace with actual Canva Client ID
  static const String redirectUri = 'http://127.0.0.1:1217/callback';

  String generateRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values).substring(0, length);
  }

  String generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  Uri buildAuthUrl({
    required String codeChallenge,
    required String state,
    String? customClientId,
    String? customRedirectUri,
  }) {
    return Uri.https('www.canva.com', '/api/oauth/authorize', {
      'response_type': 'code',
      'client_id': customClientId ?? clientId,
      'redirect_uri': customRedirectUri ?? redirectUri,
      'scope': 'design:content:read',
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });
  }

  Future<void> authenticate() async {
    final codeVerifier = generateRandomString(128);
    final codeChallenge = generateCodeChallenge(codeVerifier);
    final state = generateRandomString(32);

    final authUrl = buildAuthUrl(codeChallenge: codeChallenge, state: state);

    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl);
    } else {
      throw Exception('Could not launch Canva Auth URL');
    }
  }
}
