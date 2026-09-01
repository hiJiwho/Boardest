import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';

class FcmTokenService {
  /// Stores the FCM token under a Firestore document keyed by the schoolId.
  /// The token is saved to Firestore via the REST API.
  static Future<void> storeToken(String token, String schoolId) async {
    try {
      final docPath = 'fcm_tokens/$schoolId';
      final url = '${AppConfig.firestoreBase}/$docPath?key=${AppConfig.firebaseApiKey}';
      final payload = {
        'fields': {
          'token': {'stringValue': token},
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      };
      await http.patch(Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(payload));
    } catch (e) {
      debugPrint('[FcmTokenService] Failed to store token: $e');
    }
  }
}
