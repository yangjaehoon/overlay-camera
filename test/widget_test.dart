import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_camera/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

const _fakeCamera = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// CameraController.initialize()가 성공하도록 필요한 최소한만 구현한 페이크.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform(this._cameras);

  final List<CameraDescription> _cameras;
  final StreamController<CameraInitializedEvent> _initEvents =
      StreamController<CameraInitializedEvent>.broadcast();
  final StreamController<CameraErrorEvent> _errors =
      StreamController<CameraErrorEvent>.broadcast();
  final StreamController<DeviceOrientationChangedEvent> _orientation =
      StreamController<DeviceOrientationChangedEvent>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async => _cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async =>
      0;

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initEvents.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      _orientation.stream;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    _initEvents.add(
      const CameraInitializedEvent(
        0,
        1920,
        1080,
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Future<void> dispose(int cameraId) async {}

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mockPermissions(WidgetTester tester, {required bool granted}) {
    final status = granted ? 1 : 0; // 1=granted, 0=denied
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
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

  void useFakeCamera(WidgetTester tester, List<CameraDescription> cameras) {
    mockPermissions(tester, granted: true);
    CameraPlatform.instance = _FakeCameraPlatform(cameras);
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissionChannel, null),
    );
  }

  Future<void> settleBootstrap(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('카메라가 없으면 안내 화면이 뜬다', (tester) async {
    useFakeCamera(tester, const []);

    await tester.pumpWidget(const GhostCameraApp());
    await settleBootstrap(tester);

    expect(find.text('사용 가능한 카메라를 찾지 못했습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('설정 열기'), findsOneWidget);
  });

  testWidgets('카메라가 준비되면 촬영 UI가 렌더된다', (tester) async {
    useFakeCamera(tester, const [_fakeCamera]);

    await tester.pumpWidget(const GhostCameraApp());
    await settleBootstrap(tester);

    expect(find.text('사진'), findsOneWidget);
    expect(find.text('동영상'), findsOneWidget);
    expect(find.text('스냅샷'), findsOneWidget);
    expect(find.text('전환'), findsOneWidget);
  });

  testWidgets('스탬프 버튼을 누르면 위치 선택 패널이 나타난다', (tester) async {
    useFakeCamera(tester, const [_fakeCamera]);

    await tester.pumpWidget(const GhostCameraApp());
    await settleBootstrap(tester);

    expect(find.text('스탬프 위치'), findsNothing);

    await tester.tap(find.byTooltip('날짜·장소 표시'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('스탬프 위치'), findsOneWidget);
  });
}
