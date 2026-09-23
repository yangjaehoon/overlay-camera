/// 이름 붙여 저장하는 프리셋 목록(오버레이 프리셋, 도형 가이드 배치 등)이
/// 공통으로 따르는 정책·헬퍼. 각 컨트롤러는 실제 저장·파일 I/O는 스스로 하되,
/// "이름 검사 → 최대 개수 확인 → 덮어쓰기/추가 자리 찾기" 로직만 여기서 공유한다.
library;

/// 컨트롤러당 저장 가능한 프리셋 최대 개수.
const int kMaxPresetsPerController = 20;

/// 같은 마이크로초에 여러 id를 만들 때 충돌하지 않도록 시퀀스를 붙여 다음 id를 만든다.
class PresetIdSequence {
  static int _seq = 0;
  static String next() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}

/// 프리셋을 저장할 자리. [resolvePresetSlot]의 결과이며, 세 경우뿐이다.
sealed class PresetSlot<T> {
  const PresetSlot();
}

/// 같은 이름이 이미 있다. [index] 자리의 [existing]을 덮어쓴다.
final class PresetOverwrite<T> extends PresetSlot<T> {
  const PresetOverwrite({required this.index, required this.existing});

  final int index;
  final T existing;
}

/// 같은 이름이 없고 자리도 남아 있다. 목록 끝에 새로 추가한다.
final class PresetAppend<T> extends PresetSlot<T> {
  const PresetAppend();
}

/// 이미 [maxCount]개가 저장돼 있어 새로 추가할 수 없다.
final class PresetFull<T> extends PresetSlot<T> {
  const PresetFull(this.maxCount);

  final int maxCount;
}

/// [presets]에서 이름이 [trimmedName]인 항목을 찾아 저장할 자리를 정한다.
PresetSlot<T> resolvePresetSlot<T>({
  required List<T> presets,
  required String Function(T) nameOf,
  required String trimmedName,
  int maxCount = kMaxPresetsPerController,
}) {
  final index = presets.indexWhere((p) => nameOf(p) == trimmedName);
  if (index >= 0) {
    return PresetOverwrite(index: index, existing: presets[index]);
  }
  return presets.length >= maxCount
      ? PresetFull(maxCount)
      : const PresetAppend();
}

/// [slot]이 가리키는 자리에 [entry]를 반영한 새 목록을 돌려준다.
/// [PresetFull]은 저장할 자리가 없다는 뜻이므로 호출 전에 걸러야 한다.
List<T> writePreset<T>(List<T> presets, PresetSlot<T> slot, T entry) =>
    switch (slot) {
      PresetOverwrite(:final index) => [...presets]..[index] = entry,
      PresetAppend() => [...presets, entry],
      PresetFull() => throw StateError('자리가 없는 프리셋 슬롯에 저장을 시도했습니다.'),
    };

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  /// [test]를 만족하는 첫 항목, 없으면 null.
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
