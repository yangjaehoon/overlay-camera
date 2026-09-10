import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 사용자가 이름을 붙여 저장한 오버레이(고스트) 설정.
/// 참조 이미지는 앱 문서 폴더의 [imagePath] 에 사본으로 보관하고,
/// 위치·크기·회전·투명도·반전 상태를 함께 저장해 통째로 복원한다.
///
/// [dx]/[dy] 는 OverlayController._offset 과 같은 화면 픽셀 단위다(같은 기기
/// 재사용을 전제). 화면 크기가 크게 달라지면 위치가 어긋날 수 있다.
class OverlayPreset {
  const OverlayPreset({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.opacity,
    required this.dx,
    required this.dy,
    required this.scale,
    required this.rotation,
    required this.mirrored,
    required this.inverted,
  });

  final String id;
  final String name;
  final String imagePath;
  final double opacity;

  /// 화면 픽셀 단위 이동량(OverlayController._offset 과 동일).
  final double dx;
  final double dy;
  final double scale;
  final double rotation;
  final bool mirrored;
  final bool inverted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'opacity': opacity,
        'dx': dx,
        'dy': dy,
        'scale': scale,
        'rotation': rotation,
        'mirrored': mirrored,
        'inverted': inverted,
      };

  /// 손상된 프리셋이면 null(전체 목록을 날리지 않기 위해).
  static OverlayPreset? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final imagePath = json['imagePath'];
    if (id is! String || name is! String || imagePath is! String) return null;
    double num_(Object? v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    bool bool_(Object? v) => v is bool && v;
    return OverlayPreset(
      id: id,
      name: name,
      imagePath: imagePath,
      opacity: num_(json['opacity'], 0.45).clamp(0.0, 1.0).toDouble(),
      dx: num_(json['dx'], 0),
      dy: num_(json['dy'], 0),
      scale: num_(json['scale'], 1.0),
      rotation: num_(json['rotation'], 0),
      mirrored: bool_(json['mirrored']),
      inverted: bool_(json['inverted']),
    );
  }
}

String encodeOverlayPresets(List<OverlayPreset> presets) =>
    jsonEncode(presets.map((p) => p.toJson()).toList());

List<OverlayPreset> decodeOverlayPresets(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OverlayPreset.tryFromJson)
        .whereType<OverlayPreset>()
        .toList();
  } catch (e) {
    debugPrint('오버레이 프리셋 복원 실패: $e');
    return const [];
  }
}
