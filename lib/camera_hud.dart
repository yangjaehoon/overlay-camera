import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_session.dart';
import 'camera_widgets.dart';
import 'location_stamp_controller.dart';
import 'overlay_controller.dart';
import 'photo_stamp.dart';
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
    final file = overlay.file;
    if (file == null) return const SizedBox.shrink();

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
  const GridOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: GridPainter(), size: Size.infinite),
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
    required this.metrics,
  });

  final CameraSession session;
  final LocationStampController stamp;
  final OverlayController overlay;
  final Metrics metrics;

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
            ],
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
