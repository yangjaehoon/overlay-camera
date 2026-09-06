import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/volume_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/volume_button');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> nativeSends(String method) => messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method)),
        (_) {},
      );

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('setEnabled 는 네이티브에 값을 전달하고 중복 호출은 건너뛴다', () async {
    final sent = <bool>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setEnabled') sent.add(call.arguments as bool);
      return null;
    });
    final vb = VolumeButton(onShutter: () {}, channel: channel);

    await vb.setEnabled(true);
    await vb.setEnabled(true); // 중복 → 무시
    await vb.setEnabled(false);
    await vb.setEnabled(false);

    expect(sent, [true, false]);
    vb.dispose();
  });

  test('네이티브 shutter 는 enabled 일 때만 onShutter 를 호출한다', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    var shots = 0;
    final vb = VolumeButton(onShutter: () => shots++, channel: channel);

    await nativeSends('shutter');
    expect(shots, 0); // 아직 enabled 아님

    await vb.setEnabled(true);
    await nativeSends('shutter');
    await nativeSends('shutter');
    expect(shots, 2);

    await vb.setEnabled(false);
    await nativeSends('shutter');
    expect(shots, 2); // 꺼진 뒤엔 무시

    vb.dispose();
  });

  test('채널 미구현(iOS 등)이면 setEnabled 가 조용히 넘어간다', () async {
    // mock 핸들러를 설정하지 않음 → MissingPluginException
    final vb = VolumeButton(onShutter: () {}, channel: channel);
    await expectLater(vb.setEnabled(true), completes);
    vb.dispose();
  });

  test('dispose 후엔 네이티브 shutter 를 받아도 아무 일 없다', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    var shots = 0;
    final vb = VolumeButton(onShutter: () => shots++, channel: channel);
    await vb.setEnabled(true);
    vb.dispose();

    await nativeSends('shutter');
    expect(shots, 0);
  });
}
