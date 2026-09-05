import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'grid_controller.dart';
import 'photo_stamp.dart';
import 'shape_guide.dart';

/// 사용자 설정을 SharedPreferences에 영속화한다.
/// getter는 저장값(없으면 기본값)을 즉시 돌려주고, set* 은 즉시 인메모리 캐시를
/// 갱신하고 디스크 기록은 백그라운드로 맡긴다(반환값 없음, best-effort).
class SettingsStore {
  SettingsStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async =>
      SettingsStore._(await SharedPreferences.getInstance());

  static const _kSilent = 'silentShutter';
  static const _kStamp = 'stampEnabled';
  static const _kStampCorner = 'stampCorner';
  static const _kAutoOverlay = 'autoUseLastShot';
  static const _kOpacity = 'overlayOpacity';
  static const _kFlash = 'flashMode';
  static const _kLens = 'lensDirection';
  static const _kGrid = 'gridType';
  static const _kOutline = 'overlayOutline';
  static const _kShapes = 'shapeGuides';
  static const _kShapesLocked = 'shapeGuidesLocked';
  static const _kShapePresets = 'shapeGuidePresets';

  bool get silentShutter => _prefs.getBool(_kSilent) ?? false;
  void setSilentShutter(bool v) => _prefs.setBool(_kSilent, v);

  bool get stampEnabled => _prefs.getBool(_kStamp) ?? false;
  void setStampEnabled(bool v) => _prefs.setBool(_kStamp, v);

  bool get autoUseLastShot => _prefs.getBool(_kAutoOverlay) ?? true;
  void setAutoUseLastShot(bool v) => _prefs.setBool(_kAutoOverlay, v);

  double get overlayOpacity =>
      (_prefs.getDouble(_kOpacity) ?? 0.45).clamp(0.0, 1.0).toDouble();
  void setOverlayOpacity(double v) => _prefs.setDouble(_kOpacity, v);

  StampCorner get stampCorner =>
      _enumByIndex(StampCorner.values, _prefs.getInt(_kStampCorner),
          StampCorner.bottomRight);
  void setStampCorner(StampCorner v) => _prefs.setInt(_kStampCorner, v.index);

  FlashMode get flashMode =>
      _enumByIndex(FlashMode.values, _prefs.getInt(_kFlash), FlashMode.off);
  void setFlashMode(FlashMode v) => _prefs.setInt(_kFlash, v.index);

  /// 카메라는 index가 기기마다 달라 렌즈 방향으로 저장한다.
  CameraLensDirection get lensDirection {
    final name = _prefs.getString(_kLens);
    return CameraLensDirection.values.firstWhere(
      (d) => d.name == name,
      orElse: () => CameraLensDirection.back,
    );
  }

  void setLensDirection(CameraLensDirection v) =>
      _prefs.setString(_kLens, v.name);

  GridType get gridType =>
      _enumByIndex(GridType.values, _prefs.getInt(_kGrid), GridType.thirds);
  void setGridType(GridType v) => _prefs.setInt(_kGrid, v.index);

  bool get overlayOutline => _prefs.getBool(_kOutline) ?? false;
  void setOverlayOutline(bool v) => _prefs.setBool(_kOutline, v);

  List<ShapeGuide> get shapeGuides =>
      decodeShapeGuides(_prefs.getString(_kShapes));
  void setShapeGuides(List<ShapeGuide> shapes) =>
      _prefs.setString(_kShapes, encodeShapeGuides(shapes));

  bool get shapeGuidesLocked => _prefs.getBool(_kShapesLocked) ?? false;
  void setShapeGuidesLocked(bool v) => _prefs.setBool(_kShapesLocked, v);

  List<ShapeGuidePreset> get shapeGuidePresets =>
      decodeShapeGuidePresets(_prefs.getString(_kShapePresets));
  void setShapeGuidePresets(List<ShapeGuidePreset> presets) =>
      _prefs.setString(_kShapePresets, encodeShapeGuidePresets(presets));

  static T _enumByIndex<T>(List<T> values, int? index, T fallback) =>
      (index != null && index >= 0 && index < values.length)
          ? values[index]
          : fallback;
}
