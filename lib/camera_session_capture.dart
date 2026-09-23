part of 'camera_session.dart';

/// 무음 촬영 시 몰래 녹화하는 길이. 첫 프레임만 뽑으므로 짧을수록 좋다.
const _silentClipDuration = Duration(milliseconds: 550);

/// [CameraSession]의 촬영(사진·무음·동영상)과 탭 초점(AE/AF)을 담당한다.
mixin _CaptureMixin on AppController {
  CameraController? get _controller;
  bool get isReady;
  bool get busy;
  WorkDir get workDir;
  void Function(String message)? get onMessage;
  bool get _silentShutter;
  bool get _isRecording;
  set _isRecording(bool v);
  void _haptic(Future<void> Function() feedback);
  void _setBusy(bool value);

  bool _aeAfLocked = false;
  bool _focusing = false;

  /// 초점·노출이 한 지점에 고정돼 있는지. 테이크마다 밝기가 튀지 않게 할 때 켠다.
  bool get aeAfLocked => _aeAfLocked;

  /// 사진 한 장을 촬영해 작업 폴더에 저장하고 File을 돌려준다. 실패 시 null.
  Future<File?> capturePhoto() => _grabStill('photo');

  /// 현재 프리뷰를 캡처해 작업 폴더에 저장한다. (오버레이용, 갤러리 저장 안 함)
  Future<File?> captureSnapshot() => _grabStill('overlay');

  Future<File?> _grabStill(String prefix) async {
    _haptic(HapticFeedback.lightImpact); // 셔터 눌린 느낌
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
      await deleteQuietly(clipPath);
      await deleteQuietly(framePath);
    }
  }

  /// 녹화 토글. 정지 시 저장된 mp4(작업 폴더)를 [onStopped]로 넘긴다.
  Future<void> toggleRecording({
    required Future<void> Function(File mp4) onStopped,
  }) async {
    if (!isReady || busy) return;
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
          _haptic(HapticFeedback.mediumImpact);
          notify();
        }
      } else {
        try {
          await _controller!.startVideoRecording();
          _isRecording = true;
          _haptic(HapticFeedback.mediumImpact);
          notify();
        } on CameraException catch (e) {
          debugPrint('녹화 시작 실패: $e');
          onMessage?.call('녹화를 시작하지 못했습니다.');
        }
      }
    } finally {
      _setBusy(false);
    }
  }

  /// 프리뷰의 한 지점(0~1, 좌상단 원점)에 초점·노출을 맞춘다.
  /// [lock]이면 그 상태로 고정하고, 아니면(=false) 고정을 풀어 연속 자동으로 둔다.
  /// 이미 조정이 진행 중이면(빠른 연타·롱프레스↔탭 경쟁) 이번 호출은 버린다.
  Future<void> focusAt(Offset point, {bool lock = false}) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _focusing) return;
    _focusing = true;
    final p = Offset(point.dx.clamp(0.0, 1.0), point.dy.clamp(0.0, 1.0));
    try {
      // locked 상태에선 point 변경이 안 먹는 기기가 있어 먼저 auto로 푼다.
      await c.setFocusMode(FocusMode.auto);
      await c.setExposureMode(ExposureMode.auto);
      await Future.wait([c.setFocusPoint(p), c.setExposurePoint(p)]);
      if (lock) {
        // 잠금은 따로 감싼다: 한쪽만 실패해 "반쪽 잠금"으로 갇히지 않도록.
        try {
          await c.setFocusMode(FocusMode.locked);
          await c.setExposureMode(ExposureMode.locked);
          _aeAfLocked = true;
          _haptic(HapticFeedback.mediumImpact); // 고정됨을 확실히 알림
        } on Exception catch (e) {
          debugPrint('AE/AF 고정 실패, 자동으로 되돌림: $e');
          await _restoreAutoFocus(c);
          _aeAfLocked = false;
        }
      } else {
        _aeAfLocked = false;
      }
      notify();
    } on Exception catch (e) {
      // 초점/노출 제어를 지원하지 않는 기기·렌즈
      debugPrint('초점/노출 설정 실패: $e');
    } finally {
      _focusing = false;
    }
  }

  Future<void> _restoreAutoFocus(CameraController c) async {
    try {
      await c.setFocusMode(FocusMode.auto);
      await c.setExposureMode(ExposureMode.auto);
    } on Exception catch (_) {
      // 복구 실패까지 삼킨다(다음 focusAt이 다시 auto로 시작함)
    }
  }
}
