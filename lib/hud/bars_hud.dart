import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../camera_session.dart';
import '../camera_widgets.dart';
import '../grid_controller.dart';
import '../location_stamp_controller.dart';
import '../overlay_controller.dart';
import '../shape_guide_controller.dart';
import '../ui_metrics.dart';

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

IconData timerIcon(int seconds) {
  switch (seconds) {
    case 3:
      return Icons.timer_3;
    case 10:
      return Icons.timer_10;
    default:
      return Icons.timer_off_outlined;
  }
}

/// 셀프타이머 카운트다운. [session.countdown] > 0 일 때 화면 전체에 큰 숫자를
/// 띄우고, 아무 데나 탭하면 [onCancel]로 취소한다.
class CountdownOverlay extends StatelessWidget {
  const CountdownOverlay({
    super.key,
    required this.session,
    required this.onCancel,
  });

  final CameraSession session;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final n = session.countdown;
    if (n <= 0) return const SizedBox.shrink();
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCancel,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey(n),
                  tween: Tween(begin: 1.35, end: 1.0),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 120,
                      fontWeight: FontWeight.w300,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '탭하면 취소',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
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
    required this.onOpenQualitySettings,
  });

  final CameraSession session;
  final LocationStampController stamp;
  final OverlayController overlay;
  final GridController grid;
  final ShapeGuideController shapeGuide;
  final Metrics metrics;
  final VoidCallback onOpenGridSettings;
  final VoidCallback onOpenShapeGuideSettings;
  final VoidCallback onOpenQualitySettings;

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
                  icon: timerIcon(session.timerSeconds),
                  color: session.timerSeconds == 0
                      ? Colors.white
                      : Colors.amber,
                  size: btn,
                  iconSize: icon,
                  tooltip: '셀프타이머',
                  onTap: session.cycleTimer,
                ),
                BarButton(
                  icon: Icons.hd_outlined,
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '촬영 화질',
                  onTap: onOpenQualitySettings,
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
                // 색만 isEmpty 에 의존하므로 구조 변경 채널만 구독한다
                // (도형 드래그 중 잦은 리빌드 방지).
                ListenableBuilder(
                  listenable: shapeGuide.structure,
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
                  // 길게 누르면 후면 물리 렌즈(초광각·망원 등) 순환.
                  onLongPress: busy || recording || !session.hasMultipleBackLenses
                      ? null
                      : session.cycleBackLens,
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
