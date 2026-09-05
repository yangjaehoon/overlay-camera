import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_session.dart';
import 'camera_widgets.dart';
import 'grid_controller.dart';
import 'location_stamp_controller.dart';
import 'overlay_controller.dart';
import 'photo_stamp.dart';
import 'shape_guide.dart';
import 'shape_guide_controller.dart';
import 'ui_metrics.dart';

IconData flashIcon(FlashMode mode) {
  switch (mode) {
    case FlashMode.off:
      return Icons.flash_off;
    case FlashMode.auto:
      return Icons.flash_auto;
    case FlashMode.always:
      return Icons.flash_on;
    case FlashMode.torch:
      return Icons.highlight;
  }
}

/// 전체 화면 카메라 프리뷰 (화면을 덮도록 확대).
class CameraPreviewArea extends StatelessWidget {
  const CameraPreviewArea({super.key, required this.session});

  final CameraSession session;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final mediaSize = MediaQuery.of(context).size;
    var scale = mediaSize.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }
}

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

/// 3분할 정렬 그리드.
class GridOverlay extends StatelessWidget {
  const GridOverlay({super.key, required this.type});

  final GridType type;

  static const _goldenRatio = 0.382; // (1 - 1/phi), 나머지 선은 1 - 이 값

  @override
  Widget build(BuildContext context) {
    final fractions = switch (type) {
      GridType.none => const <double>[],
      GridType.thirds => const [1 / 3, 2 / 3],
      GridType.quarters => const [1 / 4, 2 / 4, 3 / 4],
      GridType.goldenRatio => const [_goldenRatio, 1 - _goldenRatio],
    };
    if (fractions.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: GridPainter(fractions), size: Size.infinite),
    );
  }
}

/// 화면 짧은 변 기준 도형 지름(px). 위젯 여러 곳에서 같은 공식을 쓰도록 분리.
double shapeGuideDiameter(ShapeGuide s, Size screen) =>
    (s.size * screen.shortestSide).clamp(24.0, screen.shortestSide * 2).toDouble();

/// 사용자가 배치한 원/정사각형 가이드 도형들(선만). 삭제 배지는 [ShapeGuideBadges]가
/// HUD 위 최상단 레이어에서 따로 그린다(패널에 가려 못 누르는 일이 없도록).
///
/// 편집 모드가 아니면 [IgnorePointer]로 감싸 터치를 통과시킨다(그 아래 오버레이·
/// 카메라 조작을 막지 않음). 편집 모드일 때만 드래그·크기조절 제스처를 받는다.
class ShapeGuideLayer extends StatelessWidget {
  const ShapeGuideLayer({
    super.key,
    required this.guide,
    required this.metrics,
  });

  final ShapeGuideController guide;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    if (guide.isEmpty || metrics.size.shortestSide <= 0) {
      return const SizedBox.shrink();
    }
    final strokeWidth = metrics.sp(2.5).clamp(2.0, 4.0).toDouble();
    return Stack(
      children: [
        for (final shape in guide.shapes)
          _ShapeGuideItem(
            key: ValueKey(shape.id),
            shape: shape,
            guide: guide,
            screenSize: metrics.size,
            strokeWidth: strokeWidth,
          ),
      ],
    );
  }
}

class _ShapeGuideItem extends StatefulWidget {
  const _ShapeGuideItem({
    super.key,
    required this.shape,
    required this.guide,
    required this.screenSize,
    required this.strokeWidth,
  });

  final ShapeGuide shape;
  final ShapeGuideController guide;
  final Size screenSize;
  final double strokeWidth;

  @override
  State<_ShapeGuideItem> createState() => _ShapeGuideItemState();
}

class _ShapeGuideItemState extends State<_ShapeGuideItem> {
  double _baseSize = 0;

  void _onScaleStart(ScaleStartDetails details) {
    _baseSize = widget.shape.size;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // 이동·크기를 한 번에 반영(알림 1회). 크기는 두 손가락일 때만 바꾼다.
    widget.guide.dragUpdate(
      widget.shape.id,
      pixelDelta: details.focalPointDelta,
      screenSize: widget.screenSize,
      size: details.pointerCount >= 2 ? _baseSize * details.scale : null,
    );
  }

  void _onScaleEnd(ScaleEndDetails details) => widget.guide.commit();

  @override
  Widget build(BuildContext context) {
    final s = widget.shape;
    final screen = widget.screenSize;
    final diameter = shapeGuideDiameter(s, screen);
    final left = s.cx * screen.width - diameter / 2;
    final top = s.cy * screen.height - diameter / 2;
    final editing = widget.guide.editing;

    final shapeVisual = CustomPaint(
      size: Size(diameter, diameter),
      painter: _ShapeGuidePainter(
        type: s.type,
        strokeWidth: widget.strokeWidth,
      ),
    );

    // 편집 모드가 아니면 터치를 통과시켜 아래 오버레이·카메라 조작을 막지 않는다.
    // 편집 모드에서는 opaque 로 도형 위 터치를 이 제스처가 가로챈다(아래로 전달 X).
    return Positioned(
      left: left,
      top: top,
      width: diameter,
      height: diameter,
      child: editing
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: shapeVisual,
            )
          : IgnorePointer(child: shapeVisual),
    );
  }
}

/// 도형별 삭제 배지. HUD 패널 위에 그려서 도형을 화면 구석으로 밀어도 항상 누를 수 있다.
/// 편집 모드가 아니거나 도형이 없으면 아무것도 그리지 않는다.
class ShapeGuideBadges extends StatelessWidget {
  const ShapeGuideBadges({
    super.key,
    required this.guide,
    required this.metrics,
    this.onMessage,
  });

  final ShapeGuideController guide;
  final Metrics metrics;
  final void Function(String message)? onMessage;

  static const _badge = 44.0;

  @override
  Widget build(BuildContext context) {
    final screen = metrics.size;
    if (guide.isEmpty || !guide.editing || screen.shortestSide <= 0) {
      return const SizedBox.shrink();
    }
    final pad = MediaQuery.paddingOf(context);
    // 배지가 상태바/제스처바 안쪽에 오도록 안전 영역만큼 뺀다.
    final minX = pad.left + 4;
    final maxX = screen.width - pad.right - 4 - _badge;
    final minY = pad.top + 4;
    final maxY = screen.height - pad.bottom - 4 - _badge;

    return Stack(
      children: [
        for (final shape in guide.shapes)
          _positionedBadge(shape, screen, minX, maxX, minY, maxY),
      ],
    );
  }

  Widget _positionedBadge(
    ShapeGuide shape,
    Size screen,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    final d = shapeGuideDiameter(shape, screen);
    // 도형 오른쪽 위 모서리에 배지 중심을 두고, 화면(안전 영역) 안으로 클램프.
    final x = shape.cx * screen.width + d / 2 - _badge / 2;
    final y = shape.cy * screen.height - d / 2 - _badge / 2;
    return Positioned(
      key: ValueKey(shape.id),
      left: x.clamp(minX, maxX < minX ? minX : maxX),
      top: y.clamp(minY, maxY < minY ? minY : maxY),
      child: _DeleteBadge(
        size: _badge,
        onTap: () {
          guide.remove(shape.id);
          onMessage?.call('도형을 삭제했습니다.');
        },
      ),
    );
  }
}

class _ShapeGuidePainter extends CustomPainter {
  const _ShapeGuidePainter({required this.type, required this.strokeWidth});

  final ShapeGuideType type;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 밝은 배경에서도 보이도록 어두운 헤일로를 먼저 깔고 흰 선을 얹는다.
    final halo = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 2;
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    if (type == ShapeGuideType.circle) {
      canvas.drawOval(rect, halo);
      canvas.drawOval(rect, line);
    } else {
      canvas.drawRect(rect, halo);
      canvas.drawRect(rect, line);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeGuidePainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.strokeWidth != strokeWidth;
}

/// 도형 모서리에 뜨는 삭제 배지. 눈에 잘 띄고 최소 터치 타깃(44)을 확보한다.
class _DeleteBadge extends StatelessWidget {
  const _DeleteBadge({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '도형 삭제',
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onTap,
            radius: size * 0.5,
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.close, color: Colors.redAccent, size: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 편집 모드일 때 화면 하단 가운데에 뜨는 "편집 완료" 알약 버튼.
/// 시트를 다시 열지 않고도 편집 모드를 끌 수 있게 한다.
class ShapeGuideEditBanner extends StatelessWidget {
  const ShapeGuideEditBanner({
    super.key,
    required this.guide,
    required this.metrics,
  });

  final ShapeGuideController guide;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!guide.editing) return const SizedBox.shrink();
    final m = metrics;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          // 하단 촬영 바 + 날짜·장소 스탬프 미리보기 위쪽으로 띄운다.
          padding: EdgeInsets.only(bottom: m.spc(190, 165.0, 240.0)),
          child: Material(
            color: Colors.amber,
            borderRadius: BorderRadius.circular(m.sp(24)),
            child: InkWell(
              borderRadius: BorderRadius.circular(m.sp(24)),
              onTap: () => guide.setEditing(false),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: m.sp(18),
                  vertical: m.sp(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check,
                        color: Colors.black87, size: m.spc(18, 16.0, 24.0)),
                    SizedBox(width: m.sp(6)),
                    Text(
                      '도형 편집 완료',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                        fontSize: m.spc(13, 12.0, 18.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 상단 컨트롤 바 (무음·스탬프·플래시·오버레이 조작·자동사용).
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.session,
    required this.stamp,
    required this.overlay,
    required this.grid,
    required this.shapeGuide,
    required this.metrics,
    required this.onOpenGridSettings,
    required this.onOpenShapeGuideSettings,
  });

  final CameraSession session;
  final LocationStampController stamp;
  final OverlayController overlay;
  final GridController grid;
  final ShapeGuideController shapeGuide;
  final Metrics metrics;
  final VoidCallback onOpenGridSettings;
  final VoidCallback onOpenShapeGuideSettings;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final btn = m.spc(38, 34.0, 52.0);
    final icon = m.spc(21, 19.0, 28.0);
    final maxW = m.size.width - m.sp(16);
    final hasOverlay = overlay.hasFile;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: m.sp(8), vertical: m.sp(8)),
          padding: EdgeInsets.symmetric(horizontal: m.sp(4)),
          constraints: BoxConstraints(maxWidth: m.isTablet ? 560.0 : maxW),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(m.sp(28)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BarButton(
                  icon: session.silentShutter
                      ? Icons.volume_off
                      : Icons.volume_up,
                  color: session.silentShutter ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '무음 촬영',
                  onTap: session.toggleSilentShutter,
                ),
                BarButton(
                  icon: Icons.today,
                  color: stamp.enabled ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '날짜·장소 표시',
                  onTap: stamp.toggle,
                ),
                BarButton(
                  icon: flashIcon(session.flashMode),
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '플래시',
                  onTap: session.cycleFlash,
                ),
                BarButton(
                  icon: grid.type.icon,
                  color: grid.type == GridType.none
                      ? Colors.white
                      : Colors.amber,
                  size: btn,
                  iconSize: icon,
                  tooltip: '그리드 설정',
                  onTap: onOpenGridSettings,
                ),
                // 도형 드래그마다 shapeGuide 가 알림을 쏘므로, 상단 바 전체가 아니라
                // 이 버튼만 다시 빌드되도록 별도 ListenableBuilder 로 감싼다.
                ListenableBuilder(
                  listenable: shapeGuide,
                  builder: (_, _) => BarButton(
                    icon: Icons.category_outlined,
                    color: shapeGuide.isEmpty ? Colors.white : Colors.amber,
                    size: btn,
                    iconSize: icon,
                    tooltip: '도형 가이드',
                    onTap: onOpenShapeGuideSettings,
                  ),
                ),
                BarButton(
                  icon: overlay.locked ? Icons.lock : Icons.lock_open,
                  color: overlay.locked ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 고정',
                  onTap: hasOverlay ? overlay.toggleLock : null,
                ),
                BarButton(
                  icon: Icons.restart_alt,
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 위치 초기화',
                  onTap: hasOverlay ? overlay.resetTransform : null,
                ),
                BarButton(
                  icon: Icons.delete_outline,
                  color: hasOverlay ? Colors.redAccent : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 삭제',
                  onTap: hasOverlay ? overlay.clear : null,
                ),
                BarButton(
                  icon: Icons.auto_mode,
                  color: overlay.autoUseLast ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '촬영 후 마지막 컷을 오버레이로',
                  onTap: overlay.toggleAutoUseLast,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 선택한 모서리에 찍힐 스탬프 문구 미리보기.
class StampPreview extends StatelessWidget {
  const StampPreview({super.key, required this.stamp, required this.metrics});

  final LocationStampController stamp;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!stamp.enabled) return const SizedBox.shrink();
    final m = metrics;
    // 위쪽은 상단 바 + 위치 선택 패널, 아래쪽은 하단 촬영 바를 확실히 피하도록
    // 스케일된 컴포넌트 높이 + 여유 간격만큼 띄운다.
    final topClear = m.sp(52) + m.sp(34) * 2 + m.sp(48) + m.sp(24);
    final bottomClear = m.sp(58) + m.sp(24) + m.sp(44);
    final corner = stamp.corner;
    return IgnorePointer(
      child: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: m.sp(14), vertical: m.sp(12)),
        child: Align(
          alignment: corner.alignment,
          child: Padding(
            padding: EdgeInsets.only(
              top: corner.isTop ? topClear : 0,
              bottom: corner.isTop ? 0 : bottomClear,
            ),
            child: Text(
              stamp.previewText(),
              textAlign: corner.isLeft ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                color: Colors.white,
                fontSize: m.spc(15, 13.0, 22.0),
                fontWeight: FontWeight.w600,
                height: 1.25,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 4),
                  Shadow(color: Colors.black54, blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 스탬프 위치(4모서리) 선택 패널.
class StampCornerPicker extends StatelessWidget {
  const StampCornerPicker({
    super.key,
    required this.stamp,
    required this.metrics,
  });

  final LocationStampController stamp;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!stamp.enabled) return const SizedBox.shrink();
    final m = metrics;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: EdgeInsets.only(top: m.sp(52)),
          padding: EdgeInsets.fromLTRB(m.sp(10), m.sp(8), m.sp(10), m.sp(10)),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(m.sp(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '스탬프 위치',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: m.spc(11, 10.0, 15.0),
                ),
              ),
              SizedBox(height: m.sp(6)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CornerButton(
                      corner: StampCorner.topLeft, stamp: stamp, metrics: m),
                  _CornerButton(
                      corner: StampCorner.topRight, stamp: stamp, metrics: m),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CornerButton(
                      corner: StampCorner.bottomLeft, stamp: stamp, metrics: m),
                  _CornerButton(
                      corner: StampCorner.bottomRight, stamp: stamp, metrics: m),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.corner,
    required this.stamp,
    required this.metrics,
  });

  final StampCorner corner;
  final LocationStampController stamp;
  final Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final active = stamp.corner == corner;
    final r = m.sp(8);
    return Padding(
      padding: EdgeInsets.all(m.sp(3)),
      child: Material(
        color: active ? Colors.amber : Colors.white24,
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: () => stamp.selectCorner(corner),
          child: SizedBox(
            width: m.spc(50, 44.0, 72.0),
            height: m.spc(34, 30.0, 48.0),
            child: Align(
              alignment: corner.alignment,
              child: Padding(
                padding: EdgeInsets.all(m.sp(5)),
                child: Container(
                  width: m.sp(15),
                  height: m.sp(6),
                  decoration: BoxDecoration(
                    color: active ? Colors.black87 : Colors.white70,
                    borderRadius: BorderRadius.circular(2),
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
    final sliderLen = (m.size.height * 0.30)
        .clamp(140.0, m.isTablet ? 420.0 : 260.0)
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
            ],
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

/// 하단 촬영 바. 촬영 동작은 화면에서 조율하므로 콜백으로 받는다.
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.session,
    required this.metrics,
    required this.onPickGallery,
    required this.onTakePhoto,
    required this.onToggleRecording,
    required this.onSnapshot,
  });

  final CameraSession session;
  final Metrics metrics;
  final VoidCallback onPickGallery;
  final VoidCallback onTakePhoto;
  final VoidCallback onToggleRecording;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final busy = session.busy;
    final recording = session.isRecording;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding:
              EdgeInsets.only(bottom: m.sp(20), left: m.sp(4), right: m.sp(4)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: m.size.width < 560 ? m.size.width : 560.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                RoundButton(
                  icon: Icons.photo_library_outlined,
                  onPressed: busy ? null : onPickGallery,
                  label: '갤러리',
                  scale: m.scale,
                ),
                RoundButton(
                  icon: Icons.camera_alt_outlined,
                  onPressed: busy || recording ? null : onTakePhoto,
                  label: '사진',
                  big: true,
                  scale: m.scale,
                ),
                RoundButton(
                  icon: recording ? Icons.stop : Icons.fiber_manual_record,
                  iconColor: Colors.redAccent,
                  onPressed: busy ? null : onToggleRecording,
                  label: recording ? '정지' : '동영상',
                  big: true,
                  scale: m.scale,
                ),
                RoundButton(
                  icon: Icons.center_focus_strong,
                  onPressed: busy || recording ? null : onSnapshot,
                  label: '스냅샷',
                  scale: m.scale,
                ),
                RoundButton(
                  icon: Icons.cameraswitch_outlined,
                  onPressed: busy || recording || !session.canFlip
                      ? null
                      : session.flip,
                  label: '전환',
                  scale: m.scale,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 그리드 상세 설정 바텀시트를 띄운다.
Future<void> showGridSettingsSheet(BuildContext context, GridController grid) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _GridSettingsSheet(grid: grid),
  );
}

class _GridSettingsSheet extends StatelessWidget {
  const _GridSettingsSheet({required this.grid});

  final GridController grid;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '그리드',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final type in GridType.values)
              ListenableBuilder(
                listenable: grid,
                builder: (context, _) => _GridOptionTile(
                  type: type,
                  selected: grid.type == type,
                  onTap: () => grid.select(type),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GridOptionTile extends StatelessWidget {
  const _GridOptionTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final GridType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        type.icon,
        color: selected ? Colors.amber : Colors.white70,
      ),
      title: Text(
        type.label,
        style: TextStyle(
          color: selected ? Colors.amber : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        type.description,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: Colors.amber)
          : null,
      onTap: onTap,
    );
  }
}

/// 도형 가이드 설정 바텀시트를 띄운다.
Future<void> showShapeGuideSheet(
  BuildContext context,
  ShapeGuideController guide,
) {
  return showModalBottomSheet<void>(
    context: context,
    // 프리셋 목록까지 들어가면 길어지므로, 필요 시 화면의 최대 85%까지 늘리고
    // 그 안에서 스크롤되게 한다(작은 폰에서 잘리지 않도록).
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _ShapeGuideSheet(guide: guide),
  );
}

class _ShapeGuideSheet extends StatelessWidget {
  const _ShapeGuideSheet({required this.guide});

  final ShapeGuideController guide;

  Future<void> _saveCurrentAsPreset(BuildContext context) async {
    final name = await _promptPresetName(context);
    if (name == null) return;
    guide.savePreset(name);
  }

  @override
  Widget build(BuildContext context) {
    // 추가/삭제/편집/프리셋이 즉시 반영되도록 시트를 컨트롤러에 구독시킨다.
    return ListenableBuilder(
      listenable: guide,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  '도형 가이드',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '화면에 원·정사각형을 놓고 피사체를 맞춰 촬영하세요. '
                  '평소엔 가이드로만 보이고, 편집 모드에서만 드래그·크기조절이 됩니다.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: guide.addCircle,
                        icon: const Icon(Icons.circle_outlined),
                        label: const Text('원 추가'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: guide.addSquare,
                        icon: const Icon(Icons.crop_square),
                        label: const Text('정사각형 추가'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: guide.editing,
                  onChanged: guide.isEmpty ? null : guide.setEditing,
                  activeThumbColor: Colors.amber,
                  title: const Text(
                    '도형 편집',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    '켜면 도형을 드래그·크기조절·삭제할 수 있습니다. '
                    '끄면 촬영 가이드로만 보입니다.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: guide.isEmpty ? null : guide.clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text('모두 삭제 (${guide.shapes.length}개)'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                ),
                const Divider(color: Colors.white12, height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '배치 저장/불러오기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      guide.isEmpty ? null : () => _saveCurrentAsPreset(context),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('현재 배치 저장'),
                ),
                if (guide.presets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      '저장된 배치가 없습니다. 도형을 원하는 대로 놓고 '
                      '"현재 배치 저장"을 누르세요.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                else
                  ...guide.presets.map(
                    (preset) => _PresetTile(
                      preset: preset,
                      onLoad: () {
                        // 시트를 먼저 닫고 나서 불러온다(닫히는 서브트리 리빌드 방지).
                        Navigator.of(context).pop();
                        guide.loadPreset(preset.id);
                      },
                      onDelete: () => guide.deletePreset(preset.id),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.onLoad,
    required this.onDelete,
  });

  final ShapeGuidePreset preset;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.dashboard_customize_outlined,
          color: Colors.white70),
      title: Text(preset.name, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        '도형 ${preset.shapes.length}개',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.white38),
        tooltip: '배치 삭제',
        onPressed: onDelete,
      ),
      onTap: onLoad,
    );
  }
}

/// 배치 이름을 입력받는다. 취소하거나 빈 이름이면 null.
Future<String?> _promptPresetName(BuildContext context) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => const _PresetNameDialog(),
  );
  final trimmed = result?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// 이름 입력 다이얼로그. TextEditingController 수명을 위젯이 직접 관리한다
/// (다이얼로그 종료 애니메이션 중 컨트롤러를 dispose 하면 assert 로 죽는다).
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: const Text('배치 이름', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: '예: 인물용, 상품 정면',
          hintStyle: TextStyle(color: Colors.white38),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}
