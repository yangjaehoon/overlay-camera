import 'dart:io';

import 'package:flutter/widgets.dart';

import 'settings_store.dart';
import 'work_dir.dart';

/// 고스트 오버레이의 상태(이미지·투명도·변형·잠금·자동사용)를 담당한다.
/// 드래그처럼 잦은 갱신이 카메라 프리뷰까지 리빌드하지 않도록 별도 [ChangeNotifier]로 분리.
class OverlayController extends ChangeNotifier {
  OverlayController({required this.workDir, this.settings});

  final WorkDir workDir;
  SettingsStore? settings;

  static const _minScale = 0.15;
  static const _maxScale = 6.0;

  File? _file;
  double _opacity = 0.45;
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0;
  bool _locked = false;
  bool _autoUseLast = true;
  bool _disposed = false;

  // 제스처 시작 시점 기준값
  double _baseScale = 1.0;
  double _baseRotation = 0.0;

  File? get file => _file;
  bool get hasFile => _file != null;
  double get opacity => _opacity;
  Offset get offset => _offset;
  double get scale => _scale;
  double get rotation => _rotation;
  bool get locked => _locked;
  bool get autoUseLast => _autoUseLast;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 저장된 설정으로 초기 상태를 맞춘다.
  void hydrate(SettingsStore s) {
    settings = s;
    _autoUseLast = s.autoUseLastShot;
    _opacity = s.overlayOpacity;
    _notify();
  }

  /// 오버레이 이미지를 교체한다. 이전 파일이 작업 폴더 소유면 삭제한다.
  void setFile(File f) {
    final old = _file;
    _file = f;
    _resetTransform();
    _notify();
    if (old != null && old.path != f.path) workDir.deleteIfOwned(old);
  }

  void clear() {
    final old = _file;
    _file = null;
    _locked = false;
    _notify();
    if (old != null) workDir.deleteIfOwned(old);
  }

  void _resetTransform() {
    _offset = Offset.zero;
    _scale = 1.0;
    _rotation = 0.0;
  }

  void resetTransform() {
    _resetTransform();
    _notify();
  }

  void toggleLock() {
    if (_file == null) return;
    _locked = !_locked;
    _notify();
  }

  /// 드래그 중 실시간 갱신(저장 안 함).
  void setOpacity(double v) {
    _opacity = v;
    _notify();
  }

  /// 드래그 종료 시 확정 + 저장.
  void commitOpacity(double v) {
    _opacity = v;
    settings?.setOverlayOpacity(v);
    _notify();
  }

  void toggleAutoUseLast() {
    _autoUseLast = !_autoUseLast;
    settings?.setAutoUseLastShot(_autoUseLast);
    _notify();
  }

  void onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseRotation = _rotation;
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    _scale = (_baseScale * details.scale).clamp(_minScale, _maxScale);
    _rotation = _baseRotation + details.rotation;
    _offset += details.focalPointDelta;
    _notify();
  }
}
