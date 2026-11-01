// Structured meal models without external dependencies

class MealDishItem {
  final String name;
  final List<String> allergies;
  final List<int> allergyCodes;
  int totalVotes;
  final Map<String, int> classVotes;

  MealDishItem({
    required this.name,
    this.allergies = const [],
    List<int>? allergyCodes,
    this.totalVotes = 0,
    Map<String, int>? classVotes,
  })  : allergyCodes = allergyCodes ?? [],
        classVotes = classVotes ?? {};

  String get allergyDisplay => allergies.isEmpty ? '' : '(${allergies.join(', ')})';
  String get allergyInfo => allergies.join(', ');
  int get votes => totalVotes;

  bool matchesAllergy(dynamic filter) {
    if (filter == null) return false;
    final filterStr = filter.toString().trim();
    final code = int.tryParse(filterStr);

    if (code != null) {
      if (allergyCodes.contains(code)) return true;
      final keyword = MealDayInfo.allergyCodeMap[code];
      if (keyword != null && allergies.any((a) => a == keyword || a.contains(keyword) || keyword.contains(a))) {
        return true;
      }
    }

    final keyword = filterStr;
    for (final a in allergies) {
      if (a == keyword || a.contains(keyword) || keyword.contains(a)) {
        return true;
      }
      if ((keyword == '닭' || keyword == '닭고기') && (a == '닭' || a == '닭고기')) {
        return true;
      }
      if ((keyword == '소' || keyword == '소고기' || keyword == '쇠고기') &&
          (a == '소' || a == '소고기' || a == '쇠고기')) {
        return true;
      }
      if ((keyword == '돼지' || keyword == '돼지고기') && (a == '돼지' || a == '돼지고기')) {
        return true;
      }
      if ((keyword == '새우' || keyword == '게' || keyword == '갑각' || keyword == '갑각류') &&
          (a == '새우' || a == '게' || a == '갑각' || a == '갑각류')) {
        return true;
      }
      if ((keyword == '조개' || keyword == '조개류') && (a == '조개' || a == '조개류')) {
        return true;
      }
      if ((keyword == '아황산' || keyword == '아황산류' || keyword == '아황산염') &&
          (a == '아황산' || a == '아황산류' || a == '아황산염')) {
        return true;
      }
      if ((keyword == '난류' || keyword == '달걀' || keyword == '계란') &&
          (a == '난류' || a == '달걀' || a == '계란')) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'allergies': allergies,
        'allergyCodes': allergyCodes,
        'totalVotes': totalVotes,
        'classVotes': classVotes,
      };

  factory MealDishItem.fromJson(Map<String, dynamic> json) {
    final allergies = (json['allergies'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    List<int> codes = (json['allergyCodes'] as List<dynamic>?)
            ?.map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList() ??
        [];
    if (codes.isEmpty) {
      for (final a in allergies) {
        for (final entry in MealDayInfo.allergyCodeMap.entries) {
          if (entry.value == a || entry.value.contains(a) || a.contains(entry.value)) {
            if (!codes.contains(entry.key)) codes.add(entry.key);
          }
        }
      }
    }
    return MealDishItem(
      name: json['name'] as String? ?? '',
      allergies: allergies,
      allergyCodes: codes,
      totalVotes: json['totalVotes'] as int? ?? 0,
      classVotes: (json['classVotes'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ) ??
          {},
    );
  }
}

class MealDayInfo {
  final DateTime date;
  final List<MealDishItem> dishes;
  final List<String> footnotes;
  final String calories;

  MealDayInfo({
    required this.date,
    required this.dishes,
    this.footnotes = const [],
    this.calories = '',
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'dishes': dishes.map((d) => d.toJson()).toList(),
        'footnotes': footnotes,
        'calories': calories,
      };

  factory MealDayInfo.fromJson(Map<String, dynamic> json) => MealDayInfo(
        date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        dishes: (json['dishes'] as List<dynamic>?)
                ?.map((e) => MealDishItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        footnotes: (json['footnotes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        calories: json['calories']?.toString() ?? '',
      );

  bool hasAllergy(dynamic filter) {
    if (filter == null) return false;
    return dishes.any((d) => d.matchesAllergy(filter));
  }

  Set<int> get allAllergyIndexes {
    final res = <int>{};
    for (final dish in dishes) {
      res.addAll(dish.allergyCodes);
      for (final a in dish.allergies) {
        for (final entry in allergyCodeMap.entries) {
          if (entry.value == a || entry.value.contains(a) || a.contains(entry.value)) {
            res.add(entry.key);
          }
        }
      }
    }
    return res;
  }

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

  static const Map<int, String> allergyCodeMap = {
    1: '난류',
    2: '우유',
    3: '메밀',
    4: '땅콩',
    5: '대두',
    6: '밀',
    7: '고등어',
    8: '게',
    9: '새우',
    10: '돼지고기',
    11: '복숭아',
    12: '토마토',
    13: '아황산류',
    14: '호두',
    15: '닭고기',
    16: '쇠고기',
    17: '오징어',
    18: '조개류',
    19: '잣',
  };

  static const Map<int, String> allergyBadgeShortMap = {
    1: '난류',
    2: '우유',
    3: '메밀',
    4: '땅콩',
    5: '대두',
    6: '밀',
    7: '고등어',
    8: '게',
    9: '새우',
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
    '게': '게(갑각류) 알레르기 조심',
    '새우': '새우(갑각류) 알레르기 조심',
    '갑각': '갑각류(게, 새우) 알레르기 조심',
    '돼지': '돼지고기 알레르기 조심',
    '돼지고기': '돼지고기 알레르기 조심',
    '복숭아': '복숭아 알레르기 조심',
    '토마토': '토마토 알레르기 조심',
    '아황산': '아황산염 알레르기 조심',
    '아황산류': '아황산염 알레르기 조심',
    '호두': '호두 및 견과류 알레르기 조심',
    '닭고기': '닭고기 알레르기 조심',
    '닭': '닭고기 알레르기 조심',
    '소고기': '소고기 알레르기 조심',
    '쇠고기': '쇠고기 알레르기 조심',
    '소': '소고기 알레르기 조심',
    '오징어': '오징어 알레르기 조심',
    '조개': '조개류(굴, 전복, 홍합 등) 알레르기 조심',
    '조개류': '조개류(굴, 전복, 홍합 등) 알레르기 조심',
    '잣': '잣 알레르기 조심',
  };

  factory MealDayInfo.fromNeisRaw(
    DateTime date,
    String rawDdish, {
    String calories = '',
  }) {
    if (rawDdish.trim().isEmpty) {
      return MealDayInfo(date: date, dishes: [], footnotes: [], calories: calories);
    }

    final cleaned = rawDdish.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    final lines = cleaned.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

    final List<MealDishItem> dishItems = [];
    final Set<String> detectedAllergies = {};

    final allergyPattern = RegExp(r'\(([0-9., \t\n*]+)\)');

    for (final line in lines) {
      final match = allergyPattern.firstMatch(line);
      final List<String> itemAllergies = [];
      final List<int> itemCodes = [];

      String dishName = line;
      if (match != null) {
        dishName = line.replaceAll(allergyPattern, '').trim();
        final rawNumbers = match.group(1) ?? '';
        final nums = RegExp(r'\d+').allMatches(rawNumbers).map((m) => int.tryParse(m.group(0) ?? '')).whereType<int>();

        for (final num in nums) {
          if (num >= 1 && num <= 19) {
            if (!itemCodes.contains(num)) itemCodes.add(num);
            final label = allergyBadgeShortMap[num] ?? allergyCodeMap[num];
            if (label != null && !itemAllergies.contains(label)) {
              itemAllergies.add(label);
              detectedAllergies.add(label);
            }
          }
        }
      }

      if (dishName.isNotEmpty) {
        dishItems.add(MealDishItem(
          name: dishName,
          allergies: itemAllergies,
          allergyCodes: itemCodes,
        ));
      }
    }

    final footnotes = detectedAllergies.map((a) {
      final exp = _allergyExplainMap[a] ?? '$a 알레르기 조심';
      return '! ($a) : $exp';
    }).toList();

    return MealDayInfo(
      date: date,
      dishes: dishItems,
      footnotes: footnotes,
      calories: calories,
    );
  }

  factory MealDayInfo.generateDemo(DateTime date) {
    final daySeed = date.year * 10000 + date.month * 100 + date.day;

    final menuPools = [
      [
        MealDishItem(name: '친환경 흑미밥'),
        MealDishItem(name: '소고기 된장찌개', allergies: ['소고기', '대두'], allergyCodes: [16, 5]),
        MealDishItem(name: '수제 떡갈비구이', allergies: ['돼지', '대두', '밀'], allergyCodes: [10, 5, 6]),
        MealDishItem(name: '골뱅이 야채무침', allergies: ['조개'], allergyCodes: [18]),
        MealDishItem(name: '배추김치'),
        MealDishItem(name: '맛있는 초코케이크', allergies: ['난류', '우유', '밀'], allergyCodes: [1, 2, 6]),
      ],
      [
        MealDishItem(name: '칼슘 기장밥'),
        MealDishItem(name: '바지락 미역국', allergies: ['조개'], allergyCodes: [18]),
        MealDishItem(name: '매콤 돼지갈비찜', allergies: ['돼지', '대두'], allergyCodes: [10, 5]),
        MealDishItem(name: '잡채', allergies: ['대두', '밀'], allergyCodes: [5, 6]),
        MealDishItem(name: '깍두기'),
        MealDishItem(name: '신선한 생딸기주스'),
      ],
      [
        MealDishItem(name: '차수수밥'),
        MealDishItem(name: '해물 순두부찌개', allergies: ['게', '새우', '대두'], allergyCodes: [8, 9, 5]),
        MealDishItem(name: '바삭 치킨텐더 & 머스터드', allergies: ['닭고기', '난류', '밀'], allergyCodes: [15, 1, 6]),
        MealDishItem(name: '시금치 나물무침'),
        MealDishItem(name: '총각김치'),
        MealDishItem(name: '유기농 요구르트', allergies: ['우유'], allergyCodes: [2]),
      ],
      [
        MealDishItem(name: '발아현미밥'),
        MealDishItem(name: '얼큰 부대찌개', allergies: ['돼지', '대두', '밀'], allergyCodes: [10, 5, 6]),
        MealDishItem(name: '수제 돈가스 & 브라운소스', allergies: ['돼지', '난류', '밀'], allergyCodes: [10, 1, 6]),
        MealDishItem(name: '마카로니 콘샐러드', allergies: ['난류', '우유', '밀'], allergyCodes: [1, 2, 6]),
        MealDishItem(name: '열무김치'),
        MealDishItem(name: '달콤한 멜론'),
      ],
      [
        MealDishItem(name: '베이컨 김치볶음밥', allergies: ['돼지'], allergyCodes: [10]),
        MealDishItem(name: '팽이버섯 유부장국', allergies: ['대두'], allergyCodes: [5]),
        MealDishItem(name: '왕새우튀김 & 칠리소스', allergies: ['새우', '밀'], allergyCodes: [9, 6]),
        MealDishItem(name: '치즈 계란말이', allergies: ['난류', '우유'], allergyCodes: [1, 2]),
        MealDishItem(name: '단무지 무침'),
        MealDishItem(name: '아이스 망고 푸딩', allergies: ['우유'], allergyCodes: [2]),
      ],
    ];

    const caloriePools = ['745 kcal', '712 kcal', '688 kcal', '790 kcal', '734 kcal'];
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

    return MealDayInfo(
      date: date,
      dishes: chosenDishes,
      footnotes: footnotes,
      calories: caloriePools[index],
    );
  }
}
