import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/settings_store.dart';
import 'package:ghost_camera/shape_guide.dart';
import 'package:ghost_camera/shape_guide_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const screen = Size(400, 800);

  test('addCircle / addSquare 는 도형을 추가하고 알림', () {
    final c = ShapeGuideController();
    var notified = 0;
    c.addListener(() => notified++);

    expect(c.isEmpty, true);
    c.addCircle();
    c.addSquare();
    expect(c.shapes.length, 2);
    expect(c.shapes[0].type, ShapeGuideType.circle);
    expect(c.shapes[1].type, ShapeGuideType.square);
    expect(notified, greaterThanOrEqualTo(2));

    c.dispose();
  });

  test('remove 는 해당 도형만 지우고, 없는 id는 무시', () {
    final c = ShapeGuideController();
    c.addCircle();
    c.addSquare();
    final firstId = c.shapes.first.id;

    c.remove('없는id');
    expect(c.shapes.length, 2);

    c.remove(firstId);
    expect(c.shapes.length, 1);
    expect(c.shapes.single.type, ShapeGuideType.square);

    c.dispose();
  });

  test('clearAll 은 전부 비우고, 이미 비었으면 아무 것도 안 함', () {
    final c = ShapeGuideController();
    var notified = 0;
    c.addListener(() => notified++);

    c.clearAll();
    expect(notified, 0); // 비어 있으면 알림 없음

    c.addCircle();
    c.clearAll();
    expect(c.isEmpty, true);

    c.dispose();
  });

  test('move 는 픽셀 델타를 화면 비율로 환산해 누적한다', () {
    final c = ShapeGuideController();
    c.addCircle();
    final id = c.shapes.single.id;
    expect(c.shapes.single.cx, 0.5);
    expect(c.shapes.single.cy, 0.45);

    c.move(id, const Offset(40, 80), screen); // +0.1, +0.1
    expect(c.shapes.single.cx, closeTo(0.6, 1e-9));
    expect(c.shapes.single.cy, closeTo(0.55, 1e-9));

    c.dispose();
  });

  test('move 는 화면 밖으로 나가지 않도록 가장자리에서 클램프된다', () {
    final c = ShapeGuideController();
    c.addCircle();
    final id = c.shapes.single.id;

    c.move(id, const Offset(9999, 9999), screen);
    expect(c.shapes.single.cx, lessThanOrEqualTo(0.98));
    expect(c.shapes.single.cy, lessThanOrEqualTo(0.98));

    c.move(id, const Offset(-9999, -9999), screen);
    expect(c.shapes.single.cx, greaterThanOrEqualTo(0.02));
    expect(c.shapes.single.cy, greaterThanOrEqualTo(0.02));

    c.dispose();
  });

  test('resize 는 크기를 0.06~1.8 로 클램프한다', () {
    final c = ShapeGuideController();
    c.addSquare();
    final id = c.shapes.single.id;

    c.resize(id, 99);
    expect(c.shapes.single.size, 1.8);

    c.resize(id, 0.0001);
    expect(c.shapes.single.size, 0.06);

    c.dispose();
  });

  test('toggleLock 은 잠금 상태를 뒤집는다', () {
    final c = ShapeGuideController();
    expect(c.locked, false);
    c.toggleLock();
    expect(c.locked, true);
    c.dispose();
  });

  test('설정 저장소에 도형과 잠금이 영속화되고 hydrate 로 복원된다', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsStore.load();

    final a = ShapeGuideController()..settings = s;
    a.addCircle();
    a.addSquare();
    a.move(a.shapes.first.id, const Offset(20, 40), screen);
    a.commit();
    a.toggleLock();
    final expectedCount = a.shapes.length;
    final expectedCx = a.shapes.first.cx;

    final again = await SettingsStore.load();
    final b = ShapeGuideController()..hydrate(again);
    expect(b.shapes.length, expectedCount);
    expect(b.locked, true);
    expect(b.shapes.first.cx, closeTo(expectedCx, 1e-9));

    a.dispose();
    b.dispose();
  });

  test('move/resize 도중에는 저장하지 않고 commit 시 저장한다', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsStore.load();
    final a = ShapeGuideController()..settings = s;
    a.addCircle(); // add 는 즉시 저장됨
    final id = a.shapes.single.id;

    a.move(id, const Offset(40, 0), screen); // 저장 안 함
    var mid = ShapeGuideController()..hydrate(await SettingsStore.load());
    expect(mid.shapes.single.cx, 0.5); // 아직 이동 전 값

    a.commit();
    mid = ShapeGuideController()..hydrate(await SettingsStore.load());
    expect(mid.shapes.single.cx, closeTo(0.6, 1e-9));

    a.dispose();
    mid.dispose();
  });

  group('배치 저장/불러오기', () {
    test('savePreset 은 현재 배치를 이름과 함께 저장한다', () {
      final c = ShapeGuideController();
      c.addCircle();
      c.addSquare();

      c.savePreset('  인물용  '); // 앞뒤 공백은 다듬어진다
      expect(c.presets.length, 1);
      expect(c.presets.single.name, '인물용');
      expect(c.presets.single.shapes.length, 2);

      c.dispose();
    });

    test('빈 이름은 저장하지 않는다', () {
      final c = ShapeGuideController();
      c.addCircle();
      c.savePreset('   ');
      expect(c.presets, isEmpty);
      c.dispose();
    });

    test('저장한 프리셋은 현재 도형이 바뀌어도 그대로 유지된다', () {
      final c = ShapeGuideController();
      c.addCircle();
      c.savePreset('A');

      c.clearAll();
      c.addSquare();
      c.addSquare();

      expect(c.presets.single.shapes.length, 1);
      expect(c.presets.single.shapes.single.type, ShapeGuideType.circle);

      c.dispose();
    });

    test('loadPreset 은 현재 도형을 프리셋 내용으로 교체한다', () {
      final c = ShapeGuideController();
      c.addCircle();
      c.move(c.shapes.single.id, const Offset(40, 40), screen);
      c.savePreset('원 하나');
      final presetId = c.presets.single.id;

      c.clearAll();
      c.addSquare();
      c.addSquare();
      expect(c.shapes.length, 2);

      c.loadPreset(presetId);
      expect(c.shapes.length, 1);
      expect(c.shapes.single.type, ShapeGuideType.circle);
      expect(c.shapes.single.cx, closeTo(0.6, 1e-9));

      c.dispose();
    });

    test('없는 프리셋 id 로 load/delete 하면 아무 것도 안 한다', () {
      final c = ShapeGuideController();
      c.addCircle();
      c.savePreset('A');
      var notified = 0;
      c.addListener(() => notified++);

      c.loadPreset('없음');
      c.deletePreset('없음');
      expect(notified, 0);
      expect(c.presets.length, 1);
      expect(c.shapes.length, 1);

      c.dispose();
    });

    test('deletePreset 은 해당 프리셋만 제거한다', () {
      final c = ShapeGuideController();
      c.addCircle();
      c.savePreset('A');
      c.savePreset('B');
      final idA = c.presets.first.id;

      c.deletePreset(idA);
      expect(c.presets.length, 1);
      expect(c.presets.single.name, 'B');

      c.dispose();
    });

    test('프리셋은 설정 저장소에 영속화되고 hydrate 로 복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SettingsStore.load();

      final a = ShapeGuideController()..settings = s;
      a.addCircle();
      a.addSquare();
      a.savePreset('상품 정면');

      final b = ShapeGuideController()..hydrate(await SettingsStore.load());
      expect(b.presets.length, 1);
      expect(b.presets.single.name, '상품 정면');
      expect(b.presets.single.shapes.length, 2);

      a.dispose();
      b.dispose();
    });

    test('loadPreset 후 앱을 다시 켜도 불러온 배치가 현재 배치로 유지된다', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SettingsStore.load();

      final a = ShapeGuideController()..settings = s;
      a.addCircle();
      a.savePreset('원');
      final presetId = a.presets.single.id;
      a.clearAll();
      a.addSquare();
      a.loadPreset(presetId);

      final b = ShapeGuideController()..hydrate(await SettingsStore.load());
      expect(b.shapes.length, 1);
      expect(b.shapes.single.type, ShapeGuideType.circle);

      a.dispose();
      b.dispose();
    });
  });
}
