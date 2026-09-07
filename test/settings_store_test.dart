import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/grid_controller.dart';
import 'package:ghost_camera/photo_stamp.dart';
import 'package:ghost_camera/settings_store.dart';
import 'package:ghost_camera/shape_guide.dart';
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
    expect(s.gridType, GridType.thirds);
    expect(s.overlayOutline, false);
    expect(s.overlayMirror, false);
    expect(s.overlayInvert, false);
    expect(s.levelEnabled, false);
    expect(s.shapeGuides, isEmpty);
    expect(s.shapeGuidePresets, isEmpty);
    expect(s.timerSeconds, 0);
    expect(s.resolutionPreset, ResolutionPreset.high);
  });

  test('timerSeconds 는 3·10만 유효하고 그 외는 0', () async {
    SharedPreferences.setMockInitialValues({'timerSeconds': 7});
    expect((await SettingsStore.load()).timerSeconds, 0);
    SharedPreferences.setMockInitialValues({'timerSeconds': 3});
    expect((await SettingsStore.load()).timerSeconds, 3);
    SharedPreferences.setMockInitialValues({'timerSeconds': 10});
    expect((await SettingsStore.load()).timerSeconds, 10);
  });

  test('저장 후 다시 읽으면 값이 유지된다', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsStore.load();
    s.setSilentShutter(true);
    s.setStampCorner(StampCorner.topLeft);
    s.setOverlayOpacity(0.8);
    s.setFlashMode(FlashMode.torch);
    s.setLensDirection(CameraLensDirection.front);
    s.setGridType(GridType.goldenRatio);
    s.setOverlayOutline(true);
    s.setOverlayMirror(true);
    s.setOverlayInvert(true);
    s.setLevelEnabled(true);
    s.setTimerSeconds(10);
    s.setResolutionPreset(ResolutionPreset.veryHigh);
    s.setShapeGuides(const [
      ShapeGuide(
        id: 's1',
        type: ShapeGuideType.circle,
        cx: 0.3,
        cy: 0.4,
        size: 0.25,
      ),
    ]);
    s.setShapeGuidePresets(const [
      ShapeGuidePreset(
        id: 'p1',
        name: '인물용',
        shapes: [
          ShapeGuide(
            id: 's1',
            type: ShapeGuideType.square,
            cx: 0.5,
            cy: 0.5,
            size: 0.4,
          ),
        ],
      ),
    ]);

    final again = await SettingsStore.load();
    expect(again.silentShutter, true);
    expect(again.stampCorner, StampCorner.topLeft);
    expect(again.overlayOpacity, 0.8);
    expect(again.flashMode, FlashMode.torch);
    expect(again.lensDirection, CameraLensDirection.front);
    expect(again.gridType, GridType.goldenRatio);
    expect(again.overlayOutline, true);
    expect(again.overlayMirror, true);
    expect(again.overlayInvert, true);
    expect(again.levelEnabled, true);
    expect(again.timerSeconds, 10);
    expect(again.resolutionPreset, ResolutionPreset.veryHigh);
    expect(again.shapeGuides.single.id, 's1');
    expect(again.shapeGuides.single.type, ShapeGuideType.circle);
    expect(again.shapeGuides.single.cx, 0.3);
    expect(again.shapeGuidePresets.single.name, '인물용');
    expect(again.shapeGuidePresets.single.shapes.single.type,
        ShapeGuideType.square);
  });

  test('손상된 enum 인덱스는 기본값으로 폴백', () async {
    SharedPreferences.setMockInitialValues({
      'stampCorner': 99,
      'flashMode': -1,
      'lensDirection': 'nonsense',
      'gridType': 42,
      'resolutionPreset': 999,
    });
    final s = await SettingsStore.load();
    expect(s.stampCorner, StampCorner.bottomRight);
    expect(s.flashMode, FlashMode.off);
    expect(s.lensDirection, CameraLensDirection.back);
    expect(s.gridType, GridType.thirds);
    expect(s.resolutionPreset, ResolutionPreset.high);
  });
}
