import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/overlay_controller.dart';
import 'package:ghost_camera/settings_store.dart';
import 'package:ghost_camera/work_dir.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WorkDir가 쓰는 임시 디렉터리를 테스트용 폴더로 고정하는 가짜 구현.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('overlay_controller_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 실제로 디코딩 가능한 최소 이미지를 만든다(윤곽선 추출 대상).
  File makeRealImage() {
    final image = img.Image(width: 20, height: 20);
    for (final p in image) {
      final isWhite = p.x >= 10;
      img.drawPixel(
        image,
        p.x,
        p.y,
        isWhite ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
      );
    }
    final f = File('${tmp.path}/src.png');
    f.writeAsBytesSync(img.encodePng(image));
    return f;
  }

  test('setFile은 이미지 설정 + 변형 초기화 + 알림', () {
    final c = OverlayController(workDir: WorkDir());
    var notified = 0;
    c.addListener(() => notified++);

    c.onScaleUpdate(ScaleUpdateDetails(scale: 2.0, focalPointDelta: const Offset(10, 10)));
    expect(c.scale, 2.0);

    c.setFile(File('/tmp/a.jpg'));
    expect(c.hasFile, true);
    expect(c.scale, 1.0); // 초기화됨
    expect(c.offset, Offset.zero);
    expect(notified, greaterThan(0));

    c.dispose();
  });

  test('onScaleUpdate는 배율을 0.15~6.0으로 클램프', () {
    final c = OverlayController(workDir: WorkDir());

    c.onScaleStart(ScaleStartDetails());
    c.onScaleUpdate(ScaleUpdateDetails(scale: 100));
    expect(c.scale, 6.0);

    c.onScaleStart(ScaleStartDetails());
    c.onScaleUpdate(ScaleUpdateDetails(scale: 0.001));
    expect(c.scale, 0.15);

    c.dispose();
  });

  test('toggleLock은 파일이 있을 때만 동작', () {
    final c = OverlayController(workDir: WorkDir());
    c.toggleLock();
    expect(c.locked, false); // 파일 없음 → 무시

    c.setFile(File('/tmp/a.jpg'));
    c.toggleLock();
    expect(c.locked, true);

    c.clear();
    expect(c.hasFile, false);
    expect(c.locked, false); // clear 시 잠금도 해제

    c.dispose();
  });

  test('toggleAutoUseLast', () {
    final c = OverlayController(workDir: WorkDir());
    expect(c.autoUseLast, true);
    c.toggleAutoUseLast();
    expect(c.autoUseLast, false);
    c.dispose();
  });

  test('toggleMirror / toggleInvert 는 파일이 있을 때만 동작하고 뒤집는다', () {
    final c = OverlayController(workDir: WorkDir());
    c.toggleMirror();
    c.toggleInvert();
    expect(c.mirrored, false); // 파일 없음 → 무시
    expect(c.inverted, false);

    c.setFile(File('/tmp/a.jpg'));
    c.toggleMirror();
    c.toggleInvert();
    expect(c.mirrored, true);
    expect(c.inverted, true);

    c.toggleMirror();
    expect(c.mirrored, false);
    c.dispose();
  });

  test('hydrate 로 좌우 반전·색 반전 상태를 복원한다', () async {
    SharedPreferences.setMockInitialValues({
      'overlayMirror': true,
      'overlayInvert': true,
    });
    final s = await SettingsStore.load();
    final c = OverlayController(workDir: WorkDir())..hydrate(s);
    expect(c.mirrored, true);
    expect(c.inverted, true);
    c.dispose();
  });

  test('setFile 해도 좌우 반전·색 반전은 유지된다(끈끈한 설정)', () {
    final c = OverlayController(workDir: WorkDir())..setFile(File('/a.jpg'));
    c.toggleMirror();
    c.toggleInvert();

    c.setFile(File('/b.jpg')); // 다른 사진으로 교체
    expect(c.mirrored, true);
    expect(c.inverted, true);
    // 변형은 초기화되지만 반전 옵션은 남는다.
    expect(c.scale, 1.0);
    c.dispose();
  });

  test('구조 채널은 위치 드래그(onScaleUpdate)에는 반응하지 않는다', () {
    final c = OverlayController(workDir: WorkDir())..setFile(File('/a.jpg'));
    var main = 0;
    var structural = 0;
    c.addListener(() => main++);
    c.structure.addListener(() => structural++);
    final m0 = main;
    final s0 = structural;

    c.onScaleStart(ScaleStartDetails());
    c.onScaleUpdate(ScaleUpdateDetails(focalPointDelta: const Offset(5, 5)));
    c.onScaleUpdate(ScaleUpdateDetails(focalPointDelta: const Offset(5, 5)));
    expect(main, greaterThan(m0)); // 메인은 매 프레임 울림
    expect(structural, s0); // 구조 채널은 조용

    c.toggleMirror();
    expect(structural, greaterThan(s0)); // 토글은 구조 채널도 울림

    c.dispose();
  });

  test('toggleOutline은 추출 완료 후 displayFile을 윤곽선 파일로 바꾼다', () async {
    final c = OverlayController(workDir: WorkDir());
    c.setFile(makeRealImage());
    expect(c.displayFile, c.file); // 기본은 원본 그대로

    c.toggleOutline();
    expect(c.outlineMode, true);
    expect(c.tracingOutline, true); // 추출 시작 직후엔 진행 중
    expect(c.displayFile, c.file); // 아직 추출 전이라 원본을 대신 보여줌

    // _ensureOutline()의 Isolate.run이 끝날 때까지 대기.
    await Future.delayed(const Duration(seconds: 1));
    expect(c.tracingOutline, false);
    expect(c.displayFile, isNot(c.file)); // 이제 윤곽선 파일로 전환됨
    expect(c.displayFile!.path, endsWith('.png'));

    c.toggleOutline();
    expect(c.outlineMode, false);
    expect(c.displayFile, c.file); // 끄면 원본으로 복귀

    c.dispose();
  });

  test('윤곽선 모드에서 setFile로 사진을 바꾸면 이전 윤곽선을 버리고 새로 추출한다', () async {
    final c = OverlayController(workDir: WorkDir());
    c.setFile(makeRealImage());
    c.toggleOutline();
    await Future.delayed(const Duration(seconds: 1));
    final firstOutline = c.displayFile;
    expect(firstOutline, isNot(c.file));

    c.setFile(makeRealImage());
    expect(c.displayFile, c.file); // 새 윤곽선이 나올 때까지는 원본을 보여줌
    await Future.delayed(const Duration(seconds: 1));
    expect(c.displayFile, isNot(c.file));
    expect(c.displayFile!.path, isNot(firstOutline!.path));

    c.dispose();
  });

  test('hydrate로 저장된 윤곽선 모드를 복원하면 자동으로 추출을 시작한다', () async {
    SharedPreferences.setMockInitialValues({'overlayOutline': true});
    final s = await SettingsStore.load();

    final c = OverlayController(workDir: WorkDir());
    c.setFile(makeRealImage());
    c.hydrate(s);
    expect(c.outlineMode, true);

    await Future.delayed(const Duration(seconds: 1));
    expect(c.displayFile, isNot(c.file));

    c.dispose();
  });
}
