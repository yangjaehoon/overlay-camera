import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_session.dart';

CameraDescription _cam(String name, CameraLensDirection dir) =>
    CameraDescription(name: name, lensDirection: dir, sensorOrientation: 90);

void main() {
  final back0 = _cam('back0', CameraLensDirection.back); // 기본 광각
  final front = _cam('front', CameraLensDirection.front);
  final backUltra = _cam('backUltra', CameraLensDirection.back); // 초광각
  final backTele = _cam('backTele', CameraLensDirection.back); // 망원

  group('pickFlipTarget', () {
    test('후면 → 전면: 첫 전면 카메라', () {
      final cams = [back0, front];
      expect(
        pickFlipTarget(cams, 0, lastBackIndex: 0, toFront: true),
        1,
      );
    });

    test('전면 → 후면: 마지막에 쓰던 후면 렌즈로 복귀', () {
      final cams = [back0, backUltra, backTele, front];
      expect(
        pickFlipTarget(cams, 3, lastBackIndex: 2, toFront: false),
        2,
      );
    });

    test('전면 → 후면: lastBackIndex 가 전면이면 첫 후면으로', () {
      final cams = [back0, backUltra, front];
      expect(
        pickFlipTarget(cams, 2, lastBackIndex: 2, toFront: false),
        0,
      );
    });

    test('전면 → 후면: lastBackIndex 가 범위를 벗어나면 첫 후면으로', () {
      final cams = [back0, front];
      expect(
        pickFlipTarget(cams, 1, lastBackIndex: 99, toFront: false),
        0,
      );
    });

    test('대상이 없으면 -1 (전면 카메라 없음)', () {
      final cams = [back0, backUltra];
      expect(
        pickFlipTarget(cams, 0, lastBackIndex: 0, toFront: true),
        -1,
      );
    });

    test('대상이 현재와 같으면 -1', () {
      final cams = [front, back0];
      expect(
        pickFlipTarget(cams, 1, lastBackIndex: 1, toFront: false),
        -1,
      );
    });

    test('빈 목록이면 -1', () {
      expect(
        pickFlipTarget(const [], 0, lastBackIndex: 0, toFront: true),
        -1,
      );
    });
  });

  group('nextBackLensIndex', () {
    test('후면 렌즈 3개를 순환하고 되돌아온다', () {
      final cams = [back0, backUltra, backTele, front];
      expect(nextBackLensIndex(cams, 0), 1);
      expect(nextBackLensIndex(cams, 1), 2);
      expect(nextBackLensIndex(cams, 2), 0); // wrap
    });

    test('후면 렌즈가 1개면 -1', () {
      final cams = [back0, front];
      expect(nextBackLensIndex(cams, 0), -1);
    });

    test('현재가 전면이면 -1', () {
      final cams = [back0, backUltra, front];
      expect(nextBackLensIndex(cams, 2), -1);
    });

    test('빈 목록이면 -1', () {
      expect(nextBackLensIndex(const [], 0), -1);
    });
  });
}
