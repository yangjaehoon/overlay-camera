import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/shape_guide.dart';

void main() {
  test('encode → decode 라운드트립으로 도형 목록이 그대로 복원된다', () {
    final shapes = [
      const ShapeGuide(
        id: 'a',
        type: ShapeGuideType.circle,
        cx: 0.5,
        cy: 0.45,
        size: 0.35,
      ),
      const ShapeGuide(
        id: 'b',
        type: ShapeGuideType.square,
        cx: 0.2,
        cy: 0.8,
        size: 0.6,
      ),
    ];

    final restored = decodeShapeGuides(encodeShapeGuides(shapes));
    expect(restored.length, 2);
    expect(restored[0].id, 'a');
    expect(restored[0].type, ShapeGuideType.circle);
    expect(restored[0].cx, 0.5);
    expect(restored[1].id, 'b');
    expect(restored[1].type, ShapeGuideType.square);
    expect(restored[1].size, 0.6);
  });

  test('빈 문자열/null은 빈 목록', () {
    expect(decodeShapeGuides(null), isEmpty);
    expect(decodeShapeGuides(''), isEmpty);
    expect(decodeShapeGuides('[]'), isEmpty);
  });

  test('깨진 JSON은 빈 목록으로 폴백', () {
    expect(decodeShapeGuides('{not json'), isEmpty);
    expect(decodeShapeGuides('"a string"'), isEmpty);
    expect(decodeShapeGuides('42'), isEmpty);
  });

  test('손상된 항목만 걸러내고 정상 항목은 유지한다', () {
    const raw = '['
        '{"id":"ok","type":"circle","cx":0.5,"cy":0.5,"size":0.3},'
        '{"id":"badtype","type":"triangle","cx":0.5,"cy":0.5,"size":0.3},'
        '{"id":"missing","type":"square"},'
        '{"type":"circle","cx":0.1,"cy":0.1,"size":0.1},'
        '{"id":"badnum","type":"square","cx":"x","cy":0.5,"size":0.3}'
        ']';
    final restored = decodeShapeGuides(raw);
    expect(restored.length, 1);
    expect(restored.single.id, 'ok');
  });

  test('copyWith는 지정한 값만 바꾼다', () {
    const s = ShapeGuide(
      id: 'a',
      type: ShapeGuideType.circle,
      cx: 0.5,
      cy: 0.5,
      size: 0.3,
    );
    final moved = s.copyWith(cx: 0.7);
    expect(moved.id, 'a');
    expect(moved.type, ShapeGuideType.circle);
    expect(moved.cx, 0.7);
    expect(moved.cy, 0.5);
    expect(moved.size, 0.3);
  });

  group('ShapeGuidePreset', () {
    const presets = [
      ShapeGuidePreset(
        id: 'p1',
        name: '인물용',
        shapes: [
          ShapeGuide(
            id: 's1',
            type: ShapeGuideType.circle,
            cx: 0.5,
            cy: 0.35,
            size: 0.4,
          ),
        ],
      ),
      ShapeGuidePreset(id: 'p2', name: '빈 배치', shapes: []),
    ];

    test('encode → decode 라운드트립', () {
      final restored =
          decodeShapeGuidePresets(encodeShapeGuidePresets(presets));
      expect(restored.length, 2);
      expect(restored[0].id, 'p1');
      expect(restored[0].name, '인물용');
      expect(restored[0].shapes.single.type, ShapeGuideType.circle);
      expect(restored[0].shapes.single.cy, 0.35);
      expect(restored[1].name, '빈 배치');
      expect(restored[1].shapes, isEmpty);
    });

    test('빈 문자열/null/깨진 JSON은 빈 목록', () {
      expect(decodeShapeGuidePresets(null), isEmpty);
      expect(decodeShapeGuidePresets(''), isEmpty);
      expect(decodeShapeGuidePresets('[]'), isEmpty);
      expect(decodeShapeGuidePresets('{oops'), isEmpty);
    });

    test('손상된 프리셋은 걸러내고, 프리셋 안의 손상된 도형만 제거한다', () {
      const raw = '['
          '{"id":"ok","name":"정상","shapes":['
          '{"id":"a","type":"circle","cx":0.5,"cy":0.5,"size":0.3},'
          '{"id":"bad","type":"circle","cx":"x","cy":0.5,"size":0.3}'
          ']},'
          '{"id":"noname","shapes":[]},'
          '{"name":"noid","shapes":[]}'
          ']';
      final restored = decodeShapeGuidePresets(raw);
      expect(restored.length, 1);
      expect(restored.single.id, 'ok');
      expect(restored.single.shapes.length, 1);
      expect(restored.single.shapes.single.id, 'a');
    });
  });
}
