import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/assessment_item.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BoardestStudentApp());
}

class BoardestStudentApp extends StatelessWidget {
  const BoardestStudentApp({super.key});

  static const String appVersion = '5.5.3';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boardest Student',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C101A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          surface: Color(0xFF141926),
          secondary: Color(0xFF7F5AF0),
          error: Color(0xFFEF4565),
        ),
        textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme),
      ),
      home: const StudentMainShell(),
    );
  }
}

class StudentMainShell extends StatefulWidget {
  const StudentMainShell({super.key});

  @override
  State<StudentMainShell> createState() => _StudentMainShellState();
}

class _StudentMainShellState extends State<StudentMainShell> {
  int _currentTabIndex = 0;

  // Student Profile
  String _schoolName = '양동중학교';
  String _schoolCode = '44134';
  int _grade = 1;
  int _classNum = 1;
  bool _isLoading = true;

  // Data
  List<AssessmentItem> _assessments = [];
  Set<String> _completedAssessmentIds = {};
  List<Map<String, dynamic>> _schoolNotices = [];
  String _mealCalorie = '';
  List<String> _mealDishes = [];

  // Assessments Filter
  String _selectedSubjectFilter = '전체';
  String _assessmentSearchQuery = '';

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadProfileAndData();
    // 30초마다 백그라운드 데이터 자동 갱신
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfileAndData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _schoolName = prefs.getString('student_school_name') ?? '양동중학교';
      _schoolCode = prefs.getString('student_school_code') ?? '44134';
      _grade = prefs.getInt('student_grade') ?? 1;
      _classNum = prefs.getInt('student_class_num') ?? 1;
      _completedAssessmentIds = (prefs.getStringList('student_completed_assessments') ?? []).toSet();
    });
    await _refreshData();
  }

  Future<void> _saveProfile(String school, String code, int g, int c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_school_name', school);
    await prefs.setString('student_school_code', code);
    await prefs.setInt('student_grade', g);
    await prefs.setInt('student_class_num', c);
    setState(() {
      _schoolName = school;
      _schoolCode = code;
      _grade = g;
      _classNum = c;
    });
    await _refreshData();
  }

  Future<void> _toggleAssessmentCompleted(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_completedAssessmentIds.contains(id)) {
        _completedAssessmentIds.remove(id);
      } else {
        _completedAssessmentIds.add(id);
      }
    });
    await prefs.setStringList('student_completed_assessments', _completedAssessmentIds.toList());
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchAssessments(),
      _fetchNotices(),
      _fetchMeal(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAssessments() async {
    try {
      final safeSchool = _schoolCode.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final url = 'https://jiwhosboardest-default-rtdb.firebaseio.com/school_assessments/$safeSchool.json';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && res.body != 'null' && res.body.isNotEmpty) {
        final data = json.decode(res.body);
        final List<AssessmentItem> list = [];
        if (data is Map) {
          data.forEach((key, val) {
            if (val is Map) {
              try {
                final item = AssessmentItem.fromJson(Map<String, dynamic>.from(val));
                // 내 학년 및 내 반(또는 0인 전학급 공통)에 해당하는 수행평가만 필터
                if (item.grade == _grade && (item.classNum == 0 || item.classNum == _classNum)) {
                  list.add(item);
                }
              } catch (_) {}
            }
          });
        }
        // 마감일 오름차순 (임박한 수행평가 우선)
        list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        if (mounted) setState(() => _assessments = list);
      } else {
        if (mounted) setState(() => _assessments = []);
      }
    } catch (e) {
      debugPrint('[Student] Assessments fetch error: $e');
    }
  }

  Future<void> _fetchNotices() async {
    try {
      final safeSchool = _schoolCode.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final url = 'https://jiwhosboardest-default-rtdb.firebaseio.com/school_notices/$safeSchool.json';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && res.body != 'null' && res.body.isNotEmpty) {
        final data = json.decode(res.body);
        final List<Map<String, dynamic>> list = [];
        if (data is Map) {
          data.forEach((key, val) {
            if (val is Map) {
              list.add(Map<String, dynamic>.from(val));
            }
          });
        }
        if (mounted) setState(() => _schoolNotices = list);
      }
    } catch (_) {}
  }

  Future<void> _fetchMeal() async {
    try {
      final nowStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final url = 'https://open.neis.go.kr/hub/mealServiceDietInfo?Type=json&pIndex=1&pSize=5&ATPT_OFCDC_SC_CODE=B10&SD_SCHUL_CODE=7091484&MLSV_YMD=$nowStr';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final rows = data['mealServiceDietInfo']?[1]?['row'] as List?;
        if (rows != null && rows.isNotEmpty) {
          final row = rows.first;
          final rawDish = (row['DDISH_NM'] ?? '').toString();
          final dishes = rawDish
              .replaceAll(RegExp(r'\([0-9.]+\)'), '')
              .split(RegExp(r'<br\s*/?>|\n'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          final cal = (row['CAL_INFO'] ?? '').toString();
          if (mounted) {
            setState(() {
              _mealDishes = dishes;
              _mealCalorie = cal;
            });
          }
          return;
        }
      }
    } catch (_) {}

    // Fallback Mock Lunch
    if (mounted) {
      setState(() {
        _mealDishes = ['현미찹쌀밥', '쇠고기미역국', '돼지갈비찜', '두부조림', '배추김치', '방울토마토'];
        _mealCalorie = '745.2 Kcal';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF141926),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.school_rounded, color: Color(0xFF00F5D4), size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'BOARDEST',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.5),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('STUDENT', style: TextStyle(color: Color(0xFF00F5D4), fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                Text(
                  '$_schoolName · $_grade학년 $_classNum반',
                  style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: _isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F5D4)))
                : const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _refreshData,
          ),
          IconButton(
            tooltip: '학교 및 학급 변경',
            icon: const Icon(Icons.tune_rounded, color: Colors.white70),
            onPressed: _showSettingsDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildHomeDashboardTab(),
          _buildAssessmentsTab(),
          _buildTimetableTab(),
          _buildMealTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10, width: 0.8)),
        ),
        child: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (idx) => setState(() => _currentTabIndex = idx),
          backgroundColor: const Color(0xFF141926),
          indicatorColor: const Color(0xFF00F5D4).withValues(alpha: 0.2),
          elevation: 0,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: '홈'),
            NavigationDestination(icon: Icon(Icons.assignment_turned_in_rounded), label: '수행평가'),
            NavigationDestination(icon: Icon(Icons.calendar_month_rounded), label: '시간표'),
            NavigationDestination(icon: Icon(Icons.restaurant_rounded), label: '급식'),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── TAB 1: 홈 대시보드 ─────────────────────────
  Widget _buildHomeDashboardTab() {
    final pendingCount = _assessments.where((a) => !_completedAssessmentIds.contains(a.id) && a.dDay >= 0).length;
    final urgentAssessment = _assessments.where((a) => !_completedAssessmentIds.contains(a.id) && a.dDay >= 0).firstOrNull;

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF00F5D4),
      backgroundColor: const Color(0xFF161922),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 환영 및 학급 요약 배너
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF16233B), Color(0xFF0E1726)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '안녕하세요! 👋',
                        style: GoogleFonts.notoSansKr(fontSize: 14, color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_schoolName $_grade학년 $_classNum반',
                        style: GoogleFonts.notoSansKr(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pendingCount > 0 ? '📅 제출 예정인 수행평가가 $pendingCount건 있습니다.' : '✨ 현재 예정된 미완료 수행평가가 없습니다!',
                        style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      const Text('미완료', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      Text(
                        '$pendingCount',
                        style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF00F5D4)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. 가장 임박한 수행평가 카드
          if (urgentAssessment != null) ...[
            _sectionHeader('⏰ 가장 임박한 수행평가', onAction: () => setState(() => _currentTabIndex = 1)),
            const SizedBox(height: 8),
            _buildAssessmentCard(urgentAssessment, isUrgentHighlight: true),
            const SizedBox(height: 16),
          ],

          // 3. 오늘의 급식 요약 카드
          _sectionHeader('🍱 오늘의 급식 메뉴', onAction: () => setState(() => _currentTabIndex = 3)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141926),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFFB703), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '중식 (${DateFormat('M월 d일 EEE', 'ko_KR').format(DateTime.now())})',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    if (_mealCalorie.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                        child: Text(_mealCalorie, style: const TextStyle(fontSize: 11, color: Color(0xFFFFB703))),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _mealDishes.map((dish) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(dish, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. 학교 행사 및 공지사항
          if (_schoolNotices.isNotEmpty) ...[
            _sectionHeader('📢 학교 공지 & 행사'),
            const SizedBox(height: 8),
            for (final notice in _schoolNotices.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141926),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF7F5AF0).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_rounded, color: Color(0xFF7F5AF0), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notice['title']?.toString() ?? '공지사항',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            if (notice['teacherName'] != null)
                              Text(
                                '${notice['teacherName']} 선생님',
                                style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────── TAB 2: 수행평가 & 과제 ─────────────────────────
  Widget _buildAssessmentsTab() {
    final filtered = _assessments.where((item) {
      if (_selectedSubjectFilter != '전체' && item.subject != _selectedSubjectFilter) {
        return false;
      }
      if (_assessmentSearchQuery.isNotEmpty) {
        final q = _assessmentSearchQuery.toLowerCase();
        final match = item.title.toLowerCase().contains(q) ||
            item.subject.toLowerCase().contains(q) ||
            item.description.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();

    // 과목 목록 추출
    final subjects = ['전체', ..._assessments.map((a) => a.subject).toSet()];

    return Column(
      children: [
        // 검색 & 과목 칩
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: const Color(0xFF141926),
          child: Column(
            children: [
              TextField(
                onChanged: (val) => setState(() => _assessmentSearchQuery = val.trim()),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '수행평가 과목, 제목 검색...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00F5D4), size: 20),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: subjects.map((sub) {
                    final isSel = _selectedSubjectFilter == sub;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(sub),
                        selected: isSel,
                        onSelected: (_) => setState(() => _selectedSubjectFilter = sub),
                        selectedColor: const Color(0xFF00F5D4),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        labelStyle: TextStyle(
                          color: isSel ? Colors.black : Colors.white70,
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                        ),
                        side: BorderSide(color: isSel ? const Color(0xFF00F5D4) : Colors.white12),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // 수행평가 리스트
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_turned_in_outlined, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text(
                        _assessments.isEmpty
                            ? '현재 등록된 수행평가 공지가 없습니다.'
                            : '검색 조건에 맞는 수행평가가 없습니다.',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    return _buildAssessmentCard(filtered[i]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAssessmentCard(AssessmentItem item, {bool isUrgentHighlight = false}) {
    final isDone = _completedAssessmentIds.contains(item.id);
    final dDay = item.dDay;

    Color badgeBg;
    Color badgeFg;
    if (dDay < 0) {
      badgeBg = Colors.white10;
      badgeFg = Colors.white54;
    } else if (dDay == 0 || dDay == 1) {
      badgeBg = const Color(0xFFEF4565).withValues(alpha: 0.2);
      badgeFg = const Color(0xFFEF4565);
    } else if (dDay <= 3) {
      badgeBg = const Color(0xFFFFB703).withValues(alpha: 0.2);
      badgeFg = const Color(0xFFFFB703);
    } else {
      badgeBg = const Color(0xFF00F5D4).withValues(alpha: 0.2);
      badgeFg = const Color(0xFF00F5D4);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showAssessmentDetailModal(item),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141926),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUrgentHighlight
                  ? const Color(0xFF00F5D4).withValues(alpha: 0.4)
                  : (isDone ? Colors.white10 : Colors.white.withValues(alpha: 0.15)),
              width: isUrgentHighlight ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      item.dDayString,
                      style: GoogleFonts.outfit(color: badgeFg, fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      item.subject,
                      style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  // 완료 체크 버튼
                  IconButton(
                    icon: Icon(
                      isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: isDone ? const Color(0xFF00F5D4) : Colors.white38,
                      size: 24,
                    ),
                    onPressed: () => _toggleAssessmentCompleted(item.id),
                    tooltip: isDone ? '제출 완료 취소' : '제출 완료 표시',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isDone ? Colors.white54 : Colors.white,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.event_rounded, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Text(
                    '${DateFormat('yyyy.MM.dd(EEE)', 'ko_KR').format(item.dueDate)} ${item.period > 0 ? '${item.period}교시' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.person_rounded, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Text(
                    '${item.authorName} 선생님',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  if (item.points > 0) ...[
                    const Spacer(),
                    Text('${item.points}점', style: const TextStyle(fontSize: 12, color: Color(0xFF00F5D4), fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAssessmentDetailModal(AssessmentItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141926),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF00F5D4).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text(item.subject, style: const TextStyle(color: Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  Text(item.dDayString, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF00F5D4))),
                ],
              ),
              const SizedBox(height: 12),
              Text(item.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 16),
              if (item.description.isNotEmpty) ...[
                const Text('📝 상세 설명', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item.description, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 12),
              ],
              if (item.range.isNotEmpty) ...[
                const Text('📖 수행 범위', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item.range, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                const SizedBox(height: 12),
              ],
              if (item.precautions.isNotEmpty) ...[
                const Text('⚠️ 주의사항', style: TextStyle(color: Color(0xFFEF4565), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item.precautions, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('담당: ${item.authorName} 선생님', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text('${DateFormat('yyyy.MM.dd').format(item.dueDate)} 마감', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────── TAB 3: 시간표 ─────────────────────────
  Widget _buildTimetableTab() {
    final days = ['월', '화', '수', '목', '금'];
    final sampleSubjects = [
      ['국어', '수학', '영어', '과학', '체육', '도덕', '사회'],
      ['수학', '과학', '음악', '미술', '국어', '영어', '역사'],
      ['영어', '사회', '수학', '국어', '기술가정', '체육', '동아리'],
      ['과학', '국어', '역사', '수학', '영어', '음악', '한문'],
      ['도덕', '영어', '과학', '사회', '체육', '수학', '진로'],
    ];

    final nowWeekday = DateTime.now().weekday;
    final activeDayIdx = (nowWeekday >= 1 && nowWeekday <= 5) ? (nowWeekday - 1) : 0;

    return DefaultTabController(
      initialIndex: activeDayIdx,
      length: 5,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF141926),
            child: TabBar(
              indicatorColor: const Color(0xFF00F5D4),
              labelColor: const Color(0xFF00F5D4),
              unselectedLabelColor: Colors.white54,
              tabs: days.map((d) => Tab(text: '$d요일')).toList(),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: List.generate(5, (dayIdx) {
                final daySubjects = sampleSubjects[dayIdx];
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: daySubjects.length,
                  itemBuilder: (ctx, i) {
                    final period = i + 1;
                    final subject = daySubjects[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141926),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$period',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: const Color(0xFF00F5D4)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                subject,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                              child: const Text('교실', style: TextStyle(fontSize: 11, color: Colors.white70)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── TAB 4: 급식 식단표 ─────────────────────────
  Widget _buildMealTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF141926),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFB703).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.restaurant_rounded, color: Color(0xFFFFB703), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '오늘의 급식 (${DateFormat('M월 d일 EEE', 'ko_KR').format(DateTime.now())})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ],
                  ),
                  if (_mealCalorie.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFFFB703).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text(_mealCalorie, style: const TextStyle(color: Color(0xFFFFB703), fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (final dish in _mealDishes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF00F5D4)),
                      const SizedBox(width: 10),
                      Text(dish, style: const TextStyle(fontSize: 14.5, color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onAction}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        if (onAction != null)
          InkWell(
            onTap: onAction,
            child: const Text('전체보기 >', style: TextStyle(fontSize: 12, color: Color(0xFF00F5D4), fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  void _showSettingsDialog() {
    final schoolCtrl = TextEditingController(text: _schoolName);
    final codeCtrl = TextEditingController(text: _schoolCode);
    int selectedGrade = _grade;
    int selectedClass = _classNum;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF161922),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('내 학교 및 학급 설정', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: schoolCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: '학교 이름',
                      labelStyle: TextStyle(color: Colors.white70),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: '학교 코드 (RTDB)',
                      labelStyle: TextStyle(color: Colors.white70),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedGrade,
                          dropdownColor: const Color(0xFF1E222D),
                          decoration: const InputDecoration(labelText: '학년', labelStyle: TextStyle(color: Colors.white70)),
                          items: [1, 2, 3, 4, 5, 6].map((g) => DropdownMenuItem(value: g, child: Text('$g학년'))).toList(),
                          onChanged: (v) => setDlgState(() => selectedGrade = v ?? 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedClass,
                          dropdownColor: const Color(0xFF1E222D),
                          decoration: const InputDecoration(labelText: '반', labelStyle: TextStyle(color: Colors.white70)),
                          items: List.generate(15, (i) => i + 1).map((c) => DropdownMenuItem(value: c, child: Text('$c반'))).toList(),
                          onChanged: (v) => setDlgState(() => selectedClass = v ?? 1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.white60))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4), foregroundColor: Colors.black),
                onPressed: () {
                  _saveProfile(
                    schoolCtrl.text.trim().isEmpty ? '양동중학교' : schoolCtrl.text.trim(),
                    codeCtrl.text.trim().isEmpty ? '44134' : codeCtrl.text.trim(),
                    selectedGrade,
                    selectedClass,
                  );
                  Navigator.pop(ctx);
                },
                child: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}
