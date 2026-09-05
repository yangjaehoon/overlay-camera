import 'dart:convert';

/// 화면에 배치하는 정합용 가이드 도형의 모양.
enum ShapeGuideType { circle, square }

extension ShapeGuideTypeX on ShapeGuideType {
  String get label => switch (this) {
        ShapeGuideType.circle => '원',
        ShapeGuideType.square => '정사각형',
      };
}

/// 화면 위에 사용자가 직접 배치하는 가이드 도형 하나.
/// 기기 회전이나 화면 크기가 달라져도 같은 상대 위치를 유지하도록
/// 좌표·크기를 절대 픽셀이 아닌 화면 비율(0~1)로 저장한다.
class ShapeGuide {
  const ShapeGuide({
    required this.id,
    required this.type,
    required this.cx,
    required this.cy,
    required this.size,
  });

  /// 생성 시각 기반 고유 id.
  final String id;
  final ShapeGuideType type;

  /// 중심 좌표. 화면 너비/높이에 대한 비율(0~1).
  final double cx;
  final double cy;

  /// 지름(원)/한 변(정사각형). 화면 짧은 변에 대한 비율.
  final double size;

  ShapeGuide copyWith({double? cx, double? cy, double? size}) => ShapeGuide(
        id: id,
        type: type,
        cx: cx ?? this.cx,
        cy: cy ?? this.cy,
        size: size ?? this.size,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type.name, 'cx': cx, 'cy': cy, 'size': size};

  /// 손상된 항목이면 null을 돌려준다(전체 목록을 날리지 않기 위해).
  static ShapeGuide? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final typeName = json['type'];
    final cx = json['cx'];
    final cy = json['cy'];
    final size = json['size'];
    if (id is! String ||
        typeName is! String ||
        cx is! num ||
        cy is! num ||
        size is! num) {
      return null;
    }
    ShapeGuideType? type;
    for (final t in ShapeGuideType.values) {
      if (t.name == typeName) {
        type = t;
        break;
      }
    }
    if (type == null) return null;
    return ShapeGuide(
      id: id,
      type: type,
      cx: cx.toDouble(),
      cy: cy.toDouble(),
      size: size.toDouble(),
    );
  }
}

/// 도형 목록을 저장용 JSON 문자열로 직렬화한다.
String encodeShapeGuides(List<ShapeGuide> shapes) =>
    jsonEncode(shapes.map((s) => s.toJson()).toList());

/// 저장된 JSON 문자열을 도형 목록으로 복원한다. 손상되었거나 없으면 빈 목록.
List<ShapeGuide> decodeShapeGuides(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ShapeGuide.tryFromJson)
        .whereType<ShapeGuide>()
        .toList();
  } catch (_) {
    return const [];
  }
}

/// 사용자가 이름을 붙여 저장한 도형 배치. 나중에 통째로 불러온다.
class ShapeGuidePreset {
  const ShapeGuidePreset({
    required this.id,
    required this.name,
    required this.shapes,
  });

  final String id;
  final String name;
  final List<ShapeGuide> shapes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shapes': shapes.map((s) => s.toJson()).toList(),
      };

  /// 손상된 프리셋이면 null. 도형 일부가 손상됐으면 그 도형만 걸러낸다.
  static ShapeGuidePreset? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final rawShapes = json['shapes'];
    if (id is! String || name is! String || rawShapes is! List) return null;
    final shapes = rawShapes
        .whereType<Map<String, dynamic>>()
        .map(ShapeGuide.tryFromJson)
        .whereType<ShapeGuide>()
        .toList();
    return ShapeGuidePreset(id: id, name: name, shapes: shapes);
  }
}

/// 프리셋 목록을 저장용 JSON 문자열로 직렬화한다.
String encodeShapeGuidePresets(List<ShapeGuidePreset> presets) =>
    jsonEncode(presets.map((p) => p.toJson()).toList());

/// 저장된 JSON 문자열을 프리셋 목록으로 복원한다. 손상되었거나 없으면 빈 목록.
List<ShapeGuidePreset> decodeShapeGuidePresets(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ShapeGuidePreset.tryFromJson)
        .whereType<ShapeGuidePreset>()
        .toList();
  } catch (_) {
    return const [];
  }
}
