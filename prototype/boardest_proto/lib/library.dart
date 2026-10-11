import 'package:flutter/material.dart';
import 'ui.dart';

/// 자료함 항목
class Item {
  final String title;
  final String source; // TBP | Cloud | Canva
  final Subject subject;
  final String meta;
  const Item(this.title, this.source, this.subject, this.meta);
}

final items = <Item>[
  Item('수학 2-1 교과서', 'TBP', subjects[1], '암호화 · 248p'),
  Item('국어 2-1 교과서', 'TBP', subjects[0], '암호화 · 232p'),
  Item('영어 2 교과서', 'TBP', subjects[2], '암호화 · 196p'),
  Item('1단원 도형 PPT', 'Cloud', subjects[1], '수정 오늘 09:12'),
  Item('받아쓰기 학습지.pdf', 'Cloud', subjects[0], '수정 어제'),
  Item('과학 실험 영상', 'Cloud', subjects[3], '48MB · mp4'),
  Item('도형 수업 디자인', 'Canva', subjects[1], '수정 2일 전'),
  Item('영어 퀴즈 슬라이드', 'Canva', subjects[2], '수정 3일 전'),
  Item('사회 지도 활동', 'Canva', subjects[4], '수정 1주 전'),
];

Color sourceColor(String s) => switch (s) { 'TBP' => T.orange, 'Cloud' => T.teal, _ => T.purple };
IconData sourceIcon(String s) => switch (s) { 'TBP' => Icons.menu_book_rounded, 'Cloud' => Icons.cloud_rounded, _ => Icons.palette_rounded };

/// 통합 자료함 (TBP · Cloud · Canva)
class LibraryView extends StatefulWidget {
  final VoidCallback onClose;
  final bool compact;
  const LibraryView({super.key, required this.onClose, this.compact = false});
  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  int src = 0; // 0 전체
  int sel = 0;
  String q = '';
  final queue = <String>['3교시 수학 2-1 교과서'];
  static const srcs = ['전체', 'TBP', 'Cloud', 'Canva'];

  List<Item> get list => items.where((e) => (src == 0 || e.source == srcs[src]) && e.title.contains(q)).toList();

  @override
  Widget build(BuildContext context) {
    final l = list;
    if (sel >= l.length) sel = 0;
    final cur = l.isEmpty ? null : l[sel];
    return Container(
      color: T.bg,
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(children: [
          Pressable(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: T.card2, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Text('자료함', style: T.h(26)),
          const SizedBox(width: 12),
          const PillTag('Cloud 연결됨 · RAM 전용', icon: Icons.lock_clock_rounded),
          const Spacer(),
          SizedBox(
            width: 320,
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '통합 검색 — 파일명 · 교과 · 단원',
                hintStyle: const TextStyle(color: T.sub, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: T.sub),
                filled: true,
                fillColor: T.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 170,
              child: Column(children: [
                for (var i = 0; i < srcs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Pressable(
                      onTap: () => setState(() {
                        src = i;
                        sel = 0;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: src == i ? (i == 0 ? T.teal : sourceColor(srcs[i])) : T.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: T.line),
                        ),
                        child: Row(children: [
                          Icon(i == 0 ? Icons.apps_rounded : sourceIcon(srcs[i]), color: src == i ? const Color(0xFF04141A) : T.sub, size: 20),
                          const SizedBox(width: 10),
                          Text(srcs[i], style: T.h(15, c: src == i ? const Color(0xFF04141A) : Colors.white)),
                        ]),
                      ),
                    ),
                  ),
                const Spacer(),
                const PillTag('Canva 연결됨', color: T.purple, icon: Icons.link_rounded),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: widget.compact ? 160 : 200, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.92),
                itemCount: l.length,
                itemBuilder: (_, i) {
                  final it = l[i];
                  return Reveal(
                    delayMs: i * 40,
                    child: Pressable(
                      onTap: () => setState(() => sel = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: T.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: sel == i ? sourceColor(it.source) : T.line, width: sel == i ? 2 : 1),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(colors: [it.subject.color, Color.lerp(it.subject.color, Colors.black, .5)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                              ),
                              alignment: Alignment.center,
                              child: Icon(it.subject.icon, size: 40, color: Colors.white70),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h(13)),
                          const SizedBox(height: 2),
                          Row(children: [
                            Icon(sourceIcon(it.source), size: 12, color: sourceColor(it.source)),
                            const SizedBox(width: 4),
                            Expanded(child: Text('${it.source} · ${it.meta}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h(10.5, c: T.sub, w: FontWeight.w600))),
                          ]),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (!widget.compact) ...[
              const SizedBox(width: 16),
              SizedBox(
                width: 270,
                child: Glass(
                  child: cur == null
                      ? const SizedBox()
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('미리보기', style: T.h(12, c: T.sub)),
                          const SizedBox(height: 10),
                          AspectRatio(
                            aspectRatio: 16 / 10,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(colors: [cur.subject.color, Color.lerp(cur.subject.color, Colors.black, .55)!]),
                              ),
                              child: Icon(cur.subject.icon, size: 52, color: Colors.white70),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(cur.title, style: T.h(17)),
                          const SizedBox(height: 4),
                          Text('${cur.source} · ${cur.meta}', style: T.h(12, c: T.sub, w: FontWeight.w600)),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: GradButton('열기', icon: Icons.open_in_full_rounded, onTap: () => _toast('“${cur.title}” 열기')),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: GradButton('판서와 함께 열기', icon: Icons.draw_rounded, colors: const [T.purple, T.violet], dark: false, onTap: () => _toast('판서 오버레이로 열기')),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: GradButton('수업 큐에 추가', icon: Icons.playlist_add_rounded, colors: const [T.card2, T.card2], dark: false, onTap: () {
                              setState(() => queue.add('4교시 ${cur.title}'));
                              _toast('수업 큐에 추가됨');
                            }),
                          ),
                          const SizedBox(height: 14),
                          Text('오늘 수업 큐', style: T.h(12, c: T.sub)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: [for (final e in queue) PillTag(e, color: T.orange)]),
                        ]),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: T.card2, behavior: SnackBarBehavior.floating, width: 320));
}

/// 통합 Cloud 로그인 시트 (QR · OTP · 등록 교사)
class CloudLoginSheet extends StatefulWidget {
  const CloudLoginSheet({super.key});
  @override
  State<CloudLoginSheet> createState() => _CloudLoginSheetState();
}

class _CloudLoginSheetState extends State<CloudLoginSheet> {
  int tab = 0;
  String pin = '';
  bool saveDevice = false;
  bool done = false;

  void _press(String k) {
    setState(() {
      if (k == '⌫') {
        if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
      } else if (k == 'C') {
        pin = '';
      } else if (pin.length < 6) {
        pin += k;
        if (pin.length == 6) _finish();
      }
    });
  }

  Future<void> _finish() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => done = true);
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _warn() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1B0E16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: T.red)),
        title: Row(children: [const Icon(Icons.warning_amber_rounded, color: T.red), const SizedBox(width: 8), Text('보안 취약 경고', style: T.h(18, c: T.red))]),
        content: Text('공용 전자칠판에 계정을 영구 저장하면 다른 사람이나 학생이 교사 계정에 접근할 수 있습니다.\n정말 이 기기에 저장할까요?', style: T.h(14, c: Colors.white70, w: FontWeight.w500)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소 (RAM에만 유지)')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: T.red), onPressed: () => Navigator.pop(c, true), child: const Text('동의하고 저장')),
        ],
      ),
    );
    if (ok == true) setState(() => saveDevice = true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
        child: Glass(
          radius: 28,
          padding: const EdgeInsets.all(22),
          border: T.mint.withValues(alpha: 0.35),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: done
                ? Center(
                    key: const ValueKey('ok'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.elasticOut,
                        builder: (_, v, c) => Transform.scale(scale: v, child: c),
                        child: const Icon(Icons.check_circle_rounded, color: T.mint, size: 96),
                      ),
                      const SizedBox(height: 14),
                      Text('Cloud 연결 완료', style: T.h(26)),
                      const SizedBox(height: 6),
                      Text('토큰은 이 칠판의 RAM에만 보관되며 종료 시 소각됩니다', style: T.h(13, c: T.sub, w: FontWeight.w600)),
                    ]),
                  )
                : Column(key: const ValueKey('form'), children: [
                    Row(children: [
                      const Icon(Icons.cloud_sync_rounded, color: T.mint),
                      const SizedBox(width: 10),
                      Text('Boardest Cloud 로그인', style: T.h(20)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: T.sub)),
                    ]),
                    const SizedBox(height: 10),
                    Seg(labels: const ['📱 QR (기본)', '🔢 OTP 입력', '🏫 등록된 교사'], index: tab, onChanged: (i) => setState(() => tab = i), color: T.purple),
                    const SizedBox(height: 16),
                    Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: [_qr(), _otp(), _saved()][tab])),
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _qr() => Row(key: const ValueKey(0), children: [
        const FakeQr(size: 230),
        const SizedBox(width: 26),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('스마트폰으로 스캔', style: T.h(24)),
            const SizedBox(height: 8),
            Text('boardest-cloud-connect.web.app\n2분 안에 패스키(지문/Face ID)로 승인하세요.', style: T.h(13, c: T.sub, w: FontWeight.w600)),
            const SizedBox(height: 16),
            const PillTag('토큰은 칠판 RAM에만 · 종료 시 소각', icon: Icons.memory_rounded),
            const SizedBox(height: 10),
            const PillTag('로컬 저장 없음 (Zero-Persistence)', color: T.violet, icon: Icons.shield_rounded),
            const SizedBox(height: 18),
            GradButton('데모: 승인된 것으로 진행', icon: Icons.fingerprint_rounded, onTap: _finish),
          ]),
        ),
      ]);

  Widget _otp() => Row(key: const ValueKey(1), children: [
        Expanded(
          flex: 5,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('교사 앱의 6자리 번호', style: T.h(20)),
            const SizedBox(height: 14),
            Row(children: [
              for (var i = 0; i < 6; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 62,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF070B14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: i < pin.length ? T.mint : T.line, width: i < pin.length ? 2 : 1),
                    ),
                    child: Text(i < pin.length ? pin[i] : '•', style: T.h(28, c: i < pin.length ? T.mint : Colors.white24)),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Checkbox(value: saveDevice, activeColor: T.mint, checkColor: Colors.black, onChanged: (v) => v == true ? _warn() : setState(() => saveDevice = false)),
              Expanded(child: Text('이 전자칠판에 계정 영구 등록 (보안 주의)', style: T.h(12, c: Colors.white70, w: FontWeight.w600))),
            ]),
            if (saveDevice)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF2B0F17), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF7A1E35))),
                child: Text('⚠️ 보안이 약해집니다. 공용 기기 저장을 동의하셨습니다.', style: T.h(12, c: const Color(0xFFFF8AA3), w: FontWeight.w600)),
              ),
          ]),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 4,
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', '⌫'])
                Pressable(
                  onTap: () => _press(k),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: k == 'C' || k == '⌫' ? T.card2 : const Color(0xFF070B14), borderRadius: BorderRadius.circular(14), border: Border.all(color: T.line)),
                    child: Text(k, style: T.h(22, c: k == 'C' ? T.red : (k == '⌫' ? T.orange : Colors.white))),
                  ),
                ),
            ],
          ),
        ),
      ]);

  Widget _saved() => ListView(key: const ValueKey(2), children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: const Color(0xFF2B1F0C), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6B4A14))),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: T.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text('등록된 교사는 OTP/QR 없이 바로 열립니다. 기기에 토큰이 저장되어 보안이 더 약합니다.', style: T.h(12, c: T.orange, w: FontWeight.w600))),
          ]),
        ),
        for (final n in ['김지우 선생님', '이서연 선생님'])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Pressable(
              onTap: _finish,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF0A1022), borderRadius: BorderRadius.circular(16), border: Border.all(color: T.line)),
                child: Row(children: [
                  CircleAvatar(backgroundColor: T.purple, child: Text(n[0], style: T.h(16))),
                  const SizedBox(width: 14),
                  Expanded(child: Text(n, style: T.h(17))),
                  const Icon(Icons.chevron_right_rounded, color: T.sub),
                ]),
              ),
            ),
          ),
      ]);
}
