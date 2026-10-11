import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/bst_cloud_service.dart';
import '../services/passkey_service.dart';
import '../widgets/bst_cloud_modal.dart';

class BoardestToolsView extends StatefulWidget {
  const BoardestToolsView({super.key});

  @override
  State<BoardestToolsView> createState() => _BoardestToolsViewState();
}

class _BoardestToolsViewState extends State<BoardestToolsView> {
  int _activeTabIndex = 0; // 0: Whiteboard, 1: Timer, 2: Calculator, 3: Dice/Random

  // ────────────── 1. Whiteboard State ──────────────
  final List<List<DrawingPoint?>> _strokes = [];
  List<DrawingPoint?> _currentStroke = [];
  Color _penColor = const Color(0xFF00F5D4);
  double _strokeWidth = 4.0;
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

  void _switchTab(int index) {
    setState(() => _activeTabIndex = index);
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
            case '+': res = _firstOperand + secondOperand; break;
            case '-': res = _firstOperand - secondOperand; break;
            case '×': res = _firstOperand * secondOperand; break;
            case '÷': res = secondOperand != 0 ? _firstOperand / secondOperand : 0; break;
            case '%': res = _firstOperand % secondOperand; break;
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

  // ── Cloud Modal (QR 없이 브라우저 순정 패스키 직결) ──
  Future<void> _openCloudModal() async {
    if (BstCloudService.instance.activeToken != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${BstCloudService.instance.activeTeacherName ?? "선생님"} Cloud가 이미 연결되어 있습니다.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔐 브라우저 순정 패스키 생체인증을 요청합니다...'),
        duration: Duration(seconds: 2),
      ),
    );

    // 1. 순정 패스키 로그인 즉시 요청 (QR 코드 없이 직접 인증!)
    final authRes = await PasskeyService.instance.authenticateNativePasskey();
    if (authRes.success && authRes.accessToken != null) {
      BstCloudService.instance.setDirectAccessToken(
        authRes.accessToken!,
        teacherName: authRes.teacherName ?? '선생님',
        ownerEmail: authRes.email ?? '',
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ ${authRes.teacherName ?? "선생님"} 패스키 인증 완료! Tools Cloud 연결되었습니다.'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
      return;
    }

    // 만약 등록된 패스키가 없는 경우 순정 패스키 등록
    final registerNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F141E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00F5D4), width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.fingerprint_rounded, color: Color(0xFF00F5D4), size: 24),
            const SizedBox(width: 10),
            Text('Boardest Tools 패스키 연동', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          '이 기기에 등록된 패스키가 없습니다.\n현재 브라우저에 순정 패스키(Windows Hello / Touch ID / 지문)를 등록하시겠습니까?',
          style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('🔐 순정 패스키 등록', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (registerNow == true) {
      final regOk = await PasskeyService.instance.registerNativePasskey(
        teacherName: '수업 교사',
        email: 'tools_user@boardest.local',
        schoolName: 'Boardest Tools',
      );
      if (regOk) {
        final token = 'passkey_tools_${DateTime.now().millisecondsSinceEpoch}';
        BstCloudService.instance.setDirectAccessToken(
          token,
          teacherName: '수업 교사',
          ownerEmail: 'tools_user@boardest.local',
        );
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Tools 순정 패스키가 등록 및 연결되었습니다!'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D11),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Navigation Header ──
            _buildTopHeader(),

            // ── Active Tool Body ──
            Expanded(
              child: IndexedStack(
                index: _activeTabIndex,
                children: [
                  _buildWhiteboardPanel(),
                  _buildTimerPanel(),
                  _buildCalculatorPanel(),
                  _buildDiceRandomPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header Widget ──
  Widget _buildTopHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D141C),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          // Brand Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00F5D4), Color(0xFF2EC4B6)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'TOOLS',
              style: GoogleFonts.outfit(color: const Color(0xFF080D11), fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Boardest',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(width: 4),
          Text(
            '수업도구',
            style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontWeight: FontWeight.w800, fontSize: 15),
          ),

          const SizedBox(width: 24),

          // Navigation Tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTabButton(0, Icons.brush_rounded, '판서 칠판'),
                  const SizedBox(width: 8),
                  _buildTabButton(1, Icons.timer_outlined, '타이머 & 스톱워치'),
                  const SizedBox(width: 8),
                  _buildTabButton(2, Icons.calculate_outlined, '계산기'),
                  const SizedBox(width: 8),
                  _buildTabButton(3, Icons.casino_outlined, '주사위 & 뽑기'),
                ],
              ),
            ),
          ),

          // Cloud Pairing Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: BstCloudService.instance.activeToken != null
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : const Color(0xFF00F5D4).withValues(alpha: 0.15),
              foregroundColor: BstCloudService.instance.activeToken != null
                  ? const Color(0xFF10B981)
                  : const Color(0xFF00F5D4),
              side: BorderSide(
                color: BstCloudService.instance.activeToken != null
                    ? const Color(0xFF10B981)
                    : const Color(0xFF00F5D4),
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: _openCloudModal,
            icon: Icon(
              BstCloudService.instance.activeToken != null
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_rounded,
              size: 18,
            ),
            label: Text(
              BstCloudService.instance.activeToken != null
                  ? '${BstCloudService.instance.activeTeacherName ?? '선생님'} Cloud 연결됨'
                  : 'Cloud 연동',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String title) {
    final isSelected = _activeTabIndex == index;
    return InkWell(
      onTap: () => _switchTab(index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00F5D4) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: isSelected ? const Color(0xFF080D11) : const Color(0xFF94A1B2)),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                color: isSelected ? const Color(0xFF080D11) : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════ 1. WHITEBOARD PANEL ════════════════
  Widget _buildWhiteboardPanel() {
    Color bg;
    switch (_boardBackground) {
      case 1: bg = const Color(0xFF0C2B1D); break; // Dark Green Blackboard
      case 2: bg = const Color(0xFFF8F9FA); break; // Whiteboard
      default: bg = const Color(0xFF0F141E); break; // Deep Charcoal
    }

    return Stack(
      children: [
        // Canvas Container
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

        // Floating Bottom Toolbar
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
                  // Pen Tool
                  IconButton(
                    icon: Icon(Icons.edit_rounded, color: !_isEraser ? const Color(0xFF00F5D4) : Colors.white60),
                    tooltip: '펜',
                    onPressed: () => setState(() => _isEraser = false),
                  ),
                  // Eraser Tool
                  IconButton(
                    icon: Icon(Icons.auto_fix_normal_rounded, color: _isEraser ? const Color(0xFFEF4565) : Colors.white60),
                    tooltip: '지우개',
                    onPressed: () => setState(() => _isEraser = true),
                  ),
                  Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),

                  // Colors
                  ...[
                    const Color(0xFF00F5D4),
                    const Color(0xFFFFD166),
                    const Color(0xFFEF4565),
                    const Color(0xFF7F5AF0),
                    Colors.white,
                  ].map((c) => GestureDetector(
                    onTap: () => setState(() { _penColor = c; _isEraser = false; }),
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

                  // Background Selector
                  IconButton(
                    icon: const Icon(Icons.palette_outlined, color: Colors.white70),
                    tooltip: '칠판 배경 변경',
                    onPressed: () => setState(() => _boardBackground = (_boardBackground + 1) % 3),
                  ),

                  // Undo
                  IconButton(
                    icon: const Icon(Icons.undo_rounded, color: Colors.white70),
                    tooltip: '되돌리기',
                    onPressed: () {
                      if (_strokes.isNotEmpty) {
                        setState(() => _strokes.removeLast());
                      }
                    },
                  ),

                  // Clear All
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
            // Mode Toggle
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

            // Giant Clock Display
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

            // Preset Buttons (Countdown Mode Only)
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

            // Control Buttons (Start / Pause / Reset)
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
              // Display Screen
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

              // Keypad
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
              // Left: Random Number Picker (학생 번호 뽑기)
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
                      // Giant Picked Box
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
                          child: Text('최근 뽑힌 번호: ${_pickedHistory.join(", ")}', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 24),

              // Right: Dice Roller (주사위 굴리기)
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
                              if (v != null) setState(() { _diceCount = v; _diceResults = List.generate(v, (_) => 1); });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Dice Container
                      Container(
                        height: 120,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _diceResults.map((val) => Container(
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
                              style: GoogleFonts.outfit(fontSize: 44, fontWeight: FontWeight.w900, color: const Color(0xFF080D11)),
                            ),
                          )).toList(),
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
