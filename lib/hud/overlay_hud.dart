import 'package:flutter/material.dart';

import '../overlay_controller.dart';
import '../ui_metrics.dart';

/// 색 반전(네거티브) ColorFilter. RGB를 뒤집는다.
const ColorFilter _invertColorFilter = ColorFilter.matrix(<double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0, //
]);

/// 반투명 고스트 오버레이 + 확대·이동·회전 제스처.
class OverlayLayer extends StatelessWidget {
  const OverlayLayer({super.key, required this.overlay});

  final OverlayController overlay;

  @override
  Widget build(BuildContext context) {
    if (!overlay.hasFile) return const SizedBox.shrink();
    // displayFile: 윤곽선 모드면 추출된 윤곽선(처리 중이면 원본)을 보여준다.
    final file = overlay.displayFile!;

    Widget image = Image.file(file, fit: BoxFit.contain, gaplessPlayback: true);
    if (overlay.inverted) {
      image = ColorFiltered(colorFilter: _invertColorFilter, child: image);
    }
    if (overlay.mirrored) {
      image = Transform.flip(flipX: true, child: image);
    }
    image = Transform.scale(scale: overlay.scale, child: image);
    image = Transform.rotate(angle: overlay.rotation, child: image);
    image = Transform.translate(offset: overlay.offset, child: image);
    image = Opacity(opacity: overlay.opacity, child: image);

    if (overlay.locked) {
      return IgnorePointer(child: image);
    }
    return GestureDetector(
      onScaleStart: overlay.onScaleStart,
      onScaleUpdate: overlay.onScaleUpdate,
      child: image,
    );
  }
}

/// 오버레이가 있을 때 화면 왼쪽 위에 항상 보이는 삭제 버튼.
/// 상단 바 안의 같은 기능 버튼을 못 찾는 경우를 대비한 여분의 확실한 진입점.
class OverlayQuickClear extends StatelessWidget {
  const OverlayQuickClear({
    super.key,
    required this.overlay,
    required this.metrics,
  });

  final OverlayController overlay;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!overlay.hasFile) return const SizedBox.shrink();
    final m = metrics;
    final size = m.spc(40, 36.0, 52.0);
    // 좌측 중앙: 상단 바·하단 바·우측 슬라이더·스탬프 패널과 겹치지 않는 빈 공간.
    return SafeArea(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(left: m.sp(8)),
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: overlay.clear,
              child: Tooltip(
                message: '오버레이 삭제',
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: m.spc(22, 20.0, 30.0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 우측 세로 투명도 슬라이더.
class RightControls extends StatelessWidget {
  const RightControls({super.key, required this.overlay, required this.metrics});

  final OverlayController overlay;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final toggleH = m.spc(32, 28.0, 40.0);
    // 고정 요소(아이콘 + % + 토글 3개 + 간격 + 세로 패딩) 높이.
    final fixedH = m.spc(18, 16.0, 26.0) +
        m.spc(12, 11.0, 16.0) +
        m.sp(10) +
        toggleH * 3 +
        m.sp(8) * 2 +
        m.sp(24);
    // 상단 바·하단 바와 안 겹치도록 패널이 쓸 수 있는 세로 공간을 제한하고,
    // 그 안에서 남는 만큼만 슬라이더에 준다(작은 폰에서 아이콘이 잘리지 않게).
    final maxPanelH = m.size.height - m.padding.vertical - m.sp(300);
    final sliderLen = (maxPanelH - fixedH)
        .clamp(96.0, m.isTablet ? 420.0 : 260.0)
        .toDouble();
    final hasOverlay = overlay.hasFile;
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: EdgeInsets.only(right: m.sp(6)),
          padding: EdgeInsets.symmetric(vertical: m.sp(12)),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(m.sp(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.opacity,
                  color: Colors.white, size: m.spc(18, 16.0, 26.0)),
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
                      value: overlay.opacity,
                      onChanged: hasOverlay ? overlay.setOpacity : null,
                      onChangeEnd: hasOverlay ? overlay.commitOpacity : null,
                    ),
                  ),
                ),
              ),
              Text(
                '${(overlay.opacity * 100).round()}%',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: m.spc(12, 11.0, 16.0),
                ),
              ),
              SizedBox(height: m.sp(10)),
              _OutlineToggle(overlay: overlay, metrics: m),
              SizedBox(height: m.sp(8)),
              _OverlayIconToggle(
                icon: Icons.flip,
                tooltip: '좌우 반전',
                active: overlay.mirrored,
                enabled: hasOverlay,
                onTap: overlay.toggleMirror,
                metrics: m,
              ),
              SizedBox(height: m.sp(8)),
              _OverlayIconToggle(
                icon: Icons.invert_colors,
                tooltip: '색 반전',
                active: overlay.inverted,
                enabled: hasOverlay,
                onTap: overlay.toggleInvert,
                metrics: m,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 우측 패널용 소형 아이콘 토글(켜짐=앰버, 비활성=흐림).
class _OverlayIconToggle extends StatelessWidget {
  const _OverlayIconToggle({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.enabled,
    required this.onTap,
    required this.metrics,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final size = m.spc(32, 28.0, 40.0);
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: m.spc(20, 18.0, 26.0),
              color: !enabled
                  ? Colors.white24
                  : active
                      ? Colors.amber
                      : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 사진 대신 흰색 윤곽선만 보여주는 모드 토글. 밝고 복잡한 배경에서
/// 반투명 사진보다 정합선이 더 잘 보이도록 하는 용도.
class _OutlineToggle extends StatelessWidget {
  const _OutlineToggle({required this.overlay, required this.metrics});

  final OverlayController overlay;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final hasOverlay = overlay.hasFile;
    final size = m.spc(32, 28.0, 40.0);
    return Tooltip(
      message: '흰색 윤곽선으로 보기',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: hasOverlay ? overlay.toggleOutline : null,
          child: SizedBox(
            width: size,
            height: size,
            child: overlay.tracingOutline
                ? Padding(
                    padding: EdgeInsets.all(m.sp(7)),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.amber,
                    ),
                  )
                : Icon(
                    Icons.gesture,
                    size: m.spc(20, 18.0, 26.0),
                    color: !hasOverlay
                        ? Colors.white24
                        : overlay.outlineMode
                            ? Colors.amber
                            : Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}
