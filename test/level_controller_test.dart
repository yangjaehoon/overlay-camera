import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/level_controller.dart';
import 'package:ghost_camera/settings_store.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

AccelerometerEvent _acc(double x, double y, double z) =>
    AccelerometerEvent(x, y, z, DateTime(2026));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('levelReadingFromAccel', () {
    test('세로 파지(수직)면 롤 0, 신뢰 가능', () {
      final r = levelReadingFromAccel(0, 9.8, 0);
      expect(r.rollDegrees, closeTo(0, 0.5));
      expect(r.reliable, true);
    });

    test('오른쪽으로 30도 기울이면 롤 +30 근처', () {
      final r = levelReadingFromAccel(4.9, 8.49, 0); // 9.8*(sin30, cos30)
      expect(r.rollDegrees, closeTo(30, 1.0));
      expect(r.reliable, true);
    });

    test('왼쪽으로 기울이면 롤 음수', () {
      expect(levelReadingFromAccel(-4.9, 8.49, 0).rollDegrees, lessThan(0));
    });

    test('화면이 하늘/바닥을 향하면 신뢰 불가', () {
      expect(levelReadingFromAccel(0, 0.2, 9.8).reliable, false);
    });

    test('정지(0,0,0)면 신뢰 불가', () {
      expect(levelReadingFromAccel(0, 0, 0).reliable, false);
    });
  });

  group('LevelController', () {
    late StreamController<AccelerometerEvent> stream;
    LevelController make() =>
        LevelController(streamFactory: () => stream.stream);

    setUp(() => stream = StreamController<AccelerometerEvent>.broadcast());
    tearDown(() => stream.close());

    test('기본은 꺼짐, 구독 안 함', () {
      final c = make();
      expect(c.enabled, false);
      expect(stream.hasListener, false);
      c.dispose();
    });

    test('켜면 구독하고 표본을 받아 롤을 갱신한다(EMA)', () async {
      final c = make()..setEnabled(true);
      expect(stream.hasListener, true);

      stream.add(_acc(4.9, 8.49, 0)); // 참 롤 ~30°
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(c.rollDegrees, closeTo(7.5, 2.5)); // 0.25 * 30
      c.dispose();
    });

    test('여러 표본이 쌓이면 수평을 인식한다', () async {
      final c = make()..setEnabled(true);
      for (var i = 0; i < 20; i++) {
        stream.add(_acc(0, 9.8, 0));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(c.rollDegrees, closeTo(0, 0.5));
      expect(c.isLevel, true);
      c.dispose();
    });

    test('끄면 구독 해제 + 롤 초기화, 이후 표본은 무시', () async {
      final c = make()..setEnabled(true);
      stream.add(_acc(5, 8, 0));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      c.setEnabled(false);
      expect(stream.hasListener, false);
      expect(c.rollDegrees, 0);
      expect(c.isLevel, false);
      c.dispose();
    });

    test('hydrate 로 저장된 켜짐 상태를 복원하고 구독한다', () async {
      SharedPreferences.setMockInitialValues({'levelEnabled': true});
      final s = await SettingsStore.load();

      final c = make()..hydrate(s);
      expect(c.enabled, true);
      expect(stream.hasListener, true);
      c.dispose();
    });
  });
}
