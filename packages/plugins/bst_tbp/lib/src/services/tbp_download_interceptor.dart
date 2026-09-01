import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'tbp_storage_service.dart';

/// 전자저작물 다운로드 가로채기 & 판서 보존 뷰어 연동 서비스
class TbpDownloadInterceptor {
  static final TbpDownloadInterceptor instance = TbpDownloadInterceptor._internal();
  TbpDownloadInterceptor._internal();

  /// 플러그인 레벨에서 앱의 전용 뷰어(PDF/PPT/HWP)를 연결할 수 있는 커스텀 오프너 콜백
  void Function(BuildContext context, String filePath, double scaleFactor)? customViewerOpener;

  /// 다운로드 가로채기 핸들러
  Future<void> handleDownload({
    required BuildContext context,
    required String tbpFolderPath,
    required String currentDhash,
    required String downloadUrl,
    required String filename,
    required double scaleFactor,
  }) async {
    final hasExisting = await TbpStorageService.instance.checkExistingDownload(
      tbpFolderPath,
      currentDhash,
      filename,
    );

    final fileExt = p.extension(filename).toLowerCase();
    final isSupportedExt = ['.pdf', '.ppt', '.pptx', '.hwp', '.mp4', '.avi', '.png', '.jpg', '.jpeg'].contains(fileExt);

    if (hasExisting) {
      // 기존 파일 존재 시 다운로드 거부 및 기존 판서 보존 열기
      final localFilePath = p.join(tbpFolderPath, 'Downloads', currentDhash, filename);
      openSupportedViewer(context: context, filePath: localFilePath, scaleFactor: scaleFactor);
    } else if (isSupportedExt) {
      // 지원되는 확장자는 USB 내 Downloads/{dHash}/ 로 다운로드 및 뷰어 열기
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(downloadUrl));
        final res = await req.close();

        final saveDir = Directory(p.join(tbpFolderPath, 'Downloads', currentDhash));
        if (!await saveDir.exists()) await saveDir.create(recursive: true);

        final saveFile = File(p.join(saveDir.path, filename));
        final bytes = await res.fold<List<int>>([], (p, e) => p..addAll(e));
        await saveFile.writeAsBytes(bytes);

        openSupportedViewer(context: context, filePath: saveFile.path, scaleFactor: scaleFactor);
      } catch (e) {
        debugPrint('[TbpDownloadInterceptor] Intercept error: $e');
      } finally {
        client.close();
      }
    } else {
      // 기타 미지원 확장자는 브라우저 전달
      try {
        await launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  /// 지원 뷰어로 열기
  void openSupportedViewer({
    required BuildContext context,
    required String filePath,
    required double scaleFactor,
  }) {
    if (customViewerOpener != null) {
      customViewerOpener!(context, filePath, scaleFactor);
      return;
    }
    try {
      launchUrl(Uri.file(filePath));
    } catch (e) {
      debugPrint('[TbpDownloadInterceptor] Open viewer error: $e');
    }
  }
}
