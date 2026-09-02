import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'photo_stamp.dart';

/// 사용자 설정을 SharedPreferences에 영속화한다.
/// getter는 저장값(없으면 기본값)을 즉시 돌려주고, set* 은 백그라운드로 기록한다.
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

  bool get silentShutter => _prefs.getBool(_kSilent) ?? false;
  Future<void> setSilentShutter(bool v) => _prefs.setBool(_kSilent, v);

  bool get stampEnabled => _prefs.getBool(_kStamp) ?? false;
  Future<void> setStampEnabled(bool v) => _prefs.setBool(_kStamp, v);

  bool get autoUseLastShot => _prefs.getBool(_kAutoOverlay) ?? true;
  Future<void> setAutoUseLastShot(bool v) => _prefs.setBool(_kAutoOverlay, v);

  double get overlayOpacity =>
      (_prefs.getDouble(_kOpacity) ?? 0.45).clamp(0.0, 1.0).toDouble();
  Future<void> setOverlayOpacity(double v) => _prefs.setDouble(_kOpacity, v);

  StampCorner get stampCorner =>
      _enumByIndex(StampCorner.values, _prefs.getInt(_kStampCorner),
          StampCorner.bottomRight);
  Future<void> setStampCorner(StampCorner v) =>
      _prefs.setInt(_kStampCorner, v.index);

  FlashMode get flashMode =>
      _enumByIndex(FlashMode.values, _prefs.getInt(_kFlash), FlashMode.off);
  Future<void> setFlashMode(FlashMode v) => _prefs.setInt(_kFlash, v.index);

  /// 카메라는 index가 기기마다 달라 렌즈 방향으로 저장한다.
  CameraLensDirection get lensDirection {
    final name = _prefs.getString(_kLens);
    return CameraLensDirection.values.firstWhere(
      (d) => d.name == name,
      orElse: () => CameraLensDirection.back,
    );
  }

  Future<void> setLensDirection(CameraLensDirection v) =>
      _prefs.setString(_kLens, v.name);

  static T _enumByIndex<T>(List<T> values, int? index, T fallback) =>
      (index != null && index >= 0 && index < values.length)
          ? values[index]
          : fallback;
}
