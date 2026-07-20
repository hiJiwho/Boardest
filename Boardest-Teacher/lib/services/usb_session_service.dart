import 'package:flutter/foundation.dart';

class UsbSessionService {
  static final UsbSessionService instance = UsbSessionService._();
  UsbSessionService._();

  Future<void> updateFileState(
    String sessionId,
    String filePath,
    int page,
    int totalPages,
  ) async {
    debugPrint('[UsbSessionService stub] updateFileState: $filePath (page: $page/$totalPages)');
  }
}
