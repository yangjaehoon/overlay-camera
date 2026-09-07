import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'settings_store.dart';
import 'work_dir.dart';

const _flashOrder = [
  FlashMode.off,
  FlashMode.auto,
  FlashMode.always,
  FlashMode.torch,
];

/// 플래시 버튼을 눌렀을 때 다음 모드 (off → auto → always → torch → off).
FlashMode nextFlashMode(FlashMode current) =>
    _flashOrder[(_flashOrder.indexOf(current) + 1) % _flashOrder.length];

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
  int _lastBackIndex = 0; // 마지막으로 쓴 후면 렌즈(전환 후 복귀용)
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  FlashMode _flashMode = FlashMode.off;
  bool _isRecording = false;
  bool _busy = false;
  bool _bootstrapping = false;
  String? _statusMessage;
  bool _silentShutter = false;
  bool _aeAfLocked = false;
  bool _focusing = false;
  int _timerSeconds = 0;
  int _countdown = 0;
  Timer? _countdownTimer;
  Completer<bool>? _countdownDone;
  bool _disposed = false;

  static const _timerOrder = [0, 3, 10];

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized ?? false;
  bool get isRecording => _isRecording;
  bool get busy => _busy;
  String? get statusMessage => _statusMessage;
  FlashMode get flashMode => _flashMode;
  bool get silentShutter => _silentShutter;

  List<int> get _backLensIndices => [
        for (var i = 0; i < _cameras.length; i++)
          if (_cameras[i].lensDirection == CameraLensDirection.back) i,
      ];

  /// 전/후면 전환 가능 여부(둘 다 있어야).
  bool get canFlip =>
      _cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
      _cameras.any((c) => c.lensDirection == CameraLensDirection.back);

  /// 후면에 물리 렌즈가 2개 이상이면 렌즈 순환이 가능하다(초광각·망원 등).
  bool get hasMultipleBackLenses => _backLensIndices.length >= 2;

  /// 디지털 줌 상태.
  double get zoom => _zoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  bool get canZoom => _maxZoom > _minZoom + 0.01;

  /// 초점·노출이 한 지점에 고정돼 있는지. 테이크마다 밝기가 튀지 않게 할 때 켠다.
  bool get aeAfLocked => _aeAfLocked;

  /// 셀프타이머 초(0=끔/3/10).
  int get timerSeconds => _timerSeconds;

  /// 카운트다운 중 남은 초(0=진행 안 함).
  int get countdown => _countdown;
  bool get isCountingDown => _countdown > 0;

  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void dispose() {
    _disposed = true;
    _stopCountdown();
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

  /// 저장된 설정으로 초기 상태를 맞춘다. (플래시/무음/타이머)
  void hydrate(SettingsStore s) {
    settings = s;
    _silentShutter = s.silentShutter;
    _timerSeconds = s.timerSeconds;
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
      _stopCountdown(); // 진행 중이던 카운트다운도 취소
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
      if (_cameras[_index].lensDirection == CameraLensDirection.back) {
        _lastBackIndex = _index;
      }
      await _initCamera(_index);
    } finally {
      _bootstrapping = false;
    }
  }

  Future<void> retry() => bootstrap();

  Future<void> _initCamera(int index) async {
    _aeAfLocked = false; // 새 컨트롤러는 연속 자동 초점/노출로 시작한다.
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
    // 새 컨트롤러의 줌 범위를 읽고 1배로 초기화한다.
    _zoom = 1.0;
    _minZoom = 1.0;
    _maxZoom = 1.0;
    try {
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _zoom = _minZoom;
    } catch (_) {
      // 줌을 지원하지 않거나 조회 불가한 기기 - 줌 비활성 상태로 둔다
      _zoom = 1.0;
      _minZoom = 1.0;
      _maxZoom = 1.0;
    }
    await previous?.dispose();
    _notify();
  }

  /// 전면 ↔ 후면 전환. 후면으로 돌아올 땐 마지막에 쓰던 렌즈로.
  Future<void> flip() async {
    if (_isRecording || _busy || !canFlip) return;
    final goingBack =
        _cameras[_index].lensDirection == CameraLensDirection.front;
    int next;
    if (goingBack) {
      next = (_lastBackIndex < _cameras.length &&
              _cameras[_lastBackIndex].lensDirection == CameraLensDirection.back)
          ? _lastBackIndex
          : _cameras.indexWhere(
              (c) => c.lensDirection == CameraLensDirection.back);
    } else {
      next = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front);
    }
    if (next < 0 || next == _index) return;
    _index = next;
    if (_cameras[_index].lensDirection == CameraLensDirection.back) {
      _lastBackIndex = _index;
    }
    await _initCamera(_index);
    settings?.setLensDirection(_cameras[_index].lensDirection);
  }

  /// 후면 물리 렌즈를 순환한다(초광각·기본·망원 등). 후면일 때만.
  Future<void> cycleBackLens() async {
    if (_isRecording || _busy) return;
    final backs = _backLensIndices;
    if (backs.length < 2) return;
    if (_cameras[_index].lensDirection != CameraLensDirection.back) return;
    final pos = backs.indexOf(_index);
    _index = backs[(pos + 1) % backs.length];
    _lastBackIndex = _index;
    await _initCamera(_index);
  }

  /// 디지털 줌 배율을 설정한다(min~max 로 클램프). 슬라이더/핀치 중 매 프레임 호출 가능.
  Future<void> setZoom(double level) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final z = level.clamp(_minZoom, _maxZoom).toDouble();
    if ((z - _zoom).abs() < 0.001) return;
    _zoom = z;
    _notify();
    try {
      await c.setZoomLevel(z);
    } on CameraException catch (e) {
      debugPrint('줌 설정 실패: $e');
    }
  }

  Future<void> cycleFlash() async {
    if (!isReady) return;
    final next = nextFlashMode(_flashMode);
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

  /// 셀프타이머를 0 → 3 → 10 → 0 순으로 바꾼다. 카운트다운 중이면 무시.
  void cycleTimer() {
    if (_countdown > 0) return;
    final next = (_timerOrder.indexOf(_timerSeconds) + 1) % _timerOrder.length;
    _timerSeconds = _timerOrder[next];
    settings?.setTimerSeconds(_timerSeconds);
    _notify();
  }

  /// 셀프타이머가 켜져 있으면 카운트다운 후, 아니면 즉시 [capture]를 실행한다.
  /// 카운트다운 중 [cancelCountdown]이 불리면 [capture]는 실행되지 않는다.
  Future<void> runWithTimer(Future<void> Function() capture) async {
    if (_timerSeconds == 0) {
      await capture();
      return;
    }
    if (_countdown > 0) return; // 이미 카운트다운 중

    final done = Completer<bool>();
    _countdownDone = done;
    _countdown = _timerSeconds;
    _notify();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _countdown--;
      _notify();
      if (_countdown <= 0) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        if (!done.isCompleted) done.complete(true);
      }
    });

    final finished = await done.future;
    _countdownDone = null;
    if (finished && !_disposed) await capture();
  }

  /// 진행 중인 카운트다운을 취소한다(촬영하지 않음).
  void cancelCountdown() {
    if (_countdown == 0) return;
    _stopCountdown();
    _notify();
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdown = 0;
    if (_countdownDone?.isCompleted == false) _countdownDone!.complete(false);
    _countdownDone = null;
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
        } on Exception catch (e) {
          debugPrint('AE/AF 고정 실패, 자동으로 되돌림: $e');
          await _restoreAutoFocus(c);
          _aeAfLocked = false;
        }
      } else {
        _aeAfLocked = false;
      }
      _notify();
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
