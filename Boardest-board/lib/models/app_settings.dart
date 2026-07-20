import 'school.dart';

class TimeSettings {
  final int lessonDuration; // in minutes (default 45)
  final int breakDuration; // in minutes (default 10)
  final int lunchDuration; // in minutes (default 50)
  final int lunchAfterPeriod; // period index (default 4, i.e. between 4th and 5th period)
  final String firstPeriodStart; // HH:mm format (default "08:40")
  final String morningAssemblyStart; // HH:mm format (default "08:25")
  final String morningAssemblyEnd; // HH:mm format (default "08:40")
  final String afternoonAssemblyStart; // HH:mm format (default "16:10")
  final String afternoonAssemblyEnd; // HH:mm format (default "16:30")
  // If not null, afternoonAssemblyStart is derived as lastPeriodEnd + this many minutes
  final int? afternoonAssemblyAfterMinutes;
  // If not null, morningAssemblyStart is derived as firstPeriodStart - this many minutes
  final int? morningAssemblyBeforeMinutes;

  TimeSettings({
    this.lessonDuration = 45,
    this.breakDuration = 10,
    this.lunchDuration = 50,
    this.lunchAfterPeriod = 4,
    this.firstPeriodStart = "08:40",
    this.morningAssemblyStart = "08:25",
    this.morningAssemblyEnd = "08:40",
    this.afternoonAssemblyStart = "16:10",
    this.afternoonAssemblyEnd = "16:30",
    this.afternoonAssemblyAfterMinutes,
    this.morningAssemblyBeforeMinutes,
  });

  Map<String, dynamic> toJson() {
    return {
      'lessonDuration': lessonDuration,
      'breakDuration': breakDuration,
      'lunchDuration': lunchDuration,
      'lunchAfterPeriod': lunchAfterPeriod,
      'firstPeriodStart': firstPeriodStart,
      'morningAssemblyStart': morningAssemblyStart,
      'morningAssemblyEnd': morningAssemblyEnd,
      'afternoonAssemblyStart': afternoonAssemblyStart,
      'afternoonAssemblyEnd': afternoonAssemblyEnd,
      'afternoonAssemblyAfterMinutes': afternoonAssemblyAfterMinutes,
      'morningAssemblyBeforeMinutes': morningAssemblyBeforeMinutes,
    };
  }

  factory TimeSettings.fromJson(Map<String, dynamic> json) {
    return TimeSettings(
      lessonDuration: json['lessonDuration'] as int? ?? 45,
      breakDuration: json['breakDuration'] as int? ?? 10,
      lunchDuration: json['lunchDuration'] as int? ?? 50,
      lunchAfterPeriod: json['lunchAfterPeriod'] as int? ?? 4,
      firstPeriodStart: json['firstPeriodStart'] as String? ?? "08:40",
      morningAssemblyStart: json['morningAssemblyStart'] as String? ?? "08:25",
      morningAssemblyEnd: json['morningAssemblyEnd'] as String? ?? "08:40",
      afternoonAssemblyStart: json['afternoonAssemblyStart'] as String? ?? "16:10",
      afternoonAssemblyEnd: json['afternoonAssemblyEnd'] as String? ?? "16:30",
      afternoonAssemblyAfterMinutes: json['afternoonAssemblyAfterMinutes'] as int?,
      morningAssemblyBeforeMinutes: json['morningAssemblyBeforeMinutes'] as int?,
    );
  }
}

class DDayEvent {
  final String title;
  final DateTime date;

  DDayEvent({required this.title, required this.date});

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'date': date.toIso8601String(),
    };
  }

  factory DDayEvent.fromJson(Map<String, dynamic> json) {
    return DDayEvent(
      title: json['title'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }
}

class SystemApp {
  final String name;
  final String appId;
  final String? iconPath;

  SystemApp({required this.name, required this.appId, this.iconPath});

  Map<String, String> toJson() {
    return {
      'name': name,
      'appId': appId,
      if (iconPath != null) 'iconPath': iconPath!,
    };
  }

  factory SystemApp.fromJson(Map<dynamic, dynamic> json) {
    return SystemApp(
      name: (json['name'] ?? '').toString(),
      appId: (json['appId'] ?? '').toString(),
      iconPath: json['iconPath']?.toString(),
    );
  }
}

// Slot type for the unified 3x3 launcher grid
enum LauncherSlotType { systemApp, boardestTool, empty }

class LauncherSlot {
  final LauncherSlotType type;
  final String name;
  /// For systemApp: appId (URL or .exe path)
  /// For boardestTool: tool key (e.g. 'whiteboard', 'timer', ...)
  final String id;
  final String? iconPath;

  LauncherSlot({required this.type, required this.name, required this.id, this.iconPath});

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'id': id,
    if (iconPath != null) 'iconPath': iconPath,
  };

  factory LauncherSlot.fromJson(Map<dynamic, dynamic> json) {
    return LauncherSlot(
      type: LauncherSlotType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => LauncherSlotType.boardestTool,
      ),
      name: json['name']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      iconPath: json['iconPath']?.toString(),
    );
  }

  // Built-in Boardest tools catalog
  static const List<LauncherSlot> allBoardestTools = [
    // 단순 도구 (Simple Tools)
    LauncherSlot._tool('타이머', 'timer'),
    LauncherSlot._tool('계산기', 'calculator'),
    LauncherSlot._tool('발표자', 'picker'),
    LauncherSlot._tool('날씨', 'weather'),
    LauncherSlot._tool('학사달력', 'school_calendar'),

    // 판서 관련 (Annotation Tools)
    LauncherSlot._tool('기본판서', 'whiteboard'),
    LauncherSlot._tool('문서판서', 'document_board'),
    LauncherSlot._tool('사이트 판서', 'website_board'),
    LauncherSlot._tool('설정', 'settings'),
    LauncherSlot._tool('전체앱', 'app_drawer'),
  ];

  const LauncherSlot._tool(this.name, this.id)
      : type = LauncherSlotType.boardestTool,
        iconPath = null;
}


class AppSettings {
  final School? selectedSchool;
  final int selectedGrade;
  final int selectedClass;
  final TimeSettings timeSettings;
  final Map<String, String> textbookImages; // subjectStem -> localImagePath
  // teacherFullNames 제거됨 (개인정보 보호 - 교사 실명 매핑 기능 삭제)
  final bool isSetupComplete;
  final List<DDayEvent> ddayEvents;
  /// 학사일정에서 고른 D-Day (길게 눌러 선택). null이면 가장 가까운 학사일정을 자동 표시.
  final DDayEvent? pinnedDday;
  final double scaleFactor;
  final List<SystemApp> selectedSystemApps;
  final List<LauncherSlot> launcherSlots; // 7x2 customizable grid (14 slots)
  final bool autoSleepEnabled; // 자동 절전 모드 여부
  final String cafeteriaNum; // 급식실 번호 (예: "급식실1", "급식실2")
  final String mealCallClassOrder; // 반 정렬 순서 ("asc" 또는 "desc")
  final int specialClassroomType; // 특별실 타입 (0: 일반, 1: 전용교사실, 2: 과목특수실, 3: 미교수특수실)
  final String selectedSubject; // 특별실 과목 (과목 특수실에서 사용)
  final String connectionName; // Firebase 연결 이름 (예: "My", "ClassA")
  final String classNickname; // 학급 닉네임 (예: "2학년 1반", "기쁜반")
  final String selectedTeacher; // 특별실 교사명/약칭 (개인정보 보호를 위해 마스킹하여 내부 연동용으로만 사용)
  final String windowFrameStyle; // "mac", "win7"

  bool get specialClassroomMode => specialClassroomType > 0;


  AppSettings({
    this.selectedSchool,
    this.selectedGrade = 1,
    this.selectedClass = 1,
    TimeSettings? timeSettings,
    Map<String, String>? textbookImages,
    this.isSetupComplete = false,
    List<DDayEvent>? ddayEvents,
    this.pinnedDday,
    this.scaleFactor = 1.4,
    List<SystemApp>? selectedSystemApps,
    List<LauncherSlot>? launcherSlots,
    this.autoSleepEnabled = false,
    this.cafeteriaNum = '급식실1',
    this.mealCallClassOrder = 'asc',
    this.specialClassroomType = 0,
    this.selectedSubject = '',
    this.connectionName = 'My',
    this.classNickname = '',
    this.selectedTeacher = '',
    this.windowFrameStyle = 'mac',
  })  : timeSettings = timeSettings ?? TimeSettings(),
        textbookImages = textbookImages ?? {},
        ddayEvents = ddayEvents ?? _getDefaultDDayEvents(),
        selectedSystemApps = selectedSystemApps ?? [],
        launcherSlots = launcherSlots ?? _getDefaultLauncherSlots(selectedSystemApps);

  static List<LauncherSlot> _getDefaultLauncherSlots(List<SystemApp>? sysApps) {
    final defaults = <LauncherSlot>[
      // 1행: 기본 도구 4개 + 빈 슬롯 2개 (메모장, 파일 탐색기 제거) + 시스템 앱 자유 슬롯 (7 slots)
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '타이머', id: 'timer'),
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '계산기', id: 'calculator'),
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '발표자', id: 'picker'),
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '날씨', id: 'weather'),
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '학사달력', id: 'school_calendar'),
      LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''), // 빈칸 1 (기존 메모장 제거)
      LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''), // 빈칸 2 (기존 파일 탐색기 제거)

      // 2행: 판서 3개 + 설정 1개 + 빈 슬롯 2개 + 전체앱 (7 slots)
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '기본판서', id: 'whiteboard'),
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '문서판서', id: 'document_board'),
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '사이트 판서', id: 'website_board'),
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '설정', id: 'settings'),
      LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''), // 빈칸 3 (기존 전체시간표 제거 - 학사달력과 통합됨)
      LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''), // 빈칸 4 (맨 끝 빈칸 추가로 14개 맞춤)
      LauncherSlot(type: LauncherSlotType.boardestTool, name: '전체앱', id: 'app_drawer'), // 기본 시스템 앱 3
    ];
    return defaults;
  }

  static List<DDayEvent> _getDefaultDDayEvents() {
    final now = DateTime.now();
    return [
      DDayEvent(title: '지필평가', date: DateTime(now.year, now.month, now.day).add(const Duration(days: 14))),
      DDayEvent(title: '방학', date: DateTime(now.year, now.month, now.day).add(const Duration(days: 45))),
    ];
  }

  /// Helper to extract a unified subject stem to group subjects and map textbooks/teachers.
  /// E.g., "국어1" -> "국어", "역사A" -> "역사", "영어I" -> "영어", "English II" -> "ENGLISH"
  static String getSubjectStem(String subject) {
    String cleaned = subject.trim();
    if (cleaned.isEmpty) return '';

    // 1. Strip leading split class group codes (e.g., "A_영어" -> "영어")
    if (cleaned.startsWith(RegExp(r'^[a-zA-Z]_'))) {
      cleaned = cleaned.substring(2);
    }

    // 2. Remove all non-alphanumeric characters (except Korean, English, numbers) and convert to uppercase
    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9가-힣]'), '').toUpperCase();
    if (cleaned.isEmpty) return '';

    // 3. Loop to trim trailing digits, Roman numerals, or single characters A-Z if they act as qualifiers.
    // We preserve at least 2 characters so we don't end up stripping the entire name if it is very short.
    while (cleaned.length > 1) {
      // Check for trailing digits (e.g. 국어1 -> 국어)
      if (RegExp(r'\d$').hasMatch(cleaned)) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
        continue;
      }
      // Check for trailing Roman numerals (I, V, X) (e.g. 영어II -> 영어)
      if (RegExp(r'[IVX]$').hasMatch(cleaned)) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
        continue;
      }
      // Check for trailing single English letters A-Z (e.g. 수학A -> 수학)
      if (RegExp(r'[A-Z]$').hasMatch(cleaned)) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
        continue;
      }
      break;
    }

    return cleaned;
  }

  /// Helper to create the teacher map key — 제거됨 (개인정보 보호)
  // getTeacherKey 메서드가 삭제되었습니다.

  /// Retrieves a textbook cover path using a highly robust fallback mechanism to prevent cover disappearance
  String? getTextbookPath(String subject, {int? grade}) {
    if (textbookImages.isEmpty) return null;
    final stem = getSubjectStem(subject);
    if (stem.isEmpty) return null;
    
    if (grade != null) {
      final gradeKey = '${grade}_$stem';
      if (textbookImages.containsKey(gradeKey)) {
        return textbookImages[gradeKey];
      }
    }

    if (textbookImages.containsKey(stem)) {
      return textbookImages[stem];
    }

    // Define subject relation groups to fallback dynamically
    final List<Set<String>> relationGroups = [
      {'국어', '문학', '독서', '화법과작문', '화작', '언어와매체', '언매', '고전읽기', '심화국어', '실용국어'},
      {'영어', '영어회화', '영어독해', '영어독해와작문', '영어작문', '영어회화', '영어I', '영어II', '영어1', '영어2', '실용영어', '심화영어', 'ENGLISH'},
      {'수학', '공통수학', '수학I', '수학II', '수학1', '수학2', '미적분', '확률과통계', '확통', '기하', '인공지능수학', '경제수학', '수학과제탐구'},
      {'과학', '통합과학', '물리학', '화학', '생명과학', '지구과학', '물리', '생물', '지구', '융합과학', '과학탐구실험', '물리1', '물리2', '화학1', '화학2', '생명과학1', '생명과학2', '지구과학1', '지구과학2'},
      {'사회', '통합사회', '한국사', '역사', '세계사', '동아시아사', '사회문화', '사문', '생활과윤리', '생윤', '윤리와사상', '윤사', '한국지리', '한지', '세계지리', '세지', '정치와법', '정법', '경제'},
      {'체육', '운동과건강', '스포츠생활'},
      {'음악', '미술', '연극', '예술'},
      {'기술가정', '기술', '가정', '정보'},
      {'한문', '중국어', '일본어', '스페인어', '프랑스어', '독일어'}
    ];

    // Find if the stem belongs to any relation group
    for (final group in relationGroups) {
      final normalizedGroup = group.map((e) => getSubjectStem(e)).toSet();
      if (normalizedGroup.contains(stem)) {
        for (final member in normalizedGroup) {
          if (grade != null) {
            final gradeKey = '${grade}_$member';
            if (textbookImages.containsKey(gradeKey)) {
              return textbookImages[gradeKey];
            }
          }
          if (textbookImages.containsKey(member)) {
            return textbookImages[member];
          }
        }
      }
    }

    // Secondary fallback: substring matches
    for (final key in textbookImages.keys) {
      if (key.contains('_')) {
        final parts = key.split('_');
        if (parts.length >= 2) {
          final keyGrade = int.tryParse(parts[0]);
          final keyStem = parts.sublist(1).join('_');
          if (grade == keyGrade && (keyStem.contains(stem) || stem.contains(keyStem))) {
            return textbookImages[key];
          }
        }
      } else {
        if (key.contains(stem) || stem.contains(key)) {
          return textbookImages[key];
        }
      }
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'selectedSchool': selectedSchool?.toJson(),
      'selectedGrade': selectedGrade,
      'selectedClass': selectedClass,
      'timeSettings': timeSettings.toJson(),
      'textbookImages': textbookImages,
      // teacherFullNames 제거됨 (개인정보 보호)
      'isSetupComplete': isSetupComplete,
      'ddayEvents': ddayEvents.map((e) => e.toJson()).toList(),
      if (pinnedDday != null) 'pinnedDday': pinnedDday!.toJson(),
      'scaleFactor': scaleFactor,
      'selectedSystemApps': selectedSystemApps.map((e) => e.toJson()).toList(),
      'launcherSlots': launcherSlots.map((e) => e.toJson()).toList(),
      'autoSleepEnabled': autoSleepEnabled,
      'cafeteriaNum': cafeteriaNum,
      'mealCallClassOrder': mealCallClassOrder,
      'specialClassroomType': specialClassroomType,
      'specialClassroomMode': specialClassroomMode,
      'selectedSubject': selectedSubject,
      'connectionName': connectionName,
      'classNickname': classNickname,
      'selectedTeacher': selectedTeacher,
      'windowFrameStyle': windowFrameStyle,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final sysApps = (json['selectedSystemApps'] as List?)
            ?.map((e) => SystemApp.fromJson(e as Map))
            .toList() ?? [];
    var loadedSlots = json['launcherSlots'] != null
        ? (json['launcherSlots'] as List)
            .map((e) => LauncherSlot.fromJson(e as Map))
            .toList()
        : null;

    if (loadedSlots != null) {
      final oldDefaultIds = {
        'explorer.exe', 'com.android.documentsui',
        'powerpnt.exe', 'com.microsoft.office.powerpoint',
        'mspaint.exe', 'com.sec.android.app.writeonpdf',
        'https://www.youtube.com'
      };
      bool hasOldDefaults = loadedSlots.any((slot) => slot.type == LauncherSlotType.systemApp && oldDefaultIds.contains(slot.id));
      if (hasOldDefaults) {
        loadedSlots = _getDefaultLauncherSlots(sysApps);
      } else {
        if (loadedSlots.length < 14) {
          while (loadedSlots.length < 14) {
            loadedSlots.add(LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''));
          }
        } else if (loadedSlots.length > 14) {
          loadedSlots = loadedSlots.sublist(0, 14);
        }
        // Force migration for removed built-in tools to empty slots
        loadedSlots = loadedSlots.map((slot) {
          if (slot.type == LauncherSlotType.boardestTool &&
              (slot.id == 'notepad' ||
                  slot.id == 'file_explorer' ||
                  slot.id == 'timetable' ||
                  slot.id == 'student_connect' ||
                  slot.id == 'media_board')) {
            return LauncherSlot(type: LauncherSlotType.empty, name: '', id: '');
          }
          // Ensure unified name sync for merged calendar
          if (slot.type == LauncherSlotType.boardestTool &&
              slot.id == 'school_calendar' &&
              slot.name != '학사달력') {
            return LauncherSlot(
                type: LauncherSlotType.boardestTool,
                name: '학사달력',
                id: 'school_calendar');
          }
          // Sync name for randomized picker
          if (slot.type == LauncherSlotType.boardestTool &&
              slot.id == 'picker' &&
              slot.name != '발표자') {
            return LauncherSlot(
                type: LauncherSlotType.boardestTool,
                name: '발표자',
                id: 'picker');
          }
          // Sync name for document board
          if (slot.type == LauncherSlotType.boardestTool &&
              slot.id == 'document_board' &&
              slot.name != '문서판서') {
            return LauncherSlot(
                type: LauncherSlotType.boardestTool,
                name: '문서판서',
                id: 'document_board');
          }
          return slot;
        }).toList();
      }
    }

    return AppSettings(
      selectedSchool: json['selectedSchool'] != null
          ? School.fromJson(json['selectedSchool'] as Map<String, dynamic>)
          : null,
      selectedGrade: json['selectedGrade'] as int? ?? 1,
      selectedClass: json['selectedClass'] as int? ?? 1,
      timeSettings: json['timeSettings'] != null
          ? TimeSettings.fromJson(json['timeSettings'] as Map<String, dynamic>)
          : TimeSettings(),
      textbookImages: Map<String, String>.from(json['textbookImages'] ?? {}),
      // teacherFullNames는 하위 호환성 유지를 위해 로드는 하지 않음 (제거됨)
      isSetupComplete: json['isSetupComplete'] as bool? ?? false,
      ddayEvents: json['ddayEvents'] != null
          ? (json['ddayEvents'] as List)
              .map((e) => DDayEvent.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      pinnedDday: json['pinnedDday'] != null
          ? DDayEvent.fromJson(json['pinnedDday'] as Map<String, dynamic>)
          : null,
      scaleFactor: (json['scaleFactor'] as num?)?.toDouble() ?? 1.4,
      selectedSystemApps: sysApps,
      launcherSlots: loadedSlots,
      autoSleepEnabled: json['autoSleepEnabled'] as bool? ?? false,
      cafeteriaNum: json['cafeteriaNum'] as String? ?? '급식실1',
      mealCallClassOrder: json['mealCallClassOrder'] as String? ?? 'asc',
      specialClassroomType: json['specialClassroomType'] as int? ?? (json['specialClassroomMode'] as bool? ?? false ? 3 : 0),
      selectedSubject: json['selectedSubject'] as String? ?? '',
      connectionName: json['connectionName'] as String? ?? 'My',
      classNickname: json['classNickname'] as String? ?? '',
      selectedTeacher: json['selectedTeacher'] as String? ?? '',
      windowFrameStyle: json['windowFrameStyle'] as String? ?? 'mac',
    );
  }

  AppSettings copyWith({
    School? selectedSchool,
    int? selectedGrade,
    int? selectedClass,
    TimeSettings? timeSettings,
    Map<String, String>? textbookImages,
    // teacherFullNames 파라미터 제거됨 (개인정보 보호)
    bool? isSetupComplete,
    List<DDayEvent>? ddayEvents,
    DDayEvent? pinnedDday,
    bool clearPinnedDday = false,
    double? scaleFactor,
    List<SystemApp>? selectedSystemApps,
    List<LauncherSlot>? launcherSlots,
    bool? autoSleepEnabled,
    String? cafeteriaNum,
    String? mealCallClassOrder,
    int? specialClassroomType,
    bool? specialClassroomMode,
    String? selectedSubject,
    String? connectionName,
    String? classNickname,
    String? selectedTeacher,
    String? windowFrameStyle,
  }) {
    return AppSettings(
      selectedSchool: selectedSchool ?? this.selectedSchool,
      selectedGrade: selectedGrade ?? this.selectedGrade,
      selectedClass: selectedClass ?? this.selectedClass,
      timeSettings: timeSettings ?? this.timeSettings,
      textbookImages: textbookImages ?? this.textbookImages,
      // teacherFullNames 제거됨
      isSetupComplete: isSetupComplete ?? this.isSetupComplete,
      ddayEvents: ddayEvents ?? this.ddayEvents,
      pinnedDday: clearPinnedDday ? null : (pinnedDday ?? this.pinnedDday),
      scaleFactor: scaleFactor ?? this.scaleFactor,
      selectedSystemApps: selectedSystemApps ?? this.selectedSystemApps,
      launcherSlots: launcherSlots ?? this.launcherSlots,
      autoSleepEnabled: autoSleepEnabled ?? this.autoSleepEnabled,
      cafeteriaNum: cafeteriaNum ?? this.cafeteriaNum,
      mealCallClassOrder: mealCallClassOrder ?? this.mealCallClassOrder,
      specialClassroomType: specialClassroomType ?? (specialClassroomMode != null ? (specialClassroomMode ? 3 : 0) : this.specialClassroomType),
      selectedSubject: selectedSubject ?? this.selectedSubject,
      connectionName: connectionName ?? this.connectionName,
      classNickname: classNickname ?? this.classNickname,
      selectedTeacher: selectedTeacher ?? this.selectedTeacher,
      windowFrameStyle: windowFrameStyle ?? this.windowFrameStyle,
    );
  }

  /// 교사명 마스킹 및 포맷팅 (예: "홍길" -> "홍교사", "김희" -> "김교사", "이" -> "이교사")
  static String formatTeacherDisplayName(String name) {
    final cleaned = name.replaceAll('*', '').trim();
    if (cleaned.isEmpty) return '교사';
    return '${cleaned[0]}교사';
  }
}
