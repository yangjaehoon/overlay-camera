// Basic smoke test for Ghost Camera.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghost_camera/main.dart';

void main() {
  testWidgets('앱이 정상적으로 빌드된다', (WidgetTester tester) async {
    await tester.pumpWidget(const GhostCameraApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
