import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 촬영 임시본을 두는 캐시 하위 폴더 관리.
///
/// 문서 디렉터리와 달리 OS가 저장공간 압박 시 정리할 수 있고, 앱도 세션 시작 시
/// [prune]으로 잔여 파일을 지우므로 무한 누적되지 않는다.
class WorkDir {
  Directory? _dir;

  Future<Directory> _ensure() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/ghost_work');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// [sourcePath] 파일을 작업 폴더로 복사하고 새 File을 돌려준다.
  Future<File> copyInto(
    String sourcePath,
    String prefix, {
    String ext = 'jpg',
  }) async {
    final dir = await _ensure();
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final dest = File('${dir.path}/$name');
    await File(sourcePath).copy(dest.path);
    return dest;
  }

  /// 작업 폴더 안에 아직 존재하지 않는 새 파일 경로를 예약한다.
  /// (파일 복사가 아니라 직접 내용을 만들어 써야 하는 경우, 예: 이미지 가공 결과)
  Future<File> reserve(String prefix, {String ext = 'jpg'}) async {
    final dir = await _ensure();
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    return File('${dir.path}/$name');
  }

  /// [file]이 이 작업 폴더가 소유한 파일이면 백그라운드로 삭제한다.
  void deleteIfOwned(File file) {
    final dir = _dir;
    if (dir == null || !file.path.startsWith(dir.path)) return;
    unawaited(file.delete().catchError((Object _) => file));
  }

  /// [keepPath]를 제외한 작업 폴더의 잔여 파일을 모두 지운다.
  Future<void> prune({String? keepPath}) async {
    try {
      final dir = await _ensure();
      await for (final entry in dir.list()) {
        if (entry is File && entry.path != keepPath) {
          try {
            await entry.delete();
          } catch (_) {
            // 개별 삭제 실패는 무시
          }
        }
      }
    } catch (_) {
      // 정리 실패는 치명적이지 않음
    }
  }
}
