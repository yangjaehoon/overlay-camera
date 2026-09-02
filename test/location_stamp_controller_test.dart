import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/location_stamp_controller.dart';
import 'package:ghost_camera/photo_stamp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selectCorner는 값을 바꾸고 리스너에 알린다', () {
    final c = LocationStampController();
    var notified = 0;
    c.addListener(() => notified++);

    c.selectCorner(StampCorner.topLeft);
    expect(c.corner, StampCorner.topLeft);
    expect(notified, 1);

    // 같은 값이면 알림 없음
    c.selectCorner(StampCorner.topLeft);
    expect(notified, 1);

    c.dispose();
  });

  test('toggle은 enabled를 뒤집는다', () {
    final c = LocationStampController();
    expect(c.enabled, false);
    c.toggle();
    expect(c.enabled, true);
    c.toggle();
    expect(c.enabled, false);
    c.dispose();
  });

  test('previewText는 장소가 없으면 날짜만 담는다', () {
    final c = LocationStampController();
    expect(c.previewText().contains('\n'), false);
    c.dispose();
  });
}
