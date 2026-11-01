// Lite Meal Models with 1~19 Allergy Support

class LiteMealDishItem {
  final String name;
  final List<String> allergies;
  final List<int> allergyCodes;

  LiteMealDishItem({
    required this.name,
    this.allergies = const [],
    List<int>? allergyCodes,
  }) : allergyCodes = allergyCodes ?? [];

  String get allergyDisplay => allergies.isEmpty ? '' : '(${allergies.join(', ')})';

  bool matchesAllergy(dynamic filter) {
    if (filter == null) return false;
    final filterStr = filter.toString().trim();
    final code = int.tryParse(filterStr);

    if (code != null) {
      if (allergyCodes.contains(code)) return true;
      final keyword = LiteMealDayInfo.allergyCodeMap[code];
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
      };

  factory LiteMealDishItem.fromJson(Map<String, dynamic> json) {
    final allergies = (json['allergies'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    List<int> codes = (json['allergyCodes'] as List<dynamic>?)
            ?.map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList() ??
        [];
    if (codes.isEmpty) {
      for (final a in allergies) {
        for (final entry in LiteMealDayInfo.allergyCodeMap.entries) {
          if (entry.value == a || entry.value.contains(a) || a.contains(entry.value)) {
            if (!codes.contains(entry.key)) codes.add(entry.key);
          }
        }
      }
    }
    return LiteMealDishItem(
      name: json['name'] as String? ?? '',
      allergies: allergies,
      allergyCodes: codes,
    );
  }
}

class LiteMealDayInfo {
  final DateTime date;
  final List<LiteMealDishItem> dishes;
  final List<String> footnotes;
  final String calories;

  LiteMealDayInfo({
    required this.date,
    required this.dishes,
    this.footnotes = const [],
    this.calories = '',
  });

  bool hasAllergy(dynamic filter) {
    if (filter == null) return false;
    return dishes.any((d) => d.matchesAllergy(filter));
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
    15: '닭',
    16: '소',
    17: '오징어',
    18: '조개',
    19: '잣',
  };

  static const Map<String, String> allergyExplainMap = {
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

  factory LiteMealDayInfo.fromNeisRaw(
    DateTime date,
    String rawDdish, {
    String calories = '',
  }) {
    if (rawDdish.trim().isEmpty) {
      return LiteMealDayInfo(date: date, dishes: [], footnotes: [], calories: calories);
    }

    final cleaned = rawDdish.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    final lines = cleaned.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

    final List<LiteMealDishItem> dishItems = [];
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
        dishItems.add(LiteMealDishItem(
          name: dishName,
          allergies: itemAllergies,
          allergyCodes: itemCodes,
        ));
      }
    }

    final footnotes = detectedAllergies.map((a) {
      final exp = allergyExplainMap[a] ?? '$a 알레르기 조심';
      return '! ($a) : $exp';
    }).toList();

    return LiteMealDayInfo(
      date: date,
      dishes: dishItems,
      footnotes: footnotes,
      calories: calories,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'dishes': dishes.map((d) => d.toJson()).toList(),
        'footnotes': footnotes,
        'calories': calories,
      };

  factory LiteMealDayInfo.fromJson(Map<String, dynamic> json) => LiteMealDayInfo(
        date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        dishes: (json['dishes'] as List<dynamic>?)
                ?.map((e) => LiteMealDishItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        footnotes: (json['footnotes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        calories: json['calories']?.toString() ?? '',
      );
}
