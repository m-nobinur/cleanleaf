package com.bnwise.cleanleaf

import com.bnwise.cleanleaf.visionspike.VisionBench
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // T-003 probe: only lib/spike/vision/bench_main.dart sends "ready".
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clbench")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                VisionBench(channel, this).start()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
