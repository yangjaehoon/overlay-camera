/// 이름 붙여 저장하는 프리셋 목록(오버레이 프리셋, 도형 가이드 배치 등)이
/// 공통으로 따르는 정책·헬퍼. 각 컨트롤러는 실제 저장·파일 I/O는 스스로 하되,
/// "이름 검사 → 최대 개수 확인 → 덮어쓰기/추가 자리 찾기" 로직만 여기서 공유한다.
library;

/// 컨트롤러당 저장 가능한 프리셋 최대 개수.
const int kMaxPresetsPerController = 20;

/// 같은 마이크로초에 여러 id를 만들 때 충돌하지 않도록 시퀀스를 붙여 다음 id를 만든다.
class PresetIdSequence {
  static int _seq = 0;
  static String next() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}

/// [presets]에서 이름이 [trimmedName]인 항목의 인덱스를 찾는다.
/// - 있으면 그 인덱스(덮어쓰기 대상)를 반환한다.
/// - 없는데 이미 [maxCount]개 저장돼 있으면 null을 반환해 호출자가
///   "최대 개수" 안내를 띄우게 한다.
/// - 없고 자리가 남아 있으면 -1(새로 추가)을 반환한다.
int? resolvePresetSlot<T>({
  required List<T> presets,
  required String Function(T) nameOf,
  required String trimmedName,
  int maxCount = kMaxPresetsPerController,
}) {
  final existing = presets.indexWhere((p) => nameOf(p) == trimmedName);
  if (existing < 0 && presets.length >= maxCount) return null;
  return existing;
}

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  /// [test]를 만족하는 첫 항목, 없으면 null.
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
