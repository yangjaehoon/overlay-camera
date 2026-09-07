import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../level_controller.dart';

/// 화면 중앙 수평 보조선. 가운데 짧은 고정 눈금 + 좌우로 기울어지는 선.
/// 수평(±1°)이면 노랗게 이어져 한 줄처럼 보인다. [level.enabled] 일 때만 그린다.
class LevelIndicator extends StatelessWidget {
  const LevelIndicator({super.key, required this.level});

  final LevelController level;

  @override
  Widget build(BuildContext context) {
    if (!level.enabled) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: CustomPaint(
          size: Size.infinite,
          painter: _LevelPainter(
            rollDegrees: level.rollDegrees,
            reliable: level.reliable,
            isLevel: level.isLevel,
          ),
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  const _LevelPainter({
    required this.rollDegrees,
    required this.reliable,
    required this.isLevel,
  });

  final double rollDegrees;
  final bool reliable;
  final bool isLevel;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const fixedHalf = 26.0; // 가운데 고정 눈금 반길이
    final wingOuter = math.min(size.width * 0.30, 170.0);
    const wingInner = 40.0; // 가운데를 비워 고정 눈금과 안 겹치게

    final color = isLevel ? Colors.amber : Colors.white;
    final glow = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // 가운데 고정 눈금 (항상 수평).
    final f1 = Offset(cx - fixedHalf, cy);
    final f2 = Offset(cx + fixedHalf, cy);
    canvas.drawLine(f1, f2, glow);
    canvas.drawLine(f1, f2, line);

    if (!reliable) return; // 화면이 너무 수평이면 기울기 선을 숨긴다

    // 기울어지는 좌우 날개.
    final a = -rollDegrees * math.pi / 180; // 화면상 참 수평은 기기와 반대로 회전
    final ca = math.cos(a);
    final sa = math.sin(a);
    Offset rot(double dx) => Offset(cx + dx * ca, cy + dx * sa);
    for (final seg in [
      [rot(-wingOuter), rot(-wingInner)],
      [rot(wingInner), rot(wingOuter)],
    ]) {
      canvas.drawLine(seg[0], seg[1], glow);
      canvas.drawLine(seg[0], seg[1], line);
    }
  }

  @override
  bool shouldRepaint(covariant _LevelPainter old) =>
      old.rollDegrees != rollDegrees ||
      old.reliable != reliable ||
      old.isLevel != isLevel;
}
