import 'package:flutter/material.dart';

/// 이름 붙여 저장하는 프리셋(오버레이, 도형 가이드 배치 등) 바텀시트가
/// 공통으로 쓰는 뼈대: 드래그 핸들 + 제목/설명 + (선택) 추가 컨트롤 +
/// 저장 버튼 + 프리셋 목록(비어 있으면 안내 문구).
class PresetSheetScaffold extends StatelessWidget {
  const PresetSheetScaffold({
    super.key,
    required this.listenable,
    required this.title,
    required this.description,
    this.extraContent,
    required this.saveLabel,
    required this.onSave,
    required this.emptyStateText,
    required this.presetTiles,
  });

  /// 시트 전체를 리빌드할 대상. 추가·삭제·불러오기 등 구조 변경 채널을 준다.
  final Listenable listenable;
  final String title;
  final String description;

  /// 저장 버튼 앞에 끼워 넣는 추가 컨트롤(예: 도형 추가 버튼, 편집 모드 스위치).
  final Widget? extraContent;

  final String saveLabel;
  final VoidCallback? onSave;
  final String emptyStateText;
  final List<Widget> presetTiles;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
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
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (extraContent case final extra?) ...[
                  const SizedBox(height: 16),
                  extra,
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(saveLabel),
                ),
                if (presetTiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      emptyStateText,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                else
                  ...presetTiles,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 프리셋 목록 한 줄. 대표 이미지/아이콘([leading])과 이름, 선택적 부가 설명,
/// 삭제 버튼으로 구성된다. 탭하면 불러오고, 오른쪽 아이콘을 누르면 지운다.
class PresetTile extends StatelessWidget {
  const PresetTile({
    super.key,
    required this.leading,
    required this.name,
    this.subtitle,
    required this.onLoad,
    required this.onDelete,
    required this.deleteTooltip,
  });

  final Widget leading;
  final String name;
  final Widget? subtitle;
  final VoidCallback onLoad;
  final VoidCallback onDelete;
  final String deleteTooltip;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: leading,
      title: Text(name, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.white38),
        tooltip: deleteTooltip,
        onPressed: onDelete,
      ),
      onTap: onLoad,
    );
  }
}
