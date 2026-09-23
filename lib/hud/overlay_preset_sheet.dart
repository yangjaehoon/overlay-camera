import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../overlay_controller.dart';
import 'app_bottom_sheet.dart';
import 'name_dialog.dart';
import 'preset_sheet.dart';

/// 오버레이(고스트) 프리셋 저장/불러오기 바텀시트.
Future<void> showOverlayPresetSheet(
  BuildContext context,
  OverlayController overlay,
) {
  return showAppBottomSheet<void>(
    context,
    scrollable: true,
    builder: (_) => _OverlayPresetSheet(overlay: overlay),
  );
}

class _OverlayPresetSheet extends StatelessWidget {
  const _OverlayPresetSheet({required this.overlay});

  final OverlayController overlay;

  static const _thumbSize = 44.0;

  Future<void> _saveCurrent(BuildContext context) async {
    final name = await promptName(
      context,
      title: '프리셋 이름',
      hint: '예: 정면 상반신, 창가 포즈',
    );
    if (name == null) return;
    await overlay.savePreset(name);
  }

  Widget _thumbnail(BuildContext context, String imagePath) {
    // 원본 해상도 그대로 디코드하지 않도록 화면 밀도에 맞는 픽셀 크기로 캐시한다.
    // (갤러리 원본 사진을 저장한 프리셋이 많으면 안 그러면 메모리 부담이 크다.)
    final px = (_thumbSize * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(imagePath),
        width: _thumbSize,
        height: _thumbSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: px,
        cacheHeight: px,
        errorBuilder: (_, _, _) => Container(
          width: _thumbSize,
          height: _thumbSize,
          color: Colors.white12,
          child: const Icon(
            Icons.broken_image_outlined,
            color: Colors.white38,
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PresetSheetScaffold(
      listenable: overlay.structure,
      title: '오버레이 프리셋',
      description:
          '지금 겹쳐 놓은 참조 사진과 위치·크기·회전·투명도·반전을 '
          '한 세트로 저장해 두고 나중에 통째로 불러옵니다.',
      saveLabel: overlay.hasFile ? '현재 오버레이 저장' : '먼저 오버레이를 불러오세요',
      onSave: overlay.hasFile ? () => _saveCurrent(context) : null,
      emptyStateText: '저장된 프리셋이 없습니다.',
      presetTiles: [
        for (final preset in overlay.presets)
          PresetTile(
            key: ValueKey(preset.id),
            leading: _thumbnail(context, preset.imagePath),
            name: preset.name,
            deleteTooltip: '프리셋 삭제',
            onLoad: () {
              // 시트를 먼저 닫고 불러온다(닫히는 서브트리 리빌드 방지).
              Navigator.of(context).pop();
              unawaited(overlay.loadPreset(preset.id));
            },
            onDelete: () => unawaited(overlay.deletePreset(preset.id)),
          ),
      ],
    );
  }
}
