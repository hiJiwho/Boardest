import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 교사도구 - [사용 (수업 진행)] 전담 뷰
/// - 0: 판서 칠판 (Whiteboard)
/// - 1: 타이머 & 스톱워치 (Timer & Stopwatch)
/// - 2: 계산기 (Calculator)
/// - 3: 주사위 & 랜덤 번호 뽑기 (Dice & Random Picker)
class TeacherUsageToolsView extends StatefulWidget {
  final int activeTabIndex;

  const TeacherUsageToolsView({
    super.key,
    required this.activeTabIndex,
  });

  @override
  State<TeacherUsageToolsView> createState() => _TeacherUsageToolsViewState();
}

class _TeacherUsageToolsViewState extends State<TeacherUsageToolsView> {
  // ────────────── 1. Whiteboard State ──────────────
  final List<List<DrawingPoint?>> _strokes = [];
  List<DrawingPoint?> _currentStroke = [];
  Color _penColor = const Color(0xFF00F5D4);
  final double _strokeWidth = 4.0;
  bool _isEraser = false;
  int _boardBackground = 0; // 0: Dark Blackboard, 1: Classic Green, 2: Clean White

  // ────────────── 2. Timer & Stopwatch State ──────────────
  bool _isTimerMode = true; // true: Countdown, false: Stopwatch
  int _timerSeconds = 300; // 5 mins default
  int _remainingSeconds = 300;
  bool _isTimerRunning = false;
  Timer? _tickerTimer;
  int _stopwatchElapsed = 0;

  // ────────────── 3. Calculator State ──────────────
  String _calcDisplay = '0';
  String _calcSubDisplay = '';
  double _firstOperand = 0;
  String? _pendingOperator;
  bool _shouldResetCalcDisplay = false;

  // ────────────── 4. Dice / Random Picker State ──────────────
  int _diceCount = 1;
  List<int> _diceResults = [1];
  bool _isRollingDice = false;

  int _pickerMin = 1;
  int _pickerMax = 30;
  int? _pickedNumber;
  final List<int> _pickedHistory = [];
  bool _isPickingNumber = false;

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  // ── Timer Helpers ──
  void _toggleTimer() {
    if (_isTimerRunning) {
      _tickerTimer?.cancel();
      setState(() => _isTimerRunning = false);
    } else {
      setState(() => _isTimerRunning = true);
      _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isTimerMode) {
          if (_remainingSeconds > 0) {
            setState(() => _remainingSeconds--);
          } else {
            _tickerTimer?.cancel();
            setState(() => _isTimerRunning = false);
            _showTimerFinishedDialog();
          }
        } else {
          setState(() => _stopwatchElapsed++);
        }
      });
    }
  }

  void _resetTimer() {
    _tickerTimer?.cancel();
    setState(() {
      _isTimerRunning = false;
      if (_isTimerMode) {
        _remainingSeconds = _timerSeconds;
      } else {
        _stopwatchElapsed = 0;
      }
    });
  }

  void _addTimerTime(int seconds) {
    setState(() {
      _timerSeconds += seconds;
      _remainingSeconds += seconds;
    });
  }

  void _showTimerFinishedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFEF4565), width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.alarm_on_rounded, color: Color(0xFFEF4565), size: 30),
            const SizedBox(width: 12),
            Text('타이머 종료!', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('설정한 수업 시간이 종료되었습니다.', style: GoogleFonts.notoSansKr(color: Colors.white70)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4565)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Calculator Helpers ──
  void _onCalcKeyPress(String key) {
    setState(() {
      if ('0123456789'.contains(key)) {
        if (_calcDisplay == '0' || _shouldResetCalcDisplay) {
          _calcDisplay = key;
          _shouldResetCalcDisplay = false;
        } else {
          _calcDisplay += key;
        }
      } else if (key == '.') {
        if (!_calcDisplay.contains('.')) {
          _calcDisplay += '.';
        }
      } else if (key == 'AC') {
        _calcDisplay = '0';
        _calcSubDisplay = '';
        _firstOperand = 0;
        _pendingOperator = null;
      } else if (key == '⌫') {
        if (_calcDisplay.length > 1) {
          _calcDisplay = _calcDisplay.substring(0, _calcDisplay.length - 1);
        } else {
          _calcDisplay = '0';
        }
      } else if (key == '±') {
        if (_calcDisplay.startsWith('-')) {
          _calcDisplay = _calcDisplay.substring(1);
        } else if (_calcDisplay != '0') {
          _calcDisplay = '-$_calcDisplay';
        }
      } else if ('+-×÷%'.contains(key)) {
        _firstOperand = double.tryParse(_calcDisplay) ?? 0;
        _pendingOperator = key;
        _calcSubDisplay = '$_calcDisplay $key';
        _shouldResetCalcDisplay = true;
      } else if (key == '=') {
        if (_pendingOperator != null) {
          final secondOperand = double.tryParse(_calcDisplay) ?? 0;
          double res = 0;
          switch (_pendingOperator) {
            case '+':
              res = _firstOperand + secondOperand;
              break;
            case '-':
              res = _firstOperand - secondOperand;
              break;
            case '×':
              res = _firstOperand * secondOperand;
              break;
            case '÷':
              res = secondOperand != 0 ? _firstOperand / secondOperand : 0;
              break;
            case '%':
              res = _firstOperand % secondOperand;
              break;
          }
          _calcSubDisplay = '$_firstOperand $_pendingOperator $secondOperand =';
          _calcDisplay = (res % 1 == 0) ? res.toInt().toString() : res.toStringAsFixed(2);
          _pendingOperator = null;
          _shouldResetCalcDisplay = true;
        }
      }
    });
  }

  // ── Dice & Picker Helpers ──
  void _rollDice() {
    if (_isRollingDice) return;
    setState(() => _isRollingDice = true);
    final rng = Random();
    int ticks = 0;
    Timer.periodic(const Duration(milliseconds: 70), (t) {
      ticks++;
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _diceResults = List.generate(_diceCount, (_) => rng.nextInt(6) + 1);
      });
      if (ticks > 10) {
        t.cancel();
        setState(() => _isRollingDice = false);
      }
    });
  }

  void _pickRandomNumber() {
    if (_isPickingNumber || _pickerMin > _pickerMax) return;
    setState(() => _isPickingNumber = true);
    final rng = Random();
    int ticks = 0;
    Timer.periodic(const Duration(milliseconds: 60), (t) {
      ticks++;
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _pickedNumber = _pickerMin + rng.nextInt(_pickerMax - _pickerMin + 1);
      });
      if (ticks > 12) {
        t.cancel();
        setState(() {
          _isPickingNumber = false;
          if (_pickedNumber != null && !_pickedHistory.contains(_pickedNumber)) {
            _pickedHistory.insert(0, _pickedNumber!);
            if (_pickedHistory.length > 20) _pickedHistory.removeLast();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.activeTabIndex.clamp(0, 3),
      children: [
        _buildWhiteboardPanel(),
        _buildTimerPanel(),
        _buildCalculatorPanel(),
        _buildDiceRandomPanel(),
      ],
    );
  }

  // ════════════════ 1. WHITEBOARD PANEL ════════════════
  Widget _buildWhiteboardPanel() {
    Color bg;
    switch (_boardBackground) {
      case 1:
        bg = const Color(0xFF0C2B1D);
        break;
      case 2:
        bg = const Color(0xFFF8F9FA);
        break;
      default:
        bg = const Color(0xFF0F141E);
        break;
    }

    return Stack(
      children: [
        Container(
          color: bg,
          child: GestureDetector(
            onPanStart: (details) {
              final renderBox = context.findRenderObject() as RenderBox?;
              final offset = renderBox != null ? renderBox.globalToLocal(details.globalPosition) : details.localPosition;
              setState(() {
                _currentStroke = [
                  DrawingPoint(
                    point: offset,
                    paint: Paint()
                      ..color = _isEraser ? bg : _penColor
                      ..strokeCap = StrokeCap.round
                      ..strokeWidth = _isEraser ? _strokeWidth * 3 : _strokeWidth
                      ..isAntiAlias = true,
                  ),
                ];
                _strokes.add(_currentStroke);
              });
            },
            onPanUpdate: (details) {
              final renderBox = context.findRenderObject() as RenderBox?;
              final offset = renderBox != null ? renderBox.globalToLocal(details.globalPosition) : details.localPosition;
              setState(() {
                _currentStroke.add(
                  DrawingPoint(
                    point: offset,
                    paint: Paint()
                      ..color = _isEraser ? bg : _penColor
                      ..strokeCap = StrokeCap.round
                      ..strokeWidth = _isEraser ? _strokeWidth * 3 : _strokeWidth
                      ..isAntiAlias = true,
                  ),
                );
              });
            },
            onPanEnd: (_) {
              setState(() {
                _currentStroke.add(null);
              });
            },
            child: CustomPaint(
              painter: WhiteboardCustomPainter(strokes: _strokes),
              size: Size.infinite,
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_rounded, color: !_isEraser ? const Color(0xFF00F5D4) : Colors.white60),
                    tooltip: '펜',
                    onPressed: () => setState(() => _isEraser = false),
                  ),
                  IconButton(
                    icon: Icon(Icons.auto_fix_normal_rounded, color: _isEraser ? const Color(0xFFEF4565) : Colors.white60),
                    tooltip: '지우개',
                    onPressed: () => setState(() => _isEraser = true),
                  ),
                  Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                  ...[
                    const Color(0xFF00F5D4),
                    const Color(0xFFFFD166),
                    const Color(0xFFEF4565),
                    const Color(0xFF7F5AF0),
                    Colors.white,
                  ].map((c) => GestureDetector(
                        onTap: () => setState(() {
                          _penColor = c;
                          _isEraser = false;
                        }),
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _penColor == c && !_isEraser ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      )),
                  Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                  IconButton(
                    icon: const Icon(Icons.palette_outlined, color: Colors.white70),
                    tooltip: '칠판 배경 변경',
                    onPressed: () => setState(() => _boardBackground = (_boardBackground + 1) % 3),
                  ),
                  IconButton(
                    icon: const Icon(Icons.undo_rounded, color: Colors.white70),
                    tooltip: '되돌리기',
                    onPressed: () {
                      if (_strokes.isNotEmpty) {
                        setState(() => _strokes.removeLast());
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4565)),
                    tooltip: '칠판 전체 지우기',
                    onPressed: () {
                      setState(() => _strokes.clear());
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════ 2. TIMER & STOPWATCH PANEL ════════════════
  Widget _buildTimerPanel() {
    final minutes = _isTimerMode ? (_remainingSeconds ~/ 60) : (_stopwatchElapsed ~/ 60);
    final seconds = _isTimerMode ? (_remainingSeconds % 60) : (_stopwatchElapsed % 60);
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChoiceChip(
                    label: Text('타이머 (카운트다운)', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                    selected: _isTimerMode,
                    selectedColor: const Color(0xFF00F5D4),
                    checkmarkColor: const Color(0xFF080D11),
                    onSelected: (val) {
                      if (val) {
                        _resetTimer();
                        setState(() => _isTimerMode = true);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('스톱워치', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                    selected: !_isTimerMode,
                    selectedColor: const Color(0xFF7F5AF0),
                    checkmarkColor: Colors.white,
                    onSelected: (val) {
                      if (val) {
                        _resetTimer();
                        setState(() => _isTimerMode = false);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _isTimerRunning ? const Color(0xFF00F5D4) : Colors.white.withValues(alpha: 0.1),
                  width: 2,
                ),
                boxShadow: [
                  if (_isTimerRunning)
                    BoxShadow(color: const Color(0xFF00F5D4).withValues(alpha: 0.2), blurRadius: 40, spreadRadius: 4),
                ],
              ),
              child: Text(
                timeStr,
                style: GoogleFonts.outfit(
                  fontSize: 100,
                  fontWeight: FontWeight.w900,
                  color: _isTimerRunning ? const Color(0xFF00F5D4) : Colors.white,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (_isTimerMode) ...[
              Wrap(
                spacing: 12,
                children: [
                  _buildTimerPresetButton('+30초', 30),
                  _buildTimerPresetButton('+1분', 60),
                  _buildTimerPresetButton('+3분', 180),
                  _buildTimerPresetButton('+5분', 300),
                  _buildTimerPresetButton('+10분', 600),
                ],
              ),
              const SizedBox(height: 32),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isTimerRunning ? const Color(0xFFFF8E3C) : const Color(0xFF00F5D4),
                    foregroundColor: const Color(0xFF080D11),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _toggleTimer,
                  icon: Icon(_isTimerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
                  label: Text(
                    _isTimerRunning ? '일시정지' : '시작',
                    style: GoogleFonts.notoSansKr(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _resetTimer,
                  icon: const Icon(Icons.refresh_rounded, size: 24),
                  label: Text('초기화', style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerPresetButton(String label, int seconds) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      onPressed: () => _addTimerTime(seconds),
      child: Text(label, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
    );
  }

  // ════════════════ 3. CALCULATOR PANEL ════════════════
  Widget _buildCalculatorPanel() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF121722),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF080D11),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _calcSubDisplay.isEmpty ? ' ' : _calcSubDisplay,
                      style: GoogleFonts.outfit(color: const Color(0xFF94A1B2), fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _calcDisplay,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  _buildCalcKey('AC', color: const Color(0xFFEF4565)),
                  _buildCalcKey('±', color: const Color(0xFF7F5AF0)),
                  _buildCalcKey('%', color: const Color(0xFF7F5AF0)),
                  _buildCalcKey('÷', color: const Color(0xFF00F5D4)),
                  _buildCalcKey('7'),
                  _buildCalcKey('8'),
                  _buildCalcKey('9'),
                  _buildCalcKey('×', color: const Color(0xFF00F5D4)),
                  _buildCalcKey('4'),
                  _buildCalcKey('5'),
                  _buildCalcKey('6'),
                  _buildCalcKey('-', color: const Color(0xFF00F5D4)),
                  _buildCalcKey('1'),
                  _buildCalcKey('2'),
                  _buildCalcKey('3'),
                  _buildCalcKey('+', color: const Color(0xFF00F5D4)),
                  _buildCalcKey('0'),
                  _buildCalcKey('.'),
                  _buildCalcKey('⌫'),
                  _buildCalcKey('=', color: const Color(0xFF2CB67D), isAccent: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalcKey(String text, {Color? color, bool isAccent = false}) {
    final bgColor = isAccent ? const Color(0xFF00F5D4) : const Color(0xFF1A2230);
    final textColor = isAccent ? const Color(0xFF080D11) : (color ?? Colors.white);

    return InkWell(
      onTap: () => _onCalcKeyPress(text),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
        ),
      ),
    );
  }

  // ════════════════ 4. DICE & RANDOM PICKER PANEL ════════════════
  Widget _buildDiceRandomPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121722),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.groups_rounded, color: Color(0xFF00F5D4)),
                          const SizedBox(width: 10),
                          Text(
                            '학생 번호 뽑기',
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: _pickerMin.toString()),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _pickerMin = int.tryParse(v) ?? 1,
                              style: GoogleFonts.outfit(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: '최소 번호',
                                filled: true,
                                fillColor: const Color(0xFF080D11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: _pickerMax.toString()),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _pickerMax = int.tryParse(v) ?? 30,
                              style: GoogleFonts.outfit(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: '최대 번호',
                                filled: true,
                                fillColor: const Color(0xFF080D11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        height: 120,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF080D11),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _pickedNumber != null ? '$_pickedNumber번' : '대기 중',
                          style: GoogleFonts.outfit(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: _pickedNumber != null ? const Color(0xFF00F5D4) : Colors.white24,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F5D4),
                            foregroundColor: const Color(0xFF080D11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _pickRandomNumber,
                          icon: const Icon(Icons.touch_app_rounded),
                          label: Text('랜덤 뽑기', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (_pickedHistory.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '최근 뽑힌 번호: ${_pickedHistory.join(", ")}',
                            style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121722),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.casino_rounded, color: Color(0xFF7F5AF0)),
                              const SizedBox(width: 10),
                              Text(
                                '주사위 굴리기',
                                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          DropdownButton<int>(
                            value: _diceCount,
                            dropdownColor: const Color(0xFF1A2230),
                            style: GoogleFonts.notoSansKr(color: Colors.white),
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('주사위 1개')),
                              DropdownMenuItem(value: 2, child: Text('주사위 2개')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _diceCount = v;
                                  _diceResults = List.generate(v, (_) => 1);
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        height: 120,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _diceResults
                              .map((val) => Container(
                                    width: 80,
                                    height: 80,
                                    margin: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$val',
                                      style: GoogleFonts.outfit(
                                        fontSize: 44,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF080D11),
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7F5AF0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _rollDice,
                          icon: const Icon(Icons.replay_rounded),
                          label: Text('주사위 굴리기', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Whiteboard Custom Painter ──
class DrawingPoint {
  final Offset point;
  final Paint paint;
  DrawingPoint({required this.point, required this.paint});
}

class WhiteboardCustomPainter extends CustomPainter {
  final List<List<DrawingPoint?>> strokes;
  WhiteboardCustomPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        if (stroke[i] != null && stroke[i + 1] != null) {
          canvas.drawLine(stroke[i]!.point, stroke[i + 1]!.point, stroke[i]!.paint);
        } else if (stroke[i] != null && stroke[i + 1] == null) {
          canvas.drawCircle(stroke[i]!.point, stroke[i]!.paint.strokeWidth / 2, stroke[i]!.paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
