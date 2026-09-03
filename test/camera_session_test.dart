import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/camera_session.dart';
import 'package:ghost_camera/settings_store.dart';
import 'package:ghost_camera/work_dir.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// availableCameras()만 대답하는 최소 페이크. 나머지 호출은 UnimplementedError.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform(this._cameras);

  final List<CameraDescription> _cameras;
  int availableCamerasCalls = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    availableCamerasCalls++;
    return _cameras;
  }
}

const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void mockPermissions({required bool granted}) {
    final status = granted ? 1 : 0; // 1=granted, 0=denied
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _permissionChannel,
      (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            return status;
          case 'requestPermissions':
            final list = (call.arguments as List).cast<int>();
            return {for (final v in list) v: status};
          default:
            return null;
        }
      },
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, null);
  });

  group('nextFlashMode', () {
    test('off→auto→always→torch→off 순환', () {
      expect(nextFlashMode(FlashMode.off), FlashMode.auto);
      expect(nextFlashMode(FlashMode.auto), FlashMode.always);
      expect(nextFlashMode(FlashMode.always), FlashMode.torch);
      expect(nextFlashMode(FlashMode.torch), FlashMode.off);
    });
  });

  group('hydrate', () {
    test('torch로 저장돼 있으면 off로 낮춘다', () async {
      final store = await SettingsStore.load();
      store.setFlashMode(FlashMode.torch);
      store.setSilentShutter(true);

      final session = CameraSession(workDir: WorkDir())
        ..hydrate(await SettingsStore.load());
      expect(session.flashMode, FlashMode.off);
      expect(session.silentShutter, true);
      session.dispose();
    });

    test('torch가 아니면 그대로 복원', () async {
      final store = await SettingsStore.load();
      store.setFlashMode(FlashMode.auto);

      final session = CameraSession(workDir: WorkDir())
        ..hydrate(await SettingsStore.load());
      expect(session.flashMode, FlashMode.auto);
      session.dispose();
    });
  });

  test('toggleSilentShutter는 값을 뒤집고 한 번 알린다', () async {
    final session = CameraSession(workDir: WorkDir())
      ..settings = await SettingsStore.load();
    var notified = 0;
    session.addListener(() => notified++);

    expect(session.silentShutter, false);
    session.toggleSilentShutter();
    expect(session.silentShutter, true);
    expect(notified, 1);
    session.dispose();
  });

  test('runExclusive: 진행 중이면 두 번째 호출은 무시된다', () async {
    final session = CameraSession(workDir: WorkDir());
    var runs = 0;

    final first = session.runExclusive(() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    final second = session.runExclusive(() async => runs++);
    await Future.wait([first, second]);

    expect(runs, 1);
    expect(session.busy, false);
    session.dispose();
  });

  test('didChangeAppLifecycleState(paused): 촬영 상태를 리셋하고 알린다', () {
    final session = CameraSession(workDir: WorkDir());
    var notified = 0;
    session.addListener(() => notified++);

    session.didChangeAppLifecycleState(AppLifecycleState.paused);

    expect(session.isRecording, false);
    expect(session.busy, false);
    expect(notified, 1);
    session.dispose();
  });

  test('dispose 후 상태 변경 메서드를 불러도 예외가 없다', () {
    final session = CameraSession(workDir: WorkDir())..dispose();
    expect(session.toggleSilentShutter, returnsNormally);
  });

  group('bootstrap', () {
    test('권한 거부 시 안내 메시지 설정', () async {
      mockPermissions(granted: false);
      CameraPlatform.instance = _FakeCameraPlatform([]);

      final session = CameraSession(workDir: WorkDir());
      await session.bootstrap();

      expect(session.statusMessage, contains('권한이 필요'));
      session.dispose();
    });

    test('권한 허용 + 카메라 없음 → 안내 메시지', () async {
      mockPermissions(granted: true);
      CameraPlatform.instance = _FakeCameraPlatform([]);

      final session = CameraSession(workDir: WorkDir());
      await session.bootstrap();

      expect(session.statusMessage, contains('찾지 못했'));
      session.dispose();
    });

    test('재진입 가드: 동시에 호출해도 availableCameras는 한 번만', () async {
      mockPermissions(granted: true);
      final fake = _FakeCameraPlatform([]);
      CameraPlatform.instance = fake;

      final session = CameraSession(workDir: WorkDir());
      await Future.wait([session.bootstrap(), session.bootstrap()]);

      expect(fake.availableCamerasCalls, 1);
      session.dispose();
    });
  });
}
