import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/annotation_canvas.dart';

class PdfAnnotatorService {
  /// PDF 파일의 페이지 총 개수 반환
  static Future<int> getPdfPageCount(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return 0;
      
      // PDF 페이지 수를 구하는 간단한 방식
      // 실제 pdf 라이브러리로는 페이지 렌더링만 지원하므로
      // 외부 도구나 캐싱으로 처리
      return 1; // 기본값, 별도 처리 필요
    } catch (e) {
      print('Error getting PDF page count: $e');
      return 0;
    }
  }

  /// 선택한 PDF 파일 경로 반환
  static Future<String?> pickPdfFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        return result.files.first.path;
      }
      return null;
    } catch (e) {
      print('Error picking PDF: $e');
      return null;
    }
  }

  /// 주석이 있는 PDF 저장
  static Future<String?> savePdfWithAnnotations(
    String originalPdfPath,
    List<List<AnnotationStroke>> pageAnnotations,
  ) async {
    try {
      final outputDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${outputDir.path}/annotated_$timestamp.pdf';

      // 기본 PDF 생성
      final pdf = pw.Document();

      // 원본 PDF와 주석을 합치는 로직
      // 페이지별로 처리
      for (int i = 0; i < pageAnnotations.length; i++) {
        final strokes = pageAnnotations[i];
        
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Stack(
                children: [
                  // 원본 PDF 페이지 (여기서는 이미지로 렌더링된 것으로 가정)
                  pw.Container(),
                  // 주석 렌더링
                  _buildAnnotationLayer(strokes),
                ],
              );
            },
          ),
        );
      }

      final file = File(outputPath);
      await file.writeAsBytes(await pdf.save());
      print('PDF saved to $outputPath');
      return outputPath;
    } catch (e) {
      print('Error saving PDF: $e');
      return null;
    }
  }

  /// 주석 레이어 생성
  static pw.Widget _buildAnnotationLayer(List<AnnotationStroke> strokes) {
    return pw.Container(
      // 주석 스트로크를 PDF에 렌더링
      // 각 스트로크는 선으로 표현
      child: pw.Stack(
        children: strokes.map((stroke) {
          if (stroke.isEraser) {
            return pw.SizedBox.shrink();
          }
          return pw.Container(
            // 스트로크 렌더링 로직
          );
        }).toList(),
      ),
    );
  }

  /// PDF 페이지를 이미지로 렌더링 (외부 도구 필요)
  static Future<Uint8List?> renderPdfPage(String pdfPath, int pageNumber) async {
    try {
      // pdf 라이브러리는 렌더링을 직접 지원하지 않으므로
      // 외부 PDF 렌더링 서비스나 네이티브 코드 필요
      // 여기서는 플레이스홀더
      return null;
    } catch (e) {
      print('Error rendering PDF page: $e');
      return null;
    }
  }
}
