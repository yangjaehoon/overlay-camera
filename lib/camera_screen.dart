import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'camera_session.dart';
import 'camera_widgets.dart';
import 'gallery_store.dart';
import 'location_stamp_controller.dart';
import 'photo_stamp.dart';
import 'settings_store.dart';
import 'ui_metrics.dart';
import 'work_dir.dart';

IconData _flashIcon(FlashMode mode) {
  switch (mode) {
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

/// 라이브 카메라 프리뷰 위에 반투명 참조 사진(고스트)을 겹쳐 보여주고,
/// 그 사진에 인물 위치·크기를 맞춰 사진/동영상을 촬영하는 화면.
///
/// 카메라 생명주기·촬영은 [CameraSession], 날짜·장소 스탬프는
/// [LocationStampController]가 담당하고, 이 위젯은 오버레이 상태와 화면 조립만 맡는다.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final WorkDir _workDir = WorkDir();
  final ImagePicker _picker = ImagePicker();

  late final CameraSession _session;
  late final LocationStampController _stamp;
  late final GalleryStore _gallery;

  SettingsStore? _settings;

  // 고스트 오버레이 상태
  File? _overlayFile;
  double _overlayOpacity = 0.45;
  Offset _overlayOffset = Offset.zero;
  double _overlayScale = 1.0;
  double _overlayRotation = 0.0;
  bool _overlayLocked = false;
  bool _autoUseLastShot = true;

  // 제스처 시작 시점 기준값
  double _gestureBaseScale = 1.0;
  double _gestureBaseRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _session = CameraSession(workDir: _workDir, onMessage: _toast)..attach();
    _stamp = LocationStampController(onMessage: _toast);
    _gallery = GalleryStore(onMessage: _toast);
    _session.addListener(_onControllerChange);
    _stamp.addListener(_onControllerChange);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _session.removeListener(_onControllerChange);
    _stamp.removeListener(_onControllerChange);
    _session.dispose();
    _stamp.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    if (_settings == null) {
      try {
        final s = await SettingsStore.load();
        if (!mounted) return;
        _settings = s;
        _session.settings = s;
        _session.hydrate(s);
        _stamp.hydrate(s);
        setState(() {
          _autoUseLastShot = s.autoUseLastShot;
          _overlayOpacity = s.overlayOpacity;
        });
      } on Exception catch (e) {
        debugPrint('설정 로드 실패: $e');
      }
    }

    await _session.bootstrap();
    if (!mounted) return;
    unawaited(_workDir.prune(keepPath: _overlayFile?.path));
  }

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

  /// 오버레이 이미지를 교체한다. 이전 파일이 작업 폴더 소유면 삭제한다.
  void _setOverlay(File file) {
    if (!mounted) return;
    final old = _overlayFile;
    setState(() => _overlayFile = file);
    _resetOverlayTransform();
    if (old != null && old.path != file.path) _workDir.deleteIfOwned(old);
  }

  void _clearOverlay() {
    final old = _overlayFile;
    setState(() {
      _overlayFile = null;
      _overlayLocked = false;
    });
    if (old != null) _workDir.deleteIfOwned(old);
  }

  Future<void> _pickOverlayFromGallery() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      _setOverlay(File(picked.path));
    } on Exception catch (e) {
      debugPrint('오버레이 이미지 불러오기 실패: $e');
      _toast('갤러리에서 이미지를 불러오지 못했습니다.');
    }
  }

  void _setOpacity(double value) {
    setState(() => _overlayOpacity = value);
  }

  void _toggleAutoOverlay() {
    setState(() => _autoUseLastShot = !_autoUseLastShot);
    _settings?.setAutoUseLastShot(_autoUseLastShot);
  }

  // ---------------------------------------------------------------------------
  // 촬영 흐름 (프리미티브는 CameraSession, 후처리는 여기서 조립)
  // ---------------------------------------------------------------------------

  Future<void> _takePhoto() async {
    if (!_session.isReady || _session.isRecording) return;
    await _session.runExclusive(() async {
      final raw = await _session.capturePhoto();
      if (raw == null) {
        _toast('사진을 찍지 못했습니다.');
        return;
      }
      final finalFile = await _stamp.applyTo(raw);
      if (finalFile.path != raw.path) _workDir.deleteIfOwned(raw);
      await _gallery.saveImage(finalFile.path);
      if (_autoUseLastShot) {
        _setOverlay(finalFile);
      } else {
        _workDir.deleteIfOwned(finalFile);
      }
      _toast(
        _session.silentShutter ? '무음으로 사진을 저장했습니다.' : '사진을 갤러리에 저장했습니다.',
      );
    });
  }

  Future<void> _snapshotToOverlay() async {
    if (!_session.isReady || _session.isRecording) return;
    await _session.runExclusive(() async {
      final file = await _session.captureSnapshot();
      if (file == null) {
        _toast('스냅샷을 찍지 못했습니다.');
        return;
      }
      _setOverlay(file);
      _toast('현재 화면을 오버레이로 사용합니다.');
    });
  }

  Future<void> _toggleRecording() async {
    await _session.toggleRecording(onStopped: (mp4) async {
      await _gallery.saveVideo(mp4.path);
      if (_autoUseLastShot) {
        await _setOverlayFromVideoLastFrame(mp4.path);
      }
      _workDir.deleteIfOwned(mp4);
      _toast('동영상을 갤러리에 저장했습니다.');
    });
  }

  Future<void> _setOverlayFromVideoLastFrame(String videoPath) async {
    String? thumbPath;
    try {
      final vp = VideoPlayerController.file(File(videoPath));
      await vp.initialize();
      final durationMs = vp.value.duration.inMilliseconds;
      await vp.dispose();

      // 정지 직전 프레임(끝에서 살짝 앞)을 노린다.
      const endOffsetMs = 120;
      final targetMs = durationMs > 200 ? durationMs - endOffsetMs : 0;
      thumbPath = await vt.VideoThumbnail.thumbnailFile(
        video: videoPath,
        imageFormat: vt.ImageFormat.PNG,
        timeMs: targetMs,
        quality: 100,
      );
      if (thumbPath == null) return;
      final owned = await _workDir.copyInto(thumbPath, 'overlay', ext: 'png');
      _setOverlay(owned);
    } on Exception catch (e) {
      debugPrint('마지막 프레임 추출 실패: $e');
    } finally {
      if (thumbPath != null && thumbPath != _overlayFile?.path) {
        try {
          final f = File(thumbPath);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 기타
  // ---------------------------------------------------------------------------

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
    final m = Metrics(MediaQuery.of(context));
    return Scaffold(
      backgroundColor: Colors.black,
      // 시스템 글꼴 확대가 카메라 HUD를 깨뜨리지 않도록 배율을 제한한다.
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: _session.statusMessage != null
            ? MessageView(
                message: _session.statusMessage!,
                onOpenSettings: openAppSettings,
                onRetry: _bootstrap,
              )
            : !_session.isReady
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPreview(),
                      if (_overlayFile != null) _buildOverlay(),
                      _buildGrid(),
                      if (_stamp.enabled) _buildStampPreview(m),
                      _buildTopBar(m),
                      _buildRightControls(m),
                      if (_stamp.enabled) _buildStampCornerPicker(m),
                      _buildBottomBar(m),
                    ],
                  ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _session.controller!;
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
      child: CustomPaint(painter: GridPainter(), size: Size.infinite),
    );
  }

  Widget _buildTopBar(Metrics m) {
    final btn = m.spc(38, 34.0, 52.0);
    final icon = m.spc(21, 19.0, 28.0);
    final maxW = m.size.width - m.sp(16);
    final hasOverlay = _overlayFile != null;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: m.sp(8), vertical: m.sp(8)),
          padding: EdgeInsets.symmetric(horizontal: m.sp(4)),
          constraints: BoxConstraints(maxWidth: m.isTablet ? 560.0 : maxW),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(m.sp(28)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BarButton(
                  icon: _session.silentShutter
                      ? Icons.volume_off
                      : Icons.volume_up,
                  color: _session.silentShutter ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '무음 촬영',
                  onTap: _session.toggleSilentShutter,
                ),
                BarButton(
                  icon: Icons.today,
                  color: _stamp.enabled ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '날짜·장소 표시',
                  onTap: _stamp.toggle,
                ),
                BarButton(
                  icon: _flashIcon(_session.flashMode),
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '플래시',
                  onTap: _session.cycleFlash,
                ),
                BarButton(
                  icon: _overlayLocked ? Icons.lock : Icons.lock_open,
                  color: _overlayLocked ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 고정',
                  onTap: hasOverlay
                      ? () => setState(() => _overlayLocked = !_overlayLocked)
                      : null,
                ),
                BarButton(
                  icon: Icons.restart_alt,
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 위치 초기화',
                  onTap: hasOverlay ? _resetOverlayTransform : null,
                ),
                BarButton(
                  icon: Icons.hide_image_outlined,
                  color: Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '오버레이 제거',
                  onTap: hasOverlay ? _clearOverlay : null,
                ),
                BarButton(
                  icon: Icons.auto_mode,
                  color: _autoUseLastShot ? Colors.amber : Colors.white,
                  size: btn,
                  iconSize: icon,
                  tooltip: '촬영 후 마지막 컷을 오버레이로',
                  onTap: _toggleAutoOverlay,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 선택한 모서리에 찍힐 스탬프 문구 미리보기.
  Widget _buildStampPreview(Metrics m) {
    // 위/아래 컨트롤과 겹치지 않도록 스케일된 컴포넌트 높이만큼 여백을 둔다.
    final topClear = m.sp(52) + m.sp(34) * 2 + m.sp(40) + m.sp(12);
    final bottomClear = m.sp(58) + m.sp(22) + m.sp(18);
    final corner = _stamp.corner;
    return IgnorePointer(
      child: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: m.sp(14), vertical: m.sp(12)),
        child: Align(
          alignment: corner.alignment,
          child: Padding(
            padding: EdgeInsets.only(
              top: corner.isTop ? topClear : 0,
              bottom: corner.isTop ? 0 : bottomClear,
            ),
            child: Text(
              _stamp.previewText(),
              textAlign: corner.isLeft ? TextAlign.left : TextAlign.right,
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
  Widget _buildStampCornerPicker(Metrics m) {
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

  Widget _stampCornerButton(StampCorner corner, Metrics m) {
    final active = _stamp.corner == corner;
    final r = m.sp(8);
    return Padding(
      padding: EdgeInsets.all(m.sp(3)),
      child: Material(
        color: active ? Colors.amber : Colors.white24,
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: () => _stamp.selectCorner(corner),
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

  Widget _buildRightControls(Metrics m) {
    final sliderLen = (m.size.height * 0.30)
        .clamp(140.0, m.isTablet ? 420.0 : 260.0)
        .toDouble();
    final hasOverlay = _overlayFile != null;
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
                      onChanged: hasOverlay ? _setOpacity : null,
                      onChangeEnd: hasOverlay
                          ? (v) => _settings?.setOverlayOpacity(v)
                          : null,
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

  Widget _buildBottomBar(Metrics m) {
    final busy = _session.busy;
    final recording = _session.isRecording;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding:
              EdgeInsets.only(bottom: m.sp(20), left: m.sp(4), right: m.sp(4)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: m.size.width < 560 ? m.size.width : 560.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                RoundButton(
                  icon: Icons.photo_library_outlined,
                  onPressed: busy ? null : _pickOverlayFromGallery,
                  label: '갤러리',
                  scale: m.scale,
                ),
                RoundButton(
                  icon: Icons.camera_alt_outlined,
                  onPressed: busy || recording ? null : _takePhoto,
                  label: '사진',
                  big: true,
                  scale: m.scale,
                ),
                RoundButton(
                  icon: recording ? Icons.stop : Icons.fiber_manual_record,
                  iconColor: Colors.redAccent,
                  onPressed: busy ? null : _toggleRecording,
                  label: recording ? '정지' : '동영상',
                  big: true,
                  scale: m.scale,
                ),
                RoundButton(
                  icon: Icons.center_focus_strong,
                  onPressed: busy || recording ? null : _snapshotToOverlay,
                  label: '스냅샷',
                  scale: m.scale,
                ),
                RoundButton(
                  icon: Icons.cameraswitch_outlined,
                  onPressed: busy || recording || !_session.canFlip
                      ? null
                      : _session.flip,
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
