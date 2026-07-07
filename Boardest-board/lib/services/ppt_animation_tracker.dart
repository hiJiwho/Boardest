import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;

class PptAnimationTrackerService {
  // PPT 파일 경로
  String? _pptFilePath;
  int _currentPageIndex = 0;
  int _totalPages = 0;
  bool _isAnimationPlaying = false;
  List<int> _pagesWithAnimations = [];

  /// PPT 파일 로드 및 메타데이터 읽기
  Future<bool> loadPptFile(String pptPath) async {
    try {
      _pptFilePath = pptPath;
      final file = File(pptPath);
      
      if (!await file.exists()) {
        print('PPT 파일을 찾을 수 없음: $pptPath');
        return false;
      }

      // PPT 파일 구조 분석 (Office Open XML)
      // .pptx는 ZIP 형식이므로 압축 해제하여 분석 가능
      await _analyzePptStructure(pptPath);
      return true;
    } catch (e) {
      print('PPT 파일 로드 오류: $e');
      return false;
    }
  }

  /// PPTX 파일 구조 분석
  Future<void> _analyzePptStructure(String pptPath) async {
    try {
      // PPTX는 ZIP 형식
      final bytes = await File(pptPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // slide1.xml, slide2.xml 등의 파일 찾기
      int slideCount = 0;
      final slideFiles = <String, List<int>>{};
      
      for (final file in archive) {
        final name = file.name;
        // ppt/slides/slide*.xml 패턴 찾기
        if (name.startsWith('ppt/slides/slide') && name.endsWith('.xml')) {
          slideFiles[name] = file.content as List<int>;
          slideCount++;
        }
      }
      
      _totalPages = slideCount;
      _pagesWithAnimations = [];
      
      // 각 슬라이드에서 애니메이션 정보 추출
      for (int i = 0; i < slideCount; i++) {
        final slideKey = 'ppt/slides/slide${i + 1}.xml';
        if (slideFiles.containsKey(slideKey)) {
          final slideXml = String.fromCharCodes(slideFiles[slideKey]!);
          if (_hasAnimationsInSlide(slideXml)) {
            _pagesWithAnimations.add(i);
          }
        }
      }
      
      print('PPT 로드 완료: $_totalPages 페이지, 애니메이션 있는 페이지: $_pagesWithAnimations');
    } catch (e) {
      print('PPTX 구조 분석 오류: $e');
      _totalPages = 0;
      _pagesWithAnimations = [];
    }
  }

  /// 슬라이드에 애니메이션이 있는지 확인
  bool _hasAnimationsInSlide(String slideXml) {
    try {
      final document = xml.XmlDocument.parse(slideXml);
      
      // <p:timing> 요소 검색
      final timingElements = document.findAllElements('p:timing');
      if (timingElements.isNotEmpty) {
        return true;
      }
      
      // <p:animEffect>, <p:animMotion> 등도 확인
      final animElements = document.findAllElements('p:animEffect');
      if (animElements.isNotEmpty) return true;
      
      final motionElements = document.findAllElements('p:animMotion');
      if (motionElements.isNotEmpty) return true;
      
      return false;
    } catch (e) {
      print('슬라이드 XML 파싱 오류: $e');
      return false;
    }
  }

  /// 현재 페이지 번호 반환
  int get currentPageIndex => _currentPageIndex;

  /// 전체 페이지 수 반환
  int get totalPages => _totalPages;

  /// 현재 페이지에 애니메이션이 있는지 확인
  bool hasAnimationOnCurrentPage() {
    return _pagesWithAnimations.contains(_currentPageIndex);
  }

  /// 애니메이션 재생 중 여부
  bool get isAnimationPlaying => _isAnimationPlaying;

  /// 애니메이션 시작
  void startAnimation() {
    _isAnimationPlaying = true;
    print('애니메이션 재생 시작 - 페이지 $_currentPageIndex');
  }

  /// 애니메이션 종료
  void endAnimation() {
    _isAnimationPlaying = false;
    print('애니메이션 재생 종료 - 페이지 $_currentPageIndex');
  }

  /// 다음 페이지로 이동
  /// 애니메이션 재생 중이면 false 반환 (페이지 이동 방지)
  bool nextPage() {
    if (_isAnimationPlaying && hasAnimationOnCurrentPage()) {
      print('애니메이션 재생 중이므로 페이지 이동 불가');
      return false;
    }

    if (_currentPageIndex < _totalPages - 1) {
      _currentPageIndex++;
      print('페이지 이동: ${_currentPageIndex + 1} / $_totalPages');
      
      // 새 페이지에 애니메이션이 있으면 알림
      if (hasAnimationOnCurrentPage()) {
        print('이 페이지에 애니메이션 있음');
      }
      return true;
    }
    return false;
  }

  /// 이전 페이지로 이동
  bool previousPage() {
    if (_isAnimationPlaying) {
      print('애니메이션 재생 중이므로 페이지 이동 불가');
      return false;
    }

    if (_currentPageIndex > 0) {
      _currentPageIndex--;
      print('페이지 이동: ${_currentPageIndex + 1} / $_totalPages');
      return true;
    }
    return false;
  }

  /// 특정 페이지로 이동
  bool goToPage(int pageIndex) {
    if (_isAnimationPlaying) {
      print('애니메이션 재생 중이므로 페이지 이동 불가');
      return false;
    }

    if (pageIndex >= 0 && pageIndex < _totalPages) {
      _currentPageIndex = pageIndex;
      print('페이지 이동: ${_currentPageIndex + 1} / $_totalPages');
      return true;
    }
    return false;
  }

  /// 애니메이션 목록 조회
  List<int> getPagesWithAnimations() {
    return List.from(_pagesWithAnimations);
  }

  /// 리셋
  void reset() {
    _currentPageIndex = 0;
    _totalPages = 0;
    _isAnimationPlaying = false;
    _pagesWithAnimations = [];
    _pptFilePath = null;
  }
}
