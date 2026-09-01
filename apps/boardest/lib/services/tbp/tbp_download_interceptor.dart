import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'tbp_storage_service.dart';
import '../../views/pdf_board_view.dart';
import '../../views/ppt_overlay_view.dart';
import '../../views/hwp_overlay_view.dart';

/// 전자저작물 다운로드 가로채기 & 판서 보존 뷰어 연동 서비스
class TbpDownloadInterceptor {
  static final TbpDownloadInterceptor instance = TbpDownloadInterceptor._internal();
  TbpDownloadInterceptor._internal();

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
      final localFilePath = p.join(tbpFolderPath, 'Downloads', currentDhash, filename);
      openSupportedViewer(context: context, filePath: localFilePath, scaleFactor: scaleFactor);
    } else if (isSupportedExt) {
      try {
        final client = HttpClient();
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
      }
    } else {
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
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.pdf') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfBoardView(initialFilePath: filePath, scaleFactor: scaleFactor)));
    } else if (ext == '.pptx' || ext == '.ppt') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PptOverlayView(initialFilePath: filePath, scaleFactor: scaleFactor)));
    } else if (ext == '.hwp') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => HwpOverlayView(initialFilePath: filePath, scaleFactor: scaleFactor)));
    }
  }
}
