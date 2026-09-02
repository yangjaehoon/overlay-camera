import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// 스탬프를 찍을 모서리.
enum StampCorner { topLeft, topRight, bottomLeft, bottomRight }

extension StampCornerX on StampCorner {
  bool get isLeft =>
      this == StampCorner.topLeft || this == StampCorner.bottomLeft;
  bool get isTop =>
      this == StampCorner.topLeft || this == StampCorner.topRight;

  String get label {
    switch (this) {
      case StampCorner.topLeft:
        return '왼쪽 위';
      case StampCorner.topRight:
        return '오른쪽 위';
      case StampCorner.bottomLeft:
        return '왼쪽 아래';
      case StampCorner.bottomRight:
        return '오른쪽 아래';
    }
  }

  Alignment get alignment {
    switch (this) {
      case StampCorner.topLeft:
        return Alignment.topLeft;
      case StampCorner.topRight:
        return Alignment.topRight;
      case StampCorner.bottomLeft:
        return Alignment.bottomLeft;
      case StampCorner.bottomRight:
        return Alignment.bottomRight;
    }
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 스탬프에 넣을 문구. 장소가 없으면 날짜만.
String buildStampText(DateTime now, String? place) {
  final date =
      '${now.year}.${_two(now.month)}.${_two(now.day)} ${_two(now.hour)}:${_two(now.minute)}';
  if (place == null || place.trim().isEmpty) return date;
  return '$date\n${place.trim()}';
}

/// administrativeArea / locality / subLocality 중 비어있지 않은 값들의
/// 마지막 두 토큰을 합쳐 짧은 장소명을 만든다. 전부 비면 null.
String? shortPlaceName(String? admin, String? locality, String? subLocality) {
  final tokens = [admin, locality, subLocality]
      .map((e) => e?.trim())
      .whereType<String>()
      .where((e) => e.isNotEmpty)
      .toList();
  final kept =
      tokens.length > 2 ? tokens.sublist(tokens.length - 2) : tokens;
  final place = kept.join(' ');
  return place.isEmpty ? null : place;
}

/// rawRgba 픽셀을 JPEG로 인코딩한다. 순수 Dart 연산이라 백그라운드 아이소레이트에서 실행.
Uint8List _encodeRgbaToJpg((Uint8List, int, int) args) {
  final (rgba, width, height) = args;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 92);
}

/// [src] 사진에 [text]를 [corner] 위치로 그려 넣어 새 JPEG 파일로 저장하고 그 File을 돌려준다.
/// Flutter 캔버스로 그리므로 한글·이모지 폰트가 그대로 렌더링된다.
Future<File> stampPhoto(
  File src, {
  required String text,
  required StampCorner corner,
}) async {
  final bytes = await src.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  final int iw = image.width;
  final int ih = image.height;
  final double w = iw.toDouble();
  final double h = ih.toDouble();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, w, h));
  canvas.drawImage(image, ui.Offset.zero, ui.Paint());

  final double fontSize = (w * 0.030).clamp(18.0, 96.0);
  final double margin = w * 0.028;
  final double maxWidth = w - margin * 2;

  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: corner.isLeft ? TextAlign.left : TextAlign.right,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
  )
    ..pushStyle(
      ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        shadows: [
          ui.Shadow(
            color: const Color(0xCC000000),
            blurRadius: fontSize * 0.3,
            offset: ui.Offset(0, fontSize * 0.06),
          ),
        ],
      ),
    )
    ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth));

  final double dy = corner.isTop ? margin : h - margin - paragraph.height;
  canvas.drawParagraph(paragraph, ui.Offset(margin, dy));

  final picture = recorder.endRecording();
  final rendered = await picture.toImage(iw, ih);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);

  image.dispose();
  rendered.dispose();
  picture.dispose();

  if (data == null) {
    throw StateError('스탬프 이미지를 렌더링하지 못했습니다.');
  }

  // rawRgba -> JPEG 인코딩은 순수 Dart라 UI 아이소레이트를 막지 않도록 분리한다.
  final rgba =
      Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  final jpg = await Isolate.run(() => _encodeRgbaToJpg((rgba, iw, ih)));

  final base = src.path.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
  final dst = File('${base}_stamped.jpg');
  await dst.writeAsBytes(jpg);
  return dst;
}
