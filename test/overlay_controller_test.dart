import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/overlay_controller.dart';
import 'package:ghost_camera/work_dir.dart';

void main() {
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
}
