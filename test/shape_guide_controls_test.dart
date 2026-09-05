import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_hud.dart';
import 'package:ghost_camera/shape_guide_controller.dart';
import 'package:ghost_camera/ui_metrics.dart';

const _screen = Size(400, 800);

Widget _host(ShapeGuideController guide) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: _screen),
      child: Builder(
        builder: (context) => Stack(
          children: [
            ShapeGuideControls(
              guide: guide,
              metrics: Metrics(MediaQuery.of(context)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 렌더 서피스를 위치 계산과 같은 크기로 맞추고 위젯을 띄운다.
Future<void> _pump(WidgetTester tester, ShapeGuideController guide) async {
  await tester.binding.setSurfaceSize(_screen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_host(guide));
}

void main() {
  testWidgets('편집 모드가 아니면 컨트롤을 그리지 않는다', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    guide.setEditing(false);
    await _pump(tester, guide);

    expect(find.byTooltip('도형 삭제'), findsNothing);
    expect(find.byTooltip('크기 조절'), findsNothing);
    guide.dispose();
  });

  testWidgets('편집 모드면 도형마다 삭제 배지 + 크기 핸들이 뜬다', (tester) async {
    final guide = ShapeGuideController()
      ..addCircle()
      ..addSquare();
    await _pump(tester, guide);

    expect(find.byTooltip('도형 삭제'), findsNWidgets(2));
    expect(find.byTooltip('크기 조절'), findsNWidgets(2));
    guide.dispose();
  });

  testWidgets('삭제 배지를 누르면 그 도형이 사라진다', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    await _pump(tester, guide);

    await tester.tap(find.byTooltip('도형 삭제'));
    await tester.pump();

    expect(guide.isEmpty, true);
    guide.dispose();
  });

  testWidgets('크기 핸들을 중심에서 멀리 끌면 커지고 commit 시 저장된다', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    final startSize = guide.shapes.single.size;
    await _pump(tester, guide);

    // 도형 중심은 (0.5*400, 0.42*800) = (200, 336). 핸들에서 오른쪽·아래로 끌어
    // 중심에서 더 멀어지게 한다.
    await tester.drag(find.byTooltip('크기 조절'), const Offset(80, 80));
    await tester.pump();

    expect(guide.shapes.single.size, greaterThan(startSize));
    guide.dispose();
  });

  testWidgets('크기 핸들을 중심 쪽으로 끌면 작아진다(하한 클램프)', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    await _pump(tester, guide);

    await tester.drag(find.byTooltip('크기 조절'), const Offset(-500, -500));
    await tester.pump();

    expect(guide.shapes.single.size, 0.06); // _minSize
    guide.dispose();
  });

  testWidgets('한계를 넘겨 끌었다 되돌리면 즉시 반응한다(러버밴드 없음)', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    await _pump(tester, guide);

    final startSize = guide.shapes.single.size;
    final handle = find.byTooltip('크기 조절');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    // 최대치를 한참 넘겨 바깥으로 끈다.
    await gesture.moveBy(const Offset(4000, 4000));
    await tester.pump();
    expect(guide.shapes.single.size, 1.8); // 최대로 클램프

    // 손가락을 시작 위치로 되돌리면 크기도 원래대로 돌아와야 한다
    // (누적 초과분에 갇히지 않음).
    await gesture.moveBy(const Offset(-4000, -4000));
    await tester.pump();
    expect(guide.shapes.single.size, closeTo(startSize, 0.05));

    await gesture.up();
    guide.dispose();
  });

  testWidgets('작은 도형이어도 삭제 배지와 크기 핸들이 겹치지 않는다', (tester) async {
    final guide = ShapeGuideController()..addCircle();
    await _pump(tester, guide);
    // 최소 크기로 줄인다.
    await tester.drag(find.byTooltip('크기 조절'), const Offset(-2000, -2000));
    await tester.pump();
    expect(guide.shapes.single.size, 0.06);

    final del = tester.getRect(find.byTooltip('도형 삭제'));
    final size = tester.getRect(find.byTooltip('크기 조절'));
    expect(del.overlaps(size), false, reason: '두 컨트롤이 겹쳐 삭제를 못 누르면 안 됨');
    guide.dispose();
  });
}
