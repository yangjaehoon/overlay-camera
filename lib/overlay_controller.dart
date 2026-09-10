import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'overlay_outline.dart';
import 'overlay_preset.dart';
import 'settings_store.dart';
import 'work_dir.dart';

/// 위치·크기 드래그 같은 잦은 전이가 아니라 구조 변경(파일 교체·모드 토글·
/// 투명도 확정 등)에만 알리는 채널.
class _StructureBus extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// 고스트 오버레이의 상태(이미지·투명도·변형·잠금·자동사용)를 담당한다.
/// 드래그처럼 잦은 갱신이 카메라 프리뷰까지 리빌드하지 않도록 별도 [ChangeNotifier]로 분리.
class OverlayController extends ChangeNotifier {
  OverlayController({required this.workDir, this.settings, this.onMessage});

  final WorkDir workDir;
  SettingsStore? settings;
  final void Function(String message)? onMessage;

  static const _minScale = 0.15;
  static const _maxScale = 6.0;
  static const _maxPresets = 20;

  File? _file;
  double _opacity = 0.45;
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0;
  bool _locked = false;
  bool _autoUseLast = true;
  bool _disposed = false;

  /// 위치 드래그(onScaleUpdate)에는 반응하지 않아야 하는 위젯(우측 컨트롤 패널,
  /// 상단 바 버튼 등)이 구독하는 채널.
  final _StructureBus _structure = _StructureBus();
  Listenable get structure => _structure;

  // 흰색 윤곽선 모드: 사진 대신 가장자리만 뽑은 투명 PNG를 보여준다.
  bool _outlineMode = false;
  File? _outlineFile;
  bool _tracingOutline = false;

  // 정합 보조: 좌우 반전(전면/후면 카메라 미러 차이 대응), 색 반전(네거티브 고스트).
  bool _mirrored = false;
  bool _inverted = false;

  // 제스처 시작 시점 기준값
  double _baseScale = 1.0;
  double _baseRotation = 0.0;

  // 이름 붙여 저장한 오버레이 설정. 이미지는 앱 문서 폴더에 사본 보관.
  List<OverlayPreset> _presets = const [];
  static int _idSeq = 0;

  File? get file => _file;
  bool get hasFile => _file != null;
  double get opacity => _opacity;
  Offset get offset => _offset;
  double get scale => _scale;
  double get rotation => _rotation;
  bool get locked => _locked;
  bool get autoUseLast => _autoUseLast;
  bool get outlineMode => _outlineMode;
  bool get tracingOutline => _tracingOutline;
  bool get mirrored => _mirrored;
  bool get inverted => _inverted;

  UnmodifiableListView<OverlayPreset> get presets =>
      UnmodifiableListView(_presets);

  /// 실제로 그릴 파일. 윤곽선 모드면 추출된 윤곽선을(처리 중이면 원본을 대신) 보여준다.
  File? get displayFile => _outlineMode ? (_outlineFile ?? _file) : _file;

  @override
  void dispose() {
    _disposed = true;
    _structure.dispose();
    super.dispose();
  }

  /// 잦은 전이(위치·크기 드래그)용. 오버레이 레이어만 반응하면 된다.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 구조 변경용. 메인 알림 + 구조 채널을 함께 울린다.
  void _notifyStructural() {
    if (_disposed) return;
    notifyListeners();
    _structure.ping();
  }

  /// 저장된 설정으로 초기 상태를 맞춘다.
  void hydrate(SettingsStore s) {
    settings = s;
    _autoUseLast = s.autoUseLastShot;
    _opacity = s.overlayOpacity;
    _outlineMode = s.overlayOutline;
    _mirrored = s.overlayMirror;
    _inverted = s.overlayInvert;
    _presets = s.overlayPresets;
    _notifyStructural();
    if (_outlineMode) unawaited(_ensureOutline());
  }

  /// 오버레이 이미지를 교체한다. 이전 파일(+예전 윤곽선)이 작업 폴더 소유면 삭제한다.
  void setFile(File f) {
    final old = _file;
    final oldOutline = _outlineFile;
    _file = f;
    _outlineFile = null; // 새 사진이니 이전 윤곽선은 더 이상 유효하지 않다.
    _resetTransform();
    _notifyStructural();
    if (old != null && old.path != f.path) workDir.deleteIfOwned(old);
    if (oldOutline != null) workDir.deleteIfOwned(oldOutline);
    if (_outlineMode) unawaited(_ensureOutline());
  }

  void clear() {
    final old = _file;
    final oldOutline = _outlineFile;
    _file = null;
    _outlineFile = null;
    _locked = false;
    _notifyStructural();
    if (old != null) workDir.deleteIfOwned(old);
    if (oldOutline != null) workDir.deleteIfOwned(oldOutline);
  }

  /// 윤곽선 모드를 켜고 끈다. 켤 때 아직 추출한 적 없으면 백그라운드로 추출한다.
  void toggleOutline() {
    _outlineMode = !_outlineMode;
    settings?.setOverlayOutline(_outlineMode);
    _notifyStructural();
    if (_outlineMode) unawaited(_ensureOutline());
  }

  Future<void> _ensureOutline() async {
    final source = _file;
    if (source == null || _outlineFile != null || _tracingOutline) return;
    _tracingOutline = true;
    _notifyStructural();
    try {
      final dst = await workDir.reserve('outline', ext: 'png');
      final traced = await traceOutline(source, dst);
      if (_disposed || _file?.path != source.path) {
        // 추출되는 동안 오버레이가 바뀌었거나 화면이 닫혔으면 버린다.
        workDir.deleteIfOwned(traced);
        return;
      }
      _outlineFile = traced;
    } catch (e) {
      debugPrint('윤곽선 추출 실패: $e');
      // 실패하면 원본이라도 보이도록 모드를 되돌린다.
      _outlineMode = false;
      settings?.setOverlayOutline(false);
      onMessage?.call('윤곽선을 추출하지 못해 원본으로 되돌렸습니다.');
    } finally {
      _tracingOutline = false;
      _notifyStructural();
    }
  }

  /// 오버레이 좌우 반전을 켜고 끈다.
  void toggleMirror() {
    if (_file == null) return;
    _mirrored = !_mirrored;
    settings?.setOverlayMirror(_mirrored);
    _notifyStructural();
  }

  /// 오버레이 색 반전(네거티브)을 켜고 끈다.
  void toggleInvert() {
    if (_file == null) return;
    _inverted = !_inverted;
    settings?.setOverlayInvert(_inverted);
    _notifyStructural();
  }

  void _resetTransform() {
    _offset = Offset.zero;
    _scale = 1.0;
    _rotation = 0.0;
  }

  void resetTransform() {
    _resetTransform();
    _notifyStructural();
  }

  void toggleLock() {
    if (_file == null) return;
    _locked = !_locked;
    _notifyStructural();
  }

  /// 투명도 슬라이더 드래그 중 실시간 갱신(저장 안 함).
  /// 우측 패널의 % 표시도 갱신돼야 하므로 구조 알림.
  void setOpacity(double v) {
    _opacity = v;
    _notifyStructural();
  }

  /// 드래그 종료 시 확정 + 저장.
  void commitOpacity(double v) {
    _opacity = v;
    settings?.setOverlayOpacity(v);
    _notifyStructural();
  }

  void toggleAutoUseLast() {
    _autoUseLast = !_autoUseLast;
    settings?.setAutoUseLastShot(_autoUseLast);
    _notifyStructural();
  }

  void onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseRotation = _rotation;
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    _scale = (_baseScale * details.scale).clamp(_minScale, _maxScale);
    _rotation = _baseRotation + details.rotation;
    _offset += details.focalPointDelta;
    _notify();
  }

  // --- 프리셋 저장/불러오기 -------------------------------------------------

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'png';
    final ext = path.substring(dot + 1).toLowerCase();
    return ext.length <= 5 ? ext : 'png';
  }

  Future<Directory> _presetDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/overlay_presets');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  void _persistPresets() => settings?.setOverlayPresets(_presets);

  /// 현재 오버레이(이미지 + 위치·크기·회전·투명도·반전)를 [name]으로 저장한다.
  /// 오버레이가 없으면 무시. 같은 이름이 있으면 덮어쓴다.
  Future<void> savePreset(String name) async {
    final src = _file;
    final trimmed = name.trim();
    if (src == null || trimmed.isEmpty) return;

    final existing = _presets.indexWhere((p) => p.name == trimmed);
    if (existing < 0 && _presets.length >= _maxPresets) {
      onMessage?.call('저장된 프리셋은 최대 $_maxPresets개까지입니다.');
      return;
    }

    try {
      final dir = await _presetDir();
      final id = existing >= 0 ? _presets[existing].id : _newId();
      final dest = File('${dir.path}/$id.${_extOf(src.path)}');
      if (existing >= 0 && _presets[existing].imagePath != dest.path) {
        final oldImg = File(_presets[existing].imagePath);
        if (await oldImg.exists()) await oldImg.delete();
      }
      await src.copy(dest.path);

      final entry = OverlayPreset(
        id: id,
        name: trimmed,
        imagePath: dest.path,
        opacity: _opacity,
        dx: _offset.dx,
        dy: _offset.dy,
        scale: _scale,
        rotation: _rotation,
        mirrored: _mirrored,
        inverted: _inverted,
      );
      final next = [..._presets];
      if (existing >= 0) {
        next[existing] = entry;
      } else {
        next.add(entry);
      }
      _presets = next;
      _persistPresets();
      onMessage?.call(existing >= 0
          ? '"$trimmed" 프리셋을 덮어썼습니다.'
          : '"$trimmed" 프리셋을 저장했습니다.');
      _notifyStructural();
    } on Exception catch (e) {
      debugPrint('오버레이 프리셋 저장 실패: $e');
      onMessage?.call('프리셋을 저장하지 못했습니다.');
    }
  }

  /// 저장된 프리셋을 통째로 불러온다. 이미지가 사라졌으면 그 프리셋을 정리한다.
  Future<void> loadPreset(String id) async {
    final preset = _presets.firstWhereOrNull((p) => p.id == id);
    if (preset == null) return;

    final img = File(preset.imagePath);
    if (!await img.exists()) {
      onMessage?.call('프리셋 이미지를 찾을 수 없습니다.');
      await deletePreset(id);
      return;
    }

    final old = _file;
    final oldOutline = _outlineFile;
    _file = img;
    _outlineFile = null;
    _offset = Offset(preset.dx, preset.dy);
    _scale = preset.scale.clamp(_minScale, _maxScale).toDouble();
    _rotation = preset.rotation;
    _opacity = preset.opacity;
    _mirrored = preset.mirrored;
    _inverted = preset.inverted;
    _locked = false;
    settings?.setOverlayOpacity(_opacity);
    settings?.setOverlayMirror(_mirrored);
    settings?.setOverlayInvert(_inverted);
    _notifyStructural();

    if (old != null && old.path != img.path) workDir.deleteIfOwned(old);
    if (oldOutline != null) workDir.deleteIfOwned(oldOutline);
    if (_outlineMode) unawaited(_ensureOutline());
    onMessage?.call('"${preset.name}" 프리셋을 불러왔습니다.');
  }

  Future<void> deletePreset(String id) async {
    final idx = _presets.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final removed = _presets[idx];
    _presets = [..._presets]..removeAt(idx);
    _persistPresets();
    _notifyStructural();
    try {
      final f = File(removed.imagePath);
      if (await f.exists()) await f.delete();
    } on Exception catch (_) {
      // 파일 삭제 실패는 무시(다음 정리 때 사라짐)
    }
  }
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
