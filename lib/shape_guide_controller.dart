import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;

import 'settings_store.dart';
import 'shape_guide.dart';

/// 구조 변경(추가·삭제·편집 토글·불러오기)에만 알리는 채널.
class _StructureBus extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// 화면 위에 자유롭게 배치하는 원/정사각형 가이드 도형들의 상태.
/// 위치·크기는 화면 비율로 저장되어 앱을 재시작해도 유지된다.
///
/// 도형은 기본적으로 "가이드"로만 그려져 터치를 통과시킨다(그 아래 오버레이·카메라
/// 조작을 막지 않음). [editing]을 켜야 드래그·크기조절·삭제가 가능해진다.
/// 편집 모드는 저장하지 않는다(앱을 다시 켜면 항상 가이드 상태).
class ShapeGuideController extends ChangeNotifier {
  ShapeGuideController({this.onMessage});

  /// 저장 결과 등 짧은 안내를 사용자에게 전달할 때 쓴다.
  final void Function(String message)? onMessage;

  static const _minSize = 0.06;
  static const _maxSize = 1.8;
  static const _edgeMargin = 0.02;
  static const _maxPresets = 20;

  List<ShapeGuide> _shapes = const [];
  List<ShapeGuidePreset> _presets = const [];
  bool _editing = false;
  bool _disposed = false;

  /// 드래그 중 잦은 갱신에는 반응하지 않아야 하는 위젯(편집 완료 배너, 상단 바
  /// 아이콘 등)이 구독하는 채널. 구조가 바뀔 때만 알린다.
  final _StructureBus _structure = _StructureBus();
  Listenable get structure => _structure;

  /// 설정 저장소. 로드 후 주입된다.
  SettingsStore? settings;

  /// 외부에서 리스트를 직접 바꿔 알림/저장을 건너뛰지 못하도록 읽기 전용 뷰로 노출.
  UnmodifiableListView<ShapeGuide> get shapes => UnmodifiableListView(_shapes);
  bool get isEmpty => _shapes.isEmpty;

  /// 편집 모드. 켜면 도형을 드래그·크기조절·삭제할 수 있다.
  bool get editing => _editing;

  /// 사용자가 이름 붙여 저장한 배치들.
  UnmodifiableListView<ShapeGuidePreset> get presets =>
      UnmodifiableListView(_presets);

  @override
  void dispose() {
    _disposed = true;
    _structure.dispose();
    super.dispose();
  }

  /// 잦은 전이(드래그)용. 도형 레이어·배지만 이 알림에 반응한다.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 구조 변경용. 메인 알림 + 구조 채널을 함께 울린다.
  void _notifyStructural() {
    if (_disposed) return;
    notifyListeners();
    _structure.ping();
  }

  /// 저장된 설정으로 초기 상태를 맞춘다.
  void hydrate(SettingsStore s) {
    settings = s;
    _shapes = s.shapeGuides;
    _presets = s.shapeGuidePresets;
    _notifyStructural();
  }

  /// 편집 모드를 켜고 끈다.
  void setEditing(bool value) {
    if (value == _editing) return;
    _editing = value;
    _notifyStructural();
  }

  void addCircle() => _add(ShapeGuideType.circle);
  void addSquare() => _add(ShapeGuideType.square);

  void _add(ShapeGuideType type) {
    // 새 도형이 이전 것과 완전히 겹쳐 보이지 않도록 개수에 따라 조금씩 어긋나게 놓는다.
    final step = 0.04 * (_shapes.length % 5);
    _shapes = [
      ..._shapes,
      ShapeGuide(
        id: _newId(),
        type: type,
        cx: (0.5 + step).clamp(_edgeMargin, 1 - _edgeMargin),
        cy: (0.42 + step).clamp(_edgeMargin, 1 - _edgeMargin),
        size: 0.35,
      ),
    ];
    _editing = true; // 방금 추가했으니 바로 배치할 수 있게 편집 모드로.
    _persist();
    _notifyStructural();
  }

  void remove(String id) {
    final next = _shapes.where((s) => s.id != id).toList();
    if (next.length == _shapes.length) return; // 없는 id면 무시
    _shapes = next;
    if (_shapes.isEmpty) _editing = false; // 지울 도형이 없으면 편집 모드 종료.
    _persist();
    _notifyStructural();
  }

  void clearAll() {
    if (_shapes.isEmpty) return;
    _shapes = const [];
    _editing = false; // 지울 게 없으니 편집 모드 종료.
    _persist();
    _notifyStructural();
  }

  /// 드래그/핀치 중 실시간 갱신. [pixelDelta]는 이번 이벤트의 이동량,
  /// [size]는 제스처 시작 크기 대비 절대값(핀치가 아니면 null → 크기 유지).
  /// 이동·크기 변경을 한 번에 반영해 프레임당 알림을 1회로 줄인다.
  /// 저장은 제스처 종료 시 [commit]에서 한다.
  void dragUpdate(
    String id, {
    required Offset pixelDelta,
    required Size screenSize,
    double? size,
  }) {
    if (screenSize.width <= 0 || screenSize.height <= 0) return;
    _shapes = [
      for (final s in _shapes)
        if (s.id == id)
          s.copyWith(
            cx: (s.cx + pixelDelta.dx / screenSize.width)
                .clamp(_edgeMargin, 1 - _edgeMargin),
            cy: (s.cy + pixelDelta.dy / screenSize.height)
                .clamp(_edgeMargin, 1 - _edgeMargin),
            size: size?.clamp(_minSize, _maxSize),
          )
        else
          s,
    ];
    _notify();
  }

  /// 이동·크기조절 제스처 종료 시 확정 저장.
  void commit() => _persist();

  void _persist() => settings?.setShapeGuides(_shapes);

  // 타임스탬프만으로는 같은 마이크로초에 여러 개를 만들면 충돌하므로 시퀀스를 붙인다.
  static int _idSeq = 0;
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  // --- 배치 저장/불러오기 -----------------------------------------------------

  /// 현재 배치를 [name] 이름으로 저장한다. 빈 이름이면 무시.
  /// 같은 이름이 이미 있으면 덮어써서 사본이 쌓이지 않게 한다.
  void savePreset(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final existing = _presets.indexWhere((p) => p.name == trimmed);
    if (existing < 0 && _presets.length >= _maxPresets) {
      onMessage?.call('저장된 배치는 최대 $_maxPresets개까지입니다.');
      return;
    }

    final entry = ShapeGuidePreset(
      id: existing >= 0 ? _presets[existing].id : _newId(),
      name: trimmed,
      shapes: List.of(_shapes),
    );
    if (existing >= 0) {
      final next = [..._presets];
      next[existing] = entry;
      _presets = next;
      onMessage?.call('"$trimmed" 배치를 덮어썼습니다.');
    } else {
      _presets = [..._presets, entry];
      onMessage?.call('"$trimmed" 배치를 저장했습니다.');
    }
    _persistPresets();
    _notifyStructural();
  }

  /// 저장된 배치를 통째로 불러와 현재 도형을 교체한다. 없는 id면 무시.
  void loadPreset(String id) {
    ShapeGuidePreset? preset;
    for (final p in _presets) {
      if (p.id == id) {
        preset = p;
        break;
      }
    }
    if (preset == null) return;
    // 다른 배치와 도형 id가 섞이지 않도록 불러올 때 새 id를 부여한다.
    _shapes = [
      for (final s in preset.shapes)
        ShapeGuide(
          id: _newId(),
          type: s.type,
          cx: s.cx,
          cy: s.cy,
          size: s.size,
        ),
    ];
    _editing = false; // 불러온 배치는 바로 촬영 가이드로 쓰도록 편집 모드 해제.
    _persist(); // 불러온 배치를 현재 작업 배치로도 저장
    onMessage?.call('"${preset.name}" 배치를 불러왔습니다.');
    _notifyStructural();
  }

  void deletePreset(String id) {
    final next = _presets.where((p) => p.id != id).toList();
    if (next.length == _presets.length) return;
    _presets = next;
    _persistPresets();
    _notifyStructural();
  }

  void _persistPresets() => settings?.setShapeGuidePresets(_presets);
}
