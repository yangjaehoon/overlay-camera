import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/overlay_preset.dart';

void main() {
  OverlayPreset sample() => const OverlayPreset(
        id: 'p1',
        name: '정면 상반신',
        imagePath: '/docs/overlay_presets/p1.png',
        opacity: 0.6,
        dx: 12.5,
        dy: -8.0,
        scale: 1.4,
        rotation: 0.2,
        mirrored: true,
        inverted: false,
      );

  test('toJson -> tryFromJson 왕복', () {
    final back = OverlayPreset.tryFromJson(sample().toJson())!;
    expect(back.id, 'p1');
    expect(back.name, '정면 상반신');
    expect(back.imagePath, '/docs/overlay_presets/p1.png');
    expect(back.opacity, 0.6);
    expect(back.dx, 12.5);
    expect(back.dy, -8.0);
    expect(back.scale, 1.4);
    expect(back.rotation, 0.2);
    expect(back.mirrored, true);
    expect(back.inverted, false);
  });

  test('encode -> decode 왕복', () {
    final list = [sample()];
    final decoded = decodeOverlayPresets(encodeOverlayPresets(list));
    expect(decoded, hasLength(1));
    expect(decoded.single.name, '정면 상반신');
  });

  test('필수 필드 없으면 null', () {
    expect(OverlayPreset.tryFromJson({'name': 'x', 'imagePath': 'y'}), isNull);
    expect(OverlayPreset.tryFromJson({'id': 'x', 'imagePath': 'y'}), isNull);
    expect(OverlayPreset.tryFromJson({'id': 'x', 'name': 'y'}), isNull);
  });

  test('숫자/불리언 필드 손상 시 기본값으로', () {
    final p = OverlayPreset.tryFromJson({
      'id': 'x',
      'name': 'y',
      'imagePath': 'z',
      'opacity': 'nope',
      'scale': null,
      'mirrored': 'true', // 문자열은 false 취급
    })!;
    expect(p.opacity, 0.45);
    expect(p.scale, 1.0);
    expect(p.dx, 0);
    expect(p.mirrored, false);
    expect(p.inverted, false);
  });

  test('opacity 는 0..1 로 클램프', () {
    final p = OverlayPreset.tryFromJson({
      'id': 'x',
      'name': 'y',
      'imagePath': 'z',
      'opacity': 5.0,
    })!;
    expect(p.opacity, 1.0);
  });

  test('손상된 JSON 문자열은 빈 목록', () {
    expect(decodeOverlayPresets('not json'), isEmpty);
    expect(decodeOverlayPresets('{"a":1}'), isEmpty); // List 가 아님
    expect(decodeOverlayPresets(null), isEmpty);
  });
}
