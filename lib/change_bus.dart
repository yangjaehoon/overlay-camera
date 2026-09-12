import 'package:flutter/foundation.dart';

/// 잦은 전이(드래그 등)가 아니라 구조 변경(모드 토글·파일 교체·추가/삭제 등)에만
/// 알리고 싶은 위젯이 구독하는 경량 채널. 메인 [ChangeNotifier]와 분리해 두면
/// 그 채널만 구독하는 위젯이 잦은 갱신에 불필요하게 리빌드되지 않는다.
class StructureBus extends ChangeNotifier {
  void ping() => notifyListeners();
}
