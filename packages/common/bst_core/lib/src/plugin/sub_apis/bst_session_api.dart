import '../../models/app_settings.dart';
import '../../models/school.dart';

/// 현재 수업, 선생님, 학급, 시간표 정보에 접근하는 API
abstract class BstSessionApi {
  /// 현재 보디스트 앱 설정 (학교, 학급, 선생님)
  AppSettings get settings;

  /// 현재 선택된 학교 정보
  School? get school;

  /// 현재 교사 성함 / ID
  String get teacherName;
  String get teacherId;

  /// 현재 학년 / 반
  int get grade;
  int get classNum;

  /// 현재 교시 (1~7교시, 쉬는시간 등)
  int get currentPeriod;

  /// 오늘 시간표 과목 목록 조회
  List<String> get todaySubjects;

  /// 급식실 번호 / 급식실 정보
  String get cafeteriaNum;

  /// 설정 변경 시 수신할 수 있는 Stream
  Stream<AppSettings> get onSettingsChanged;
}
