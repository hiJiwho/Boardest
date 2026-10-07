// Structured meal models without external dependencies

class MealDishItem {
  final String name;
  final List<String> allergies;
  int totalVotes;
  final Map<String, int> classVotes;

  MealDishItem({
    required this.name,
    this.allergies = const [],
    this.totalVotes = 0,
    Map<String, int>? classVotes,
  }) : classVotes = classVotes ?? {};

  String get allergyDisplay => allergies.isEmpty ? '' : '(${allergies.join(', ')})';

  Map<String, dynamic> toJson() => {
        'name': name,
        'allergies': allergies,
        'totalVotes': totalVotes,
        'classVotes': classVotes,
      };

  factory MealDishItem.fromJson(Map<String, dynamic> json) => MealDishItem(
        name: json['name'] as String? ?? '',
        allergies: (json['allergies'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        totalVotes: json['totalVotes'] as int? ?? 0,
        classVotes: (json['classVotes'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            ) ??
            {},
      );
}

class MealDayInfo {
  final DateTime date;
  final List<MealDishItem> dishes;
  final List<String> footnotes;

  MealDayInfo({
    required this.date,
    required this.dishes,
    this.footnotes = const [],
  });

  String get dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    final dateStr = '${date.month}/${date.day}';
    if (diff == 0) return '$dateStr 급식 (오늘)';
    if (diff == 1) return '$dateStr 급식 (내일)';
    if (diff == -1) return '$dateStr 급식 (어제)';
    
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '$dateStr (${weekdays[date.weekday - 1]}) 급식';
  }

  static const Map<int, String> _allergyCodeMap = {
    1: '난류',
    2: '우유',
    3: '메밀',
    4: '땅콩',
    5: '대두',
    6: '밀',
    7: '고등어',
    8: '갑각', // 게
    9: '갑각', // 새우
    10: '돼지',
    11: '복숭아',
    12: '토마토',
    13: '아황산',
    14: '호두',
    15: '닭고기',
    16: '소고기',
    17: '오징어',
    18: '조개',
    19: '잣',
  };

  static const Map<String, String> _allergyExplainMap = {
    '난류': '난류(달걀) 알레르기 조심',
    '우유': '우유 및 유제품 알레르기 조심',
    '메밀': '메밀 알레르기 조심',
    '땅콩': '땅콩 알레르기 조심',
    '대두': '대두(콩) 알레르기 조심',
    '밀': '밀(글루텐) 알레르기 조심',
    '고등어': '고등어 알레르기 조심',
    '갑각': '갑각류(게, 새우) 알레르기 조심',
    '돼지': '돼지고기 알레르기 조심',
    '복숭아': '복숭아 알레르기 조심',
    '토마토': '토마토 알레르기 조심',
    '아황산': '아황산염 알레르기 조심',
    '호두': '호두 및 견과류 알레르기 조심',
    '닭고기': '닭고기 알레르기 조심',
    '소고기': '소고기 알레르기 조심',
    '오징어': '오징어 알레르기 조심',
    '조개': '조개류(굴, 전복, 홍합 등) 알레르기 조심',
    '잣': '잣 알레르기 조심',
  };

  /// Parses raw NEIS DDISH_NM containing HTML breaks and parentheses numbers e.g. "소고기된장국(5.6.16.)<br/>맛있는케이크(1.2.8.)"
  factory MealDayInfo.fromNeisRaw(DateTime date, String rawDdish) {
    if (rawDdish.trim().isEmpty) {
      return MealDayInfo(date: date, dishes: [], footnotes: []);
    }

    final cleaned = rawDdish.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    final lines = cleaned.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

    final List<MealDishItem> dishItems = [];
    final Set<String> detectedAllergies = {};

    final allergyPattern = RegExp(r'\(([0-9. \t\n]+)\)');

    for (final line in lines) {
      final match = allergyPattern.firstMatch(line);
      final List<String> itemAllergies = [];

      String dishName = line;
      if (match != null) {
        dishName = line.replaceAll(allergyPattern, '').trim();
        final rawNumbers = match.group(1) ?? '';
        final nums = RegExp(r'\d+').allMatches(rawNumbers).map((m) => int.tryParse(m.group(0) ?? '')).whereType<int>();

        for (final num in nums) {
          final label = _allergyCodeMap[num];
          if (label != null && !itemAllergies.contains(label)) {
            itemAllergies.add(label);
            detectedAllergies.add(label);
          }
        }
      }

      if (dishName.isNotEmpty) {
        dishItems.add(MealDishItem(
          name: dishName,
          allergies: itemAllergies,
        ));
      }
    }

    final footnotes = detectedAllergies.map((a) {
      final exp = _allergyExplainMap[a] ?? '$a 알레르기 조심';
      return '! ($a) : $exp';
    }).toList();

    return MealDayInfo(date: date, dishes: dishItems, footnotes: footnotes);
  }

  /// Generates delicious middle school lunch menu for Demo mode deterministically
  factory MealDayInfo.generateDemo(DateTime date) {
    final daySeed = date.year * 10000 + date.month * 100 + date.day;
    final weekday = date.weekday;

    // In Demo mode, always provide demo meal for evaluation even on weekends
    final effectiveSeed = daySeed;

    final menuPools = [
      [
        MealDishItem(name: '친환경 흑미밥'),
        MealDishItem(name: '소고기 된장찌개', allergies: ['소고기', '대두']),
        MealDishItem(name: '수제 떡갈비구이', allergies: ['돼지', '대두', '밀']),
        MealDishItem(name: '골뱅이 야채무침', allergies: ['조개']),
        MealDishItem(name: '배추김치'),
        MealDishItem(name: '맛있는 초코케이크', allergies: ['난류', '우유', '밀']),
      ],
      [
        MealDishItem(name: '칼슘 기장밥'),
        MealDishItem(name: '바지락 미역국', allergies: ['조개']),
        MealDishItem(name: '매콤 돼지갈비찜', allergies: ['돼지', '대두']),
        MealDishItem(name: '잡채', allergies: ['대두', '밀']),
        MealDishItem(name: '깍두기'),
        MealDishItem(name: '신선한 생딸기주스'),
      ],
      [
        MealDishItem(name: '차수수밥'),
        MealDishItem(name: '해물 순두부찌개', allergies: ['갑각', '대두']),
        MealDishItem(name: '바삭 치킨텐더 & 머스터드', allergies: ['닭고기', '난류', '밀']),
        MealDishItem(name: '시금치 나물무침'),
        MealDishItem(name: '총각김치'),
        MealDishItem(name: '유기농 요구르트', allergies: ['우유']),
      ],
      [
        MealDishItem(name: '발아현미밥'),
        MealDishItem(name: '얼큰 부대찌개', allergies: ['돼지', '대두', '밀']),
        MealDishItem(name: '수제 돈가스 & 브라운소스', allergies: ['돼지', '난류', '밀']),
        MealDishItem(name: '마카로니 콘샐러드', allergies: ['난류', '우유', '밀']),
        MealDishItem(name: '열무김치'),
        MealDishItem(name: '달콤한 멜론'),
      ],
      [
        MealDishItem(name: '베이컨 김치볶음밥', allergies: ['돼지']),
        MealDishItem(name: '팽이버섯 유부장국', allergies: ['대두']),
        MealDishItem(name: '왕새우튀김 & 칠리소스', allergies: ['갑각', '밀']),
        MealDishItem(name: '치즈 계란말이', allergies: ['난류', '우유']),
        MealDishItem(name: '단무지 무침'),
        MealDishItem(name: '아이스 망고 푸딩', allergies: ['우유']),
      ],
    ];

    final index = (daySeed % menuPools.length);
    final chosenDishes = menuPools[index];

    final Set<String> detected = {};
    for (final d in chosenDishes) {
      detected.addAll(d.allergies);
    }

    final footnotes = detected.map((a) {
      final exp = _allergyExplainMap[a] ?? '$a 알레르기 조심';
      return '! ($a) : $exp';
    }).toList();

    return MealDayInfo(date: date, dishes: chosenDishes, footnotes: footnotes);
  }
}
