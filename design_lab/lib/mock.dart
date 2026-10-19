import 'package:flutter/material.dart';

/// 디자인 시안 전용 목업 데이터 (기능 없음)
class Period {
  final int no;
  final String subject;
  final String teacher;
  final String time;
  final Color color;
  final IconData icon;
  final String book;
  const Period(this.no, this.subject, this.teacher, this.time, this.color, this.icon, this.book);
}

const periods = <Period>[
  Period(1, '수학', '이수학', '09:00', Color(0xFF4D96FF), Icons.functions_rounded, '수학 I'),
  Period(2, '국어', '김국어', '10:00', Color(0xFFFF6B6B), Icons.menu_book_rounded, '문학'),
  Period(3, '영어', '박영어', '11:00', Color(0xFF00C896), Icons.translate_rounded, 'English'),
  Period(4, '과학', '최과학', '12:00', Color(0xFF7F5AF0), Icons.science_rounded, '통합과학'),
  Period(5, '체육', '정체육', '13:40', Color(0xFFFF8906), Icons.sports_soccer_rounded, '체육'),
  Period(6, '창의체험', '한담임', '14:40', Color(0xFFFFD166), Icons.palette_rounded, '창체'),
];

const nowPeriod = 3; // index (4교시 진행 중)

const mealMenu = <String>['현미잡곡밥', '소고기미역국', '닭갈비볶음', '시금치나물', '배추김치', '딸기요거트'];
const mealAllergy = <String>['⚠ 난류·우유', '', '⚠ 닭고기·대두', '', '', '⚠ 우유'];

const notices = <(String, String)>[
  ('10/22', '2학기 학부모 상담 주간 안내'),
  ('10/24', '체육대회 반 티셔츠 수합'),
  ('10/28', '진로 적성검사 (3교시)'),
  ('10/31', '핼러윈 환경미화 심사'),
];

class FileItem {
  final String name;
  final String kind;
  final String size;
  final Color color;
  final IconData icon;
  const FileItem(this.name, this.kind, this.size, this.color, this.icon);
}

const files = <FileItem>[
  FileItem('수학I_03단원_삼각함수.pdf', 'PDF', '3.4 MB', Color(0xFFFF6B6B), Icons.picture_as_pdf_rounded),
  FileItem('2026_모의고사_기출분석.pptx', 'PPT', '8.9 MB', Color(0xFFFF8906), Icons.slideshow_rounded),
  FileItem('삼각함수_지도안.hwpx', 'HWP', '1.4 MB', Color(0xFF4D96FF), Icons.description_rounded),
  FileItem('[전자교과서] 수학I 비상', 'TBP', '45 MB', Color(0xFF7F5AF0), Icons.auto_stories_rounded),
  FileItem('함수의극한_인터랙티브', 'HTMLP', '3.1 MB', Color(0xFF00C4CC), Icons.co_present_rounded),
  FileItem('10월19일_3교시_판서', 'PEN', '5.1 MB', Color(0xFF00C896), Icons.draw_rounded),
  FileItem('인공지능수학_특강자료.pdf', 'PDF', '4.2 MB', Color(0xFFFF6B6B), Icons.picture_as_pdf_rounded),
  FileItem('미적분_개념노트.pptx', 'PPT', '6.7 MB', Color(0xFFFF8906), Icons.slideshow_rounded),
];

/// 교과서 표지 목업 (실제 교과서 사진 느낌 연출)
class BookCover extends StatelessWidget {
  final Period p;
  final double radius;
  final bool showTitle;
  final bool isHero;
  const BookCover(this.p, {super.key, this.radius = 12, this.showTitle = true, this.isHero = false});

  @override
  Widget build(BuildContext context) {
    if (!isHero) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.color, Color.lerp(p.color, Colors.black, 0.45)!],
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 10, offset: const Offset(2, 4))],
        ),
        child: Stack(children: [
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(p.icon, size: 70, color: Colors.white.withOpacity(0.18)),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 6,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.horizontal(left: Radius.circular(radius)),
              ),
            ),
          ),
          if (showTitle)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(p.book, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
        ]),
      );
    }

    // [isHero: true] 지금 수업 중인 대형 교과서 표지
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(p.color, Colors.white, 0.15)!,
            p.color,
            Color.lerp(p.color, Colors.black, 0.55)!,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 24, offset: const Offset(4, 12)),
          BoxShadow(color: p.color.withOpacity(0.35), blurRadius: 36, offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(children: [
        // 책 배경 은은한 대형 패턴 아이콘
        Positioned(
          right: -20,
          bottom: -20,
          child: Icon(p.icon, size: 180, color: Colors.white.withOpacity(0.15)),
        ),
        // 왼쪽 책등 (Spine) 입체 하이라이트
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(
            width: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.4),
                  Colors.white.withOpacity(0.1),
                  Colors.black.withOpacity(0.3),
                ],
              ),
              borderRadius: BorderRadius.horizontal(left: Radius.circular(radius)),
            ),
          ),
        ),
        // 책 표지 내용
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 상단: 교육과정 검정 태그
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: const Text('2022 개정 · 검정', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                const Text('고등학교', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),

              // 중앙: 교과서 이름 크게
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.book,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      letterSpacing: -0.5,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(1, 2))],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(2)),
                  ),
                ],
              ),

              // 하단: 출판사 및 저자 표기
              Row(children: [
                const Icon(Icons.menu_book_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${p.subject} 교과서',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${p.teacher} 저',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

/// 1920x1080 / 1280x800 고정 캔버스를 화면에 맞게 축소
class DesignFrame extends StatelessWidget {
  final double w, h;
  final Widget child;
  const DesignFrame({super.key, required this.w, required this.h, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF000000),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(width: w, height: h, child: ClipRect(child: child)),
        ),
      ),
    );
  }
}

/// 화면 하단에 마우스를 올리면 나타나는 데모 컨트롤 (목록 이동 / 현재 교시 전환)
class DemoBar extends StatefulWidget {
  final String title;
  final int? value;
  final int count;
  final ValueChanged<int>? onChanged;
  const DemoBar({super.key, required this.title, this.value, this.count = 0, this.onChanged});

  @override
  State<DemoBar> createState() => _DemoBarState();
}

class _DemoBarState extends State<DemoBar> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 44,
      child: MouseRegion(
        opaque: false,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: IgnorePointer(
          ignoring: !hover,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: hover ? 1 : 0,
            child: Center(
              child: Material(
                color: Colors.black.withOpacity(0.82),
                borderRadius: BorderRadius.circular(30),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('← 목록')),
                    Text(widget.title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    if (widget.value != null) ...[
                      const SizedBox(width: 14),
                      const Text('현재 교시', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      for (int i = 0; i < widget.count; i++)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: InkWell(
                            onTap: () => widget.onChanged?.call(i),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: i == widget.value ? const Color(0xFF00F5D4) : Colors.white12),
                              child: Text('${i + 1}', style: TextStyle(color: i == widget.value ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                            ),
                          ),
                        ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
