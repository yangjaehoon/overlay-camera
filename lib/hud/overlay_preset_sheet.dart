import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../overlay_controller.dart';
import 'name_dialog.dart';

/// 오버레이(고스트) 프리셋 저장/불러오기 바텀시트.
Future<void> showOverlayPresetSheet(
  BuildContext context,
  OverlayController overlay,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _OverlayPresetSheet(overlay: overlay),
  );
}

class _OverlayPresetSheet extends StatelessWidget {
  const _OverlayPresetSheet({required this.overlay});

  final OverlayController overlay;

  Future<void> _saveCurrent(BuildContext context) async {
    final name = await promptName(
      context,
      title: '프리셋 이름',
      hint: '예: 정면 상반신, 창가 포즈',
    );
    if (name == null) return;
    await overlay.savePreset(name);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: overlay.structure,
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
                  '오버레이 프리셋',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '지금 겹쳐 놓은 참조 사진과 위치·크기·회전·투명도·반전을 '
                  '한 세트로 저장해 두고 나중에 통째로 불러옵니다.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed:
                      overlay.hasFile ? () => _saveCurrent(context) : null,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(
                    overlay.hasFile ? '현재 오버레이 저장' : '먼저 오버레이를 불러오세요',
                  ),
                ),
                if (overlay.presets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      '저장된 프리셋이 없습니다.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                else
                  ...overlay.presets.map(
                    (preset) => _PresetTile(
                      key: ValueKey(preset.id),
                      name: preset.name,
                      imagePath: preset.imagePath,
                      onLoad: () {
                        // 시트를 먼저 닫고 불러온다(닫히는 서브트리 리빌드 방지).
                        Navigator.of(context).pop();
                        unawaited(overlay.loadPreset(preset.id));
                      },
                      onDelete: () => unawaited(overlay.deletePreset(preset.id)),
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
    super.key,
    required this.name,
    required this.imagePath,
    required this.onLoad,
    required this.onDelete,
  });

  final String name;
  final String imagePath;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  static const _thumbSize = 44.0;

  @override
  Widget build(BuildContext context) {
    // 원본 해상도 그대로 디코드하지 않도록 화면 밀도에 맞는 픽셀 크기로 캐시한다.
    // (갤러리 원본 사진을 저장한 프리셋이 많으면 안 그러면 메모리 부담이 크다.)
    final px = (_thumbSize * MediaQuery.devicePixelRatioOf(context)).round();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: ClipRRect(
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
            child: const Icon(Icons.broken_image_outlined,
                color: Colors.white38, size: 20),
          ),
        ),
      ),
      title: Text(name, style: const TextStyle(color: Colors.white)),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.white38),
        tooltip: '프리셋 삭제',
        onPressed: onDelete,
      ),
      onTap: onLoad,
    );
  }
}
