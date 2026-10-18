import 'package:flutter/material.dart';
export '../../models/meal_models.dart';
import '../../models/meal_models.dart';
import '../../services/meal_vote_service.dart';
import '../../services/neis_service.dart';
import 'monthly_meal_calendar_dialog.dart';

class BstDualMealCard extends StatefulWidget {
  final String schoolName;
  final List<MealDishItem> todayDishes;
  final String todayCalories;
  final List<MealDishItem> tomorrowDishes;
  final String tomorrowCalories;
  final String tomorrowDateLabel;
  final bool isCloudActive;
  final VoidCallback? onCloudToggle;

  // 점심 시간 투표 설정 (예: 12:30 ~ 13:20)
  final TimeOfDay lunchStartTime;
  final TimeOfDay lunchEndTime;
  final DateTime? currentTime;
  final Future<void> Function(String dishName)? onVote;
  final ValueChanged<String>? onShowVoteBreakdown;

  const BstDualMealCard({
    super.key,
    this.schoolName = '양동중학교',
    required this.todayDishes,
    this.todayCalories = '745 kcal',
    required this.tomorrowDishes,
    this.tomorrowCalories = '682 kcal',
    this.tomorrowDateLabel = '다음 급식 (월)',
    this.isCloudActive = false,
    this.onCloudToggle,
    this.lunchStartTime = const TimeOfDay(hour: 12, minute: 30),
    this.lunchEndTime = const TimeOfDay(hour: 13, minute: 20),
    this.currentTime,
    this.onVote,
    this.onShowVoteBreakdown,
  });

  @override
  State<BstDualMealCard> createState() => _BstDualMealCardState();
}

class _BstDualMealCardState extends State<BstDualMealCard> {
  late List<MealDishItem> _todayList;
  final Set<String> _highlightedDishes = {};
  final Map<String, int> _voteCountsMap = {};

  @override
  void initState() {
    super.initState();
    _todayList = List.from(widget.todayDishes);
    MealVoteService.instance.votesNotifier.addListener(_onVotesChanged);
  }

  void _onVotesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant BstDualMealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todayDishes != widget.todayDishes) {
      _todayList = List.from(widget.todayDishes);
    }
  }

  @override
  void dispose() {
    MealVoteService.instance.votesNotifier.removeListener(_onVotesChanged);
    super.dispose();
  }

  DateTime get _now => widget.currentTime ?? DateTime.now();

  bool _isVotingActive() {
    final now = _now;
    final start = DateTime(now.year, now.month, now.day, widget.lunchStartTime.hour, widget.lunchStartTime.minute);
    final endMinus10 = DateTime(now.year, now.month, now.day, widget.lunchEndTime.hour, widget.lunchEndTime.minute - 10);
    return !now.isBefore(start) && now.isBefore(endMinus10);
  }

  bool _isResultRevealed() {
    final now = _now;
    final revealTime = DateTime(now.year, now.month, now.day, widget.lunchEndTime.hour, widget.lunchEndTime.minute - 9);
    final end = DateTime(now.year, now.month, now.day, widget.lunchEndTime.hour, widget.lunchEndTime.minute);
    return !now.isBefore(revealTime) && now.isBefore(end);
  }

  Future<void> _recordVote(MealDishItem dish) async {
    await widget.onVote?.call(dish.name);
    if (mounted) {
      setState(() {
        _voteCountsMap[dish.name] = (_voteCountsMap[dish.name] ?? 0) + 1;
      });
    }
  }

  void _onDishTap(MealDishItem dish) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF162032),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final isVoted = (_voteCountsMap[dish.name] ?? 0) > 0;
        final isHigh = _highlightedDishes.contains(dish.name);
        final canVote = _isVotingActive();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dish.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ 알레르기 유발물질 정보',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFF8906),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dish.allergyInfo.isNotEmpty ? dish.allergyInfo : '알레르기 해당 사항 없음 (안전)',
                      style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // 형광펜 토글
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          if (isHigh) {
                            _highlightedDishes.remove(dish.name);
                          } else {
                            _highlightedDishes.add(dish.name);
                          }
                        });
                        Navigator.pop(ctx);
                      },
                      icon: Icon(
                        isHigh ? Icons.highlight_off : Icons.border_color,
                        color: const Color(0xFF00F5D4),
                      ),
                      label: Text(
                        isHigh ? '형광펜 해제' : '형광펜 표시',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF00F5D4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 최애 메뉴 투표
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: !canVote
                          ? null
                          : () async {
                              await _recordVote(dish);
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('\'${dish.name}\'에 최애 메뉴 투표 완료! (결과는 종료 9분 전 공개)'),
                                  backgroundColor: const Color(0xFF00F5D4),
                                ),
                              );
                            },
                      icon: Icon(
                        isVoted ? Icons.favorite : Icons.favorite_border,
                        color: isVoted ? Colors.redAccent : Colors.black,
                      ),
                      label: Text(
                        isVoted ? '투표 완료' : (canVote ? '최애 메뉴 투표' : '투표 시간 아님'),
                        style: TextStyle(
                          color: isVoted ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isVoted ? Colors.redAccent : const Color(0xFF00F5D4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  int? _selectedAllergyFilter; // 선택된 알레르기 번호 (1: 난류, 2: 우유, 5: 대두, 6: 밀 등)

  void _showVoteBreakdownDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162032),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bar_chart_rounded, color: Color(0xFF00F5D4)),
            SizedBox(width: 8),
            Text('오늘 급식 메뉴별 투표 통계', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '점심시간 ~ 종료 10분 전까지 자유 투표\n종료 9분 전 집계 결과입니다.',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
              ),
              const SizedBox(height: 12),
              ..._todayList.map((d) {
                final myClicks = _voteCountsMap[d.name] ?? 0;
                final voteCount = d.votes > 0 ? d.votes : myClicks;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(d.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F5D4).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$voteCount표', style: const TextStyle(color: Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Color(0xFF00F5D4))),
          ),
        ],
      ),
    );
  }

  bool _isMonthlyView = false;
  Future<Map<int, MealDayInfo>>? _monthMealsFuture;

  void _ensureMonthMealsLoaded() {
    if (_monthMealsFuture == null) {
      final now = widget.currentTime ?? DateTime.now();
      _monthMealsFuture = NeisService().fetchMonthMeals(widget.schoolName, now.year, now.month);
    }
  }

  Widget _buildMonthlyMealGrid() {
    _ensureMonthMealsLoaded();
    final now = widget.currentTime ?? DateTime.now();
    const weekdayLabels = ['월', '화', '수', '목', '금'];

    final allergyLabels = {
      1: '1.난류', 2: '2.우유', 5: '5.대두', 6: '6.밀', 9: '9.토마토/김치', 10: '10.돼지', 15: '15.닭', 16: '16.소'
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Text(
                  '📆 ${now.month}월 월간 급식 달력 (${widget.schoolName})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00F5D4),
                  ),
                ),
                const Spacer(),
                Text(
                  '알레르기 번호 탭 시 해당 식단 강조',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          // 상단 알레르기 선택 칩 가로 스크롤
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: allergyLabels.entries.map((entry) {
                final isSelected = _selectedAllergyFilter == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF00F5D4),
                    backgroundColor: Colors.white.withOpacity(0.06),
                    onSelected: (val) {
                      setState(() {
                        _selectedAllergyFilter = val ? entry.key : null;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<int, MealDayInfo>>(
              future: _monthMealsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)));
                }
                final monthMap = snapshot.data ?? {};
                final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
                final List<Map<String, dynamic>> monthlyItems = [];

                for (int d = 1; d <= daysInMonth; d++) {
                  final curDate = DateTime(now.year, now.month, d);
                  // 평일(월~금)만 급식 목록에 추가
                  if (curDate.weekday >= 1 && curDate.weekday <= 5) {
                    final dayInfo = monthMap[d];
                    final dateLabel = '${now.month}/$d (${weekdayLabels[curDate.weekday - 1]})';
                    final menuStr = dayInfo != null && dayInfo.dishes.isNotEmpty
                        ? dayInfo.dishes.map((e) => e.name).join(', ')
                        : '급식 정보가 없습니다';
                    final kcalStr = dayInfo != null && dayInfo.calories.isNotEmpty ? dayInfo.calories : '';
                    final allergies = dayInfo?.allAllergyIndexes.toList() ?? [];

                    monthlyItems.add({
                      'day': d,
                      'date': dateLabel,
                      'menu': menuStr,
                      'kcal': kcalStr,
                      'allergies': allergies,
                      'isToday': d == now.day,
                    });
                  }
                }

                if (monthlyItems.isEmpty) {
                  return Center(
                    child: Text('이번 달 등록된 급식 식단표가 없습니다.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: monthlyItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 10, color: Colors.white10),
                  itemBuilder: (context, index) {
                    final item = monthlyItems[index];
                    final allergies = (item['allergies'] as List<int>?) ?? [];
                    final isHighlighted = _selectedAllergyFilter != null && allergies.contains(_selectedAllergyFilter);
                    final isToday = item['isToday'] == true;

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? const Color(0xFFFFD166).withOpacity(0.18)
                            : (isToday ? const Color(0xFF00F5D4).withOpacity(0.08) : Colors.transparent),
                        borderRadius: BorderRadius.circular(6),
                        border: isHighlighted
                            ? Border.all(color: const Color(0xFFFFD166), width: 1.2)
                            : (isToday ? Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4), width: 1) : null),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 72,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isHighlighted
                                  ? const Color(0xFFFFD166).withOpacity(0.25)
                                  : (isToday ? const Color(0xFF00F5D4) : const Color(0xFF00F5D4).withOpacity(0.12)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item['date'] as String,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: isHighlighted ? const Color(0xFFFFD166) : (isToday ? Colors.black : const Color(0xFF00F5D4)),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item['menu'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isHighlighted || isToday ? FontWeight.w900 : FontWeight.w600,
                                color: isHighlighted ? const Color(0xFFFFD166) : (isToday ? Colors.white : const Color(0xFFE2E8F0)),
                              ),
                            ),
                          ),
                          if ((item['kcal'] as String).isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              item['kcal'] as String,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final revealResult = _isResultRevealed();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101726).withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 바
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🍱 급식 식단표 (클릭 시 알레르기 & 투표)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. 월간 식단표 달력 버튼
                  InkWell(
                    onTap: () {
                      MonthlyMealCalendarDialog.show(
                        context,
                        schoolName: widget.schoolName,
                        initialDate: _now,
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF00F5D4).withOpacity(0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month_rounded, size: 13, color: Color(0xFF00F5D4)),
                          SizedBox(width: 4),
                          Text(
                            '📆 월간 식단표',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF00F5D4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Cloud 전환 버튼
                  InkWell(
                    onTap: widget.onCloudToggle,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.isCloudActive
                            ? const Color(0xFF00F5D4).withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: widget.isCloudActive
                              ? const Color(0xFF00F5D4)
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text('☁️ ', style: TextStyle(fontSize: 11)),
                          Text(
                            widget.isCloudActive ? '식단표 보기' : 'Cloud 전환',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: widget.isCloudActive
                                  ? const Color(0xFF00F5D4)
                                  : Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 메인 콘텐츠: 월간 보기 or 2열 일간 보기
          Expanded(
            child: _isMonthlyView
                ? _buildMonthlyMealGrid()
                : Row(
              children: [
                // 오늘 점심
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '오늘 점심 (금)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF00F5D4),
                              ),
                            ),
                            Text(
                              widget.todayCalories,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 12, color: Colors.white12),
                        Expanded(
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: _todayList.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 5),
                            itemBuilder: (context, index) {
                              final dish = _todayList[index];
                              final isHigh = _highlightedDishes.contains(dish.name);
                              final localVoteCount = _voteCountsMap[dish.name] ?? 0;
                              final totalServerVotes = MealVoteService.instance.getTotalVotes(dish.name);

                              return InkWell(
                                onTap: () async {
                                  if (_isVotingActive()) {
                                    await _recordVote(dish);
                                  } else {
                                    _onDishTap(dish);
                                  }
                                },
                                onLongPress: () {
                                  if (_isResultRevealed()) {
                                    widget.onShowVoteBreakdown?.call(dish.name);
                                  } else {
                                    _onDishTap(dish);
                                  }
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isHigh
                                        ? const Color(0xFFFFD166).withOpacity(0.25)
                                        : (localVoteCount > 0 ? Colors.redAccent.withOpacity(0.12) : Colors.transparent),
                                    borderRadius: BorderRadius.circular(6),
                                    border: isHigh
                                        ? Border.all(color: const Color(0xFFFFD166))
                                        : (localVoteCount > 0 ? Border.all(color: Colors.redAccent.withOpacity(0.4)) : null),
                                  ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  dish.name,
                                                  style: TextStyle(
                                                    fontSize: 17.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: isHigh
                                                        ? const Color(0xFFFFD166)
                                                        : const Color(0xFFF1F5F9),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (dish.allergies.isNotEmpty) ...[
                                                const SizedBox(width: 6),
                                                Wrap(
                                                  spacing: 3,
                                                  children: dish.allergies.take(3).map((a) => Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.amber.withOpacity(0.18),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: Colors.amber.withOpacity(0.4), width: 0.8),
                                                    ),
                                                    child: Text(
                                                      a,
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w800,
                                                        color: Color(0xFFFFB703),
                                                      ),
                                                    ),
                                                  )).toList(),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (localVoteCount > 0 && !revealResult)
                                          Container(
                                            margin: const EdgeInsets.only(left: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 0.8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.favorite, size: 10, color: Colors.redAccent),
                                                const SizedBox(width: 3),
                                                Text(
                                                  '$localVoteCount',
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    color: Colors.redAccent,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (revealResult && totalServerVotes > 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFD166).withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFFFD166), width: 1),
                                            ),
                                            child: Text(
                                              '$totalServerVotes표 👑',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFFFFD166),
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(width: 10),

                // 내일(다음) 점심
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              widget.tomorrowDateLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF00F5D4),
                              ),
                            ),
                            Text(
                              widget.tomorrowCalories,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 12, color: Colors.white12),
                        Expanded(
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: widget.tomorrowDishes.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 5),
                            itemBuilder: (context, index) {
                              final dish = widget.tomorrowDishes[index];
                              final isHigh = _highlightedDishes.contains(dish.name);
                              final isVoted = (_voteCountsMap[dish.name] ?? 0) > 0;

                              return InkWell(
                                onTap: () {},
                                onLongPress: () {
                                  setState(() {
                                    if (isHigh) {
                                      _highlightedDishes.remove(dish.name);
                                    } else {
                                      _highlightedDishes.add(dish.name);
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isHigh
                                        ? const Color(0xFFFFD166).withOpacity(0.25)
                                        : (isVoted ? Colors.redAccent.withOpacity(0.12) : Colors.transparent),
                                    borderRadius: BorderRadius.circular(6),
                                    border: isHigh
                                        ? Border.all(color: const Color(0xFFFFD166))
                                        : (isVoted ? Border.all(color: Colors.redAccent.withOpacity(0.4)) : null),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                dish.name,
                                                style: TextStyle(
                                                  fontSize: 17.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: isHigh
                                                      ? const Color(0xFFFFD166)
                                                      : const Color(0xFFCBD5E1),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (dish.allergies.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Wrap(
                                                spacing: 3,
                                                children: dish.allergies.take(3).map((a) => Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withOpacity(0.14),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.amber.withOpacity(0.3), width: 0.8),
                                                  ),
                                                  child: Text(
                                                    a,
                                                    style: const TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w800,
                                                      color: Color(0xFFFFB703),
                                                    ),
                                                  ),
                                                )).toList(),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (isVoted)
                                        const Text(' ❤️', style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
