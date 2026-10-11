class PasskeyNativeHelper {
  static Future<bool> triggerSystemPasskey({
    required String email,
    required String displayName,
  }) async {
    return false;
  }

  static Future<({bool success, String? email, String? id})> triggerSystemPasskeyGet() async {
    return (success: false, email: null, id: null);
  }
}
