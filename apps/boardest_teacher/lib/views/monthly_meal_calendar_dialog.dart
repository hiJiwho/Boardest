import 'package:flutter/material.dart';
import '../models/meal_models.dart';
import '../services/neis_service.dart';

/// 교사용 앱용 월간 급식 식단표 달력 모달 다이얼로그
class MonthlyMealCalendarDialog extends StatefulWidget {
  final String schoolName;
  final DateTime initialDate;

  const MonthlyMealCalendarDialog({
    super.key,
    required this.schoolName,
    required this.initialDate,
  });

  static Future<void> show(BuildContext context, {required String schoolName, DateTime? initialDate}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => MonthlyMealCalendarDialog(
        schoolName: schoolName,
        initialDate: initialDate ?? DateTime.now(),
      ),
    );
  }

  @override
  State<MonthlyMealCalendarDialog> createState() => _MonthlyMealCalendarDialogState();
}

class _MonthlyMealCalendarDialogState extends State<MonthlyMealCalendarDialog> {
  late int _year;
  late int _month;
  int? _selectedAllergyFilter;
  Future<Map<int, MealDayInfo>>? _mealsFuture;

  static const List<String> _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  static const Map<int, String> _allergyLabels = {
    1: '1.난류',
    2: '2.우유',
    5: '5.대두',
    6: '6.밀',
    9: '9.토마토',
    10: '10.돼지',
    15: '15.닭',
    16: '16.소',
  };

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _fetchMeals();
  }

  void _fetchMeals() {
    _mealsFuture = NeisService().fetchMonthMeals(widget.schoolName, _year, _month);
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _year--;
        _month = 12;
      } else {
        _month--;
      }
      _fetchMeals();
    });
  }

  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _year++;
        _month = 1;
      } else {
        _month++;
      }
      _fetchMeals();
    });
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _year = now.year;
      _month = now.month;
      _fetchMeals();
    });
  }

  void _showDayMealDetail(BuildContext context, int day, MealDayInfo? info) {
    if (info == null || info.dishes.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.restaurant_menu_rounded, color: Color(0xFF2EC4B6), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '$_month월 $day일 급식 상세',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  if (info.calories.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2EC4B6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        info.calories,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2EC4B6)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ...info.dishes.map((dish) {
                final isMatch = _selectedAllergyFilter != null &&
                    dish.allergies.any((a) => a.contains('$_selectedAllergyFilter'));
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMatch ? const Color(0xFFFFD166).withOpacity(0.18) : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: isMatch ? Border.all(color: const Color(0xFFFFD166), width: 1.2) : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dish.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isMatch ? const Color(0xFFFFD166) : Colors.white,
                          ),
                        ),
                      ),
                      if (dish.allergies.isNotEmpty)
                        Text(
                          '알레르기: ${dish.allergies.join(", ")}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isMatch ? const Color(0xFFFFD166) : Colors.white54,
                          ),
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2EC4B6),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDayWeekday = DateTime(_year, _month, 1).weekday % 7; // 0=Sun, 1=Mon, ..., 6=Sat
    final daysInMonth = DateTime(_year, _month + 1, 0).day;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        width: 1050,
        height: 720,
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.3), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Color(0xFF2EC4B6), size: 24),
                  const SizedBox(width: 10),
                  Text(
                    '${widget.schoolName} 월간 급식 달력',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 28),
                    onPressed: _prevMonth,
                    tooltip: '이전 달',
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2EC4B6).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.3)),
                    ),
                    child: Text(
                      '$_year년 $_month월',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2EC4B6),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 28),
                    onPressed: _nextMonth,
                    tooltip: '다음 달',
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _goToday,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2EC4B6),
                      side: BorderSide(color: const Color(0xFF2EC4B6).withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('오늘', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Allergy Filter Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white.withOpacity(0.015),
              child: Row(
                children: [
                  const Text('알레르기 강조: ', style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _allergyLabels.entries.map((e) {
                          final isSelected = _selectedAllergyFilter == e.key;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(
                                e.value,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: const Color(0xFFFFD166),
                              backgroundColor: Colors.white.withOpacity(0.05),
                              onSelected: (val) {
                                setState(() {
                                  _selectedAllergyFilter = val ? e.key : null;
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Weekday Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.white.withOpacity(0.04),
              child: Row(
                children: List.generate(7, (i) {
                  Color textColor = Colors.white70;
                  if (i == 0) textColor = const Color(0xFFFF6B6B);
                  if (i == 6) textColor = const Color(0xFF4D96FF);
                  return Expanded(
                    child: Text(
                      _weekdays[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Calendar Grid Area
            Expanded(
              child: FutureBuilder<Map<int, MealDayInfo>>(
                future: _mealsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF2EC4B6)),
                    );
                  }

                  final meals = snapshot.data ?? {};
                  final totalCells = firstDayWeekday + daysInMonth;
                  final rows = (totalCells / 7).ceil();

                  return GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 1.15,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: rows * 7,
                    itemBuilder: (ctx, index) {
                      final dayNum = index - firstDayWeekday + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.01),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        );
                      }

                      final dayOfWeek = index % 7;
                      final isSunday = dayOfWeek == 0;
                      final isSaturday = dayOfWeek == 6;
                      final isWeekend = isSunday || isSaturday;
                      final isToday = _year == now.year && _month == now.month && dayNum == now.day;

                      final dayMeal = meals[dayNum];
                      final dishes = dayMeal?.dishes ?? [];
                      final hasMeal = dishes.isNotEmpty;

                      final hasAllergyMatch = _selectedAllergyFilter != null &&
                          dishes.any((d) => d.allergies.any((a) => a.contains('$_selectedAllergyFilter')));

                      Color numColor = Colors.white;
                      if (isSunday) numColor = const Color(0xFFFF6B6B);
                      if (isSaturday) numColor = const Color(0xFF4D96FF);

                      return InkWell(
                        onTap: hasMeal ? () => _showDayMealDetail(context, dayNum, dayMeal) : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: hasAllergyMatch
                                ? const Color(0xFFFFD166).withOpacity(0.12)
                                : (isToday
                                    ? const Color(0xFF2EC4B6).withOpacity(0.1)
                                    : (isWeekend
                                        ? Colors.white.withOpacity(0.015)
                                        : Colors.white.withOpacity(0.035))),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isToday
                                  ? const Color(0xFF2EC4B6)
                                  : (hasAllergyMatch
                                      ? const Color(0xFFFFD166)
                                      : Colors.white.withOpacity(0.08)),
                              width: isToday ? 1.8 : 0.8,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isToday ? FontWeight.w900 : FontWeight.bold,
                                      color: isToday ? const Color(0xFF2EC4B6) : numColor,
                                    ),
                                  ),
                                  if (isToday)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2EC4B6),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '오늘',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  if (!isToday && dayMeal != null && dayMeal.calories.isNotEmpty)
                                    Text(
                                      dayMeal.calories.replaceAll('kcal', 'k').trim(),
                                      style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Expanded(
                                child: hasMeal
                                    ? ListView.builder(
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: dishes.length > 4 ? 4 : dishes.length,
                                        itemBuilder: (_, dIdx) {
                                          final d = dishes[dIdx];
                                          final match = _selectedAllergyFilter != null &&
                                              d.allergies.any((a) => a.contains('$_selectedAllergyFilter'));
                                          return Text(
                                            d.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10,
                                              height: 1.25,
                                              fontWeight: match ? FontWeight.w900 : FontWeight.w500,
                                              color: match
                                                  ? const Color(0xFFFFD166)
                                                  : (isToday ? Colors.white : const Color(0xFFCBD5E1)),
                                            ),
                                          );
                                        },
                                      )
                                    : (isWeekend
                                        ? const SizedBox()
                                        : Center(
                                            child: Text(
                                              '급식 없음',
                                              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.2)),
                                            ),
                                          )),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
