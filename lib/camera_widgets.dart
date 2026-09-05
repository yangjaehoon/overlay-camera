import 'package:flutter/material.dart';

/// 상단 바용 소형 아이콘 버튼. 아이콘이 작아도 터치 영역은 최소 44를 확보한다.
class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    required this.icon,
    required this.color,
    required this.size,
    required this.iconSize,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hit = size < 44.0 ? 44.0 : size;
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkResponse(
          onTap: onTap,
          radius: hit * 0.55,
          child: SizedBox(
            width: hit,
            height: hit,
            child: Icon(
              icon,
              size: iconSize,
              color: onTap == null ? Colors.white24 : color,
            ),
          ),
        ),
      ),
    );
  }
}

/// 하단 촬영 바용 원형 버튼 + 라벨.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.label,
    this.big = false,
    this.iconColor = Colors.white,
    this.scale = 1.0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String label;
  final bool big;
  final Color iconColor;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = (big ? 58.0 : 46.0) * scale;
    final iconSize = (big ? 28.0 : 22.0) * scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                color: onPressed == null ? Colors.white24 : iconColor,
                size: iconSize,
              ),
            ),
          ),
        ),
        SizedBox(height: 4 * scale),
        Text(
          label,
          style: TextStyle(color: Colors.white, fontSize: 11 * scale),
        ),
      ],
    );
  }
}

/// 카메라를 쓸 수 없을 때 표시하는 안내 화면.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.message,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('다시 시도'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: onOpenSettings,
                  child: const Text('설정 열기'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 촬영 가이드 그리드. [fractions]에 준 비율 위치에 세로·가로선을 긋는다.
/// 예: 3분할 = [1/3, 2/3], 4분할 = [1/4, 2/4, 3/4].
class GridPainter extends CustomPainter {
  const GridPainter(this.fractions);

  final List<double> fractions;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (final f in fractions) {
      final dx = size.width * f;
      final dy = size.height * f;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) =>
      oldDelegate.fractions != fractions;
}
