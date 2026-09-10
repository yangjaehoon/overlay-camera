import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../shape_guide.dart';
import '../shape_guide_controller.dart';
import '../ui_metrics.dart';
import 'name_dialog.dart';

/// 화면 짧은 변 기준 도형 지름(px). 위젯 여러 곳에서 같은 공식을 쓰도록 분리.
double shapeGuideDiameter(ShapeGuide s, Size screen) =>
    (s.size * screen.shortestSide).clamp(24.0, screen.shortestSide * 2).toDouble();

/// 사용자가 배치한 원/정사각형 가이드 도형들(선만). 삭제·크기 컨트롤은 [ShapeGuideControls]가
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

/// 편집 모드에서 도형마다 뜨는 조작 컨트롤(오른쪽 위 = 삭제, 오른쪽 아래 = 크기 조절).
/// HUD 패널 위 최상단 레이어에서 그려 도형을 화면 구석으로 밀어도 조작할 수 있다.
/// 편집 모드가 아니거나 도형이 없으면 아무것도 그리지 않는다.
class ShapeGuideControls extends StatelessWidget {
  const ShapeGuideControls({
    super.key,
    required this.guide,
    required this.metrics,
    this.onMessage,
  });

  final ShapeGuideController guide;
  final Metrics metrics;
  final void Function(String message)? onMessage;

  @override
  Widget build(BuildContext context) {
    final screen = metrics.size;
    if (guide.isEmpty || !guide.editing || screen.shortestSide <= 0) {
      return const SizedBox.shrink();
    }
    final p = MediaQuery.paddingOf(context);
    // 컨트롤이 상태바/제스처바 안쪽에 오도록 안전 영역 + 여백만큼 뺀다.
    final safe = EdgeInsets.fromLTRB(
      p.left + 4,
      p.top + 4,
      p.right + 4,
      p.bottom + 4,
    );
    return Stack(
      children: [
        for (final shape in guide.shapes)
          _ShapeControls(
            key: ValueKey(shape.id),
            shape: shape,
            guide: guide,
            screen: screen,
            safe: safe,
            onMessage: onMessage,
          ),
      ],
    );
  }
}

/// 한 도형의 삭제 배지 + 크기 핸들. 안전 영역 안으로 클램프하고, 둘이 겹칠
/// 상황(작은 도형·구석)이면 벌려서 둘 다 누를 수 있게 한다.
class _ShapeControls extends StatelessWidget {
  const _ShapeControls({
    super.key,
    required this.shape,
    required this.guide,
    required this.screen,
    required this.safe,
    this.onMessage,
  });

  final ShapeGuide shape;
  final ShapeGuideController guide;
  final Size screen;
  final EdgeInsets safe;
  final void Function(String message)? onMessage;

  static const _size = 44.0; // 최소 터치 타깃
  static const _gap = 4.0; // 두 컨트롤 사이 최소 간격

  @override
  Widget build(BuildContext context) {
    final d = shapeGuideDiameter(shape, screen);
    final cx = shape.cx * screen.width;
    final cy = shape.cy * screen.height;

    final minX = safe.left;
    final maxX = math.max(minX, screen.width - safe.right - _size);
    final minY = safe.top;
    final maxY = math.max(minY, screen.height - safe.bottom - _size);

    // 이상적 위치: 도형 오른쪽 위 / 오른쪽 아래 모서리 → 화면 안으로 클램프.
    final rightX = (cx + d / 2 - _size / 2).clamp(minX, maxX);
    var delX = rightX;
    var delY = (cy - d / 2 - _size / 2).clamp(minY, maxY);
    var sizeX = rightX;
    var sizeY = (cy + d / 2 - _size / 2).clamp(minY, maxY);

    // 클램프 후 두 컨트롤이 겹치면 떼어놓는다(크기 핸들을 삭제 배지 아래로).
    final need = _size + _gap;
    if ((delX - sizeX).abs() < _size && (delY - sizeY).abs() < need) {
      if (delY + need <= maxY) {
        sizeY = delY + need;
      } else if (sizeY - need >= minY) {
        delY = sizeY - need;
      } else {
        sizeX = math.max(minX, delX - need); // 세로 공간이 없으면 가로로 분리
      }
    }

    return Stack(
      children: [
        Positioned(
          left: delX,
          top: delY,
          child: _DeleteBadge(
            size: _size,
            onTap: () {
              guide.remove(shape.id);
              onMessage?.call('도형을 삭제했습니다.');
            },
          ),
        ),
        Positioned(
          left: sizeX,
          top: sizeY,
          child: _ResizeHandle(
            size: _size,
            shape: shape,
            guide: guide,
            screenSize: screen,
          ),
        ),
      ],
    );
  }
}

/// 도형 오른쪽 아래 모서리의 크기 조절 핸들.
/// 손가락을 중심 바깥쪽으로 밀면 커지고 안쪽으로 당기면 작아진다(중심 고정).
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.size,
    required this.shape,
    required this.guide,
    required this.screenSize,
  });

  final double size;
  final ShapeGuide shape;
  final ShapeGuideController guide;
  final Size screenSize;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset _startFinger = Offset.zero;
  Offset _outward = Offset.zero; // 제스처 시작 시 중심→핸들 방향 단위벡터
  double _startDiameter = 0;
  bool _pressed = false;

  void _onPanStart(DragStartDetails d) {
    final s = widget.shape;
    // 리사이즈는 위치를 바꾸지 않으므로 중심은 고정. 시작 시 한 번만 계산.
    final center = Offset(
      s.cx * widget.screenSize.width,
      s.cy * widget.screenSize.height,
    );
    _startFinger = d.globalPosition;
    final v = _startFinger - center;
    _outward = v / math.max(1.0, v.distance);
    _startDiameter = shapeGuideDiameter(s, widget.screenSize);
    setState(() => _pressed = true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    // 시작 지점 대비 손가락이 "바깥 방향"으로 이동한 성분(부호 있음)을 지름 증감으로
    // 환산한다. 모서리 대각선이라 √2 보정. 절대 위치 기반이라 한계를 넘겼다
    // 되돌려도 갇히지 않고 바로 반응한다.
    final moved = d.globalPosition - _startFinger;
    final proj = moved.dx * _outward.dx + moved.dy * _outward.dy;
    final newDiameter = _startDiameter + proj * 2 / math.sqrt2;
    widget.guide.dragUpdate(
      widget.shape.id,
      pixelDelta: Offset.zero,
      screenSize: widget.screenSize,
      size: newDiameter / widget.screenSize.shortestSide,
    );
  }

  void _finish() {
    widget.guide.commit();
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '크기 조절',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 손을 대자마자 크기가 반응하도록(초기 데드존 제거).
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (_) => _finish(),
        onPanCancel: _finish,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: _pressed ? 30 : 26,
              height: _pressed ? 30 : 26,
              decoration: BoxDecoration(
                color: _pressed ? Colors.black87 : Colors.black54,
                // 원형인 삭제 배지와 구분되도록 둥근 사각형.
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white70, width: 1.5),
              ),
              child: const Icon(
                Icons.open_in_full,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
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
    final name = await promptName(
      context,
      title: '배치 이름',
      hint: '예: 인물용, 상품 정면',
    );
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
                  '화면에 원·정사각형을 놓고 피사체를 맞춰 촬영하세요. 평소엔 '
                  '가이드로만 보이고, 편집 모드에서 도형을 끌어 옮기거나 오른쪽 아래 '
                  '핸들로 크기를 조절합니다.',
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
                // 도형이 있어야 켜고 끌 게 있으므로 그때만 노출한다.
                // (도형 추가 시 편집 모드는 자동으로 켜진다.)
                if (!guide.isEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: guide.editing,
                    onChanged: guide.setEditing,
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
                if (!guide.isEmpty)
                  TextButton.icon(
                    onPressed: guide.clearAll,
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
