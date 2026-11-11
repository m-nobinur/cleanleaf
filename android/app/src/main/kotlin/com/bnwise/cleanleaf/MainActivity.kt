package com.bnwise.cleanleaf

import android.os.Build
import android.os.Bundle
import com.bnwise.cleanleaf.camera.CameraProbe
import com.bnwise.cleanleaf.camera.CameraProbeHostApi
import com.bnwise.cleanleaf.camera.FramesStreamHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Spike only: the unattended probe must run even when the phone is on the lock screen.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val probe = CameraProbe(this, flutterEngine.renderer)
        CameraProbeHostApi.setUp(messenger, probe)
        FramesStreamHandler.register(messenger, probe.frames)
    }
}
