import 'package:flutter/material.dart';

import '../camera_widgets.dart';
import '../grid_controller.dart';
import '../level_controller.dart';
import '../location_stamp_controller.dart';
import '../photo_stamp.dart';
import '../ui_metrics.dart';

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

/// 그리드·수평계 설정 바텀시트를 띄운다.
Future<void> showGridSettingsSheet(
  BuildContext context,
  GridController grid,
  LevelController level,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _GridSettingsSheet(grid: grid, level: level),
  );
}

class _GridSettingsSheet extends StatelessWidget {
  const _GridSettingsSheet({required this.grid, required this.level});

  final GridController grid;
  final LevelController level;

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
            const Divider(color: Colors.white12, height: 20),
            ListenableBuilder(
              listenable: level,
              builder: (context, _) => SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20),
                value: level.enabled,
                onChanged: (_) => level.toggle(),
                activeThumbColor: Colors.amber,
                secondary: Icon(
                  Icons.straighten,
                  color: level.enabled ? Colors.amber : Colors.white70,
                ),
                title: const Text(
                  '수평 보조선',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  '화면 가운데 수평선. 기울면 흰색, 수평이면 노란 한 줄.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
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
