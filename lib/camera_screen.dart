import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'camera_hud.dart';
import 'camera_session.dart';
import 'camera_widgets.dart';
import 'gallery_store.dart';
import 'location_stamp_controller.dart';
import 'overlay_controller.dart';
import 'settings_store.dart';
import 'ui_metrics.dart';
import 'work_dir.dart';

/// 라이브 카메라 프리뷰 위에 반투명 참조 사진(고스트)을 겹쳐 보여주고,
/// 그 사진에 인물 위치·크기를 맞춰 사진/동영상을 촬영하는 화면.
///
/// 상태는 세 컨트롤러가 나눠 갖는다: [CameraSession](카메라·촬영),
/// [LocationStampController](날짜·장소 스탬프), [OverlayController](고스트 오버레이).
/// HUD 위젯은 `camera_hud.dart`에 있고, 이 위젯은 컨트롤러 배선과 촬영 흐름 조율,
/// 그리고 컨트롤러별 [ListenableBuilder] 조립만 담당한다.
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
  late final OverlayController _overlay;
  late final GalleryStore _gallery;

  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _session = CameraSession(workDir: _workDir, onMessage: _toast)..attach();
    _stamp = LocationStampController(onMessage: _toast);
    _overlay = OverlayController(workDir: _workDir);
    _gallery = GalleryStore(onMessage: _toast);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _session.dispose();
    _stamp.dispose();
    _overlay.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!_settingsLoaded) {
      try {
        final s = await SettingsStore.load();
        if (!mounted) return;
        _settingsLoaded = true;
        _session.settings = s;
        _session.hydrate(s);
        _stamp.hydrate(s);
        _overlay.hydrate(s);
      } on Exception catch (e) {
        debugPrint('설정 로드 실패: $e');
      }
    }

    await _session.bootstrap();
    if (!mounted) return;
    unawaited(_workDir.prune(keepPath: _overlay.file?.path));
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
      if (_overlay.autoUseLast) {
        _overlay.setFile(finalFile);
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
      _overlay.setFile(file);
      _toast('현재 화면을 오버레이로 사용합니다.');
    });
  }

  Future<void> _toggleRecording() async {
    await _session.toggleRecording(onStopped: (mp4) async {
      await _gallery.saveVideo(mp4.path);
      if (_overlay.autoUseLast) {
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
      _overlay.setFile(owned);
    } on Exception catch (e) {
      debugPrint('마지막 프레임 추출 실패: $e');
    } finally {
      if (thumbPath != null && thumbPath != _overlay.file?.path) {
        try {
          final f = File(thumbPath);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _pickOverlayFromGallery() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      _overlay.setFile(File(picked.path));
    } on Exception catch (e) {
      debugPrint('오버레이 이미지 불러오기 실패: $e');
      _toast('갤러리에서 이미지를 불러오지 못했습니다.');
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
  // 조립
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final m = Metrics(MediaQuery.of(context));
    return Scaffold(
      backgroundColor: Colors.black,
      // 시스템 글꼴 확대가 카메라 HUD를 깨뜨리지 않도록 배율을 제한한다.
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        // 카메라 상태(에러/준비)만 게이트에서 처리하고, 준비된 화면은 child로 넘겨
        // 잦은 세션 알림에도 Stack 자체는 다시 만들지 않는다.
        child: ListenableBuilder(
          listenable: _session,
          builder: (context, child) {
            if (_session.statusMessage != null) {
              return MessageView(
                message: _session.statusMessage!,
                onOpenSettings: openAppSettings,
                onRetry: _bootstrap,
              );
            }
            if (!_session.isReady) {
              return const Center(child: CircularProgressIndicator());
            }
            return child!;
          },
          child: _buildReadyStack(m),
        ),
      ),
    );
  }

  /// 준비된 화면. 컨트롤러별 [ListenableBuilder]로 서브트리를 나눠, 한 컨트롤러의
  /// 갱신(예: 오버레이 드래그)이 무관한 서브트리(프리뷰 등)를 리빌드하지 않게 한다.
  Widget _buildReadyStack(Metrics m) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ListenableBuilder(
          listenable: _session,
          builder: (_, _) => CameraPreviewArea(session: _session),
        ),
        ListenableBuilder(
          listenable: _overlay,
          builder: (_, _) => OverlayLayer(overlay: _overlay),
        ),
        const GridOverlay(),
        ListenableBuilder(
          listenable: _overlay,
          builder: (_, _) => OverlayQuickClear(overlay: _overlay, metrics: m),
        ),
        ListenableBuilder(
          listenable: _stamp,
          builder: (_, _) => StampPreview(stamp: _stamp, metrics: m),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_session, _stamp, _overlay]),
          builder: (_, _) => TopBar(
            session: _session,
            stamp: _stamp,
            overlay: _overlay,
            metrics: m,
          ),
        ),
        ListenableBuilder(
          listenable: _overlay,
          builder: (_, _) => RightControls(overlay: _overlay, metrics: m),
        ),
        ListenableBuilder(
          listenable: _stamp,
          builder: (_, _) => StampCornerPicker(stamp: _stamp, metrics: m),
        ),
        ListenableBuilder(
          listenable: _session,
          builder: (_, _) => BottomBar(
            session: _session,
            metrics: m,
            onPickGallery: _pickOverlayFromGallery,
            onTakePhoto: _takePhoto,
            onToggleRecording: _toggleRecording,
            onSnapshot: _snapshotToOverlay,
          ),
        ),
      ],
    );
  }
}
