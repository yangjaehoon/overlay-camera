import 'dart:async';

import 'package:flutter/material.dart';

import '../camera_session.dart';
import '../ui_metrics.dart';

String zoomLabel(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}×' : '${v.toStringAsFixed(1)}×';

/// 줌 바에 띄울 프리셋 배율. 항상 1×(또는 초광각 min)과 max 를 포함하고,
/// 범위가 넉넉하면 2× 를 넣는다.
List<double> zoomPresets(double min, double max) {
  double round1(double v) => double.parse(v.toStringAsFixed(1));
  final set = <double>{};
  if (min < 0.95) set.add(round1(min)); // 초광각
  set.add(min < 1.05 ? 1.0 : round1(min));
  if (max > 2.3) set.add(2.0);
  set.add(round1(max));
  // 끝점을 소수 1자리로 반올림하면 최대 0.05 밀린다. 허용오차를 그 절반이 아닌
  // 반올림 폭(0.05)으로 잡아야 반올림된 min·max 프리셋이 필터에서 탈락하지 않는다.
  return set.where((v) => v >= min - 0.05 && v <= max + 0.05).toList()..sort();
}

/// 하단 가운데 디지털 줌 바. 프리셋(1×/2×/최대 등) 칩 + 좌우 드래그로 미세 조절.
/// 줌을 지원하지 않는 기기에서는 그리지 않는다.
class ZoomBar extends StatelessWidget {
  const ZoomBar({super.key, required this.session, required this.metrics});

  final CameraSession session;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!session.isReady || !session.canZoom) return const SizedBox.shrink();
    final m = metrics;
    final presets = zoomPresets(session.minZoom, session.maxZoom);
    final z = session.zoom;
    final active = presets.reduce(
      (a, b) => (z - a).abs() <= (z - b).abs() ? a : b,
    );
    final span = session.maxZoom - session.minZoom;

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: m.spc(150, 128.0, 190.0)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => unawaited(
              session.setZoom(z + d.delta.dx / 160 * span),
            ),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: m.sp(6),
                vertical: m.sp(4),
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(m.sp(22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in presets)
                    _ZoomChip(
                      label: p == active ? zoomLabel(z) : zoomLabel(p),
                      active: p == active,
                      onTap: () => unawaited(session.setZoom(p)),
                      metrics: m,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.metrics,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: m.sp(8),
            vertical: m.sp(6),
          ),
          decoration: BoxDecoration(
            color: active ? Colors.amber : Colors.transparent,
            borderRadius: BorderRadius.circular(m.sp(20)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: m.spc(34, 30.0, 46.0)),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? Colors.black87 : Colors.white,
                fontSize: m.spc(12, 11.0, 16.0),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 노출 보정 값 라벨. 0 은 "0", 양수는 "+1.0", 음수는 "-1.3".
String evLabel(double v) {
  if (v.abs() < 0.05) return '0';
  final s = v.toStringAsFixed(1);
  return v > 0 ? '+$s' : s;
}

/// 좌측 세로 노출 보정(EV) 슬라이더. 우측 오버레이 패널과 대칭.
/// 노출 보정을 지원하지 않는 기기에서는 그리지 않는다.
class ExposureBar extends StatelessWidget {
  const ExposureBar({super.key, required this.session, required this.metrics});

  final CameraSession session;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!session.isReady || !session.canSetExposure) {
      return const SizedBox.shrink();
    }
    final m = metrics;
    final maxPanelH = m.size.height - m.padding.vertical - m.sp(300);
    final sliderLen =
        maxPanelH.clamp(96.0, m.isTablet ? 360.0 : 220.0).toDouble();
    final lo = session.minExposureOffset;
    final hi = session.maxExposureOffset;
    final value = session.exposureOffset.clamp(lo, hi).toDouble();
    // 기기 스텝이 있으면 그 눈금으로 스냅되게 한다(연속 지원이거나
    // 눈금이 너무 촘촘하면 그냥 연속 슬라이더로).
    final step = session.exposureStep;
    final rawDiv = step > 0 ? ((hi - lo) / step).round() : 0;
    final divisions = (rawDiv >= 2 && rawDiv <= 60) ? rawDiv : null;
    return SafeArea(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(left: m.sp(6)),
          padding: EdgeInsets.symmetric(vertical: m.sp(12), horizontal: m.sp(2)),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(m.sp(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: Colors.white,
                size: m.spc(18, 16.0, 26.0),
              ),
              SizedBox(
                width: m.spc(40, 36.0, 52.0),
                height: sliderLen,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: value,
                      min: lo,
                      max: hi,
                      divisions: divisions,
                      onChanged: (v) =>
                          unawaited(session.setExposureOffset(v)),
                    ),
                  ),
                ),
              ),
              Text(
                evLabel(session.exposureOffset),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: m.spc(12, 11.0, 16.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
