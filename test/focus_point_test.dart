import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_hud.dart';

void main() {
  group('previewFocusPoint', () {
    test('세로 폰 + 4:3 카메라: 가로가 잘려 탭 X가 안쪽으로 매핑된다', () {
      const screen = Size(1080, 2340); // aspect ≈ 0.4615
      const aspect = 4 / 3; // 카메라 프리뷰(가로) 비율
      // raw ≈ 0.6154 < 1 → scale ≈ 1.625, visible ≈ 0.6154, start ≈ 0.1923

      final center = previewFocusPoint(const Offset(0.5, 0.5), screen, aspect);
      expect(center.dx, closeTo(0.5, 1e-6)); // 중앙은 중앙
      expect(center.dy, closeTo(0.5, 1e-6));

      final left = previewFocusPoint(const Offset(0, 0.3), screen, aspect);
      expect(left.dx, closeTo(0.1923, 1e-3)); // 화면 왼쪽 끝 → 센서 안쪽
      expect(left.dy, 0.3); // 세로는 그대로

      final right = previewFocusPoint(const Offset(1, 0.7), screen, aspect);
      expect(right.dx, closeTo(0.8077, 1e-3));
      expect(right.dy, 0.7);
    });

    test('raw == 1 이면 항등(크롭 없음)', () {
      // screen.aspectRatio * aspect == 1
      const screen = Size(1000, 2000); // aspect 0.5
      const aspect = 2.0;
      final p = previewFocusPoint(const Offset(0.2, 0.9), screen, aspect);
      expect(p.dx, closeTo(0.2, 1e-9));
      expect(p.dy, closeTo(0.9, 1e-9));
    });

    test('raw > 1 이면 세로가 잘린다', () {
      const screen = Size(1080, 1200); // aspect 0.9
      const aspect = 16 / 9; // ≈ 1.778 → raw ≈ 1.6 > 1
      final top = previewFocusPoint(const Offset(0.5, 0), screen, aspect);
      expect(top.dx, 0.5); // 가로는 그대로
      expect(top.dy, greaterThan(0.0)); // 화면 위쪽 끝 → 센서 안쪽
      expect(top.dy, lessThan(0.5));

      final center = previewFocusPoint(const Offset(0.5, 0.5), screen, aspect);
      expect(center.dy, closeTo(0.5, 1e-6));
    });

    test('비정상 입력(0·NaN)이면 그대로 돌려준다', () {
      const screen = Size(1080, 2340);
      final z = previewFocusPoint(const Offset(0.3, 0.4), screen, 0);
      expect(z, const Offset(0.3, 0.4));
      final n = previewFocusPoint(const Offset(0.3, 0.4), screen, double.nan);
      expect(n, const Offset(0.3, 0.4));
    });

    test('결과는 항상 0~1 로 클램프된다', () {
      const screen = Size(1080, 2340);
      final p = previewFocusPoint(const Offset(1.5, -0.2), screen, 4 / 3);
      expect(p.dx, inInclusiveRange(0.0, 1.0));
      expect(p.dy, inInclusiveRange(0.0, 1.0));
    });
  });
}
