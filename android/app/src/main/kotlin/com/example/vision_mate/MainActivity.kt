package com.example.vision_mate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val volumeButtonChannel = "visionmate/volume_button"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, volumeButtonChannel)
    }

    // Mirrors configureFlutterEngine: clears our reference to this engine's
    // channel when the engine is detached (e.g. engine cache invalidated,
    // activity recreated). Without this, a key event that arrives mid-
    // teardown could call invokeMethod on a channel bound to a
    // BinaryMessenger whose Dart side is already gone — this makes sure
    // that reference is dropped as soon as the engine says it's detaching,
    // so onKeyDown/onKeyUp firing around that moment is a safe no-op
    // (methodCallHandler == null) rather than a call into nothing.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onKeyDown(keyCode: Int, event: android.view.KeyEvent): Boolean {
        if (keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP) {
            // Ignore Android's auto-repeat key-down events: one physical hold
            // must produce one start event and one release event.
            if (event.repeatCount == 0) channel?.invokeMethod("volumeUpPressed", null)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: android.view.KeyEvent): Boolean {
        if (keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP) {
            channel?.invokeMethod("volumeUpReleased", null)
            return true
        }
        return super.onKeyUp(keyCode, event)
    }
}