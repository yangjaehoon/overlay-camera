import 'package:flutter/foundation.dart';

import 'change_bus.dart';
import 'settings_store.dart';

/// 화면의 상태를 나눠 갖는 컨트롤러들의 공통 뼈대.
///
/// 모든 컨트롤러가 똑같이 필요로 하던 두 가지를 여기로 모았다.
/// - dispose 후 알림 차단: 비동기 작업이 늦게 끝나 [notify]를 부를 때
///   이미 화면이 닫혔으면 조용히 무시한다.
/// - 설정 주입: [settings]는 앱 시작 시 [hydrate]로 한 번 주입된다.
abstract class AppController extends ChangeNotifier {
  bool _disposed = false;

  /// 이미 dispose 됐는지. 늦게 끝난 비동기 작업이 결과를 버릴지 판단할 때 쓴다.
  bool get isDisposed => _disposed;

  /// 설정 저장소. [hydrate]로 주입된다.
  SettingsStore? settings;

  /// 저장된 설정으로 초기 상태를 맞춘다. 구현은 [settings]부터 보관한다.
  void hydrate(SettingsStore s);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// dispose 이후에는 조용히 무시하는 [notifyListeners].
  @protected
  void notify() {
    if (!_disposed) notifyListeners();
  }
}

/// 잦은 전이(드래그 등)와 구조 변경(모드 토글·파일 교체·추가/삭제)을 서로 다른
/// 채널로 알리는 컨트롤러. 구조 변경에만 반응하면 되는 위젯은 [structure]를
/// 구독해 드래그 중 리빌드를 피한다.
abstract class StructuralController extends AppController {
  final StructureBus _structure = StructureBus();

  /// 구조 변경에만 반응하고 싶은 위젯이 구독하는 채널.
  Listenable get structure => _structure;

  @override
  void dispose() {
    _structure.dispose();
    super.dispose();
  }

  /// 구조 변경용. 메인 알림 + 구조 채널을 함께 울린다.
  @protected
  void notifyStructural() {
    if (isDisposed) return;
    notifyListeners();
    _structure.ping();
  }
}
