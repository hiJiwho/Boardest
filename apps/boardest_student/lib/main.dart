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
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          surface: Color(0xFF161922),
          secondary: Color(0xFFFFB703),
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

  // 학생 프로필 상태 (설정 다이얼로그나 SharedPreferences로 연동)
  String schoolName = '학교 미설정';
  int grade = 1;
  int classNum = 1;

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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$schoolName $grade학년 $classNum반',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '학교 및 학급 설정',
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: const [
          _TabPlaceholder(
            title: '홈 / 알림장',
            icon: Icons.dashboard_rounded,
            description: '우리 반 알림장, 당일 시간표 요약, 급식 메뉴 등을 한눈에 확인하는 대시보드입니다.',
          ),
          _TabPlaceholder(
            title: '수행평가 & 과제',
            icon: Icons.assignment_turned_in_rounded,
            description: 'RTDB 연동 수행평가 캘린더, D-Day 카운트다운, 학생 개인별 제출 체크리스트를 구현하는 영역입니다.',
          ),
          _TabPlaceholder(
            title: '시간표',
            icon: Icons.calendar_month_rounded,
            description: 'NEIS API 또는 로컬 시간표 연동을 통해 오늘의 수업 및 남은 시간을 표시하는 영역입니다.',
          ),
          _TabPlaceholder(
            title: '급식표',
            icon: Icons.restaurant_rounded,
            description: '오늘 및 이번 주 급식 식단과 알레르기 유발 식품 필터를 제공하는 영역입니다.',
          ),
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

  void _showSettingsDialog() {
    final schoolCtrl = TextEditingController(text: schoolName);
    int selectedGrade = grade;
    int selectedClass = classNum;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E222D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('학교 및 학급 설정', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: schoolCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '학교명 또는 학교코드',
                    labelStyle: TextStyle(color: Colors.white70),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F5D4))),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: selectedGrade,
                        dropdownColor: const Color(0xFF1E222D),
                        decoration: const InputDecoration(labelText: '학년', labelStyle: TextStyle(color: Colors.white70)),
                        items: [1, 2, 3].map((g) => DropdownMenuItem(value: g, child: Text('$g학년'))).toList(),
                        onChanged: (v) => setDlgState(() => selectedGrade = v ?? 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: selectedClass,
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
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.white60))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4), foregroundColor: Colors.black),
                onPressed: () {
                  setState(() {
                    schoolName = schoolCtrl.text.trim().isEmpty ? '학교 미설정' : schoolCtrl.text.trim();
                    grade = selectedGrade;
                    classNum = selectedClass;
                  });
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

class _TabPlaceholder extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;

  const _TabPlaceholder({
    required this.title,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF161922),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: const Color(0xFF00F5D4)),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white60, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
