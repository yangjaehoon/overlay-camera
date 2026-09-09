import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

const _videoExts = {
  '.mp4', '.mov', '.m4v', '.webm', '.3gp', '.3gpp', '.mkv', '.avi', '.ts',
};

/// 경로 확장자로 동영상 파일인지 판별한다.
bool isVideoPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return _videoExts.contains(path.substring(dot).toLowerCase());
}

/// 밀리초를 m:ss(.d) 시계 표기로. 10분 미만이면 m:ss, 그 이상은 mm:ss.
String formatClock(int ms) {
  final totalSec = ms ~/ 1000;
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 영상에서 오버레이(고스트)로 쓸 프레임을 스크럽해서 고른다.
/// 고른 위치(밀리초)를 돌려주고, 취소하면 null.
Future<int?> showVideoFrameSheet(BuildContext context, String videoPath) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _VideoFrameSheet(videoPath: videoPath),
  );
}

class _VideoFrameSheet extends StatefulWidget {
  const _VideoFrameSheet({required this.videoPath});

  final String videoPath;

  @override
  State<_VideoFrameSheet> createState() => _VideoFrameSheetState();
}

class _VideoFrameSheetState extends State<_VideoFrameSheet> {
  VideoPlayerController? _controller;
  String? _error;
  double _ms = 0;
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(File(widget.videoPath));
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.seekTo(Duration.zero);
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() => _controller = c);
    } on Exception catch (e) {
      debugPrint('영상 로드 실패: $e');
      await c.dispose();
      if (mounted) setState(() => _error = '영상을 열 수 없습니다.');
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || _scrubbing || !mounted) return;
    if (c.value.isPlaying) {
      setState(
        () => _ms = c.value.position.inMilliseconds.toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _seek(double ms) async {
    setState(() => _ms = ms);
    await _controller?.seekTo(Duration(milliseconds: ms.round()));
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
      await c.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '프레임 선택',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _body(context),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
    }
    final c = _controller;
    if (c == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: CircularProgressIndicator(),
      );
    }

    final durationMs = c.value.duration.inMilliseconds.toDouble();
    final maxMs = durationMs <= 0 ? 1.0 : durationMs;
    final value = _ms.clamp(0.0, maxMs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.42,
          ),
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio == 0 ? 1 : c.value.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: VideoPlayer(c),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: _togglePlay,
              icon: Icon(
                c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: value,
                  max: maxMs,
                  onChangeStart: (_) {
                    _scrubbing = true;
                    if (c.value.isPlaying) unawaited(c.pause());
                  },
                  onChanged: (v) => unawaited(_seek(v)),
                  onChangeEnd: (_) => _scrubbing = false,
                ),
              ),
            ),
            Text(
              '${formatClock(value.round())} / ${formatClock(durationMs.round())}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(value.round()),
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: const Text('이 프레임 사용'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
