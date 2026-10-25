import 'package:flutter/material.dart';

class TbpCrxBridge {
  TbpCrxBridge._();
  static final TbpCrxBridge instance = TbpCrxBridge._();

  Future<bool> checkExtensionInstalled() async => false;

  Future<bool> launchBoardBookExtension({
    required BuildContext context,
    required String title,
    required String fileUrl,
    required String type,
    String? driveToken,
    String? pointerId,
  }) async => false;
}
