import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../camera_session.dart';

/// 시트에 노출하는 해상도 후보(너무 낮은 것·중간 단계는 생략).
const _choices = <ResolutionPreset>[
  ResolutionPreset.medium,
  ResolutionPreset.high,
  ResolutionPreset.veryHigh,
  ResolutionPreset.max,
];

String resolutionLabel(ResolutionPreset p) => switch (p) {
      ResolutionPreset.low => '아주 낮음',
      ResolutionPreset.medium => '낮음',
      ResolutionPreset.high => '표준',
      ResolutionPreset.veryHigh => '높음',
      ResolutionPreset.ultraHigh => '아주 높음',
      ResolutionPreset.max => '최대',
    };

String resolutionDesc(ResolutionPreset p) => switch (p) {
      ResolutionPreset.low => '약 240p',
      ResolutionPreset.medium => '약 480p · 용량이 가장 작음',
      ResolutionPreset.high => '약 720p (기본)',
      ResolutionPreset.veryHigh => '약 1080p',
      ResolutionPreset.ultraHigh => '약 2160p (4K)',
      ResolutionPreset.max => '기기 최고 화질 · 느릴 수 있음',
    };

/// 촬영 화질(해상도) 선택 바텀시트.
Future<void> showResolutionSheet(BuildContext context, CameraSession session) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ResolutionSheet(session: session),
  );
}

class _ResolutionSheet extends StatelessWidget {
  const _ResolutionSheet({required this.session});

  final CameraSession session;

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
                  '촬영 화질',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final preset in _choices)
              ListenableBuilder(
                listenable: session,
                builder: (context, _) {
                  final selected = session.resolutionPreset == preset;
                  return ListTile(
                    enabled: !session.busy,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? Colors.amber : Colors.white54,
                    ),
                    title: Text(
                      resolutionLabel(preset),
                      style: TextStyle(
                        color: selected ? Colors.amber : Colors.white,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      resolutionDesc(preset),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () => session.setResolutionPreset(preset),
                  );
                },
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                '사진·동영상·무음 촬영 모두에 적용됩니다. 바꾸면 프리뷰가 잠깐 끊깁니다.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
