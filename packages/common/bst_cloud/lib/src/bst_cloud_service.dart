import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Connection pairing status
enum PairingStatus {
  pending,
  connected,
  approved,
  rejected,
  expired,
  disconnected,
}

/// Pairing request data model
class PairingRequest {
  final String requestId;
  final String schoolCode;
  final String classroomName;
  final String? teacherName;
  final PairingStatus status;
  final String? token;
  final String? folderId;
  final String? otpCode;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime? approvedAt;

  PairingRequest({
    required this.requestId,
    required this.schoolCode,
    required this.classroomName,
    this.teacherName,
    this.status = PairingStatus.pending,
    this.token,
    this.folderId,
    this.otpCode,
    this.expiresAt,
    DateTime? createdAt,
    this.approvedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isConnected => status == PairingStatus.connected || status == PairingStatus.approved;
  bool get isPending => status == PairingStatus.pending;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  PairingRequest copyWith({
    String? requestId,
    String? schoolCode,
    String? classroomName,
    String? teacherName,
    PairingStatus? status,
    String? token,
    String? folderId,
    String? otpCode,
    DateTime? expiresAt,
    DateTime? createdAt,
    DateTime? approvedAt,
  }) {
    return PairingRequest(
      requestId: requestId ?? this.requestId,
      schoolCode: schoolCode ?? this.schoolCode,
      classroomName: classroomName ?? this.classroomName,
      teacherName: teacherName ?? this.teacherName,
      status: status ?? this.status,
      token: token ?? this.token,
      folderId: folderId ?? this.folderId,
      otpCode: otpCode ?? this.otpCode,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'schoolCode': schoolCode,
      'classroomName': classroomName,
      'teacherName': teacherName,
      'status': status.name,
      'token': token,
      'folderId': folderId,
      'otpCode': otpCode,
      'expiresAt': expiresAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'approvedAt': approvedAt?.toIso8601String(),
    };
  }

  factory PairingRequest.fromJson(Map<String, dynamic> json) {
    return PairingRequest(
      requestId: json['requestId'] as String? ?? '',
      schoolCode: json['schoolCode'] as String? ?? '',
      classroomName: json['classroomName'] as String? ?? '',
      teacherName: json['teacherName'] as String?,
      status: _parseStatus(json['status'] as String?),
      token: json['token'] as String?,
      folderId: json['folderId'] as String?,
      otpCode: json['otpCode'] as String?,
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      approvedAt: json['approvedAt'] != null ? DateTime.tryParse(json['approvedAt'] as String) : null,
    );
  }

  static PairingStatus _parseStatus(String? raw) {
    if (raw == null) return PairingStatus.pending;
    switch (raw.toLowerCase()) {
      case 'connected':
        return PairingStatus.connected;
      case 'approved':
        return PairingStatus.approved;
      case 'rejected':
        return PairingStatus.rejected;
      case 'expired':
        return PairingStatus.expired;
      case 'disconnected':
        return PairingStatus.disconnected;
      case 'pending':
      default:
        return PairingStatus.pending;
    }
  }
}

/// Google Drive OAuth Token Exchange result
class OAuthTokenResult {
  final bool success;
  final String? accessToken;
  final int? expiresIn;
  final String? tokenType;
  final String? error;

  const OAuthTokenResult._({
    required this.success,
    this.accessToken,
    this.expiresIn,
    this.tokenType,
    this.error,
  });

  factory OAuthTokenResult.success({
    required String accessToken,
    int? expiresIn,
    String? tokenType,
  }) {
    return OAuthTokenResult._(
      success: true,
      accessToken: accessToken,
      expiresIn: expiresIn,
      tokenType: tokenType ?? 'Bearer',
    );
  }

  factory OAuthTokenResult.failure(String errorMessage) {
    return OAuthTokenResult._(
      success: false,
      error: errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    'accessToken': accessToken,
    'expiresIn': expiresIn,
    'tokenType': tokenType,
    'error': error,
  };
}

/// BstCloudService: Central cloud connection, DriveCast pairing, and classroom presence service
class BstCloudService {
  static final BstCloudService instance = BstCloudService();

  final http.Client _client;
  final String _rtdbBaseUrl;
  final String _firestoreBaseUrl;

  final Map<String, dynamic> _syncStateStore = {};
  final Map<String, ValueNotifier<dynamic>> _syncStateNotifiers = {};
  final Map<String, PairingRequest> _pairingRequests = {};
  final Map<String, List<String>> _onlineClassroomsCache = {};

  BstCloudService({
    http.Client? httpClient,
    String? rtdbBaseUrl,
    String? firestoreBaseUrl,
  })  : _client = httpClient ?? http.Client(),
        _rtdbBaseUrl = rtdbBaseUrl ?? 'https://jiwhosboardest-default-rtdb.firebaseio.com',
        _firestoreBaseUrl = firestoreBaseUrl ??
            'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents';

  // ---------------------------------------------------------------------------
  // Sync State Management
  // ---------------------------------------------------------------------------

  void saveSyncState(String key, dynamic value) {
    _syncStateStore[key] = value;
    if (!_syncStateNotifiers.containsKey(key)) {
      _syncStateNotifiers[key] = ValueNotifier(value);
    } else {
      _syncStateNotifiers[key]!.value = value;
    }
  }

  void listenSyncState(String key, void Function(dynamic value) callback) {
    if (!_syncStateNotifiers.containsKey(key)) {
      _syncStateNotifiers[key] = ValueNotifier(_syncStateStore[key]);
    }
    _syncStateNotifiers[key]!.addListener(() {
      callback(_syncStateNotifiers[key]!.value);
    });
  }

  dynamic getSyncState(String key) => _syncStateStore[key];

  // ---------------------------------------------------------------------------
  // Mission 1: Online Classrooms Query
  // ---------------------------------------------------------------------------

  /// Normalizes school codes into valid alphanumeric RTDB path segments
  static String normalizeSchoolCode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'default';
    final t = raw.trim().toLowerCase();
    if (t == 'ydm' || t.contains('양동') || t == '44134' || t == '48588') {
      return 'ydm';
    }
    if (t == 'demo' || t.contains('데모')) {
      return 'demo';
    }
    final sanitized = t.replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    return sanitized.isNotEmpty ? sanitized : 'default';
  }

  /// Returns the resilient default school classroom directory
  List<String> getDefaultClassrooms() {
    final classrooms = <String>[];
    for (var g = 1; g <= 3; g++) {
      for (var c = 1; c <= 8; c++) {
        classrooms.add('$g학년 $c반');
      }
    }
    classrooms.addAll(['과학실', '음악실', '미술실', '컴퓨터실', '체육관', '도서관']);
    return classrooms;
  }

  /// Query online classrooms under schools/{schoolCode}/classrooms or active RTDB presence nodes
  Future<List<String>> getOnlineClassrooms([String? schoolCode]) async {
    final effectiveCode = normalizeSchoolCode(schoolCode ?? getSyncState('schoolCode') as String?);

    // 1. Try querying remote classrooms from schools/{schoolCode}/classrooms.json
    try {
      final classroomsUrl = Uri.parse('$_rtdbBaseUrl/schools/$effectiveCode/classrooms.json');
      final response = await _client.get(classroomsUrl).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 && response.body != 'null' && response.body.isNotEmpty) {
        final decoded = json.decode(response.body);
        final parsed = _extractClassroomList(decoded);
        if (parsed.isNotEmpty) {
          _onlineClassroomsCache[effectiveCode] = parsed;
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('[BstCloudService] Remote classrooms query error ($effectiveCode): $e');
    }

    // 2. Try querying active presence nodes under presence/{schoolCode}.json
    try {
      final presenceUrl = Uri.parse('$_rtdbBaseUrl/presence/$effectiveCode.json');
      final presenceRes = await _client.get(presenceUrl).timeout(const Duration(seconds: 3));

      if (presenceRes.statusCode == 200 && presenceRes.body != 'null' && presenceRes.body.isNotEmpty) {
        final decoded = json.decode(presenceRes.body);
        final parsed = _extractClassroomList(decoded);
        if (parsed.isNotEmpty) {
          _onlineClassroomsCache[effectiveCode] = parsed;
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('[BstCloudService] Presence query error ($effectiveCode): $e');
    }

    // 3. Fallback to cache if available
    if (_onlineClassroomsCache.containsKey(effectiveCode) &&
        _onlineClassroomsCache[effectiveCode]!.isNotEmpty) {
      return _onlineClassroomsCache[effectiveCode]!;
    }

    // 4. Fallback to standard resilient classroom list
    final defaultList = getDefaultClassrooms();
    _onlineClassroomsCache[effectiveCode] = defaultList;
    return defaultList;
  }

  List<String> _extractClassroomList(dynamic data) {
    final list = <String>[];
    if (data is Map) {
      data.forEach((key, val) {
        if (val is Map) {
          final name = val['name'] as String? ?? val['classroomName'] as String? ?? key.toString();
          final isOnline = val['online'] as bool? ?? val['isOnline'] as bool? ?? true;
          if (isOnline && name.isNotEmpty && !list.contains(name)) {
            list.add(name);
          }
        } else if (val == true || val == 1 || val == 'online') {
          final roomKey = key.toString();
          if (!list.contains(roomKey)) list.add(roomKey);
        } else if (val is String && val.isNotEmpty) {
          if (!list.contains(val)) list.add(val);
        }
      });
    } else if (data is List) {
      for (final item in data) {
        if (item is String && item.isNotEmpty && !list.contains(item)) {
          list.add(item);
        } else if (item is Map) {
          final name = item['name'] as String? ?? item['classroomName'] as String?;
          if (name != null && name.isNotEmpty && !list.contains(name)) {
            list.add(name);
          }
        }
      }
    }
    return list;
  }

  // ---------------------------------------------------------------------------
  // Mission 1: Approve Connection Request
  // ---------------------------------------------------------------------------

  /// Creates and registers a local pairing request
  PairingRequest createPairingRequest({
    required String requestId,
    required String classroomName,
    required String schoolCode,
    String? teacherName,
    String? otpCode,
  }) {
    final request = PairingRequest(
      requestId: requestId,
      classroomName: classroomName,
      schoolCode: schoolCode,
      teacherName: teacherName,
      otpCode: otpCode,
      status: PairingStatus.pending,
    );
    _pairingRequests[requestId] = request;
    saveSyncState('pairing_request_$requestId', request.toJson());
    return request;
  }

  PairingRequest? getPairingRequest(String requestId) => _pairingRequests[requestId];
  List<PairingRequest> getPendingRequests() =>
      _pairingRequests.values.where((r) => r.isPending).toList();

  /// Approve pending pairing requests and set status to connected.
  /// Also pushes approval updates to RTDB and Firestore REST endpoints.
  Future<bool> approveConnectionRequest(
    String requestId, {
    String? teacherName,
    String? classroomName,
    String? token,
    String? folderId,
    int durationHours = 1,
    String status = 'connected',
  }) async {
    if (requestId.trim().isEmpty) return false;

    final resolvedTeacher = teacherName ?? '선생님';
    final resolvedClassroom = classroomName ?? requestId;
    final expiresAt = DateTime.now().add(Duration(hours: durationHours));
    final resolvedToken = token ?? 'token_$requestId';
    final resolvedFolder = folderId ?? 'folder_$requestId';
    final now = DateTime.now().toUtc();

    // 1. Update in-memory pairing request
    final existing = _pairingRequests[requestId];
    final updated = existing != null
        ? existing.copyWith(
            status: PairingStatus.connected,
            token: resolvedToken,
            folderId: resolvedFolder,
            expiresAt: expiresAt,
            approvedAt: now,
            teacherName: teacherName ?? existing.teacherName,
          )
        : PairingRequest(
            requestId: requestId,
            schoolCode: 'default',
            classroomName: resolvedClassroom,
            teacherName: resolvedTeacher,
            status: PairingStatus.connected,
            token: resolvedToken,
            folderId: resolvedFolder,
            expiresAt: expiresAt,
            approvedAt: now,
          );

    _pairingRequests[requestId] = updated;

    // 2. Notify sync state listeners
    saveSyncState('pairing_status_$requestId', status);
    saveSyncState('latest_approved_request', requestId);
    saveSyncState('pairing_request_$requestId', updated.toJson());

    // 3. Dispatch remote approval to RTDB
    try {
      final rtdbUrl = Uri.parse('$_rtdbBaseUrl/pairing_requests/$requestId.json');
      final rtdbBody = {
        'status': status,
        'requestId': requestId,
        'classroomName': resolvedClassroom,
        'teacherName': resolvedTeacher,
        'token': resolvedToken,
        'folderId': resolvedFolder,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'approvedAt': now.toIso8601String(),
      };

      await _client
          .patch(
            rtdbUrl,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(rtdbBody),
          )
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[BstCloudService] RTDB approveConnectionRequest warning: $e');
    }

    // 4. Dispatch remote approval to Firestore cloud_connections collection
    try {
      final docId = Uri.encodeComponent(resolvedTeacher);
      final classId = Uri.encodeComponent(resolvedClassroom);
      final firestoreUrl = Uri.parse('$_firestoreBaseUrl/cloud_connections/$docId/requests/$classId');

      final firestoreBody = {
        'fields': {
          'status': {'stringValue': status},
          'token': {'stringValue': resolvedToken},
          'folderId': {'stringValue': resolvedFolder},
          'expiresAt': {'stringValue': expiresAt.toUtc().toIso8601String()},
          'timestamp': {'timestampValue': now.toIso8601String()},
        }
      };

      await _client
          .patch(
            firestoreUrl,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(firestoreBody),
          )
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[BstCloudService] Firestore approveConnectionRequest warning: $e');
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Mission 2: Google Drive OAuth Token Exchange
  // ---------------------------------------------------------------------------

  /// Exchanges a Google OAuth 2.0 refresh token for a fresh access token
  Future<OAuthTokenResult> exchangeRefreshToken({
    required String refreshToken,
    String? clientId,
    String? clientSecret,
    String? tokenEndpoint,
  }) async {
    if (refreshToken.trim().isEmpty) {
      return OAuthTokenResult.failure('Refresh token cannot be empty');
    }

    final endpoint = Uri.parse(tokenEndpoint ?? 'https://oauth2.googleapis.com/token');

    final body = {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      if (clientId != null && clientId.isNotEmpty) 'client_id': clientId,
      if (clientSecret != null && clientSecret.isNotEmpty) 'client_secret': clientSecret,
    };

    try {
      final response = await _client.post(
        endpoint,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final accessToken = data['access_token'] as String?;
        final expiresIn = data['expires_in'] as int?;
        final tokenType = data['token_type'] as String?;

        if (accessToken != null && accessToken.isNotEmpty) {
          return OAuthTokenResult.success(
            accessToken: accessToken,
            expiresIn: expiresIn,
            tokenType: tokenType,
          );
        } else {
          return OAuthTokenResult.failure('access_token missing in OAuth response');
        }
      } else {
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errData = json.decode(response.body);
          if (errData is Map && errData['error'] != null) {
            errorMsg = '${errData['error']}: ${errData['error_description'] ?? ''}';
          }
        } catch (_) {}
        return OAuthTokenResult.failure(errorMsg);
      }
    } catch (e) {
      return OAuthTokenResult.failure('OAuth token exchange error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Mission 2: DriveCast Board Pairing Protocol
  // ---------------------------------------------------------------------------

  /// Generates a standard 6-digit pairing OTP
  String generatePairingOtp([int length = 6]) {
    final random = Random.secure();
    final max = pow(10, length).toInt();
    final num = random.nextInt(max);
    return num.toString().padLeft(length, '0');
  }

  /// Verifies a 6-digit pairing OTP
  bool verifyPairingOtp(String inputOtp, String expectedOtp) {
    final cleanInput = inputOtp.trim();
    final cleanExpected = expectedOtp.trim();
    if (cleanInput.isEmpty || cleanExpected.isEmpty) return false;
    if (cleanInput.length != cleanExpected.length) return false;
    if (!RegExp(r'^\d+$').hasMatch(cleanInput)) return false;
    return cleanInput == cleanExpected;
  }

  /// Formats the standard DriveCast QR code payload URI
  String generateDriveCastQrPayload({
    required String requestId,
    required String schoolCode,
    required String classroomName,
    required String otpCode,
    String scheme = 'boardest',
    String host = 'drivecast',
  }) {
    final uri = Uri(
      scheme: scheme,
      host: host,
      queryParameters: {
        'requestId': requestId,
        'school': schoolCode,
        'room': classroomName,
        'otp': otpCode,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    return uri.toString();
  }

  /// Parses and validates a DriveCast QR code payload URI
  Map<String, String>? parseDriveCastQrPayload(String qrPayload) {
    try {
      final uri = Uri.parse(qrPayload.trim());
      if (uri.scheme != 'boardest') return null;
      if (uri.host != 'drivecast' && uri.path != '/drivecast') return null;

      final requestId = uri.queryParameters['requestId'];
      final school = uri.queryParameters['school'];
      final room = uri.queryParameters['room'];
      final otp = uri.queryParameters['otp'];

      if (requestId == null || requestId.isEmpty) return null;

      return {
        'requestId': requestId,
        'school': school ?? 'default',
        'room': room ?? '',
        'otp': otp ?? '',
        'timestamp': uri.queryParameters['t'] ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    for (final notifier in _syncStateNotifiers.values) {
      notifier.dispose();
    }
    _syncStateNotifiers.clear();
    _syncStateStore.clear();
    _pairingRequests.clear();
    _onlineClassroomsCache.clear();
  }
}
