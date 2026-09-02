import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'photo_stamp.dart';
import 'settings_store.dart';

/// 날짜·장소 스탬프의 상태와 위치 조회를 담당한다.
class LocationStampController extends ChangeNotifier {
  LocationStampController({this.onMessage});

  /// 사용자에게 보여줄 안내 메시지 콜백 (토스트 등).
  final void Function(String message)? onMessage;

  /// 설정 저장소. 로드 후 주입된다.
  SettingsStore? settings;

  bool _enabled = false;
  StampCorner _corner = StampCorner.bottomRight;
  String? _place;
  bool _resolving = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get enabled => _enabled;
  StampCorner get corner => _corner;
  String? get place => _place;
  bool get resolving => _resolving;

  /// 저장된 설정으로 초기 상태를 맞춘다.
  void hydrate(SettingsStore s) {
    settings = s;
    _enabled = s.stampEnabled;
    _corner = s.stampCorner;
    _notify();
    if (_enabled) unawaited(refreshPlace());
  }

  void toggle() {
    _enabled = !_enabled;
    settings?.setStampEnabled(_enabled);
    _notify();
    // 켤 때마다 현재 위치를 다시 확인한다.
    if (_enabled) unawaited(refreshPlace());
  }

  void selectCorner(StampCorner value) {
    if (value == _corner) return;
    _corner = value;
    settings?.setStampCorner(value);
    _notify();
  }

  /// 스탬프에 넣을 현재 문구.
  String textNow() => buildStampText(DateTime.now(), _place);

  /// 미리보기용 문구 (위치 확인 중이면 안내를 대신 표시).
  String previewText() {
    final hint = _place ?? (_resolving ? '위치 확인 중…' : null);
    return buildStampText(DateTime.now(), hint);
  }

  /// [src] 사진에 스탬프를 그려 넣은 새 파일을 돌려준다.
  /// 스탬프가 꺼져 있거나 실패하면 [src] 그대로 돌려준다.
  Future<File> applyTo(File src) async {
    if (!_enabled) return src;
    try {
      return await stampPhoto(src, text: textNow(), corner: _corner);
    } on Exception catch (e) {
      debugPrint('스탬프 적용 실패: $e');
      onMessage?.call('스탬프를 적용하지 못해 원본으로 저장합니다.');
      return src;
    }
  }

  /// 현재 위치를 역지오코딩해 장소명을 갱신한다.
  /// 권한·서비스가 없거나 실패하면 장소 없이 날짜만 남는다.
  Future<void> refreshPlace() async {
    if (_resolving) return;
    _resolving = true;
    _notify();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        onMessage?.call('위치 서비스가 꺼져 있어 날짜만 표시됩니다.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        onMessage?.call('위치 권한이 없어 날짜만 표시됩니다.');
        return;
      }

      var position = await Geolocator.getLastKnownPosition();
      final stale = position == null ||
          DateTime.now().difference(position.timestamp) >
              const Duration(minutes: 2);
      if (stale) {
        position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 8));
      }

      final marks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (marks.isEmpty) return;
      final mk = marks.first;
      _place =
          shortPlaceName(mk.administrativeArea, mk.locality, mk.subLocality);
    } on TimeoutException {
      onMessage?.call('위치를 확인하지 못해 날짜만 표시됩니다.');
    } catch (e) {
      // 어떤 실패든(권한 취소·플러그인 오류 등) 장소 없이 날짜만으로 강등한다.
      debugPrint('위치 확인 실패: $e');
    } finally {
      _resolving = false;
      _notify();
    }
  }
}
