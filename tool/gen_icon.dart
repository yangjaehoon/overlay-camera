// 임시 앱 아이콘/스플래시 이미지를 생성한다. 유령 실루엣 + 카메라 렌즈.
//
// 실행:  dart run tool/gen_icon.dart
// 이후:  dart run flutter_launcher_icons
//        dart run flutter_native_splash:create
//
// 정식 디자인이 나오면 assets/icon/*.png 를 교체하고 위 두 명령만 다시 돌리면 된다.

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// 브랜드 색.
final _bg = img.ColorRgb8(0x4C, 0x3A, 0x9E); // 보라
final _ghost = img.ColorRgb8(0xFF, 0xFF, 0xFF);
final _barrel = img.ColorRgb8(0x2E, 0x25, 0x68);
final _glass = img.ColorRgb8(0x8B, 0x7B, 0xF0);
final _aperture = img.ColorRgb8(0x24, 0x1E, 0x52);
final _highlight = img.ColorRgb8(0xEF, 0xEC, 0xFF);

const _render = 2048; // 슈퍼샘플 후 1024로 축소
const _out = 1024;

/// 유령+렌즈 글리프를 [image] 위 정사각형 박스(왼쪽 [bx], 위 [by], 한 변 [bs])에 그린다.
void _drawGlyph(img.Image image, double bx, double by, double bs) {
  double x(double nx) => bx + nx * bs;
  double y(double ny) => by + ny * bs;

  // 유령 몸통: 위쪽 반원 돔 + 세로 옆면 + 물결 밑단을 하나의 폴리곤으로.
  // 돔+꼬리를 합친 시각적 무게중심이 박스 정중앙에 오도록 살짝 아래로.
  final verts = <img.Point>[];
  const domeCx = 0.5, domeCy = 0.49, domeR = 0.38;
  const sideBottom = 0.79;
  for (var i = 0; i <= 80; i++) {
    final t = i / 80;
    final ang = math.pi * (1 - t); // 왼쪽 → 위 → 오른쪽
    verts.add(img.Point(
      x(domeCx + domeR * math.cos(ang)),
      y(domeCy - domeR * math.sin(ang)),
    ));
  }
  verts.add(img.Point(x(domeCx + domeR), y(sideBottom))); // 오른쪽 옆면 아래로
  const waveBase = 0.80, waveAmp = 0.10, humps = 3;
  for (var i = 0; i <= 90; i++) {
    final nx = (domeCx + domeR) - i / 90 * (2 * domeR); // 오른쪽 → 왼쪽
    final phase = ((domeCx + domeR) - nx) / (2 * domeR) * 2 * math.pi * humps;
    verts.add(img.Point(x(nx), y(waveBase + waveAmp * (0.5 - 0.5 * math.cos(phase)))));
  }
  verts.add(img.Point(x(domeCx - domeR), y(domeCy))); // 왼쪽 옆면 → 시작점으로 닫힘
  img.fillPolygon(image, vertices: verts, color: _ghost);

  // 카메라 렌즈(동심원).
  int px(double nx) => x(nx).round();
  int py(double ny) => y(ny).round();
  int r(double n) => (n * bs).round();
  img.fillCircle(image, x: px(0.5), y: py(0.53), radius: r(0.23),
      color: _barrel, antialias: true);
  img.fillCircle(image, x: px(0.5), y: py(0.53), radius: r(0.165),
      color: _glass, antialias: true);
  img.fillCircle(image, x: px(0.5), y: py(0.53), radius: r(0.075),
      color: _aperture, antialias: true);
  img.fillCircle(image, x: px(0.44), y: py(0.46), radius: r(0.05),
      color: _highlight, antialias: true);
}

img.Image _compose({required bool withBackground, required double boxFraction}) {
  final canvas = img.Image(width: _render, height: _render, numChannels: 4);
  if (withBackground) {
    img.fill(canvas, color: _bg);
  }
  final bs = _render * boxFraction;
  final origin = (_render - bs) / 2;
  _drawGlyph(canvas, origin, origin, bs);
  return img.copyResize(canvas,
      width: _out, height: _out, interpolation: img.Interpolation.cubic);
}

void _write(String path, img.Image image) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('  $path');
}

void main() {
  stdout.writeln('아이콘/스플래시 생성:');
  _write('assets/icon/app_icon.png',
      _compose(withBackground: true, boxFraction: 0.82));
  _write('assets/icon/app_icon_foreground.png',
      _compose(withBackground: false, boxFraction: 0.70));
  _write('assets/icon/splash.png',
      _compose(withBackground: false, boxFraction: 0.52));
  stdout.writeln('완료. 다음: dart run flutter_launcher_icons '
      '&& dart run flutter_native_splash:create');
}
