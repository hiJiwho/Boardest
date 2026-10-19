import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'class_screens.dart';
import 'skins.dart';
import 'teacher_screens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final fontLoader = FontLoader('SiwonhanSeolreim');
    fontLoader.addFont(rootBundle.load('assets/fonts/SEOLEIMcool.ttf'));
    await fontLoader.load();
  } catch (_) {}
  runApp(const DesignLab());
}

class DesignLab extends StatelessWidget {
  const DesignLab({super.key});

  @override
  Widget build(BuildContext context) {
    const skin = MaterialSkin();

    return MaterialApp(
      title: 'Boardest Design Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'SiwonhanSeolreim',
      ),
      initialRoute: '/',
      onGenerateRoute: (s) {
        final name = s.name ?? '/';
        Widget page = const Index();

        if (name == '/class-l') {
          page = const ClassScreenJK(variant: 'L', skin: skin);
        } else if (name == '/class-m') {
          page = const ClassScreenJK(variant: 'M', skin: skin);
        } else if (name == '/class-k') {
          page = const ClassScreenJK(variant: 'K', skin: skin);
        } else if (name == '/class-j') {
          page = const ClassScreenJK(variant: 'J', skin: skin);
        } else if (name == '/teacher-k') {
          page = const TeacherScreenJK(variant: 'K', skin: skin);
        } else if (name == '/teacher-j') {
          page = const TeacherScreenJK(variant: 'J', skin: skin);
        }

        return MaterialPageRoute(settings: s, builder: (_) => page);
      },
    );
  }
}

class Index extends StatelessWidget {
  const Index({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1017),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40), children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('bt', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Boardest Design Lab (K+I 믹스 & Teacher K 확정)', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                Text('시원한 설레임체 전면 번들링 · 대형 교과서 + 하단 진행도', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
            ]),
            const SizedBox(height: 28),

            // Class 신규 L, M (K+I 믹스)
            _sectionHeader('🏫 Class (K+I 믹스 신규안)', '교과서 사진 대폭 확대 · 진행도 하단 전폭 배치 · 순백색 시계 · 바닥 식단표 + 우측 세로 독'),
            const SizedBox(height: 10),
            _designCard(
              context,
              tag: 'Class L (추천)',
              title: 'Class L · K+I 믹스 (대형 교과서 + 하단 전폭 진행도)',
              desc: '교과서 표지 320px 대폭 확대 + 하단 전폭 진행도 영역 + M3 스타일 교과서 썸네일 블록 물레방아.',
              route: '/class-l',
              highlight: true,
            ),
            const SizedBox(height: 10),
            _designCard(
              context,
              tag: 'Class M',
              title: 'Class M · K+I 믹스 (초대형 교과서 + 하단 눈금 게이지)',
              desc: '비수업 64px 콤팩트로 현재 교과서를 340px 초대형으로 극대화 + 하단 0/25/50분 눈금 진행도 게이지.',
              route: '/class-m',
              highlight: true,
            ),
            const SizedBox(height: 10),
            _designCard(
              context,
              tag: 'Class K (이전)',
              title: 'Class K · 교과서 표지 블록형',
              desc: '이전 K안 (비교용).',
              route: '/class-k',
              highlight: false,
            ),

            const SizedBox(height: 32),

            // Teacher 확정 K
            _sectionHeader('👨‍🏫 Teacher (👑 K안 확정)', '좌측 [1~6교시 교사 세로 시간표] + 우측 [OTP & Drive 용량] + [광폭 Cloud]'),
            const SizedBox(height: 10),
            _designCard(
              context,
              tag: 'Teacher K (확정)',
              title: '👑 Teacher K · 확정 디자인',
              desc: '교사용 메인 확정안! 좌측 시간표 타임라인 + 우측 OTP & Drive 사용량(6.3GB/15GB) + 대형 파일함.',
              route: '/teacher-k',
              highlight: true,
            ),
            const SizedBox(height: 10),
            _designCard(
              context,
              tag: 'Teacher J (참고)',
              title: 'Teacher J · 상단 3단 위젯형',
              desc: '이전 J안 (비교용).',
              route: '/teacher-j',
              highlight: false,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00F5D4))),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(fontSize: 12.5, color: Colors.white54)),
    ]);
  }

  Widget _designCard(BuildContext context, {
    required String tag,
    required String title,
    required String desc,
    required String route,
    required bool highlight,
  }) {
    return Card(
      elevation: 0,
      color: highlight ? const Color(0xFF142422) : const Color(0xFF161C24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlight ? const Color(0xFF00F5D4).withOpacity(0.5) : Colors.white10,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pushNamed(context, route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: highlight ? const Color(0xFF00F5D4) : Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: highlight ? Colors.black : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_rounded, color: Color(0xFF00F5D4), size: 22),
          ]),
        ),
      ),
    );
  }
}
