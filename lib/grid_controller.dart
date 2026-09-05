import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import 'settings_store.dart';

/// 촬영 가이드 그리드 종류. 안드로이드 기본 카메라와 같은 구성(없음/3×3/4×4/황금비율).
enum GridType { none, thirds, quarters, goldenRatio }

extension GridTypeX on GridType {
  String get label {
    switch (this) {
      case GridType.none:
        return '없음';
      case GridType.thirds:
        return '3×3 (삼분할)';
      case GridType.quarters:
        return '4×4';
      case GridType.goldenRatio:
        return '황금비율';
    }
  }

  String get description {
    switch (this) {
      case GridType.none:
        return '가이드 선을 표시하지 않는다.';
      case GridType.thirds:
        return '가장 흔한 구도 기준. 선의 교차점에 피사체를 두면 안정적이다.';
      case GridType.quarters:
        return '더 촘촘한 격자. 수평·수직을 세밀하게 맞출 때 유용.';
      case GridType.goldenRatio:
        return '삼분할보다 중앙에 조금 더 가까운 비율(약 0.382/0.618).';
    }
  }

  IconData get icon {
    switch (this) {
      case GridType.none:
        return Icons.grid_off;
      case GridType.thirds:
        return Icons.grid_3x3;
      case GridType.quarters:
        return Icons.grid_4x4;
      case GridType.goldenRatio:
        return Icons.grid_goldenratio;
    }
  }
}

/// 그리드 종류 상태. 설정 저장소에 영속화된다.
class GridController extends ChangeNotifier {
  GridType _type = GridType.thirds;
  bool _disposed = false;

  /// 설정 저장소. 로드 후 주입된다.
  SettingsStore? settings;

  GridType get type => _type;

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
    _type = s.gridType;
    _notify();
  }

  void select(GridType value) {
    if (value == _type) return;
    _type = value;
    settings?.setGridType(value);
    _notify();
  }
}
