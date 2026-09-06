package com.dobino.ghostCam

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 볼륨 버튼을 셔터로 쓴다. 카메라 화면이 활성일 때만(Dart 가 setEnabled(true))
 * 볼륨 키 이벤트를 소비해 시스템 볼륨 변경을 막고 Dart 로 "shutter" 를 보낸다.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var interceptVolume = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ghost_cam/volume_button",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        interceptVolume = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (interceptVolume &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            if (event.repeatCount == 0) channel?.invokeMethod("shutter", null)
            return true // 소비 → 시스템 볼륨 UI 안 뜸
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (interceptVolume &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }
}
