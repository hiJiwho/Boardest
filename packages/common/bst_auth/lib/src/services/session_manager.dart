import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

class SessionManager {
  Timer? _sessionTimer;
  final Duration sessionTimeout = const Duration(hours: 1);

  void startSession() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(sessionTimeout, _onSessionExpired);
  }

  void _onSessionExpired() {
    print('Session expired. Logging out...');
    FirebaseAuth.instance.signOut();
  }

  void resetSession() {
    startSession();
  }

  void dispose() {
    _sessionTimer?.cancel();
  }
}
