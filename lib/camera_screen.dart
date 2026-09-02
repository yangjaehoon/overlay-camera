import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'main.dart';
import 'photo_stamp.dart';

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

  // 날짜·장소 스탬프
  bool _stampEnabled = false;
  StampCorner _stampCorner = StampCorner.bottomRight;
  String? _stampPlace;
  bool _resolvingPlace = false;

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
      final finalFile = await _maybeStamp(saved);
      await _saveImageToGallery(finalFile.path);
      if (_autoUseLastShot) {
        setState(() {
          _overlayFile = finalFile;
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

  /// 스탬프 옵션이 켜져 있으면 사진에 날짜·장소를 그려 넣은 새 파일을 돌려준다.
  Future<File> _maybeStamp(File src) async {
    if (!_stampEnabled) return src;
    try {
      return await stampPhoto(
        src,
        text: buildStampText(DateTime.now(), _stampPlace),
        corner: _stampCorner,
      );
    } catch (_) {
      _toast('스탬프를 적용하지 못해 원본으로 저장합니다.');
      return src;
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
  // 날짜·장소 스탬프
  // ---------------------------------------------------------------------------

  void _toggleStamp() {
    final next = !_stampEnabled;
    setState(() => _stampEnabled = next);
    // 켤 때마다 현재 위치를 다시 확인한다. (장소가 바뀐 뒤 다시 켜면 갱신)
    if (next) _refreshStampPlace();
  }

  /// 현재 위치를 역지오코딩해 스탬프에 넣을 장소명을 갱신한다.
  /// 권한이 없거나 실패하면 장소 없이 날짜만 찍힌다.
  Future<void> _refreshStampPlace() async {
    if (_resolvingPlace) return;
    setState(() => _resolvingPlace = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('위치 서비스가 꺼져 있어 날짜만 표시됩니다.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast('위치 권한이 없어 날짜만 표시됩니다.');
        return;
      }

      var position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));

      final marks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (!mounted || marks.isEmpty) return;
      final m = marks.first;
      final tokens = <String?>[
        m.administrativeArea,
        m.locality,
        m.subLocality,
      ].map((e) => e?.trim()).where((e) => e != null && e.isNotEmpty).cast<String>().toList();
      final place =
          (tokens.length > 2 ? tokens.sublist(tokens.length - 2) : tokens)
              .join(' ');
      setState(() => _stampPlace = place.isEmpty ? null : place);
    } on TimeoutException {
      _toast('위치를 확인하지 못해 날짜만 표시됩니다.');
    } catch (_) {
      // 그 외 실패도 날짜만
    } finally {
      if (mounted) setState(() => _resolvingPlace = false);
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

  /// 화면 크기에 따른 반응형 치수. iPhone mini부터 태블릿까지 대응.
  _Metrics get _m => _Metrics(MediaQuery.of(context));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // 시스템 글꼴 확대가 카메라 HUD를 깨뜨리지 않도록 배율을 제한한다.
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: _statusMessage != null
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
                      if (_stampEnabled) _buildStampPreview(),
                      _buildTopBar(),
                      _buildRightControls(),
                      if (_stampEnabled) _buildStampCornerPicker(),
                      _buildBottomBar(),
                    ],
                  ),
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
    final m = _m;
    final btn = m.spc(38, 34.0, 52.0);
    final icon = m.spc(21, 19.0, 28.0);
    final maxW = m.size.width - m.sp(16);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: m.sp(8), vertical: m.sp(8)),
          padding: EdgeInsets.symmetric(horizontal: m.sp(4)),
          constraints: BoxConstraints(
            maxWidth: m.isTablet ? 560.0 : maxW,
          ),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(m.sp(28)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BarButton(
                  icon: _silentShutter ? Icons.volume_off : Icons.volume_up,
                  color: _silentShutter ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '무음 촬영',
                  onTap: () =>
                      setState(() => _silentShutter = !_silentShutter),
                ),
                _BarButton(
                  icon: Icons.today,
                  color: _stampEnabled ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '날짜·장소 표시',
                  onTap: _toggleStamp,
                ),
                _BarButton(
                  icon: _flashIcon,
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '플래시',
                  onTap: _cycleFlash,
                ),
                _BarButton(
                  icon: _overlayLocked ? Icons.lock : Icons.lock_open,
                  color: _overlayLocked ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 고정',
                  onTap: _overlayFile == null
                      ? null
                      : () => setState(() => _overlayLocked = !_overlayLocked),
                ),
                _BarButton(
                  icon: Icons.restart_alt,
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 위치 초기화',
                  onTap: _overlayFile == null ? null : _resetOverlayTransform,
                ),
                _BarButton(
                  icon: Icons.hide_image_outlined,
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 제거',
                  onTap: _overlayFile == null
                      ? null
                      : () => setState(() {
                            _overlayFile = null;
                            _overlayLocked = false;
                          }),
                ),
                _BarButton(
                  icon: Icons.auto_mode,
                  color: _autoUseLastShot ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '촬영 후 마지막 컷을 오버레이로',
                  onTap: () =>
                      setState(() => _autoUseLastShot = !_autoUseLastShot),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 선택한 모서리에 찍힐 스탬프 문구 미리보기.
  Widget _buildStampPreview() {
    final m = _m;
    final placeHint = _stampPlace ?? (_resolvingPlace ? '위치 확인 중…' : null);
    // 위/아래 컨트롤과 겹치지 않도록 스케일된 컴포넌트 높이만큼 여백을 둔다.
    final topClear = m.sp(52) + m.sp(34) * 2 + m.sp(40) + m.sp(12);
    final bottomClear = m.sp(58) + m.sp(22) + m.sp(18);
    return IgnorePointer(
      child: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: m.sp(14), vertical: m.sp(12)),
        child: Align(
          alignment: _stampCorner.alignment,
          child: Padding(
            padding: EdgeInsets.only(
              top: _stampCorner.isTop ? topClear : 0,
              bottom: _stampCorner.isTop ? 0 : bottomClear,
            ),
            child: Text(
              buildStampText(DateTime.now(), placeHint),
              textAlign: _stampCorner.isLeft ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                color: Colors.white,
                fontSize: m.spc(15, 13.0, 22.0),
                fontWeight: FontWeight.w600,
                height: 1.25,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 4),
                  Shadow(color: Colors.black54, blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 스탬프 위치(4모서리) 선택 패널.
  Widget _buildStampCornerPicker() {
    final m = _m;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: EdgeInsets.only(top: m.sp(52)),
          padding: EdgeInsets.fromLTRB(m.sp(10), m.sp(8), m.sp(10), m.sp(10)),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(m.sp(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '스탬프 위치',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: m.spc(11, 10.0, 15.0),
                ),
              ),
              SizedBox(height: m.sp(6)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stampCornerButton(StampCorner.topLeft, m),
                  _stampCornerButton(StampCorner.topRight, m),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stampCornerButton(StampCorner.bottomLeft, m),
                  _stampCornerButton(StampCorner.bottomRight, m),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stampCornerButton(StampCorner corner, _Metrics m) {
    final active = _stampCorner == corner;
    final r = m.sp(8);
    return Padding(
      padding: EdgeInsets.all(m.sp(3)),
      child: Material(
        color: active ? Colors.amber : Colors.white24,
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: () => setState(() => _stampCorner = corner),
          child: SizedBox(
            width: m.spc(50, 44.0, 72.0),
            height: m.spc(34, 30.0, 48.0),
            child: Align(
              alignment: corner.alignment,
              child: Padding(
                padding: EdgeInsets.all(m.sp(5)),
                child: Container(
                  width: m.sp(15),
                  height: m.sp(6),
                  decoration: BoxDecoration(
                    color: active ? Colors.black87 : Colors.white70,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightControls() {
    final m = _m;
    final sliderLen = (m.size.height * 0.30)
        .clamp(140.0, m.isTablet ? 420.0 : 260.0)
        .toDouble();
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: EdgeInsets.only(right: m.sp(6)),
          padding: EdgeInsets.symmetric(vertical: m.sp(12)),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(m.sp(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.opacity,
                  color: Colors.white, size: m.spc(18, 16.0, 26.0)),
              SizedBox(
                width: m.spc(40, 36.0, 52.0),
                height: sliderLen,
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
                style: TextStyle(
                  color: Colors.white,
                  fontSize: m.spc(12, 11.0, 16.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final m = _m;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: m.sp(20), left: m.sp(4), right: m.sp(4)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: m.size.width < 560 ? m.size.width : 560.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundButton(
                  icon: Icons.photo_library_outlined,
                  onPressed: _busy ? null : _pickOverlayFromGallery,
                  label: '갤러리',
                  scale: m.scale,
                ),
                _RoundButton(
                  icon: Icons.camera_alt_outlined,
                  onPressed: _busy || _isRecording ? null : _takePhoto,
                  label: '사진',
                  big: true,
                  scale: m.scale,
                ),
                _RoundButton(
                  icon: _isRecording ? Icons.stop : Icons.fiber_manual_record,
                  iconColor: Colors.redAccent,
                  onPressed: _busy ? null : _toggleRecording,
                  label: _isRecording ? '정지' : '동영상',
                  big: true,
                  scale: m.scale,
                ),
                _RoundButton(
                  icon: Icons.center_focus_strong,
                  onPressed: _busy || _isRecording ? null : _snapshotToOverlay,
                  label: '스냅샷',
                  scale: m.scale,
                ),
                _RoundButton(
                  icon: Icons.cameraswitch_outlined,
                  onPressed: _busy || _isRecording || cameras.length < 2
                      ? null
                      : _flipCamera,
                  label: '전환',
                  scale: m.scale,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 화면 크기 기반 반응형 치수. iPhone mini(~320~375)부터 태블릿(>=600)까지 대응.
class _Metrics {
  _Metrics(MediaQueryData mq)
      : size = mq.size,
        padding = mq.padding,
        _shortest = mq.size.shortestSide;

  final Size size;
  final EdgeInsets padding;
  final double _shortest;

  bool get isTablet => _shortest >= 600;

  /// 기준 폭 390 대비 배율. 폰은 0.82~1.15, 태블릿은 1.3 고정.
  double get scale => isTablet
      ? 1.3
      : (_shortest / 390).clamp(0.82, 1.15).toDouble();

  /// 스케일이 적용된 크기.
  double sp(double v) => v * scale;

  /// 스케일 적용 후 [lo]~[hi]로 제한한 크기.
  double spc(double v, double lo, double hi) =>
      (v * scale).clamp(lo, hi).toDouble();
}

/// 상단 바용 소형 아이콘 버튼.
class _BarButton extends StatelessWidget {
  const _BarButton({
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
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: size * 0.6,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: onTap == null ? Colors.white24 : color,
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
