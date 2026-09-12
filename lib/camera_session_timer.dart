part of 'camera_session.dart';

const _timerOrder = [0, 3, 10];

/// [CameraSession]의 셀프타이머(0/3/10초)와 카운트다운 상태를 담당한다.
mixin _SelfTimerMixin on ChangeNotifier {
  bool get _disposed;
  SettingsStore? get settings;
  void _notify();
  void _haptic(Future<void> Function() feedback);

  int _timerSeconds = 0;
  int _countdown = 0;
  Timer? _countdownTimer;
  Completer<bool>? _countdownDone;

  /// 셀프타이머 초(0=끔/3/10).
  int get timerSeconds => _timerSeconds;

  /// 카운트다운 중 남은 초(0=진행 안 함).
  int get countdown => _countdown;
  bool get isCountingDown => _countdown > 0;

  /// 셀프타이머를 0 → 3 → 10 → 0 순으로 바꾼다. 카운트다운 중이면 무시.
  void cycleTimer() {
    if (_countdown > 0) return;
    final next = (_timerOrder.indexOf(_timerSeconds) + 1) % _timerOrder.length;
    _timerSeconds = _timerOrder[next];
    settings?.setTimerSeconds(_timerSeconds);
    _haptic(HapticFeedback.selectionClick);
    _notify();
  }

  /// 셀프타이머가 켜져 있으면 카운트다운 후, 아니면 즉시 [capture]를 실행한다.
  /// 카운트다운 중 [cancelCountdown]이 불리면 [capture]는 실행되지 않는다.
  Future<void> runWithTimer(Future<void> Function() capture) async {
    if (_timerSeconds == 0) {
      await capture();
      return;
    }
    if (_countdown > 0) return; // 이미 카운트다운 중

    final done = Completer<bool>();
    _countdownDone = done;
    _countdown = _timerSeconds;
    _notify();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _countdown--;
      _notify();
      if (_countdown <= 0) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        if (!done.isCompleted) done.complete(true);
      } else {
        _haptic(HapticFeedback.selectionClick); // 남은 초마다 똑딱
      }
    });

    final finished = await done.future;
    _countdownDone = null;
    if (finished && !_disposed) await capture();
  }

  /// 진행 중인 카운트다운을 취소한다(촬영하지 않음).
  void cancelCountdown() {
    if (_countdown == 0) return;
    _stopCountdown();
    _notify();
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdown = 0;
    if (_countdownDone?.isCompleted == false) _countdownDone!.complete(false);
    _countdownDone = null;
  }
}
