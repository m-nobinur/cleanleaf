package com.bnwise.cleanleaf

import android.os.Bundle
import android.util.Log
import com.bnwise.cleanleaf.detection.DetectionBench
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (bench == null) {
            val b = DetectionBench(applicationContext)
            bench = b
            Thread({
                Thread.sleep(3000)
                runCatching { b.run() }.onFailure {
                    Log.e("CLBENCH", "failed", it)
                    Log.i("CLBENCH", "DONE error")
                }
            }, "clbench").start()
        }
    }

    override fun onPause() {
        super.onPause()
        bench?.interrupted = true
        Log.i("CLBENCH", "onPause")
    }

    companion object {
        @Volatile
        private var bench: DetectionBench? = null
    }
}
