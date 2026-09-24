import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'controller_base.dart';
import 'overlay_outline.dart';
import 'overlay_preset.dart';
import 'path_utils.dart';
import 'preset_utils.dart';
import 'settings_store.dart';
import 'work_dir.dart';

/// 고스트 오버레이의 상태(이미지·투명도·변형·잠금·자동사용)를 담당한다.
/// 드래그처럼 잦은 갱신이 카메라 프리뷰까지 리빌드하지 않도록 별도 [ChangeNotifier]로 분리.
class OverlayController extends StructuralController {
  OverlayController({
    required this.workDir,
    SettingsStore? settings,
    this.onMessage,
  }) {
    this.settings = settings;
  }

  final WorkDir workDir;
  final void Function(String message)? onMessage;

  static const _minScale = 0.15;
  static const _maxScale = 6.0;

  File? _file;
  double _opacity = 0.45;
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0;
  bool _locked = false;
  bool _autoUseLast = true;

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
  void hydrate(SettingsStore s) {
    settings = s;
    _autoUseLast = s.autoUseLastShot;
    _opacity = s.overlayOpacity;
    _outlineMode = s.overlayOutline;
    _mirrored = s.overlayMirror;
    _inverted = s.overlayInvert;
    _presets = s.overlayPresets;
    notifyStructural();
    if (_outlineMode) unawaited(_ensureOutline());
    unawaited(_pruneOrphanPresetImages());
  }

  /// 오버레이 이미지를 교체한다. 이전 파일(+예전 윤곽선)이 작업 폴더 소유면 삭제한다.
  void setFile(File f) {
    final old = _file;
    final oldOutline = _outlineFile;
    _file = f;
    _outlineFile = null; // 새 사진이니 이전 윤곽선은 더 이상 유효하지 않다.
    _resetTransform();
    notifyStructural();
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
    notifyStructural();
    if (old != null) workDir.deleteIfOwned(old);
    if (oldOutline != null) workDir.deleteIfOwned(oldOutline);
  }

  /// 윤곽선 모드를 켜고 끈다. 켤 때 아직 추출한 적 없으면 백그라운드로 추출한다.
  void toggleOutline() {
    _outlineMode = !_outlineMode;
    settings?.setOverlayOutline(_outlineMode);
    notifyStructural();
    if (_outlineMode) unawaited(_ensureOutline());
  }

  Future<void> _ensureOutline() async {
    final source = _file;
    if (source == null || _outlineFile != null || _tracingOutline) return;
    _tracingOutline = true;
    notifyStructural();
    try {
      final dst = await workDir.reserve('outline', ext: 'png');
      final traced = await traceOutline(source, dst);
      if (isDisposed || _file?.path != source.path) {
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
      notifyStructural();
    }
  }

  /// 오버레이 좌우 반전을 켜고 끈다.
  void toggleMirror() {
    if (_file == null) return;
    _mirrored = !_mirrored;
    settings?.setOverlayMirror(_mirrored);
    notifyStructural();
  }

  /// 오버레이 색 반전(네거티브)을 켜고 끈다.
  void toggleInvert() {
    if (_file == null) return;
    _inverted = !_inverted;
    settings?.setOverlayInvert(_inverted);
    notifyStructural();
  }

  void _resetTransform() {
    _offset = Offset.zero;
    _scale = 1.0;
    _rotation = 0.0;
  }

  void resetTransform() {
    _resetTransform();
    notifyStructural();
  }

  void toggleLock() {
    if (_file == null) return;
    _locked = !_locked;
    notifyStructural();
  }

  /// 투명도 슬라이더 드래그 중 실시간 갱신(저장 안 함).
  /// 우측 패널의 % 표시도 갱신돼야 하므로 구조 알림.
  void setOpacity(double v) {
    _opacity = v;
    notifyStructural();
  }

  /// 드래그 종료 시 확정 + 저장.
  void commitOpacity(double v) {
    _opacity = v;
    settings?.setOverlayOpacity(v);
    notifyStructural();
  }

  void toggleAutoUseLast() {
    _autoUseLast = !_autoUseLast;
    settings?.setAutoUseLastShot(_autoUseLast);
    notifyStructural();
  }

  void onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseRotation = _rotation;
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    _scale = (_baseScale * details.scale).clamp(_minScale, _maxScale);
    _rotation = _baseRotation + details.rotation;
    _offset += details.focalPointDelta;
    notify();
  }

  // --- 프리셋 저장/불러오기 -------------------------------------------------

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

    final slot = resolvePresetSlot(
      presets: _presets,
      nameOf: (p) => p.name,
      trimmedName: trimmed,
    );
    if (slot case PresetFull(:final maxCount)) {
      onMessage?.call('저장된 프리셋은 최대 $maxCount개까지입니다.');
      return;
    }
    final overwritten = switch (slot) {
      PresetOverwrite(:final existing) => existing,
      _ => null,
    };

    try {
      final dir = await _presetDir();
      // 덮어쓰기면 기존 id를 유지해 이미지 파일 이름도 그대로 간다.
      final id = overwritten?.id ?? PresetIdSequence.next();
      final dest = File('${dir.path}/$id.${extensionOf(src.path)}');
      final staleImg = overwritten != null && overwritten.imagePath != dest.path
          ? File(overwritten.imagePath)
          : null;

      // 먼저 새 이미지를 복사해 두고, 그게 성공한 뒤에만 옛 이미지(확장자가
      // 바뀐 덮어쓰기 등으로 경로가 달라진 경우)를 지운다. 복사가 실패해도
      // 기존 프리셋은 온전히 남아야 한다.
      await src.copy(dest.path);
      if (staleImg != null && await staleImg.exists()) {
        await staleImg.delete();
      }

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
      _presets = writePreset(_presets, slot, entry);
      _persistPresets();
      onMessage?.call(
        overwritten != null
            ? '"$trimmed" 프리셋을 덮어썼습니다.'
            : '"$trimmed" 프리셋을 저장했습니다.',
      );
      notifyStructural();
    } on Exception catch (e) {
      debugPrint('오버레이 프리셋 저장 실패: $e');
      onMessage?.call('프리셋을 저장하지 못했습니다.');
    }
  }

  /// 저장된 프리셋을 통째로 불러온다. 이미지가 사라졌으면 그 프리셋을 정리한다.
  Future<void> loadPreset(String id) async {
    final preset = _presets.firstWhereOrNull((p) => p.id == id);
    if (preset == null) return;

    try {
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
      notifyStructural();

      if (old != null && old.path != img.path) workDir.deleteIfOwned(old);
      if (oldOutline != null) workDir.deleteIfOwned(oldOutline);
      if (_outlineMode) unawaited(_ensureOutline());
      onMessage?.call('"${preset.name}" 프리셋을 불러왔습니다.');
    } on Exception catch (e) {
      debugPrint('오버레이 프리셋 불러오기 실패: $e');
      onMessage?.call('프리셋을 불러오지 못했습니다.');
    }
  }

  /// 프리셋을 목록·이미지 파일 모두에서 지운다.
  Future<void> deletePreset(String id) async {
    final idx = _presets.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final removed = _presets[idx];
    _presets = [..._presets]..removeAt(idx);
    _persistPresets();
    notifyStructural();
    try {
      final f = File(removed.imagePath);
      if (await f.exists()) await f.delete();
    } on Exception catch (e) {
      // 목록에서는 이미 지워졌으니 사용자에게는 알리지 않는다. 파일이 남아도
      // _pruneOrphanPresetImages 가 다음 hydrate 때 정리한다.
      debugPrint('프리셋 이미지 파일 삭제 실패: $e');
    }
  }

  /// [_presetDir] 안에서 어떤 프리셋도 참조하지 않는 파일을 지운다.
  /// (삭제 실패로 남은 파일, 저장 도중 죽어서 못 지운 파일 등) hydrate 때 한 번 돈다.
  Future<void> _pruneOrphanPresetImages() async {
    try {
      final dir = await _presetDir();
      final referenced = _presets.map((p) => p.imagePath).toSet();
      await for (final entry in dir.list()) {
        if (entry is File && !referenced.contains(entry.path)) {
          try {
            await entry.delete();
          } catch (_) {
            // 개별 삭제 실패는 무시(다음 hydrate 에 다시 시도)
          }
        }
      }
    } on Exception catch (e) {
      debugPrint('프리셋 폴더 정리 실패: $e');
    }
  }
}
