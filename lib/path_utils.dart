/// 파일 경로를 다루는 순수 함수 모음. UI·컨트롤러 어디서든 쓰므로 위젯 파일이
/// 아니라 여기에 둔다.
library;

const _videoExts = {
  '.mp4',
  '.mov',
  '.m4v',
  '.webm',
  '.3gp',
  '.3gpp',
  '.mkv',
  '.avi',
  '.ts',
};

/// 경로 확장자로 동영상 파일인지 판별한다.
bool isVideoPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return _videoExts.contains(path.substring(dot).toLowerCase());
}

/// [path]의 확장자(점 없이, 소문자). 확장자가 없거나 비정상적으로 길면
/// [fallback]을 돌려준다(경로 안의 점을 확장자로 오인하지 않기 위함).
String extensionOf(String path, {String fallback = 'png'}) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return fallback;
  final ext = path.substring(dot + 1).toLowerCase();
  return ext.length <= 5 ? ext : fallback;
}
