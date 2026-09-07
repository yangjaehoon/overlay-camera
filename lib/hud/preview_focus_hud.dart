import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../camera_session.dart';

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

/// 화면 탭 지점(정규화 0~1)을 프리뷰 cover-crop을 역보정해 프리뷰(센서) 정규화
/// 좌표로 바꾼다. [CameraPreviewArea]가 프리뷰를 화면에 꽉 차게 확대(중앙 크롭)하므로
/// 그대로 넘기면 가장자리로 갈수록 초점 지점이 어긋난다.
Offset previewFocusPoint(
  Offset screenNorm,
  Size screen,
  double controllerAspect,
) {
  final raw = screen.aspectRatio * controllerAspect;
  if (!raw.isFinite || raw <= 0) return screenNorm;
  final scale = raw < 1 ? 1 / raw : raw; // 프리뷰에 적용된 확대 배율
  final visible = 1 / scale; // 잘리는 축에서 화면에 보이는 비율
  final start = (1 - visible) / 2;
  final x = raw < 1 ? start + screenNorm.dx * visible : screenNorm.dx;
  final y = raw < 1 ? screenNorm.dy : start + screenNorm.dy * visible;
  return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
}

/// 프리뷰를 탭하면 그 지점에 초점·노출을 맞추고, 길게 누르면 AE/AF를 고정한다.
/// 고정 상태에서 탭하면 고정이 풀리고 그 지점 연속 자동으로 돌아간다.
/// translucent + 탭/롱프레스만 처리해 드래그는 아래 레이어(오버레이·도형)로 넘긴다.
class FocusLayer extends StatefulWidget {
  const FocusLayer({super.key, required this.session});

  final CameraSession session;

  @override
  State<FocusLayer> createState() => _FocusLayerState();
}

class _FocusLayerState extends State<FocusLayer>
    with SingleTickerProviderStateMixin {
  static const _reticleSize = 84.0;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Listenable _repaint = Listenable.merge([_anim, widget.session]);
  Offset? _pos; // 마지막 조준 지점(화면 좌표)

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _focus(Offset local, Size size, {required bool lock}) {
    final session = widget.session;
    if (!session.isReady) return;
    final screenNorm = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    final aspect = session.controller?.value.aspectRatio ?? 1.0;
    unawaited(session.focusAt(
      previewFocusPoint(screenNorm, size, aspect),
      lock: lock,
    ));
    setState(() => _pos = local);
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              gestures: {
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (r) => r.onTapUp =
                      (d) => _focus(d.localPosition, size, lock: false),
                ),
                LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer>(
                  // 오버레이/도형을 "눌렀다 끌기"와 헷갈리지 않도록 살짝 길게.
                  () => LongPressGestureRecognizer(
                    duration: const Duration(milliseconds: 650),
                  ),
                  (r) => r.onLongPressStart =
                      (d) => _focus(d.localPosition, size, lock: true),
                ),
              },
            ),
          ),
          AnimatedBuilder(
            animation: _repaint,
            builder: (context, _) {
              final pos = _pos;
              final locked = widget.session.aeAfLocked;
              // 조준 사각형: 고정이면 계속, 아니면 잠깐 보였다 사라진다.
              // 카메라가 준비 안 된 동안(전환·재초기화)엔 숨긴다.
              if (pos == null ||
                  !widget.session.isReady ||
                  (!locked && _anim.isCompleted)) {
                return const SizedBox.shrink();
              }
              final maxLeft =
                  math.max(4.0, size.width - _reticleSize - 4);
              final maxTop = math.max(
                pad.top + 4,
                size.height - _reticleSize - (locked ? 40.0 : 4.0),
              );
              return Positioned(
                left: (pos.dx - _reticleSize / 2).clamp(4.0, maxLeft),
                top: (pos.dy - _reticleSize / 2).clamp(pad.top + 4, maxTop),
                child: IgnorePointer(
                  child: _FocusReticle(
                    size: _reticleSize,
                    t: _anim.value,
                    locked: locked,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FocusReticle extends StatelessWidget {
  const _FocusReticle({
    required this.size,
    required this.t,
    required this.locked,
  });

  final double size;
  final double t; // 애니메이션 진행 0~1
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final ease = Curves.easeOut.transform(t.clamp(0.0, 1.0));
    final scale = locked ? 1.0 : 1.0 + 0.3 * (1 - ease);
    final opacity =
        locked ? 1.0 : (t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3)).clamp(0.0, 1.0);
    final color = locked ? Colors.amber : Colors.white;
    return Opacity(
      opacity: opacity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: scale,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2),
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 4),
                ],
              ),
            ),
          ),
          if (locked) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'AE/AF 잠금',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
