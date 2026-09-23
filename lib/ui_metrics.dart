import 'package:flutter/widgets.dart';

/// 화면 크기 기반 반응형 치수. iPhone mini(~320~375)부터 태블릿(>=600)까지 대응.
/// build()에서 한 번 만들어 하위 빌더에 넘겨 쓴다.
class Metrics {
  Metrics(MediaQueryData mq) : size = mq.size, padding = mq.padding {
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

  /// 좌우 세로 패널(노출 슬라이더·오버레이 컨트롤)이 쓸 수 있는 최대 높이.
  /// 상단 바와 하단 촬영 바가 차지하는 만큼을 화면 높이에서 뺀다.
  double get sidePanelMaxHeight => size.height - padding.vertical - sp(300);

  /// 스탬프 미리보기가 상단 요소(상단 바 + 스탬프 위치 선택 패널)를 피하려면
  /// 화면 위에서 띄워야 하는 거리. 각 항은 그 요소의 스케일된 높이다.
  double get stampTopClearance =>
      sp(52) + // 상단 바
      sp(34) * 2 + // 위치 선택 버튼 2줄
      sp(48) + // 패널 제목·여백
      sp(24); // 여유 간격

  /// 스탬프 미리보기가 하단 촬영 바를 피하려면 화면 아래에서 띄워야 하는 거리.
  double get stampBottomClearance =>
      sp(58) + // 촬영 버튼
      sp(24) + // 버튼 아래 라벨·여백
      sp(44); // 여유 간격
}
