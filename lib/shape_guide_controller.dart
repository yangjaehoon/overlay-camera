import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;

import 'settings_store.dart';
import 'shape_guide.dart';

/// 화면 위에 자유롭게 배치하는 원/정사각형 가이드 도형들의 상태.
/// 위치·크기는 화면 비율로 저장되어 앱을 재시작해도 유지된다.
class ShapeGuideController extends ChangeNotifier {
  static const _minSize = 0.06;
  static const _maxSize = 1.8;
  static const _edgeMargin = 0.02;

  List<ShapeGuide> _shapes = const [];
  bool _locked = false;
  bool _disposed = false;

  /// 설정 저장소. 로드 후 주입된다.
  SettingsStore? settings;

  List<ShapeGuide> get shapes => _shapes;
  bool get isEmpty => _shapes.isEmpty;
  bool get locked => _locked;

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
    _shapes = s.shapeGuides;
    _locked = s.shapeGuidesLocked;
    _notify();
  }

  void addCircle() => _add(ShapeGuideType.circle);
  void addSquare() => _add(ShapeGuideType.square);

  void _add(ShapeGuideType type) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _shapes = [
      ..._shapes,
      ShapeGuide(id: id, type: type, cx: 0.5, cy: 0.45, size: 0.35),
    ];
    _persist();
    _notify();
  }

  void remove(String id) {
    final next = _shapes.where((s) => s.id != id).toList();
    if (next.length == _shapes.length) return; // 없는 id면 무시
    _shapes = next;
    _persist();
    _notify();
  }

  void clearAll() {
    if (_shapes.isEmpty) return;
    _shapes = const [];
    _persist();
    _notify();
  }

  void toggleLock() {
    _locked = !_locked;
    settings?.setShapeGuidesLocked(_locked);
    _notify();
  }

  /// 드래그 중 실시간 이동(픽셀 델타를 화면 비율로 환산해 누적). 저장은 [commit]에서.
  void move(String id, Offset pixelDelta, Size screenSize) {
    if (screenSize.width <= 0 || screenSize.height <= 0) return;
    _shapes = [
      for (final s in _shapes)
        if (s.id == id)
          s.copyWith(
            cx: (s.cx + pixelDelta.dx / screenSize.width)
                .clamp(_edgeMargin, 1 - _edgeMargin),
            cy: (s.cy + pixelDelta.dy / screenSize.height)
                .clamp(_edgeMargin, 1 - _edgeMargin),
          )
        else
          s,
    ];
    _notify();
  }

  /// 핀치 중 실시간 크기 변경(제스처 시작 시점 크기 기준 절대값). 저장은 [commit]에서.
  void resize(String id, double newSize) {
    _shapes = [
      for (final s in _shapes)
        if (s.id == id) s.copyWith(size: newSize.clamp(_minSize, _maxSize))
        else s,
    ];
    _notify();
  }

  /// 이동·크기조절 제스처 종료 시 확정 저장.
  void commit() => _persist();

  void _persist() => settings?.setShapeGuides(_shapes);
}
