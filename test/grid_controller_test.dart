import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/grid_controller.dart';
import 'package:ghost_camera/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('기본값은 3×3', () {
    final g = GridController();
    expect(g.type, GridType.thirds);
    g.dispose();
  });

  test('select는 값을 바꾸고 알린다', () {
    final g = GridController();
    var notified = 0;
    g.addListener(() => notified++);

    g.select(GridType.goldenRatio);
    expect(g.type, GridType.goldenRatio);
    expect(notified, 1);

    // 같은 값이면 알림 없음
    g.select(GridType.goldenRatio);
    expect(notified, 1);

    g.dispose();
  });

  test('select는 설정 저장소에 영속화한다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();
    final g = GridController()..hydrate(store);

    g.select(GridType.quarters);
    expect((await SettingsStore.load()).gridType, GridType.quarters);

    g.dispose();
  });

  test('hydrate는 저장된 값을 불러온다', () async {
    SharedPreferences.setMockInitialValues({'gridType': GridType.none.index});
    final store = await SettingsStore.load();
    final g = GridController()..hydrate(store);
    expect(g.type, GridType.none);
    g.dispose();
  });

  test('dispose 후 select를 불러도 예외가 없다', () {
    final g = GridController()..dispose();
    expect(() => g.select(GridType.quarters), returnsNormally);
  });
}
