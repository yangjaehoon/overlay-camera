import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// [src] 사진을 흰색 윤곽선만 남은 투명 PNG로 변환해 [dst]에 쓰고 그 File을 돌려준다.
/// [dst] 위치는 호출자가 정한다(작업 폴더 소유로 관리하기 위함).
/// 정합용 가이드일 뿐 원본 화질이 필요 없으므로, 크면 [maxDimension]으로
/// 축소해 처리 속도를 확보한다. 무거운 연산은 백그라운드 아이소레이트에서 돈다.
Future<File> traceOutline(
  File src,
  File dst, {
  int maxDimension = 1280,
  int threshold = 60,
}) async {
  final bytes = await src.readAsBytes();
  final png = await Isolate.run(() => _trace(bytes, maxDimension, threshold));
  await dst.writeAsBytes(png);
  return dst;
}

Uint8List _trace(Uint8List bytes, int maxDimension, int threshold) {
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('이미지를 디코딩하지 못했습니다.');
  }
  image = img.bakeOrientation(image); // 갤러리 사진의 EXIF 회전을 반영

  if (image.width > maxDimension || image.height > maxDimension) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? maxDimension : null,
      height: image.height > image.width ? maxDimension : null,
    );
  }

  // Sobel 에지 검출: 결과는 경계가 밝고 나머지는 어두운 흑백 이미지.
  final edges = img.sobel(image);

  // 밝기 임계값을 넘는 픽셀만 불투명한 흰 선으로 남기고 나머지는 투명하게 지운다.
  final out = img.Image(
    width: edges.width,
    height: edges.height,
    numChannels: 4,
  );
  for (final p in edges) {
    final isEdge = p.luminanceNormalized * 255 >= threshold;
    out.setPixelRgba(p.x, p.y, 255, 255, 255, isEdge ? 255 : 0);
  }

  return img.encodePng(out);
}
