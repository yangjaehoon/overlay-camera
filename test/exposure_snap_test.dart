import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_session.dart';

void main() {
  group('snapExposureOffset', () {
    test('step<=0 이면 클램프만 한다', () {
      expect(snapExposureOffset(0.37, -2.0, 2.0, 0.0), 0.37);
      expect(snapExposureOffset(5.0, -2.0, 2.0, 0.0), 2.0);
      expect(snapExposureOffset(-5.0, -2.0, 2.0, 0.0), -2.0);
      expect(snapExposureOffset(0.37, -2.0, 2.0, -1.0), 0.37); // 음수 step 도 연속 취급
    });

    test('step 이 있으면 그 배수로 스냅', () {
      // step = 1/3
      expect(snapExposureOffset(0.30, -2.0, 2.0, 1 / 3), closeTo(1 / 3, 1e-9));
      expect(snapExposureOffset(0.10, -2.0, 2.0, 1 / 3), closeTo(0.0, 1e-9));
      expect(snapExposureOffset(-0.30, -2.0, 2.0, 1 / 3), closeTo(-1 / 3, 1e-9));
    });

    test('스냅 결과가 범위를 벗어나면 다시 클램프', () {
      // step=0.5, max=1.8 -> 1.75 를 스냅하면 2.0 이지만 max 로 잘림
      expect(snapExposureOffset(1.8, -1.8, 1.8, 0.5), 1.8);
      expect(snapExposureOffset(-1.8, -1.8, 1.8, 0.5), -1.8);
    });

    test('정확히 스텝 위의 값은 그대로', () {
      expect(snapExposureOffset(1.0, -2.0, 2.0, 0.5), 1.0);
      expect(snapExposureOffset(0.0, -2.0, 2.0, 0.5), 0.0);
    });
  });
}
