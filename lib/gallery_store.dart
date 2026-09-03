import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

/// 갤러리(사진 보관함) 저장. 실패 시 [onMessage]로 안내한다.
class GalleryStore {
  GalleryStore({this.onMessage, this.album = 'Ghost Cam'});

  final void Function(String message)? onMessage;
  final String album;

  Future<void> saveImage(String path) => _save(() => Gal.putImage(path, album: album));

  Future<void> saveVideo(String path) => _save(() => Gal.putVideo(path, album: album));

  Future<void> _save(Future<void> Function() put) async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await put();
    } on GalException {
      onMessage?.call('갤러리 저장 권한을 확인해 주세요.');
    } on Exception catch (e) {
      debugPrint('갤러리 저장 실패: $e');
      onMessage?.call('갤러리에 저장하지 못했습니다.');
    }
  }
}
