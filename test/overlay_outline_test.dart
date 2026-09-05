import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/overlay_outline.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('overlay_outline_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 절반은 검정, 절반은 흰색인 이미지를 만든다. 가운데 경계에서만 에지가 검출돼야 한다.
  File makeHalfSplitImage() {
    final image = img.Image(width: 40, height: 40);
    for (final p in image) {
      final isWhite = p.x >= 20;
      img.drawPixel(
        image,
        p.x,
        p.y,
        isWhite ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
      );
    }
    final src = File('${tmp.path}/src.png');
    src.writeAsBytesSync(img.encodePng(image));
    return src;
  }

  test('경계가 있는 이미지는 흰색 불투명 픽셀이 있는 투명 PNG를 만든다', () async {
    final src = makeHalfSplitImage();
    final dst = File('${tmp.path}/out.png');

    final result = await traceOutline(src, dst);
    expect(result.path, dst.path);
    expect(dst.existsSync(), true);

    final decoded = img.decodePng(dst.readAsBytesSync())!;
    expect(decoded.numChannels, 4); // 알파 채널 포함

    var opaqueCount = 0;
    var transparentCount = 0;
    for (final p in decoded) {
      if (p.a > 0) {
        opaqueCount++;
        // 남는 픽셀은 흰색이어야 한다.
        expect(p.r, 255);
        expect(p.g, 255);
        expect(p.b, 255);
      } else {
        transparentCount++;
      }
    }
    expect(opaqueCount, greaterThan(0)); // 경계가 검출됨
    expect(transparentCount, greaterThan(0)); // 평평한 영역은 지워짐
  });

  test('균일한 색상 이미지는 에지가 없어 전부 투명하다', () async {
    final image = img.Image(width: 20, height: 20);
    for (final p in image) {
      img.drawPixel(image, p.x, p.y, img.ColorRgb8(128, 128, 128));
    }
    final src = File('${tmp.path}/flat.png');
    src.writeAsBytesSync(img.encodePng(image));
    final dst = File('${tmp.path}/flat_out.png');

    await traceOutline(src, dst);
    final decoded = img.decodePng(dst.readAsBytesSync())!;
    for (final p in decoded) {
      expect(p.a, 0);
    }
  });

  test('maxDimension보다 큰 이미지는 축소된다', () async {
    final image = img.Image(width: 2000, height: 1000);
    for (final p in image) {
      final isWhite = p.x >= 1000;
      img.drawPixel(
        image,
        p.x,
        p.y,
        isWhite ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
      );
    }
    final src = File('${tmp.path}/big.png');
    src.writeAsBytesSync(img.encodePng(image));
    final dst = File('${tmp.path}/big_out.png');

    await traceOutline(src, dst, maxDimension: 500);
    final decoded = img.decodePng(dst.readAsBytesSync())!;
    expect(decoded.width, lessThanOrEqualTo(500));
    expect(decoded.height, lessThanOrEqualTo(500));
  });

  test('디코딩할 수 없는 파일이면 에러를 던진다', () async {
    final src = File('${tmp.path}/not_image.txt');
    src.writeAsBytesSync([1, 2, 3, 4]);
    final dst = File('${tmp.path}/never.png');

    expect(() => traceOutline(src, dst), throwsA(anything));
  });
}
