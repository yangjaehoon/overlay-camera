part of 'camera_session.dart';

/// 노출 보정 값을 [min]~[max] 로 클램프하고, [step]>0 이면 그 배수로 스냅한다.
/// [step]<=0(연속 지원 기기)이면 클램프만 한다.
double snapExposureOffset(double value, double min, double max, double step) {
  final v = value.clamp(min, max).toDouble();
  if (step <= 0) return v;
  return ((v / step).roundToDouble() * step).clamp(min, max).toDouble();
}

/// [CameraSession]의 줌·노출 상태와 조작을 담당한다. 드래그 중 매 프레임
/// 바뀌는 값은 [zoomTick]/[exposureTick] 이라는 경량 채널로만 알려 메인
/// notifyListeners(하단바·상단바·프리뷰 리빌드)와 분리한다.
mixin _ZoomExposureMixin on ChangeNotifier {
  CameraController? get _controller;
  bool get _disposed;

  final StructureBus _zoomBus = StructureBus();
  final StructureBus _evBus = StructureBus();
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _ev = 0.0; // 노출 보정(EV, 스톱)
  double _minEv = 0.0;
  double _maxEv = 0.0;
  double _evStep = 0.0;
  double? _pendingEv;
  bool _applyingEv = false;

  /// 디지털 줌 상태. [zoomTick] 은 배율 변경만 알리는 경량 채널이다.
  double get zoom => _zoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  Listenable get zoomTick => _zoomBus;

  /// 프리뷰가 눈에 띄게 확대되는 기기에서만 줌 바를 노출한다(1.15배 이상).
  bool get canZoom => _maxZoom > _minZoom + 0.15;

  /// 노출 보정(EV). [exposureTick] 은 값 변경만 알리는 경량 채널.
  double get exposureOffset => _ev;
  double get minExposureOffset => _minEv;
  double get maxExposureOffset => _maxEv;
  double get exposureStep => _evStep;
  Listenable get exposureTick => _evBus;

  /// 노출 보정 범위가 있는 기기에서만 슬라이더를 노출한다
  /// (미지원 기기는 min==max==0 으로 보고됨).
  bool get canSetExposure => _maxEv - _minEv > 0.01;

  /// 새 컨트롤러의 줌 범위를 읽고 1배로 초기화한다.
  Future<void> _loadZoomRange(CameraController c) async {
    _resetZoom();
    try {
      final r = await Future.wait([c.getMinZoomLevel(), c.getMaxZoomLevel()]);
      _minZoom = r[0];
      _maxZoom = r[1];
      _zoom = r[0];
    } on Exception catch (e) {
      // CameraException(줌 미지원) / MissingPluginException 등
      debugPrint('줌 범위 조회 실패: $e');
      _resetZoom();
    } on UnimplementedError {
      // 플랫폼 인터페이스 미구현(테스트 페이크 등)
      _resetZoom();
    }
  }

  /// 노출 보정 범위를 읽고 0(보정 없음)으로 초기화한다.
  Future<void> _loadExposureRange(CameraController c) async {
    _resetExposure();
    try {
      final r = await Future.wait([
        c.getMinExposureOffset(),
        c.getMaxExposureOffset(),
        c.getExposureOffsetStepSize(),
      ]);
      _minEv = r[0];
      _maxEv = r[1];
      _evStep = r[2] < 0 ? 0.0 : r[2];
    } on Exception catch (e) {
      debugPrint('노출 보정 범위 조회 실패: $e');
      _resetExposure();
    } on UnimplementedError {
      _resetExposure();
    }
  }

  void _resetZoom() {
    _zoom = 1.0;
    _minZoom = 1.0;
    _maxZoom = 1.0;
  }

  void _resetExposure() {
    _ev = 0.0;
    _minEv = 0.0;
    _maxEv = 0.0;
    _evStep = 0.0;
  }

  /// 디지털 줌 배율을 설정한다(min~max 로 클램프). 슬라이더/핀치 중 매 프레임 호출 가능.
  Future<void> setZoom(double level) async {
    final c = _controller;
    if (_disposed || c == null || !c.value.isInitialized) return;
    final z = level.clamp(_minZoom, _maxZoom).toDouble();
    if ((z - _zoom).abs() < 0.001) return;
    final prev = _zoom;
    _zoom = z;
    _zoomBus.ping();
    try {
      await c.setZoomLevel(z);
    } on CameraException catch (e) {
      debugPrint('줌 설정 실패: $e');
      _zoom = prev; // 실제로 안 걸렸으면 UI도 되돌린다
      if (!_disposed) _zoomBus.ping();
    }
  }

  /// 노출 보정(EV)을 설정한다(min~max 로 클램프, 기기 스텝으로 스냅).
  /// 슬라이더 드래그 중 매 프레임 호출돼도 마지막 값만 적용되도록 합친다
  /// (Android 는 이전 setExposureOffset 을 취소하고 예외를 던지므로).
  /// 참고: AE/AF 고정 중에는 기기에 따라 보정이 화면에 즉시 반영되지 않을 수 있다.
  Future<void> setExposureOffset(double value) async {
    final c = _controller;
    if (_disposed || c == null || !c.value.isInitialized || !canSetExposure) {
      return;
    }
    final target = snapExposureOffset(value, _minEv, _maxEv, _evStep);
    if ((target - _ev).abs() < 0.001) return;
    _ev = target;
    _evBus.ping();

    _pendingEv = target;
    if (_applyingEv) return; // 적용 루프가 이미 돌고 있으면 값만 갱신해 둔다
    _applyingEv = true;
    try {
      while (_pendingEv != null && !_disposed) {
        final want = _pendingEv!;
        _pendingEv = null;
        final cc = _controller;
        if (cc == null || !cc.value.isInitialized) break;
        try {
          final applied = await cc.setExposureOffset(want);
          // 드래그가 멈춘 뒤에만 기기가 실제 적용한 값으로 보정(중간엔 튀지 않게).
          if (_pendingEv == null &&
              !_disposed &&
              (applied - _ev).abs() > 0.001) {
            _ev = applied;
            _evBus.ping();
          }
        } on CameraException catch (e) {
          debugPrint('노출 보정 실패: $e');
        }
      }
    } finally {
      _applyingEv = false;
    }
  }
}
