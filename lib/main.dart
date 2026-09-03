import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 오류를 로그로 남기되, 처리한 것으로 삼키지는 않는다.
  // false를 돌려줘야 OS 크래시 리포트(TestFlight/App Store Connect)에 잡힌다.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return false;
  };

  // 카메라 HUD는 세로 기준으로 설계돼 있어 세로로 고정한다.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const GhostCameraApp());
}

class GhostCameraApp extends StatelessWidget {
  const GhostCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghost Cam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}
