import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';

/// Canva OAuth 2.0 디자인 모델
class CanvaDesign {
  final String id;
  final String title;
  final String embedUrl;
  final String? thumbnailUrl;
  final String updatedAt;

  CanvaDesign({
    required this.id,
    required this.title,
    required this.embedUrl,
    this.thumbnailUrl,
    required this.updatedAt,
  });

  factory CanvaDesign.fromJson(Map<String, dynamic> json) {
    final urls = json['urls'] as Map<String, dynamic>?;
    final editUrl = urls?['edit_url']?.toString() ?? '';
    final embedUrl = urls?['embed_url']?.toString() ??
        (editUrl.isNotEmpty
            ? editUrl.replaceAll('/edit', '/view?embed')
            : 'https://www.canva.com/design/${json['id']}/view?embed');

    return CanvaDesign(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Canva 프레젠테이션',
      embedUrl: embedUrl,
      thumbnailUrl: json['thumbnail']?['url']?.toString(),
      updatedAt: json['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}

/// Canva OAuth 2.0 API 통합 전담 서비스
class CanvaOAuthService {
  static final CanvaOAuthService instance = CanvaOAuthService._internal();
  CanvaOAuthService._internal();

  static const String _canvaTokenKey = 'bst_canva_access_token';
  static const String _canvaRefreshTokenKey = 'bst_canva_refresh_token';

  String? _accessToken;
  String? _refreshToken;

  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;
  String? get accessToken => _accessToken;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_canvaTokenKey);
      _refreshToken = prefs.getString(_canvaRefreshTokenKey);
    } catch (_) {}
  }

  /// Canva OAuth 2.0 PKCE 인증 브라우저 실행
  Future<bool> startOAuthFlow() async {
    try {
      if (kIsWeb) {
        const webAuthUrl = 'https://boardest-teacher-oauth.web.app/?canva=true';
        await launchUrl(Uri.parse(webAuthUrl), mode: LaunchMode.platformDefault);
        return true;
      }
      final authUrl = 'http://127.0.0.1:1217/start-canva-oauth';
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('[CanvaOAuthService] OAuth launch error: $e');
    }
    return false;
  }

  /// Canva OAuth 토큰 세션 저장
  Future<void> setTokens(String access, {String? refresh}) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_canvaTokenKey, access);
    if (refresh != null) await prefs.setString(_canvaRefreshTokenKey, refresh);
  }

  Future<bool> refreshCanvaToken() async {
    if (_refreshToken == null || _refreshToken!.isEmpty) return false;
    try {
      final basicAuth = base64Encode(utf8.encode('${AppConfig.canvaClientId}:${AppConfig.canvaClientSecret}'));
      final response = await http.post(
        Uri.parse('https://api.canva.com/rest/v1/oauth/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic $basicAuth',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccess = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;
        if (newAccess != null && newAccess.isNotEmpty) {
          await setTokens(newAccess, refresh: newRefresh ?? _refreshToken);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[CanvaOAuthService] refresh error: $e');
    }
    return false;
  }

  /// Canva REST API v1 (`https://api.canva.com/v1/designs`) 호출하여 교사의 실제 Canva 디자인 목록 조회
  Future<List<CanvaDesign>> fetchUserDesigns() async {
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      try {
        final response = await http.get(
          Uri.parse('https://api.canva.com/v1/designs'),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final items = data['items'] as List? ?? [];
          if (items.isNotEmpty) {
            return items.map((i) => CanvaDesign.fromJson(i as Map<String, dynamic>)).toList();
          }
        } else if (response.statusCode == 401) {
          final refreshed = await refreshCanvaToken();
          if (refreshed) {
            final retryResponse = await http.get(
              Uri.parse('https://api.canva.com/v1/designs'),
              headers: {
                'Authorization': 'Bearer $_accessToken',
                'Accept': 'application/json',
              },
            ).timeout(const Duration(seconds: 6));
            if (retryResponse.statusCode == 200) {
              final data = jsonDecode(retryResponse.body) as Map<String, dynamic>;
              final items = data['items'] as List? ?? [];
              if (items.isNotEmpty) {
                return items.map((i) => CanvaDesign.fromJson(i as Map<String, dynamic>)).toList();
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[CanvaOAuthService] Fetch designs error: $e');
      }
    }
    return _getFallbackDesigns();
  }

  List<CanvaDesign> _getFallbackDesigns() {
    return [];
  }
}
