import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/photo_stamp.dart';
import 'package:ghost_camera/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('저장값이 없으면 기본값', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsStore.load();
    expect(s.silentShutter, false);
    expect(s.stampEnabled, false);
    expect(s.autoUseLastShot, true);
    expect(s.overlayOpacity, 0.45);
    expect(s.stampCorner, StampCorner.bottomRight);
    expect(s.flashMode, FlashMode.off);
    expect(s.lensDirection, CameraLensDirection.back);
  });

  test('저장 후 다시 읽으면 값이 유지된다', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsStore.load();
    await s.setSilentShutter(true);
    await s.setStampCorner(StampCorner.topLeft);
    await s.setOverlayOpacity(0.8);
    await s.setFlashMode(FlashMode.torch);
    await s.setLensDirection(CameraLensDirection.front);

    final again = await SettingsStore.load();
    expect(again.silentShutter, true);
    expect(again.stampCorner, StampCorner.topLeft);
    expect(again.overlayOpacity, 0.8);
    expect(again.flashMode, FlashMode.torch);
    expect(again.lensDirection, CameraLensDirection.front);
  });

  test('손상된 enum 인덱스는 기본값으로 폴백', () async {
    SharedPreferences.setMockInitialValues({
      'stampCorner': 99,
      'flashMode': -1,
      'lensDirection': 'nonsense',
    });
    final s = await SettingsStore.load();
    expect(s.stampCorner, StampCorner.bottomRight);
    expect(s.flashMode, FlashMode.off);
    expect(s.lensDirection, CameraLensDirection.back);
  });
}
