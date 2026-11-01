import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bst_cloud/bst_cloud.dart';



void main() {
  group('CloudFile Model Tests', () {
    test('CloudFile serialization and deserialization', () {
      final now = DateTime.utc(2026, 8, 21, 12, 0, 0);
      final file = CloudFile(
        id: 'file_123',
        name: 'Lesson1.tbp',
        mimeType: 'application/octet-stream',
        size: 10240,
        modifiedTime: now,
        downloadUrl: 'https://drive.google.com/download/file_123',
        thumbnailUrl: 'https://drive.google.com/thumbnail/file_123',
      );

      expect(file.isTbp, isTrue);
      expect(file.isPdf, isFalse);
      expect(file.isFolder, isFalse);

      final json = file.toJson();
      expect(json['id'], 'file_123');
      expect(json['name'], 'Lesson1.tbp');
      expect(json['size'], 10240);

      final restored = CloudFile.fromJson(json);
      expect(restored.id, 'file_123');
      expect(restored.name, 'Lesson1.tbp');
      expect(restored.size, 10240);
      expect(restored.modifiedTime, now);
      expect(restored.downloadUrl, contains('file_123'));
      expect(restored.thumbnailUrl, contains('file_123'));
    });

    test('CloudFile mime type detection for PDF and Folder', () {
      final pdfFile = CloudFile(
        id: 'pdf_1',
        name: 'syllabus.pdf',
        mimeType: 'application/pdf',
        size: 500,
        modifiedTime: DateTime.now(),
      );
      expect(pdfFile.isPdf, isTrue);
      expect(pdfFile.isTbp, isFalse);

      final folder = CloudFile(
        id: 'folder_1',
        name: 'Curriculum',
        mimeType: 'application/vnd.google-apps.folder',
        size: 0,
        modifiedTime: DateTime.now(),
      );
      expect(folder.isFolder, isTrue);
    });
  });

  group('CloudDriveService Tests', () {
    test('CloudDriveService manages cached files and sync status lifecycle', () async {
      final service = CloudDriveService();
      expect(service.status, equals(CloudSyncStatus.idle));
      expect(service.cachedFiles, isEmpty);

      final file1 = CloudFile(
        id: '1',
        name: 'math.tbp',
        mimeType: 'application/octet-stream',
        size: 200,
        modifiedTime: DateTime.now(),
      );
      final file2 = CloudFile(
        id: '2',
        name: 'science.tbp',
        mimeType: 'application/octet-stream',
        size: 400,
        modifiedTime: DateTime.now(),
      );

      service.setFiles([file1]);
      expect(service.cachedFiles.length, 1);

      service.addFile(file2);
      expect(service.cachedFiles.length, 2);

      service.removeFile('1');
      expect(service.cachedFiles.length, 1);
      expect(service.cachedFiles.first.id, '2');

      final statuses = <CloudSyncStatus>[];
      final sub = service.statusStream.listen(statuses.add);

      await service.syncFiles();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(service.status, equals(CloudSyncStatus.completed));
      expect(statuses, containsAll([CloudSyncStatus.syncing, CloudSyncStatus.completed]));

      await sub.cancel();
      service.dispose();
    });
  });

  group('DriveCastViewer Widget Test', () {
    testWidgets('DriveCastViewer renders correctly', (tester) async {
      await tester.pumpWidget(
        const TestAppWrapper(child: DriveCastViewer()),
      );
      expect(find.text('DriveCast Viewer'), findsOneWidget);
    });
  });

  group('BstCloudService Online Classrooms & Presence Tests', () {
    test('getOnlineClassrooms extracts classrooms from remote RTDB query', () async {
      final mockClient = MockBstHttpClient((request) async {
        if (request.url.path.contains('/schools/ydm/classrooms.json')) {
          return http.Response.bytes(
            utf8.encode('{"1-1": {"name": "1학년 1반", "online": true}, "1-2": {"name": "1학년 2반", "online": true}}'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('null', 404);
      });

      final service = BstCloudService(httpClient: mockClient);
      final classrooms = await service.getOnlineClassrooms('ydm');

      expect(classrooms, containsAll(['1학년 1반', '1학년 2반']));
      expect(classrooms.length, equals(2));
      service.dispose();
    });

    test('getOnlineClassrooms falls back to active RTDB presence node when classrooms node is empty', () async {
      final mockClient = MockBstHttpClient((request) async {
        if (request.url.path.contains('/schools/demo/classrooms.json')) {
          return http.Response('null', 200);
        }
        if (request.url.path.contains('/presence/demo.json')) {
          return http.Response.bytes(
            utf8.encode('{"2학년 3반": true, "3학년 1반": true}'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('null', 404);
      });

      final service = BstCloudService(httpClient: mockClient);
      final classrooms = await service.getOnlineClassrooms('demo');

      expect(classrooms, containsAll(['2학년 3반', '3학년 1반']));
      service.dispose();
    });

    test('getOnlineClassrooms falls back to default classrooms on error or offline', () async {
      final mockClient = MockBstHttpClient((request) async {
        throw Exception('Network disconnected');
      });

      final service = BstCloudService(httpClient: mockClient);
      final classrooms = await service.getOnlineClassrooms('unknown_school');

      expect(classrooms, contains('1학년 1반'));
      expect(classrooms, contains('3학년 8반'));
      expect(classrooms, contains('과학실'));
      expect(classrooms.length, equals(30)); // 3*8 = 24 + 6 special = 30
      service.dispose();
    });

    test('normalizeSchoolCode standardizes school identifiers', () {
      expect(BstCloudService.normalizeSchoolCode(' 양동중학교 '), equals('ydm'));
      expect(BstCloudService.normalizeSchoolCode('48588'), equals('ydm'));
      expect(BstCloudService.normalizeSchoolCode('demo'), equals('demo'));
      expect(BstCloudService.normalizeSchoolCode(''), equals('default'));
      expect(BstCloudService.normalizeSchoolCode(null), equals('default'));
    });
  });

  group('BstCloudService Connection Approval Tests', () {
    test('approveConnectionRequest transitions pending request to connected status', () async {
      String? patchedRtdbBody;
      String? patchedFirestoreBody;

      final mockClient = MockBstHttpClient((request) async {
        if (request.url.path.contains('/pairing_requests/')) {
          patchedRtdbBody = request.body;
          return http.Response('{"status": "ok"}', 200);
        }
        if (request.url.path.contains('/cloud_connections/')) {
          patchedFirestoreBody = request.body;
          return http.Response('{"status": "ok"}', 200);
        }
        return http.Response('null', 404);
      });

      final service = BstCloudService(httpClient: mockClient);

      // Create a pending request
      final created = service.createPairingRequest(
        requestId: 'req_001',
        classroomName: '1학년 3반',
        schoolCode: 'ydm',
        teacherName: '박선생님',
        otpCode: '123456',
      );
      expect(created.isPending, isTrue);
      expect(service.getPendingRequests().length, equals(1));

      // Approve request
      final success = await service.approveConnectionRequest(
        'req_001',
        teacherName: '박선생님',
        classroomName: '1학년 3반',
        token: 'token_secret_xyz',
        folderId: 'folder_drive_789',
        durationHours: 2,
        status: 'connected',
      );

      expect(success, isTrue);

      final updated = service.getPairingRequest('req_001');
      expect(updated, isNotNull);
      expect(updated!.isConnected, isTrue);
      expect(updated.status, equals(PairingStatus.connected));
      expect(updated.token, equals('token_secret_xyz'));
      expect(updated.folderId, equals('folder_drive_789'));
      expect(updated.approvedAt, isNotNull);

      // Verify sync state
      expect(service.getSyncState('pairing_status_req_001'), equals('connected'));
      expect(service.getSyncState('latest_approved_request'), equals('req_001'));

      // Verify remote payloads
      expect(patchedRtdbBody, isNotNull);
      expect(patchedRtdbBody, contains('token_secret_xyz'));
      expect(patchedRtdbBody, contains('connected'));

      expect(patchedFirestoreBody, isNotNull);
      expect(patchedFirestoreBody, contains('connected'));

      service.dispose();
    });

    test('approveConnectionRequest handles empty requestId gracefully', () async {
      final service = BstCloudService();
      final result = await service.approveConnectionRequest('   ');
      expect(result, isFalse);
      service.dispose();
    });
  });

  group('Google Drive OAuth Token Exchange Tests', () {
    test('exchangeRefreshToken succeeds and returns access token on 200 response', () async {
      final mockClient = MockBstHttpClient((request) async {
        if (request.url.path.contains('/token')) {
          expect(request.bodyFields['grant_type'], equals('refresh_token'));
          expect(request.bodyFields['refresh_token'], equals('1//refresh_token_valid'));
          return http.Response(
            '{"access_token": "ya29.mock_access_token_abc", "expires_in": 3600, "token_type": "Bearer"}',
            200,
          );
        }
        return http.Response('null', 404);
      });

      final service = BstCloudService(httpClient: mockClient);
      final result = await service.exchangeRefreshToken(
        refreshToken: '1//refresh_token_valid',
        clientId: 'mock_client_id.apps.googleusercontent.com',
        clientSecret: 'mock_client_secret',
      );

      expect(result.success, isTrue);
      expect(result.accessToken, equals('ya29.mock_access_token_abc'));
      expect(result.expiresIn, equals(3600));
      expect(result.tokenType, equals('Bearer'));
      expect(result.error, isNull);
      service.dispose();
    });

    test('exchangeRefreshToken handles empty refresh token error', () async {
      final service = BstCloudService();
      final result = await service.exchangeRefreshToken(refreshToken: '  ');
      expect(result.success, isFalse);
      expect(result.error, contains('cannot be empty'));
      service.dispose();
    });

    test('exchangeRefreshToken handles OAuth error response', () async {
      final mockClient = MockBstHttpClient((request) async {
        return http.Response(
          '{"error": "invalid_grant", "error_description": "Token has been expired or revoked."}',
          400,
        );
      });

      final service = BstCloudService(httpClient: mockClient);
      final result = await service.exchangeRefreshToken(
        refreshToken: 'revoked_token',
      );

      expect(result.success, isFalse);
      expect(result.error, contains('invalid_grant'));
      service.dispose();
    });
  });

  group('DriveCast Board Pairing Protocol Tests', () {
    test('generatePairingOtp produces valid 6-digit OTP', () {
      final service = BstCloudService();
      for (int i = 0; i < 10; i++) {
        final otp = service.generatePairingOtp(6);
        expect(otp.length, equals(6));
        expect(RegExp(r'^\d{6}$').hasMatch(otp), isTrue);
      }
      service.dispose();
    });

    test('verifyPairingOtp accurately compares OTP codes', () {
      final service = BstCloudService();
      expect(service.verifyPairingOtp('123456', '123456'), isTrue);
      expect(service.verifyPairingOtp(' 123456 ', '123456'), isTrue);
      expect(service.verifyPairingOtp('123456', '654321'), isFalse);
      expect(service.verifyPairingOtp('abc123', 'abc123'), isFalse); // Non-digit
      expect(service.verifyPairingOtp('123', '123456'), isFalse);
      service.dispose();
    });

    test('generateDriveCastQrPayload and parseDriveCastQrPayload roundtrip correctly', () {
      final service = BstCloudService();
      final qrString = service.generateDriveCastQrPayload(
        requestId: 'pair_req_99',
        schoolCode: 'ydm',
        classroomName: '2학년 4반',
        otpCode: '852963',
      );

      expect(qrString, startsWith('boardest://drivecast?'));

      final parsed = service.parseDriveCastQrPayload(qrString);
      expect(parsed, isNotNull);
      expect(parsed!['requestId'], equals('pair_req_99'));
      expect(parsed['school'], equals('ydm'));
      expect(parsed['room'], equals('2학년 4반'));
      expect(parsed['otp'], equals('852963'));

      // Malformed payloads reject cleanly
      expect(service.parseDriveCastQrPayload('https://example.com'), isNull);
      expect(service.parseDriveCastQrPayload('boardest://other?foo=bar'), isNull);
      expect(service.parseDriveCastQrPayload('not-a-url'), isNull);

      service.dispose();
    });

    test('PairingRequest model serialization and state properties', () {
      final now = DateTime.utc(2026, 11, 1, 12, 0, 0);
      final req = PairingRequest(
        requestId: 'r1',
        schoolCode: 'ydm',
        classroomName: '1-1',
        teacherName: '김선생님',
        status: PairingStatus.connected,
        token: 'tok123',
        folderId: 'fld123',
        otpCode: '456789',
        expiresAt: now.add(const Duration(hours: 2)),
        createdAt: now,
        approvedAt: now,
      );

      expect(req.isConnected, isTrue);
      expect(req.isPending, isFalse);

      final json = req.toJson();
      expect(json['requestId'], equals('r1'));
      expect(json['status'], equals('connected'));

      final restored = PairingRequest.fromJson(json);
      expect(restored.requestId, equals('r1'));
      expect(restored.status, equals(PairingStatus.connected));
      expect(restored.teacherName, equals('김선생님'));
      expect(restored.token, equals('tok123'));
    });
  });
}

class TestAppWrapper extends StatelessWidget {
  final Widget child;
  const TestAppWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: child,
    );
  }
}

class MockBstHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) _handler;

  MockBstHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      final response = await _handler(request);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }
    throw UnimplementedError();
  }
}

