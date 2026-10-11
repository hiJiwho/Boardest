import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;
import 'dart:js' show allowInterop;

class PasskeyNativeHelper {
  static Future<bool> triggerSystemPasskey({
    required String email,
    required String displayName,
  }) async {
    try {
      final func = js.context['triggerNativePasskeyCreate'];
      if (func != null) {
        final completer = Completer<bool>();
        final promise = js.context.callMethod('triggerNativePasskeyCreate', [email, displayName]);
        promise.callMethod('then', [
          allowInterop((result) {
            completer.complete(result == true);
          }),
          allowInterop((error) {
            completer.complete(false);
          }),
        ]);
        return await completer.future.timeout(const Duration(seconds: 40), onTimeout: () => false);
      }
    } catch (_) {}
    return false;
  }

  static Future<({bool success, String? email, String? id})> triggerSystemPasskeyGet() async {
    try {
      final func = js.context['triggerNativePasskeyGet'];
      if (func != null) {
        final completer = Completer<({bool success, String? email, String? id})>();
        final promise = js.context.callMethod('triggerNativePasskeyGet', []);
        promise.callMethod('then', [
          allowInterop((result) {
            if (result != null) {
              try {
                final jsonStr = result.toString();
                final parsed = jsonDecode(jsonStr);
                completer.complete((
                  success: parsed['success'] == true,
                  email: parsed['email'] as String?,
                  id: parsed['id'] as String?,
                ));
              } catch (_) {
                completer.complete((success: true, email: null, id: null));
              }
            } else {
              completer.complete((success: false, email: null, id: null));
            }
          }),
          allowInterop((error) {
            completer.complete((success: false, email: null, id: null));
          }),
        ]);
        return await completer.future.timeout(const Duration(seconds: 40), onTimeout: () => (success: false, email: null, id: null));
      }
    } catch (_) {}
    return (success: false, email: null, id: null);
  }
}
