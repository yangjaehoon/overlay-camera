import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 삼켜지지 않는 오류도 최소한 로그로 남긴다. (베타 진단용)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
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
