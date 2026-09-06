import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_hud.dart';
import 'package:ghost_camera/overlay_controller.dart';
import 'package:ghost_camera/work_dir.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory tmp;
  late File image;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('overlay_layer_test');
    image = File('${tmp.path}/x.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 2, height: 2)));
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget host(OverlayController c) => MaterialApp(
        home: Stack(
          children: [
            ListenableBuilder(
              listenable: c,
              builder: (_, _) => OverlayLayer(overlay: c),
            ),
          ],
        ),
      );

  // 좌우 반전 Transform 은 m00(대각 첫 성분)이 음수다.
  bool hasFlip(WidgetTester t) => t
      .widgetList<Transform>(find.byType(Transform))
      .any((w) => w.transform.storage[0] < 0);

  testWidgets('기본은 색 반전·좌우 반전 위젯이 없다', (tester) async {
    final c = OverlayController(workDir: WorkDir())..setFile(image);
    await tester.pumpWidget(host(c));

    expect(find.byType(ColorFiltered), findsNothing);
    expect(hasFlip(tester), false);
    c.dispose();
  });

  testWidgets('inverted 면 ColorFiltered 를 씌운다', (tester) async {
    final c = OverlayController(workDir: WorkDir())..setFile(image);
    c.toggleInvert();
    await tester.pumpWidget(host(c));

    expect(find.byType(ColorFiltered), findsOneWidget);
    c.dispose();
  });

  testWidgets('mirrored 면 좌우 반전 Transform 을 씌운다', (tester) async {
    final c = OverlayController(workDir: WorkDir())..setFile(image);
    c.toggleMirror();
    await tester.pumpWidget(host(c));

    expect(hasFlip(tester), true);
    c.dispose();
  });

  testWidgets('토글을 되돌리면 위젯도 사라진다', (tester) async {
    final c = OverlayController(workDir: WorkDir())..setFile(image);
    c.toggleInvert();
    c.toggleMirror();
    await tester.pumpWidget(host(c));
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(hasFlip(tester), true);

    c.toggleInvert();
    c.toggleMirror();
    await tester.pump();
    expect(find.byType(ColorFiltered), findsNothing);
    expect(hasFlip(tester), false);
    c.dispose();
  });
}
