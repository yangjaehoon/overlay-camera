import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'main.dart';

/// 라이브 카메라 프리뷰 위에 반투명 참조 사진(고스트)을 겹쳐 보여주고,
/// 그 사진에 인물 위치·크기를 맞춰 사진/동영상을 촬영하는 화면.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;

  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  bool _isRecording = false;
  bool _busy = false;
  String? _statusMessage;

  // 고스트 오버레이 상태
  File? _overlayFile;
  double _overlayOpacity = 0.45;
  Offset _overlayOffset = Offset.zero;
  double _overlayScale = 1.0;
  double _overlayRotation = 0.0;
  bool _overlayLocked = false;
  bool _autoUseLastShot = true;

  // 무음 촬영: 셔터음이 강제되는 기기에서도 소리 없이 정지 이미지를 얻기 위해
  // 아주 짧게 동영상을 녹화한 뒤 첫 프레임을 추출하는 방식.
  bool _silentShutter = false;

  // 제스처 시작 시점 기준값
  double _gestureBaseScale = 1.0;
  double _gestureBaseRotation = 0.0;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_cameraIndex);
    }
  }

  Future<void> _bootstrap() async {
    final statuses = await <Permission>[
      Permission.camera,
      Permission.microphone,
    ].request();

    final cameraDenied = statuses[Permission.camera] != PermissionStatus.granted;
    if (cameraDenied) {
      setState(() => _statusMessage = '카메라 권한이 필요합니다. 설정에서 허용해 주세요.');
      return;
    }

    if (cameras.isEmpty) {
      try {
        cameras = await availableCameras();
      } on CameraException {
        // 무시하고 아래에서 처리
      }
    }
    if (cameras.isEmpty) {
      setState(() => _statusMessage = '사용 가능한 카메라를 찾지 못했습니다.');
      return;
    }

    final backIndex = cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    _cameraIndex = backIndex >= 0 ? backIndex : 0;
    await _initCamera(_cameraIndex);
  }

  Future<void> _initCamera(int index) async {
    final previous = _controller;
    final controller = CameraController(
      cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      try {
        await controller.setFlashMode(_flashMode);
      } on CameraException {
        // 일부 기기는 플래시 미지원
      }
      await previous?.dispose();
      setState(() {});
    } on CameraException {
      setState(() => _statusMessage = '카메라를 초기화하지 못했습니다.');
    }
  }

  bool get _isReady =>
      _controller != null && _controller!.value.isInitialized;

  // ---------------------------------------------------------------------------
  // 오버레이 조작
  // ---------------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _gestureBaseScale = _overlayScale;
    _gestureBaseRotation = _overlayRotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _overlayScale = (_gestureBaseScale * details.scale).clamp(0.15, 6.0);
      _overlayRotation = _gestureBaseRotation + details.rotation;
      _overlayOffset += details.focalPointDelta;
    });
  }

  void _resetOverlayTransform() {
    setState(() {
      _overlayOffset = Offset.zero;
      _overlayScale = 1.0;
      _overlayRotation = 0.0;
    });
  }

  Future<void> _pickOverlayFromGallery() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      setState(() {
        _overlayFile = File(picked.path);
        _resetOverlayTransform();
      });
    } catch (_) {
      _toast('갤러리에서 이미지를 불러오지 못했습니다.');
    }
  }

  /// 프리뷰 상태에서 현재 화면을 캡처해 오버레이로 사용 (저장하지 않음).
  Future<void> _snapshotToOverlay() async {
    if (!_isReady || _busy || _isRecording) return;
    setState(() => _busy = true);
    try {
      final saved = await _grabStill('overlay');
      if (saved == null) {
        _toast('스냅샷을 찍지 못했습니다.');
        return;
      }
      setState(() {
        _overlayFile = saved;
        _resetOverlayTransform();
      });
      _toast('현재 화면을 오버레이로 저장했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 촬영
  // ---------------------------------------------------------------------------

  Future<void> _takePhoto() async {
    if (!_isReady || _busy || _isRecording) return;
    setState(() => _busy = true);
    try {
      final saved = await _grabStill('photo');
      if (saved == null) {
        _toast('사진을 찍지 못했습니다.');
        return;
      }
      await _saveImageToGallery(saved.path);
      if (_autoUseLastShot) {
        setState(() {
          _overlayFile = saved;
          _resetOverlayTransform();
        });
      }
      _toast(_silentShutter ? '무음으로 사진을 저장했습니다.' : '사진을 갤러리에 저장했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 정지 이미지 한 장을 앱 폴더에 저장하고 File을 돌려준다. 실패 시 null.
  /// 무음 모드면 셔터음 없이 촬영하는 방식을 사용한다.
  Future<File?> _grabStill(String prefix) async {
    if (_silentShutter) return _grabSilentStill(prefix);
    try {
      final shot = await _controller!.takePicture();
      return _copyToAppDir(shot.path, prefix);
    } on CameraException {
      return null;
    }
  }

  /// 셔터음이 강제되는 기기 대응: 아주 짧게 동영상을 녹화한 뒤 첫 프레임을 뽑아
  /// 정지 이미지로 저장한다. 동영상 녹화 경로에는 셔터음이 없다.
  Future<File?> _grabSilentStill(String prefix) async {
    final controller = _controller!;
    String? clipPath;
    String? framePath;
    try {
      await controller.startVideoRecording();
      await Future<void>.delayed(const Duration(milliseconds: 550));
      final clip = await controller.stopVideoRecording();
      clipPath = clip.path;

      framePath = await vt.VideoThumbnail.thumbnailFile(
        video: clip.path,
        imageFormat: vt.ImageFormat.JPEG,
        timeMs: 0,
        quality: 95,
      );
      if (framePath == null) return null;
      return await _copyToAppDir(framePath, prefix, ext: 'jpg');
    } on CameraException {
      return null;
    } finally {
      for (final path in [clipPath, framePath]) {
        if (path == null) continue;
        try {
          final f = File(path);
          if (f.existsSync()) await f.delete();
        } catch (_) {
          // 임시 파일 정리 실패는 무시
        }
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (!_isReady || _busy) return;

    if (_isRecording) {
      setState(() => _busy = true);
      try {
        final file = await _controller!.stopVideoRecording();
        setState(() => _isRecording = false);
        final saved = await _copyToAppDir(file.path, 'video', ext: 'mp4');
        await _saveVideoToGallery(saved.path);
        if (_autoUseLastShot) {
          await _setOverlayFromVideoLastFrame(saved.path);
        }
        _toast('동영상을 갤러리에 저장했습니다.');
      } on CameraException {
        _toast('동영상 저장에 실패했습니다.');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() => _isRecording = true);
      } on CameraException {
        _toast('녹화를 시작하지 못했습니다.');
      }
    }
  }

  Future<void> _setOverlayFromVideoLastFrame(String videoPath) async {
    try {
      final vp = VideoPlayerController.file(File(videoPath));
      await vp.initialize();
      final durationMs = vp.value.duration.inMilliseconds;
      await vp.dispose();

      final targetMs = durationMs > 200 ? durationMs - 120 : 0;
      final thumbPath = await vt.VideoThumbnail.thumbnailFile(
        video: videoPath,
        imageFormat: vt.ImageFormat.PNG,
        timeMs: targetMs,
        quality: 100,
      );
      if (thumbPath == null) return;
      setState(() {
        _overlayFile = File(thumbPath);
        _resetOverlayTransform();
      });
    } catch (_) {
      // 마지막 프레임 추출 실패는 조용히 무시
    }
  }

  // ---------------------------------------------------------------------------
  // 파일 / 갤러리
  // ---------------------------------------------------------------------------

  Future<File> _copyToAppDir(
    String sourcePath,
    String prefix, {
    String ext = 'jpg',
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final dest = File('${dir.path}/$name');
    await File(sourcePath).copy(dest.path);
    return dest;
  }

  Future<void> _saveImageToGallery(String path) async {
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) await Gal.requestAccess();
      await Gal.putImage(path, album: 'GhostCamera');
    } on GalException {
      _toast('갤러리 저장 권한을 확인해 주세요.');
    }
  }

  Future<void> _saveVideoToGallery(String path) async {
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) await Gal.requestAccess();
      await Gal.putVideo(path, album: 'GhostCamera');
    } on GalException {
      _toast('갤러리 저장 권한을 확인해 주세요.');
    }
  }

  // ---------------------------------------------------------------------------
  // 기타 컨트롤
  // ---------------------------------------------------------------------------

  Future<void> _flipCamera() async {
    if (cameras.length < 2 || _isRecording || _busy) return;
    _cameraIndex = (_cameraIndex + 1) % cameras.length;
    await _initCamera(_cameraIndex);
  }

  Future<void> _cycleFlash() async {
    if (!_isReady) return;
    const order = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
    final next = order[(order.indexOf(_flashMode) + 1) % order.length];
    try {
      await _controller!.setFlashMode(next);
      setState(() => _flashMode = next);
    } on CameraException {
      _toast('이 기기에서는 플래시를 사용할 수 없습니다.');
    }
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _statusMessage != null
          ? _MessageView(
              message: _statusMessage!,
              onOpenSettings: openAppSettings,
            )
          : !_isReady
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPreview(),
                    if (_overlayFile != null) _buildOverlay(),
                    _buildGrid(),
                    _buildTopBar(),
                    _buildRightControls(),
                    _buildBottomBar(),
                  ],
                ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller!;
    final mediaSize = MediaQuery.of(context).size;
    var scale = mediaSize.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }

  Widget _buildOverlay() {
    Widget image = Image.file(_overlayFile!, fit: BoxFit.contain);
    image = Transform.scale(scale: _overlayScale, child: image);
    image = Transform.rotate(angle: _overlayRotation, child: image);
    image = Transform.translate(offset: _overlayOffset, child: image);
    image = Opacity(opacity: _overlayOpacity, child: image);

    if (_overlayLocked) {
      return IgnorePointer(child: image);
    }
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: image,
    );
  }

  Widget _buildGrid() {
    return IgnorePointer(
      child: CustomPaint(painter: _GridPainter(), size: Size.infinite),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  _silentShutter ? Icons.volume_off : Icons.volume_up,
                  color: _silentShutter ? Colors.amber : Colors.white,
                ),
                tooltip: '무음 촬영',
                onPressed: () =>
                    setState(() => _silentShutter = !_silentShutter),
              ),
              IconButton(
                icon: Icon(_flashIcon, color: Colors.white),
                onPressed: _cycleFlash,
              ),
              IconButton(
                icon: Icon(
                  _overlayLocked ? Icons.lock : Icons.lock_open,
                  color: _overlayLocked ? Colors.amber : Colors.white,
                ),
                tooltip: '오버레이 고정',
                onPressed: _overlayFile == null
                    ? null
                    : () => setState(() => _overlayLocked = !_overlayLocked),
              ),
              IconButton(
                icon: const Icon(Icons.restart_alt, color: Colors.white),
                tooltip: '오버레이 위치 초기화',
                onPressed: _overlayFile == null ? null : _resetOverlayTransform,
              ),
              IconButton(
                icon: Icon(
                  Icons.hide_image_outlined,
                  color: _overlayFile == null ? Colors.white24 : Colors.white,
                ),
                tooltip: '오버레이 제거',
                onPressed: _overlayFile == null
                    ? null
                    : () => setState(() {
                          _overlayFile = null;
                          _overlayLocked = false;
                        }),
              ),
              IconButton(
                icon: Icon(
                  Icons.auto_mode,
                  color: _autoUseLastShot ? Colors.amber : Colors.white,
                ),
                tooltip: '촬영 후 마지막 컷을 오버레이로',
                onPressed: () =>
                    setState(() => _autoUseLastShot = !_autoUseLastShot),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightControls() {
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.opacity, color: Colors.white, size: 18),
              SizedBox(
                width: 40,
                height: 200,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: _overlayOpacity,
                      onChanged: _overlayFile == null
                          ? null
                          : (v) => setState(() => _overlayOpacity = v),
                    ),
                  ),
                ),
              ),
              Text(
                '${(_overlayOpacity * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundButton(
                icon: Icons.photo_library_outlined,
                onPressed: _busy ? null : _pickOverlayFromGallery,
                label: '갤러리',
              ),
              _RoundButton(
                icon: Icons.camera_alt_outlined,
                onPressed: _busy || _isRecording ? null : _takePhoto,
                label: '사진',
                big: true,
              ),
              _RoundButton(
                icon: _isRecording ? Icons.stop : Icons.fiber_manual_record,
                iconColor: Colors.redAccent,
                onPressed: _busy ? null : _toggleRecording,
                label: _isRecording ? '정지' : '동영상',
                big: true,
              ),
              _RoundButton(
                icon: Icons.center_focus_strong,
                onPressed: _busy || _isRecording ? null : _snapshotToOverlay,
                label: '스냅샷',
              ),
              _RoundButton(
                icon: Icons.cameraswitch_outlined,
                onPressed:
                    _busy || _isRecording || cameras.length < 2 ? null : _flipCamera,
                label: '전환',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onPressed,
    required this.label,
    this.big = false,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String label;
  final bool big;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final size = big ? 64.0 : 48.0;
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
                size: big ? 30 : 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.onOpenSettings});

  final String message;
  final VoidCallback onOpenSettings;

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
            OutlinedButton(
              onPressed: onOpenSettings,
              child: const Text('설정 열기'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3분할 정렬 그리드.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
