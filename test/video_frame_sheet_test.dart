import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_hud.dart';

void main() {
  group('isVideoPath', () {
    test('동영상 확장자면 true', () {
      expect(isVideoPath('/a/b/clip.mp4'), true);
      expect(isVideoPath('VID_0001.MOV'), true);
      expect(isVideoPath('x.webm'), true);
      expect(isVideoPath('x.3gp'), true);
    });

    test('이미지/무확장자면 false', () {
      expect(isVideoPath('/a/b/photo.jpg'), false);
      expect(isVideoPath('shot.png'), false);
      expect(isVideoPath('noext'), false);
      expect(isVideoPath('/dir.mp4/file.heic'), false);
    });
  });

  group('formatClock', () {
    test('분:초', () {
      expect(formatClock(0), '0:00');
      expect(formatClock(5000), '0:05');
      expect(formatClock(65000), '1:05');
      expect(formatClock(600000), '10:00');
    });

    test('초 미만은 버림', () {
      expect(formatClock(1999), '0:01');
    });
  });
}
