import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/photo_stamp.dart';

void main() {
  group('buildStampText', () {
    test('장소가 null이면 날짜만, 0 패딩 적용', () {
      final text = buildStampText(DateTime(2026, 3, 5, 9, 7), null);
      expect(text, '2026.03.05 09:07');
    });

    test('장소가 공백뿐이면 날짜만', () {
      expect(buildStampText(DateTime(2026, 12, 31, 23, 59), '   '), '2026.12.31 23:59');
    });

    test('장소가 있으면 둘째 줄에 붙는다', () {
      final text = buildStampText(DateTime(2026, 1, 2, 3, 4), '서울특별시 중구');
      expect(text, '2026.01.02 03:04\n서울특별시 중구');
    });
  });

  group('shortPlaceName', () {
    test('토큰 3개면 마지막 두 개만', () {
      expect(shortPlaceName('경기도', '성남시', '분당구'), '성남시 분당구');
    });

    test('null/빈 토큰은 건너뛴다', () {
      expect(shortPlaceName('서울특별시', null, '  '), '서울특별시');
    });

    test('전부 비면 null', () {
      expect(shortPlaceName(null, '', '   '), isNull);
    });

    test('토큰 2개는 그대로', () {
      expect(shortPlaceName('부산광역시', '해운대구', null), '부산광역시 해운대구');
    });
  });
}
