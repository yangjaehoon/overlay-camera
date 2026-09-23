import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'change_bus.dart';
import 'controller_base.dart';
import 'settings_store.dart';
import 'work_dir.dart';

part 'camera_session_zoom_exposure.dart';
part 'camera_session_timer.dart';
part 'camera_session_capture.dart';

const _flashOrder = [
  FlashMode.off,
  FlashMode.auto,
  FlashMode.always,
  FlashMode.torch,
];

/// 플래시 버튼을 눌렀을 때 다음 모드 (off → auto → always → torch → off).
FlashMode nextFlashMode(FlashMode current) =>
    _flashOrder[(_flashOrder.indexOf(current) + 1) % _flashOrder.length];

/// 전/후면 전환 시 이동할 카메라 인덱스.
/// [toFront] 면 첫 전면 카메라, 아니면 [lastBackIndex](유효할 때) 또는 첫 후면 카메라.
/// 대상이 없거나 현재와 같으면 -1.
int pickFlipTarget(
  List<CameraDescription> cameras,
  int currentIndex, {
  required int lastBackIndex,
  required bool toFront,
}) {
  int next;
  if (toFront) {
    next = cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
  } else {
    final lastOk =
        lastBackIndex >= 0 &&
        lastBackIndex < cameras.length &&
        cameras[lastBackIndex].lensDirection == CameraLensDirection.back;
    next = lastOk
        ? lastBackIndex
        : cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
          );
  }
  return (next < 0 || next == currentIndex) ? -1 : next;
}

/// [cameras] 중 후면 렌즈들의 인덱스.
List<int> backLensIndices(List<CameraDescription> cameras) => [
  for (var i = 0; i < cameras.length; i++)
    if (cameras[i].lensDirection == CameraLensDirection.back) i,
];

/// 후면 물리 렌즈 순환 시 다음 인덱스. 후면 렌즈가 2개 미만이거나
/// [currentIndex] 가 후면이 아니면 -1.
int nextBackLensIndex(List<CameraDescription> cameras, int currentIndex) {
  final backs = backLensIndices(cameras);
  if (backs.length < 2) return -1;
  final pos = backs.indexOf(currentIndex);
  return pos < 0 ? -1 : backs[(pos + 1) % backs.length];
}

/// 카메라 컨트롤러의 생명주기와 촬영(사진·무음·동영상)을 담당한다.
/// 상태 변경 시 [notifyListeners]로 알리고, 안내 메시지는 [onMessage]로 전달한다.
///
/// 책임별로 [_ZoomExposureMixin](줌·노출), [_SelfTimerMixin](셀프타이머),
/// [_CaptureMixin](촬영·초점)으로 나눠 각각 별도 파일(`camera_session_*.dart`,
/// `part of` 로 이 파일과 한 라이브러리를 이룬다)에 두었다. 카메라 목록·컨트롤러
/// 생명주기·렌즈 전환처럼 여러 책임이 함께 쓰는 상태만 이 클래스가 직접 갖는다.
class CameraSession extends AppController
    with
        WidgetsBindingObserver,
        _ZoomExposureMixin,
        _SelfTimerMixin,
        _CaptureMixin {
  CameraSession({required this.workDir, this.onMessage});

  @override
  final WorkDir workDir;
  @override
  final void Function(String message)? onMessage;

  /// 촬영 해상도. 사진·무음 캡처·영상 마지막 프레임 화질을 모두 결정한다.
  /// (올리면 stampPhoto 메모리 사용량도 비례해 커진다) hydrate 로 저장값이 주입된다.
  ResolutionPreset _resolution = ResolutionPreset.high;

  final List<CameraDescription> _cameras = [];
  @override
  CameraController? _controller;
  int _index = 0;
  int _lastBackIndex = 0; // 마지막으로 쓴 후면 렌즈(전환 후 복귀용)
  FlashMode _flashMode = FlashMode.off;
  @override
  bool _isRecording = false;
  bool _busy = false;
  bool _bootstrapping = false;
  String? _statusMessage;
  @override
  bool _silentShutter = false;

  CameraController? get controller => _controller;
  @override
  bool get isReady => _controller?.value.isInitialized ?? false;
  bool get isRecording => _isRecording;
  @override
  bool get busy => _busy;
  String? get statusMessage => _statusMessage;
  FlashMode get flashMode => _flashMode;
  bool get silentShutter => _silentShutter;
  ResolutionPreset get resolutionPreset => _resolution;

  /// 전/후면 전환 가능 여부(둘 다 있어야).
  bool get canFlip =>
      _cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
      _cameras.any((c) => c.lensDirection == CameraLensDirection.back);

  /// 후면에 물리 렌즈가 2개 이상이면 렌즈 순환이 가능하다(초광각·망원 등).
  bool get hasMultipleBackLenses => backLensIndices(_cameras).length >= 2;

  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void dispose() {
    _stopCountdown();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _zoomBus.dispose();
    _evBus.dispose();
    super.dispose();
  }

  @override
  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notify();
  }

  /// 촉각 피드백. 미지원 플랫폼·테스트 환경에서는 조용히 무시한다.
  @override
  void _haptic(Future<void> Function() feedback) {
    try {
      feedback().catchError((Object _) {});
    } catch (_) {
      // 햅틱 미지원
    }
  }

  /// 저장된 설정으로 초기 상태를 맞춘다. (플래시/무음/타이머/해상도)
  @override
  void hydrate(SettingsStore s) {
    settings = s;
    _silentShutter = s.silentShutter;
    _timerSeconds = s.timerSeconds;
    _resolution = s.resolutionPreset;
    // torch를 저장했다면 앱을 켜자마자 손전등이 켜지는 것을 막는다.
    _flashMode = s.flashMode == FlashMode.torch ? FlashMode.off : s.flashMode;
    notify();
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
      notify();
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
      notify();

      if (!await _requestCameraPermission()) {
        _fail('카메라 권한이 필요합니다. 설정에서 허용해 주세요.');
        return;
      }
      if (!await _loadCameras()) {
        _fail('사용 가능한 카메라를 찾지 못했습니다.');
        return;
      }
      _selectSavedLens();
      await _initCamera(_index);
    } finally {
      _bootstrapping = false;
    }
  }

  /// 카메라·마이크 권한을 요청하고, 카메라가 허용됐는지 돌려준다.
  /// 요청 자체가 실패하면 허용되지 않은 것으로 본다.
  Future<bool> _requestCameraPermission() async {
    try {
      final statuses = await <Permission>[
        Permission.camera,
        Permission.microphone,
      ].request();
      return statuses[Permission.camera] == PermissionStatus.granted;
    } on Exception catch (e) {
      debugPrint('권한 요청 실패: $e');
      return false;
    }
  }

  /// 아직 목록이 비어 있으면 카메라 목록을 조회한다. 쓸 카메라가 있으면 true.
  Future<bool> _loadCameras() async {
    if (_cameras.isEmpty) {
      try {
        _cameras.addAll(await availableCameras());
      } on CameraException catch (e) {
        debugPrint('카메라 목록 조회 실패: $e');
      }
    }
    return _cameras.isNotEmpty;
  }

  /// 저장된 렌즈 방향(없으면 후면, 그마저 없으면 첫 카메라)으로 [_index]를 맞춘다.
  void _selectSavedLens() {
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
  }

  /// 카메라를 쓸 수 없는 이유를 화면에 띄운다.
  void _fail(String message) {
    _statusMessage = message;
    notify();
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
      _fail('카메라를 초기화하지 못했습니다.');
      return;
    }

    if (isDisposed) {
      if (_controller == controller) _controller = null;
      await controller.dispose();
      return;
    }
    // 플래시 적용 + 줌/노출 범위 조회는 서로 의존이 없다. 순차로 하면
    // 렌즈 전환·앱 복귀마다 플랫폼 왕복 지연이 누적되므로 함께 실행한다.
    // 각 헬퍼는 예외를 자체 처리하므로 이 Future.wait 는 실패하지 않는다.
    await Future.wait([
      _applyFlashMode(controller),
      _loadZoomRange(controller),
      _loadExposureRange(controller),
    ]);
    await previous?.dispose();
    notify();
  }

  Future<void> _applyFlashMode(CameraController c) async {
    try {
      await c.setFlashMode(_flashMode);
    } on CameraException {
      // 일부 기기는 플래시 미지원
    }
  }

  /// 전면 ↔ 후면 전환. 후면으로 돌아올 땐 마지막에 쓰던 렌즈로.
  Future<void> flip() async {
    if (_isRecording || _busy || !canFlip) return;
    final onFront = _cameras[_index].lensDirection == CameraLensDirection.front;
    final next = pickFlipTarget(
      _cameras,
      _index,
      lastBackIndex: _lastBackIndex,
      toFront: !onFront,
    );
    if (next < 0) return;
    await _switchTo(next);
    if (_controller != null) {
      settings?.setLensDirection(_cameras[_index].lensDirection);
    }
  }

  /// 후면 물리 렌즈를 순환한다(초광각·기본·망원 등). 후면일 때만.
  Future<void> cycleBackLens() async {
    if (_isRecording || _busy) return;
    final next = nextBackLensIndex(_cameras, _index);
    if (next < 0) return;
    await _switchTo(next);
  }

  /// 렌즈 전환 구간을 [_busy]로 직렬화한다. flip·cycleBackLens 가 겹쳐
  /// _initCamera 가 동시에 도는 것을 막는다.
  Future<void> _switchTo(int index) async {
    _setBusy(true);
    try {
      _index = index;
      if (_cameras[_index].lensDirection == CameraLensDirection.back) {
        _lastBackIndex = _index;
      }
      await _initCamera(_index);
      if (_controller != null) _haptic(HapticFeedback.selectionClick);
    } finally {
      _setBusy(false);
    }
  }

  /// 촬영 해상도를 바꾼다. 컨트롤러를 새 프리셋으로 다시 초기화한다.
  /// 녹화 중이거나 다른 작업 중이면 무시.
  Future<void> setResolutionPreset(ResolutionPreset preset) async {
    if (_isRecording || _busy || _bootstrapping) return;
    if (preset == _resolution) return;
    _resolution = preset;
    settings?.setResolutionPreset(preset);
    notify(); // 시트가 선택 표시를 즉시 갱신
    if (_cameras.isEmpty) return; // 아직 부트스트랩 전이면 다음 _initCamera 가 반영
    _setBusy(true);
    try {
      await _initCamera(_index);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> cycleFlash() async {
    if (!isReady) return;
    final next = nextFlashMode(_flashMode);
    try {
      await _controller!.setFlashMode(next);
      _flashMode = next;
      settings?.setFlashMode(next);
      _haptic(HapticFeedback.selectionClick);
      notify();
    } on CameraException {
      onMessage?.call('이 기기에서는 플래시를 사용할 수 없습니다.');
    }
  }

  void toggleSilentShutter() {
    _silentShutter = !_silentShutter;
    settings?.setSilentShutter(_silentShutter);
    _haptic(HapticFeedback.selectionClick);
    notify();
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
}
