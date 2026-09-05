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
    expect(s.shapeGuides, isEmpty);
    expect(s.shapeGuidesLocked, false);
    expect(s.shapeGuidePresets, isEmpty);
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
    s.setShapeGuides(const [
      ShapeGuide(
        id: 's1',
        type: ShapeGuideType.circle,
        cx: 0.3,
        cy: 0.4,
        size: 0.25,
      ),
    ]);
    s.setShapeGuidesLocked(true);
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
    expect(again.shapeGuides.single.id, 's1');
    expect(again.shapeGuides.single.type, ShapeGuideType.circle);
    expect(again.shapeGuides.single.cx, 0.3);
    expect(again.shapeGuidesLocked, true);
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
    });
    final s = await SettingsStore.load();
    expect(s.stampCorner, StampCorner.bottomRight);
    expect(s.flashMode, FlashMode.off);
    expect(s.lensDirection, CameraLensDirection.back);
    expect(s.gridType, GridType.thirds);
  });
}
