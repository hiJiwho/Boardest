import '../lib/services/comcigan_service.dart';

void main() async {
  final service = ComciganService();
  try {
    print('양동중학교 (44134) 시간표 데이터 조회 중...');
    final raw = await service.fetchTimetableRaw(44134);
    print('성공적으로 raw 가져옴!');
    final result = service.parseTimetable(raw);
    print('성공적으로 parse 완료! 학교명: ${result.schoolName}');
    print('학급 수: ${result.classCounts}');
    if (result.lessons.isNotEmpty) {
      print('첫 번째 수업: ${result.lessons.first.subject} (${result.lessons.first.teacher})');
    } else {
      print('수업 정보 없음');
    }
  } catch (e) {
    print('❌ 에러 발생: $e');
  }
}
