import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BoardestStudentApp());
}

class BoardestStudentApp extends StatelessWidget {
  const BoardestStudentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boardest Student',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          surface: Color(0xFF161922),
          secondary: Color(0xFFFFB703),
        ),
        textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme),
      ),
      home: const StudentHomeScreen(),
    );
  }
}

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  int _currentTabIndex = 0;

  // 기본 사용자 프로필 (구글 로그인 및 설정 모달로 변경 가능)
  String studentName = '김학생';
  String schoolName = '서울중학교';
  int grade = 2;
  int classNum = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161922),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.school_rounded, color: Color(0xFF00F5D4), size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'Boardest Student',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$schoolName $grade-$classNum',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '프로필 설정',
            icon: const Icon(Icons.account_circle_outlined, color: Colors.white70),
            onPressed: _showProfileDialog,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: const [
          _DashboardTab(),
          _AssessmentTab(),
          _TimetableTab(),
          _MealTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (idx) => setState(() => _currentTabIndex = idx),
        backgroundColor: const Color(0xFF161922),
        indicatorColor: const Color(0xFF00F5D4).withOpacity(0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: '홈'),
          NavigationDestination(icon: Icon(Icons.assignment_turned_in_rounded), label: '수행평가'),
          NavigationDestination(icon: Icon(Icons.calendar_month_rounded), label: '시간표'),
          NavigationDestination(icon: Icon(Icons.restaurant_rounded), label: '급식'),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    final nameCtrl = TextEditingController(text: studentName);
    final schoolCtrl = TextEditingController(text: schoolName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('학생 프로필 설정', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: '이름', labelStyle: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: schoolCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: '학교명', labelStyle: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4), foregroundColor: Colors.black),
            onPressed: () {
              setState(() {
                studentName = nameCtrl.text.trim();
                schoolName = schoolCtrl.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 상단 인사말 및 알림장 카드
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D273B), Color(0xFF141926)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: Color(0xFF00F5D4), size: 20),
                  const SizedBox(width: 8),
                  Text('우리 반 알림장', style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '• 내일 3교시 과학 수행평가 실험 보고서 제출일입니다.\n• 학교 디벗 충전 상태 확인하고 등교하세요!',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 수행평가 마감 임박 카드
        Text('🔥 마감 임박 수행평가', style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 10),
        _buildAssessmentSummaryItem('수학 II', '이차방정식 서술형 평가', 'D-2', const Color(0xFFFF6B6B)),
        const SizedBox(height: 8),
        _buildAssessmentSummaryItem('영어', '영미시 낭독 및 해석 제출', 'D-5', const Color(0xFF00F5D4)),
        const SizedBox(height: 20),
        // 오늘의 급식 미리보기
        Text('🍱 오늘의 급식', style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161922),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: const Text(
            '차수수밥, 돈육김치찌개, 안동찜닭, 콩나물무침, 깍두기, 멜론 (812 Kcal)',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildAssessmentSummaryItem(String subject, String title, String dDay, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(dDay, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Text(subject, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _AssessmentTab extends StatelessWidget {
  const _AssessmentTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '수행평가 캘린더 & 체크리스트\n(친구가 구현할 핵심 영역입니다!)',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white60, height: 1.6),
      ),
    );
  }
}

class _TimetableTab extends StatelessWidget {
  const _TimetableTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '오늘의 시간표 및 교시별 남은 시간\n(NEIS API 연동 지원 예정)',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white60, height: 1.6),
      ),
    );
  }
}

class _MealTab extends StatelessWidget {
  const _MealTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '이번 주 급식표 & 알레르기 유발 식품 필터링\n(학교 급식 자동 연동)',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white60, height: 1.6),
      ),
    );
  }
}
