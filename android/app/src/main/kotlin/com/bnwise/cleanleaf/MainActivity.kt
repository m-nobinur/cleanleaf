package com.bnwise.cleanleaf

import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import com.bnwise.cleanleaf.detection.DetectionBench
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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

    override fun onResume() {
        super.onResume()
        bench?.onForeground(true)
        Log.i("CLBENCH", "onResume")
    }

    override fun onPause() {
        super.onPause()
        bench?.onForeground(false)
        Log.i("CLBENCH", "onPause")
    }

    companion object {
        @Volatile
        private var bench: DetectionBench? = null
    }
}
