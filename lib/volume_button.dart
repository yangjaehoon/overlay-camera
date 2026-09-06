import 'dart:async';

import 'package:flutter/services.dart';

/// 볼륨 버튼 셔터. 네이티브(Android: MainActivity)에서 "shutter" 를 받아
/// [onShutter] 를 호출한다. [setEnabled]로 가로채기를 켜고 끈다.
///
/// iOS는 하드웨어 볼륨 키가 앱에 이벤트로 오지 않아 별도 네이티브 처리가
/// 필요하며, 현재 채널이 없으므로 [setEnabled]가 조용히 무시된다.
class VolumeButton {
  VolumeButton({required this.onShutter, MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('ghost_cam/volume_button') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  final void Function() onShutter;
  bool _enabled = false;

  bool get enabled => _enabled;

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'shutter' && _enabled) onShutter();
    return null;
  }

  /// 볼륨 키 가로채기를 켜고 끈다. 카메라가 활성일 때만 켠다.
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    try {
      await _channel.invokeMethod('setEnabled', value);
    } on MissingPluginException {
      // 지원하지 않는 플랫폼(현재 iOS)에서는 무시
    } on PlatformException {
      // 네이티브 처리 실패도 치명적이지 않음
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    if (_enabled) {
      _enabled = false;
      unawaited(_channel
          .invokeMethod('setEnabled', false)
          .catchError((Object _) => null));
    }
  }
}
