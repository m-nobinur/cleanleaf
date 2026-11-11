package com.bnwise.cleanleaf

import com.bnwise.cleanleaf.camera.CameraProbe
import com.bnwise.cleanleaf.camera.CameraProbeHostApi
import com.bnwise.cleanleaf.camera.FramesStreamHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val probe = CameraProbe(this, flutterEngine.renderer)
        CameraProbeHostApi.setUp(messenger, probe)
        FramesStreamHandler.register(messenger, probe.frames)
    }
}
