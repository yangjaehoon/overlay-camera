import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_hud.dart';
import 'package:ghost_camera/shape_guide_controller.dart';
import 'package:ghost_camera/ui_metrics.dart';

Widget _host(ShapeGuideController guide) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Builder(
        builder: (context) => Stack(
          children: [
            ShapeGuideBadges(
              guide: guide,
              metrics: Metrics(MediaQuery.of(context)),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('편집 모드가 아니면 컨트롤을 그리지 않는다', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    guide.setEditing(false);
    await tester.pumpWidget(_host(guide));

    expect(find.byTooltip('도형 삭제'), findsNothing);
    expect(find.byTooltip('크기 조절'), findsNothing);
    guide.dispose();
  });

  testWidgets('편집 모드면 도형마다 삭제 배지 + 크기 핸들이 뜬다', (tester) async {
    final guide = ShapeGuideController()
      ..addCircle()
      ..addSquare();
    await tester.pumpWidget(_host(guide));

    expect(find.byTooltip('도형 삭제'), findsNWidgets(2));
    expect(find.byTooltip('크기 조절'), findsNWidgets(2));
    guide.dispose();
  });

  testWidgets('삭제 배지를 누르면 그 도형이 사라진다', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    await tester.pumpWidget(_host(guide));

    await tester.tap(find.byTooltip('도형 삭제'));
    await tester.pump();

    expect(guide.isEmpty, true);
    guide.dispose();
  });

  testWidgets('크기 핸들을 바깥으로 끌면 도형이 커지고, commit 시 저장된다', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    final startSize = guide.shapes.single.size;
    await tester.pumpWidget(_host(guide));

    // 핸들은 DragStartBehavior.down 이라 이동량이 그대로 반영된다.
    // 오른쪽·아래로 (60,60) → 지름 += 120px, size += 120/400 = 0.3
    await tester.drag(find.byTooltip('크기 조절'), const Offset(60, 60));
    await tester.pump();

    expect(guide.shapes.single.size, greaterThan(startSize));
    expect(guide.shapes.single.size, closeTo(startSize + 0.3, 1e-6));
    guide.dispose();
  });

  testWidgets('크기 핸들을 안쪽으로 끌면 도형이 작아진다(하한까지)', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    await tester.pumpWidget(_host(guide));

    await tester.drag(find.byTooltip('크기 조절'), const Offset(-500, -500));
    await tester.pump();

    expect(guide.shapes.single.size, 0.06); // _minSize 로 클램프
    guide.dispose();
  });
}
