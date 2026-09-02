import 'package:flutter/widgets.dart';

/// 화면 크기 기반 반응형 치수. iPhone mini(~320~375)부터 태블릿(>=600)까지 대응.
/// build()에서 한 번 만들어 하위 빌더에 넘겨 쓴다.
class Metrics {
  Metrics(MediaQueryData mq)
      : size = mq.size,
        padding = mq.padding {
    final shortest = mq.size.shortestSide;
    isTablet = shortest >= 600;
    // 기준 폭 390 대비 배율. 폰은 0.82~1.15, 태블릿은 1.3 고정.
    scale = isTablet ? 1.3 : (shortest / 390).clamp(0.82, 1.15).toDouble();
  }

  final Size size;
  final EdgeInsets padding;
  late final bool isTablet;
  late final double scale;

  /// 스케일이 적용된 크기.
  double sp(double v) => v * scale;

  /// 스케일 적용 후 [lo]~[hi]로 제한한 크기.
  double spc(double v, double lo, double hi) =>
      (v * scale).clamp(lo, hi).toDouble();
}
