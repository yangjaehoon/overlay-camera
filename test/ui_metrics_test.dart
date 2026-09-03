import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/ui_metrics.dart';

Metrics _forShortestSide(double shortest) =>
    Metrics(MediaQueryData(size: Size(shortest, shortest * 2)));

void main() {
  test('작은 폰은 배율 하한 0.82로 클램프', () {
    final m = _forShortestSide(300);
    expect(m.isTablet, false);
    expect(m.scale, 0.82);
  });

  test('기준 폭 390에서 배율 1.0', () {
    expect(_forShortestSide(390).scale, closeTo(1.0, 1e-9));
  });

  test('큰 폰은 배율 상한 1.15로 클램프', () {
    expect(_forShortestSide(500).scale, 1.15);
  });

  test('짧은 변 600 이상은 태블릿, 배율 1.3 고정', () {
    final m = _forShortestSide(700);
    expect(m.isTablet, true);
    expect(m.scale, 1.3);
  });

  test('sp / spc 계산', () {
    final m = _forShortestSide(390); // scale 1.0
    expect(m.sp(10), 10);
    expect(m.spc(10, 12, 20), 12); // 하한으로 올림
    expect(m.spc(30, 12, 20), 20); // 상한으로 내림
  });
}
