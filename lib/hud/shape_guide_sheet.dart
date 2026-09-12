import 'package:flutter/material.dart';

import '../shape_guide_controller.dart';
import 'app_bottom_sheet.dart';
import 'name_dialog.dart';
import 'preset_sheet.dart';

/// 도형 가이드 설정 바텀시트를 띄운다.
Future<void> showShapeGuideSheet(
  BuildContext context,
  ShapeGuideController guide,
) {
  // 프리셋 목록까지 들어가면 길어지므로, 필요 시 화면의 최대 85%까지 늘리고
  // 그 안에서 스크롤되게 한다(작은 폰에서 잘리지 않도록).
  return showAppBottomSheet<void>(
    context,
    scrollable: true,
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
    return PresetSheetScaffold(
      listenable: guide,
      title: '도형 가이드',
      description: '화면에 원·정사각형을 놓고 피사체를 맞춰 촬영하세요. 평소엔 '
          '가이드로만 보이고, 편집 모드에서 도형을 끌어 옮기거나 오른쪽 아래 '
          '핸들로 크기를 조절합니다.',
      extraContent: _ShapePresetControls(guide: guide),
      saveLabel: '현재 배치 저장',
      onSave: guide.isEmpty ? null : () => _saveCurrentAsPreset(context),
      emptyStateText: '저장된 배치가 없습니다. 도형을 원하는 대로 놓고 '
          '"현재 배치 저장"을 누르세요.',
      presetTiles: [
        for (final preset in guide.presets)
          PresetTile(
            key: ValueKey(preset.id),
            leading: const Icon(Icons.dashboard_customize_outlined,
                color: Colors.white70),
            name: preset.name,
            subtitle: Text(
              '도형 ${preset.shapes.length}개',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            deleteTooltip: '배치 삭제',
            onLoad: () {
              // 시트를 먼저 닫고 나서 불러온다(닫히는 서브트리 리빌드 방지).
              Navigator.of(context).pop();
              guide.loadPreset(preset.id);
            },
            onDelete: () => guide.deletePreset(preset.id),
          ),
      ],
    );
  }
}

/// 도형 추가·편집 모드·전체 삭제 컨트롤 + "배치 저장/불러오기" 구간 제목.
/// 저장 버튼 자체는 [PresetSheetScaffold]가 공통으로 그린다.
class _ShapePresetControls extends StatelessWidget {
  const _ShapePresetControls({required this.guide});

  final ShapeGuideController guide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            title: const Text('도형 편집', style: TextStyle(color: Colors.white)),
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
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
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
      ],
    );
  }
}
