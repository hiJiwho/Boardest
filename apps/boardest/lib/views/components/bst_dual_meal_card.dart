import 'package:flutter/material.dart';
export '../../models/meal_models.dart';
import '../../models/meal_models.dart';
import '../../services/meal_vote_service.dart';

class BstDualMealCard extends StatefulWidget {
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
  String? _votedDish;

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
    return !now.isBefore(revealTime) && !now.isBefore(end);
  }

  Future<void> _recordVote(MealDishItem dish) async {
    await widget.onVote?.call(dish.name);
    if (mounted) setState(() => _votedDish = dish.name);
  }

  void _onDishTap(MealDishItem dish) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF162032),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final isVoted = _votedDish == dish.name;
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
                final voteCount = d.votes > 0 ? d.votes : (_votedDish == d.name ? 1 : 0);
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

  Widget _buildMonthlyMealGrid() {
    // 월간 식단표 그리드 (월~금 주간 단위 리스트)
    final sampleWeeklyMenus = [
      {'date': '10/12 (월)', 'menu': '발아현미밥, 얼큰콩나물국(5), 안동찜닭(5,6,15), 시금치무침, 깍두기(9)', 'kcal': '682 kcal', 'allergies': [5, 6, 9, 15]},
      {'date': '10/13 (화)', 'menu': '차수수밥, 돈육김치찌개(9,10), 삼치데리야끼구이(5,6), 계란말이(1), 총각김치(9)', 'kcal': '715 kcal', 'allergies': [1, 5, 6, 9, 10]},
      {'date': '10/14 (수)', 'menu': '카레라이스(2,5,6,12,13,16,18), 팽이버섯된장국(5,6), 수제치킨텐더(1,5,6,15), 오이양파무침, 깍두기(9)', 'kcal': '760 kcal', 'allergies': [1, 2, 5, 6, 9, 12, 13, 15, 16, 18]},
      {'date': '10/15 (목)', 'menu': '기장밥, 쇠고기뭇국(16), 매콤돼지갈비찜(5,6,10), 숙주나물, 배추김치(9)', 'kcal': '698 kcal', 'allergies': [5, 6, 9, 10, 16]},
      {'date': '10/16 (금)', 'menu': '혼합잡곡밥(5), 순두부찌개(1,5,9,18), 오리훈제채소볶음, 쌈무, 깍두기(9)', 'kcal': '730 kcal', 'allergies': [1, 5, 9, 18]},
    ];

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
                const Text(
                  '📆 월간 급식 달력 & 알레르기 필터',
                  style: TextStyle(
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
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: sampleWeeklyMenus.length,
              separatorBuilder: (_, __) => const Divider(height: 10, color: Colors.white10),
              itemBuilder: (context, index) {
                final item = sampleWeeklyMenus[index];
                final allergies = (item['allergies'] as List<int>?) ?? [];
                final isHighlighted = _selectedAllergyFilter != null && allergies.contains(_selectedAllergyFilter);

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  decoration: BoxDecoration(
                    color: isHighlighted ? const Color(0xFFFFD166).withOpacity(0.18) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: isHighlighted ? Border.all(color: const Color(0xFFFFD166), width: 1.2) : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 72,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isHighlighted ? const Color(0xFFFFD166).withOpacity(0.25) : const Color(0xFF00F5D4).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item['date'] as String,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: isHighlighted ? const Color(0xFFFFD166) : const Color(0xFF00F5D4),
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
                            fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.w600,
                            color: isHighlighted ? const Color(0xFFFFD166) : const Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item['kcal'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
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
                  // 1. 월간 식단표 토글 버튼
                  InkWell(
                    onTap: () => setState(() => _isMonthlyView = !_isMonthlyView),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isMonthlyView
                            ? const Color(0xFFFF8906).withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isMonthlyView
                              ? const Color(0xFFFF8906)
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Text(
                        _isMonthlyView ? '📅 일간 보기' : '📆 월간 식단표',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _isMonthlyView
                              ? const Color(0xFFFF8906)
                              : Colors.white.withOpacity(0.85),
                        ),
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
                              final isVoted = _votedDish == dish.name;

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
                                        if (isVoted)
                                          const Text(' ❤️', style: TextStyle(fontSize: 12)),
                                        if (revealResult && MealVoteService.instance.getTotalVotes(dish.name) > 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${MealVoteService.instance.getTotalVotes(dish.name)}표 👑',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.redAccent,
                                                fontWeight: FontWeight.bold,
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
                              final isVoted = _votedDish == dish.name;

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
