import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'settings_store.dart';

/// 가속도계 한 표본에서 계산한 수평계 상태.
class LevelReading {
  const LevelReading(this.rollDegrees, this.reliable);

  /// 세로 파지 기준 좌우 기울기(도). 오른쪽으로 기울면 +.
  final double rollDegrees;

  /// 화면이 너무 수평(위·아래로 향함)이면 롤 값이 불안정하다.
  final bool reliable;
}

/// 가속도(x=오른쪽, y=위, z=화면 밖) → 수평계 읽기.
LevelReading levelReadingFromAccel(double x, double y, double z) {
  final planar = math.sqrt(x * x + y * y);
  final total = math.sqrt(x * x + y * y + z * z);
  final reliable = total > 0.5 && planar / total > 0.28;
  final roll = math.atan2(x, y) * 180 / math.pi;
  return LevelReading(roll, reliable);
}

/// 화면 중앙 수평 보조선(수평계). 가속도계를 구독해 좌우 기울기를 알려준다.
/// [enabled]일 때만 센서를 구독한다(배터리). 값은 저역통과 필터로 부드럽게,
/// 알림은 의미 있는 변화가 있을 때만 보낸다(드래그성 리빌드 방지).
class LevelController extends ChangeNotifier with WidgetsBindingObserver {
  static const _levelThresholdDeg = 1.0; // 이 이내면 "수평"
  static const _smoothing = 0.25; // EMA 계수
  static const _notifyStepDeg = 0.15; // 이 이상 변할 때만 알림

  StreamSubscription<AccelerometerEvent>? _sub;
  bool _enabled = false;
  bool _disposed = false;
  double _roll = 0;
  bool _reliable = false;
  double _lastNotifiedRoll = 0;

  /// 테스트에서 센서 스트림을 주입할 수 있게 한다.
  final Stream<AccelerometerEvent> Function()? _streamFactory;

  LevelController({SettingsStore? settings, this._streamFactory}) {
    if (settings != null) {
      this.settings = settings;
      _enabled = settings.levelEnabled;
    }
  }

  SettingsStore? settings;

  bool get enabled => _enabled;

  /// 세로 파지 기준 좌우 기울기(도).
  double get rollDegrees => _roll;

  /// 롤 값을 믿을 수 있는지(화면이 지나치게 수평이 아님).
  bool get reliable => _reliable;

  /// 수평 여부(신뢰 가능하고 기울기가 임계값 이내).
  bool get isLevel => _reliable && _roll.abs() < _levelThresholdDeg;

  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  void hydrate(SettingsStore s) {
    settings = s;
    setEnabled(s.levelEnabled);
  }

  void toggle() => setEnabled(!_enabled);

  void setEnabled(bool value) {
    if (_enabled == value && (_sub != null) == value) {
      _enabled = value;
      return;
    }
    _enabled = value;
    settings?.setLevelEnabled(value);
    if (value) {
      _start();
    } else {
      _stop();
      _roll = 0;
      _reliable = false;
      _lastNotifiedRoll = 0;
    }
    if (!_disposed) notifyListeners();
  }

  void _start() {
    _sub?.cancel();
    final stream = _streamFactory?.call() ??
        accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval);
    _sub = stream.listen(_onSample, onError: (_) {
      // 센서 미지원 기기 등: 조용히 끈다.
      _stop();
    });
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onSample(AccelerometerEvent e) {
    if (_disposed || !_enabled) return;
    final r = levelReadingFromAccel(e.x, e.y, e.z);
    final wasLevel = isLevel;
    _roll = _roll + _smoothing * (r.rollDegrees - _roll);
    _reliable = r.reliable;
    if ((_roll - _lastNotifiedRoll).abs() >= _notifyStepDeg ||
        isLevel != wasLevel) {
      _lastNotifiedRoll = _roll;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stop();
    } else if (state == AppLifecycleState.resumed && _enabled && _sub == null) {
      _start();
    }
  }
}
