import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_hud.dart';

void main() {
  group('zoomPresets', () {
    test('줌 범위가 없으면 1배 하나만', () {
      expect(zoomPresets(1.0, 1.0), [1.0]);
    });

    test('일반 후면(1~8배)은 1·2·최대', () {
      expect(zoomPresets(1.0, 8.0), [1.0, 2.0, 8.0]);
    });

    test('초광각이 있으면 min 을 앞에 넣는다', () {
      expect(zoomPresets(0.5, 10.0), [0.5, 1.0, 2.0, 10.0]);
    });

    test('최대가 2.3배 이하면 2배 프리셋은 넣지 않는다', () {
      expect(zoomPresets(1.0, 2.0), [1.0, 2.0]);
    });

    test('끝점이 소수 1자리로 반올림돼 밀려도 최대 배율 칩이 살아있다', () {
      // 8.06 -> "8.1", 7.96 -> "8.0", 10.06 -> "10.1" 로 반올림되며
      // 예전 ±0.01 필터에서는 전부 탈락해 [1.0, 2.0] 만 남았다.
      expect(zoomPresets(1.0, 8.06).last, closeTo(8.1, 0.001));
      expect(zoomPresets(1.0, 7.96).last, closeTo(8.0, 0.001));
      expect(zoomPresets(1.0, 10.06).last, closeTo(10.1, 0.001));
      expect(zoomPresets(1.0, 8.06), contains(2.0));
    });

    test('초광각 min 이 애매하게 반올림돼도 초광각 칩이 살아있다', () {
      // 0.94 -> "0.9"
      expect(zoomPresets(0.94, 8.0).first, closeTo(0.9, 0.001));
    });

    test('항상 오름차순이고 max 를 포함한다', () {
      final list = zoomPresets(0.6, 5.0);
      final sorted = [...list]..sort();
      expect(list, sorted);
      expect(list.last, 5.0);
      expect(list.first, lessThanOrEqualTo(1.0));
    });

    test('모든 값이 [min, max] 범위 안에 있다', () {
      for (final (min, max) in [(1.0, 1.2), (0.5, 3.0), (2.0, 2.1)]) {
        for (final v in zoomPresets(min, max)) {
          expect(v, greaterThanOrEqualTo(min - 0.01));
          expect(v, lessThanOrEqualTo(max + 0.01));
        }
      }
    });
  });

  group('zoomLabel', () {
    test('정수 배율은 소수점 없이', () {
      expect(zoomLabel(1.0), '1×');
      expect(zoomLabel(2.0), '2×');
    });

    test('소수 배율은 한 자리까지', () {
      expect(zoomLabel(1.5), '1.5×');
      expect(zoomLabel(0.6), '0.6×');
    });
  });

  group('evLabel', () {
    test('0 근처는 "0"', () {
      expect(evLabel(0.0), '0');
      expect(evLabel(0.03), '0');
      expect(evLabel(-0.02), '0');
    });

    test('양수는 + 접두사', () {
      expect(evLabel(1.0), '+1.0');
      expect(evLabel(0.7), '+0.7');
    });

    test('음수는 - 부호 그대로', () {
      expect(evLabel(-1.0), '-1.0');
      expect(evLabel(-1.33), '-1.3');
    });
  });
}
