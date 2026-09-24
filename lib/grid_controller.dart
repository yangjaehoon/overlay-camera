import 'package:flutter/material.dart' show IconData, Icons;

import 'controller_base.dart';
import 'settings_store.dart';

/// 촬영 가이드 그리드 종류. 안드로이드 기본 카메라와 같은 구성(없음/3×3/4×4/황금비율).
enum GridType { none, thirds, quarters, goldenRatio }

extension GridTypeX on GridType {
  String get label => switch (this) {
    GridType.none => '없음',
    GridType.thirds => '3×3 (삼분할)',
    GridType.quarters => '4×4',
    GridType.goldenRatio => '황금비율',
  };

  String get description => switch (this) {
    GridType.none => '가이드 선을 표시하지 않는다.',
    GridType.thirds => '가장 흔한 구도 기준. 선의 교차점에 피사체를 두면 안정적이다.',
    GridType.quarters => '더 촘촘한 격자. 수평·수직을 세밀하게 맞출 때 유용.',
    GridType.goldenRatio => '삼분할보다 중앙에 조금 더 가까운 비율(약 0.382/0.618).',
  };

  IconData get icon => switch (this) {
    GridType.none => Icons.grid_off,
    GridType.thirds => Icons.grid_3x3,
    GridType.quarters => Icons.grid_4x4,
    GridType.goldenRatio => Icons.grid_goldenratio,
  };
}

/// 그리드 종류 상태. 설정 저장소에 영속화된다.
class GridController extends AppController {
  GridType _type = GridType.thirds;

  GridType get type => _type;

  @override
  void hydrate(SettingsStore s) {
    settings = s;
    _type = s.gridType;
    notify();
  }

  void select(GridType value) {
    if (value == _type) return;
    _type = value;
    settings?.setGridType(value);
    notify();
  }
}
