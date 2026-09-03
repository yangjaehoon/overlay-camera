import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'settings_store.dart';
import 'work_dir.dart';

/// 카메라 컨트롤러의 생명주기와 촬영(사진·무음·동영상)을 담당한다.
/// 상태 변경 시 [notifyListeners]로 알리고, 안내 메시지는 [onMessage]로 전달한다.
class CameraSession extends ChangeNotifier with WidgetsBindingObserver {
  CameraSession({required this.workDir, this.onMessage});

  final WorkDir workDir;
  final void Function(String message)? onMessage;

  /// 설정 저장소. 로드 후 주입된다.
  SettingsStore? settings;

  /// 촬영 해상도. 사진·무음 캡처·영상 마지막 프레임 화질을 모두 결정한다.
  /// (올리면 stampPhoto 메모리 사용량도 비례해 커진다)
  static const _resolution = ResolutionPreset.high;

  /// 무음 촬영 시 몰래 녹화하는 길이. 첫 프레임만 뽑으므로 짧을수록 좋다.
  static const _silentClipDuration = Duration(milliseconds: 550);

  final List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _index = 0;
  FlashMode _flashMode = FlashMode.off;
  bool _isRecording = false;
  bool _busy = false;
  bool _bootstrapping = false;
  String? _statusMessage;
  bool _silentShutter = false;
  bool _disposed = false;

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized ?? false;
  bool get isRecording => _isRecording;
  bool get busy => _busy;
  String? get statusMessage => _statusMessage;
  FlashMode get flashMode => _flashMode;
  bool get silentShutter => _silentShutter;
  bool get canFlip => _cameras.length >= 2;

  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    _notify();
  }

  /// 저장된 설정으로 초기 상태를 맞춘다. (플래시/무음)
  void hydrate(SettingsStore s) {
    settings = s;
    _silentShutter = s.silentShutter;
    // torch를 저장했다면 앱을 켜자마자 손전등이 켜지는 것을 막는다.
    _flashMode = s.flashMode == FlashMode.torch ? FlashMode.off : s.flashMode;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive는 알림 배너·제어센터·자체 권한 다이얼로그에서도 발생하므로
    // 프리뷰가 불필요하게 깜빡이지 않도록 paused/hidden에서만 해제한다.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      final controller = _controller;
      _controller = null;
      // 진행 중이던 촬영이 끊기면 상태가 잠길 수 있어 함께 되돌린다.
      _isRecording = false;
      _busy = false;
      controller?.dispose();
      _notify();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null &&
          _statusMessage == null &&
          _cameras.isNotEmpty) {
        unawaited(_initCamera(_index));
      }
    }
  }

  /// 권한 요청 → 카메라 목록 조회 → 저장된 렌즈로 초기화.
  /// 진행 중 재호출(재시도 버튼 연타 등)은 무시한다.
  Future<void> bootstrap() async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    try {
      _statusMessage = null;
      _notify();

      Map<Permission, PermissionStatus> statuses;
      try {
        statuses = await <Permission>[
          Permission.camera,
          Permission.microphone,
        ].request();
      } on Exception catch (e) {
        debugPrint('권한 요청 실패: $e');
        statuses = const {};
      }

      if (statuses[Permission.camera] != PermissionStatus.granted) {
        _statusMessage = '카메라 권한이 필요합니다. 설정에서 허용해 주세요.';
        _notify();
        return;
      }

      if (_cameras.isEmpty) {
        try {
          _cameras.addAll(await availableCameras());
        } on CameraException catch (e) {
          debugPrint('카메라 목록 조회 실패: $e');
        }
      }
      if (_cameras.isEmpty) {
        _statusMessage = '사용 가능한 카메라를 찾지 못했습니다.';
        _notify();
        return;
      }

      final savedDir = settings?.lensDirection ?? CameraLensDirection.back;
      var idx = _cameras.indexWhere((c) => c.lensDirection == savedDir);
      if (idx < 0) {
        idx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
      }
      _index = idx >= 0 ? idx : 0;
      await _initCamera(_index);
    } finally {
      _bootstrapping = false;
    }
  }

  Future<void> retry() => bootstrap();

  Future<void> _initCamera(int index) async {
    final previous = _controller;
    final controller = CameraController(
      _cameras[index],
      _resolution,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      debugPrint('카메라 초기화 실패: $e');
      await controller.dispose();
      await previous?.dispose();
      if (_controller == controller) _controller = null;
      _statusMessage = '카메라를 초기화하지 못했습니다.';
      _notify();
      return;
    }

    if (_disposed) {
      if (_controller == controller) _controller = null;
      await controller.dispose();
      return;
    }
    try {
      await controller.setFlashMode(_flashMode);
    } on CameraException {
      // 일부 기기는 플래시 미지원
    }
    await previous?.dispose();
    _notify();
  }

  Future<void> flip() async {
    if (_cameras.length < 2 || _isRecording || _busy) return;
    _index = (_index + 1) % _cameras.length;
    await _initCamera(_index);
    settings?.setLensDirection(_cameras[_index].lensDirection);
  }

  Future<void> cycleFlash() async {
    if (!isReady) return;
    const order = [
      FlashMode.off,
      FlashMode.auto,
      FlashMode.always,
      FlashMode.torch,
    ];
    final next = order[(order.indexOf(_flashMode) + 1) % order.length];
    try {
      await _controller!.setFlashMode(next);
      _flashMode = next;
      settings?.setFlashMode(next);
      _notify();
    } on CameraException {
      onMessage?.call('이 기기에서는 플래시를 사용할 수 없습니다.');
    }
  }

  void toggleSilentShutter() {
    _silentShutter = !_silentShutter;
    settings?.setSilentShutter(_silentShutter);
    _notify();
  }

  /// [action]을 촬영 중복 없이(busy 플래그로 보호) 실행한다.
  /// 이미 다른 작업이 진행 중이면 아무것도 하지 않는다.
  Future<void> runExclusive(Future<void> Function() action) async {
    if (_busy) return;
    _setBusy(true);
    try {
      await action();
    } finally {
      _setBusy(false);
    }
  }

  /// 사진 한 장을 촬영해 작업 폴더에 저장하고 File을 돌려준다. 실패 시 null.
  Future<File?> capturePhoto() => _grabStill('photo');

  /// 현재 프리뷰를 캡처해 작업 폴더에 저장한다. (오버레이용, 갤러리 저장 안 함)
  Future<File?> captureSnapshot() => _grabStill('overlay');

  Future<File?> _grabStill(String prefix) async {
    try {
      if (_silentShutter) return await _grabSilentStill(prefix);
      final shot = await _controller!.takePicture();
      return await workDir.copyInto(shot.path, prefix);
    } on CameraException catch (e) {
      debugPrint('촬영 실패: $e');
      return null;
    } on Exception catch (e) {
      // 저장공간 부족 등 파일 IO 실패
      debugPrint('촬영본 저장 실패: $e');
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
      await Future<void>.delayed(_silentClipDuration);
      final clip = await controller.stopVideoRecording();
      clipPath = clip.path;

      framePath = await vt.VideoThumbnail.thumbnailFile(
        video: clip.path,
        imageFormat: vt.ImageFormat.JPEG,
        timeMs: 0,
        quality: 95,
      );
      if (framePath == null) return null;
      return await workDir.copyInto(framePath, prefix, ext: 'jpg');
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

  /// 녹화 토글. 정지 시 저장된 mp4(작업 폴더)를 [onStopped]로 넘긴다.
  Future<void> toggleRecording({
    required Future<void> Function(File mp4) onStopped,
  }) async {
    if (!isReady || _busy) return;
    _setBusy(true);
    try {
      if (_isRecording) {
        try {
          final x = await _controller!.stopVideoRecording();
          final mp4 = await workDir.copyInto(x.path, 'video', ext: 'mp4');
          await onStopped(mp4);
        } on CameraException catch (e) {
          debugPrint('동영상 정지 실패: $e');
          onMessage?.call('동영상 저장에 실패했습니다.');
        } on Exception catch (e) {
          debugPrint('동영상 저장 실패: $e');
          onMessage?.call('동영상 저장에 실패했습니다.');
        } finally {
          _isRecording = false;
          _notify();
        }
      } else {
        try {
          await _controller!.startVideoRecording();
          _isRecording = true;
          _notify();
        } on CameraException catch (e) {
          debugPrint('녹화 시작 실패: $e');
          onMessage?.call('녹화를 시작하지 못했습니다.');
        }
      }
    } finally {
      _setBusy(false);
    }
  }
}
