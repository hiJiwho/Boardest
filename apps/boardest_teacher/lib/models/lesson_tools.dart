import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 타이머 모드: 카운트다운 타이머 vs 스톱워치
enum LessonTimerMode { countdown, stopwatch }

/// 수업 타이머 & 스톱워치 상태 엔진
class LessonTimerEngine extends ChangeNotifier {
  LessonTimerMode _mode = LessonTimerMode.countdown;
  int _targetSeconds = 300; // 5분 기본값
  int _remainingSeconds = 300;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  bool _hasFinished = false;
  VoidCallback? onFinished;

  LessonTimerEngine({
    int initialTargetSeconds = 300,
    LessonTimerMode initialMode = LessonTimerMode.countdown,
    this.onFinished,
  }) {
    _targetSeconds = initialTargetSeconds;
    _remainingSeconds = initialTargetSeconds;
    _mode = initialMode;
  }

  LessonTimerMode get mode => _mode;
  int get targetSeconds => _targetSeconds;
  int get remainingSeconds => _remainingSeconds;
  int get elapsedSeconds => _elapsedSeconds;
  bool get isRunning => _isRunning;
  bool get hasFinished => _hasFinished;

  void setMode(LessonTimerMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    _isRunning = false;
    _hasFinished = false;
    notifyListeners();
  }

  void toggle() {
    if (_isRunning) {
      pause();
    } else {
      start();
    }
  }

  void start() {
    if (_isRunning) return;
    if (_mode == LessonTimerMode.countdown && _remainingSeconds <= 0) {
      _remainingSeconds = _targetSeconds > 0 ? _targetSeconds : 60;
      _targetSeconds = _remainingSeconds;
    }
    _isRunning = true;
    _hasFinished = false;
    notifyListeners();
  }

  void pause() {
    if (!_isRunning) return;
    _isRunning = false;
    notifyListeners();
  }

  void reset() {
    _isRunning = false;
    _hasFinished = false;
    if (_mode == LessonTimerMode.countdown) {
      _remainingSeconds = _targetSeconds;
    } else {
      _elapsedSeconds = 0;
    }
    notifyListeners();
  }

  void adjustSeconds(int delta) {
    if (_mode == LessonTimerMode.countdown) {
      final updated = (_remainingSeconds + delta).clamp(0, 7200);
      _remainingSeconds = updated;
      _targetSeconds = updated;
      if (_remainingSeconds > 0) _hasFinished = false;
    } else {
      _elapsedSeconds = (_elapsedSeconds + delta).clamp(0, 36000);
    }
    notifyListeners();
  }

  void setTargetSeconds(int seconds) {
    _targetSeconds = seconds.clamp(1, 7200);
    _remainingSeconds = _targetSeconds;
    _hasFinished = false;
    notifyListeners();
  }

  /// 1초마다 주기적으로 호출되는 틱
  void tick() {
    if (!_isRunning) return;

    if (_mode == LessonTimerMode.countdown) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        notifyListeners();
        if (_remainingSeconds == 0) {
          _isRunning = false;
          _hasFinished = true;
          triggerAlertSound();
          notifyListeners();
          onFinished?.call();
        }
      }
    } else {
      _elapsedSeconds++;
      notifyListeners();
    }
  }

  /// 타이머 종료 시 비프/알림음 트리거
  void triggerAlertSound() {
    try {
      SystemSound.play(SystemSoundType.alert);
      Future.delayed(const Duration(milliseconds: 350), () {
        try {
          SystemSound.play(SystemSoundType.alert);
        } catch (_) {}
      });
    } catch (_) {}
  }

  String get formattedDisplay {
    final secs = _mode == LessonTimerMode.countdown ? _remainingSeconds : _elapsedSeconds;
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 주사위 결과 모델
class DiceRollResult {
  final List<int> values;
  final DateTime timestamp;

  DiceRollResult(this.values) : timestamp = DateTime.now();

  int get sum => values.fold(0, (a, b) => a + b);
}

/// 암호학적으로 안전한 주사위 생성 엔진
class LessonDiceEngine extends ChangeNotifier {
  int _diceCount = 1;
  List<int> _currentValues = [1];
  bool _isRolling = false;
  final List<DiceRollResult> _history = [];
  final Random _secureRandom;

  LessonDiceEngine({Random? random}) : _secureRandom = random ?? Random.secure();

  int get diceCount => _diceCount;
  List<int> get currentValues => List.unmodifiable(_currentValues);
  bool get isRolling => _isRolling;
  List<DiceRollResult> get history => List.unmodifiable(_history);
  int get sum => _currentValues.fold(0, (a, b) => a + b);

  void setDiceCount(int count) {
    if (_isRolling) return;
    _diceCount = count.clamp(1, 4);
    _currentValues = List.generate(_diceCount, (_) => 1);
    notifyListeners();
  }

  /// 단일 또는 다중 주사위 값 생성 (1..6)
  int generateFairDieValue() {
    return _secureRandom.nextInt(6) + 1;
  }

  /// 즉시 롤 (단위 테스트 및 최종 확정용)
  List<int> rollImmediate() {
    final values = List.generate(_diceCount, (_) => generateFairDieValue());
    _currentValues = values;
    _history.insert(0, DiceRollResult(values));
    if (_history.length > 30) _history.removeLast();
    notifyListeners();
    return values;
  }

  /// 애니메이션 롤링 시작
  Future<List<int>> rollWithAnimation({int steps = 10, Duration interval = const Duration(milliseconds: 70)}) async {
    if (_isRolling) return _currentValues;
    _isRolling = true;
    notifyListeners();

    for (int i = 0; i < steps; i++) {
      await Future.delayed(interval);
      _currentValues = List.generate(_diceCount, (_) => generateFairDieValue());
      notifyListeners();
    }

    final finalResult = rollImmediate();
    _isRolling = false;
    notifyListeners();
    return finalResult;
  }
}

/// 중복 없는 발표자/학생 추첨 엔진 (전원 추첨 전까지 중복 차단)
class StudentPickerEngine extends ChangeNotifier {
  int _totalStudents = 30;
  final Set<int> _pickedStudents = {};
  int? _currentWinner;
  bool _isRolling = false;
  final List<int> _drawHistory = [];
  final Random _secureRandom;

  StudentPickerEngine({int total = 30, Random? random})
      : _totalStudents = total.clamp(2, 99),
        _secureRandom = random ?? Random.secure();

  int get totalStudents => _totalStudents;
  Set<int> get pickedStudents => Set.unmodifiable(_pickedStudents);
  int? get currentWinner => _currentWinner;
  bool get isRolling => _isRolling;
  List<int> get drawHistory => List.unmodifiable(_drawHistory);

  /// 아직 추첨되지 않은 학생 목록
  List<int> get remainingStudents {
    final remaining = <int>[];
    for (int i = 1; i <= _totalStudents; i++) {
      if (!_pickedStudents.contains(i)) {
        remaining.add(i);
      }
    }
    return remaining;
  }

  int get remainingCount => remainingStudents.length;
  bool get isCycleComplete => remainingStudents.isEmpty;

  void setTotalStudents(int total) {
    if (_isRolling) return;
    _totalStudents = total.clamp(2, 99);
    // 총원 변경 시 초과하는 번호 정리
    _pickedStudents.removeWhere((id) => id > _totalStudents);
    notifyListeners();
  }

  /// 추첨 이력 전체 초기화 (새로운 사이클 시작)
  void resetCycle() {
    _pickedStudents.clear();
    _currentWinner = null;
    notifyListeners();
  }

  /// 1명 즉시 추첨 (중복 배제, 전원 완료 시 자동 리셋 후 추첨)
  int drawImmediate() {
    if (remainingStudents.isEmpty) {
      resetCycle();
    }
    final candidates = remainingStudents;
    final winnerIndex = _secureRandom.nextInt(candidates.length);
    final winner = candidates[winnerIndex];

    _currentWinner = winner;
    _pickedStudents.add(winner);
    _drawHistory.insert(0, winner);
    if (_drawHistory.length > 50) _drawHistory.removeLast();
    notifyListeners();
    return winner;
  }

  /// 롤링 애니메이션 포함 추첨
  Future<int?> drawWithAnimation({int steps = 14, Duration interval = const Duration(milliseconds: 60)}) async {
    if (_isRolling) return _currentWinner;
    if (remainingStudents.isEmpty) {
      resetCycle();
    }

    _isRolling = true;
    _currentWinner = null;
    notifyListeners();

    final pool = List<int>.from(remainingStudents);
    for (int i = 0; i < steps; i++) {
      await Future.delayed(interval);
      final tempIndex = _secureRandom.nextInt(pool.length);
      _currentWinner = pool[tempIndex];
      notifyListeners();
    }

    final winner = drawImmediate();
    _isRolling = false;
    notifyListeners();
    return winner;
  }
}

/// 스포트라이트 및 돋보기 기하학 모델
class SpotlightGeometry {
  final Offset center;
  final double radius;
  final double darkness;
  final bool isMagnifier;
  final double magnification;

  const SpotlightGeometry({
    required this.center,
    this.radius = 120.0,
    this.darkness = 0.75,
    this.isMagnifier = false,
    this.magnification = 1.75,
  });

  bool isInside(Offset point) {
    return (point - center).distance <= radius;
  }

  SpotlightGeometry copyWith({
    Offset? center,
    double? radius,
    double? darkness,
    bool? isMagnifier,
    double? magnification,
  }) {
    return SpotlightGeometry(
      center: center ?? this.center,
      radius: radius ?? this.radius,
      darkness: darkness ?? this.darkness,
      isMagnifier: isMagnifier ?? this.isMagnifier,
      magnification: magnification ?? this.magnification,
    );
  }
}
