package com.bnwise.cleanleaf

import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.util.Log
import android.view.WindowManager
import com.bnwise.cleanleaf.detection.DetectionBench
import com.bnwise.cleanleaf.detection.RestartActivity
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (bench == null) {
            val b = DetectionBench(applicationContext)
            bench = b
            Thread({
                Thread.sleep(1500)
                val more = runCatching { b.runStep() }.getOrElse {
                    Log.e("CLBENCH", "failed", it)
                    Log.i("CLBENCH", "DONE error")
                    false
                }
                if (more) {
                    runOnUiThread {
                        startActivity(
                            Intent(this, RestartActivity::class.java)
                                .putExtra(RestartActivity.EXTRA_PID, Process.myPid())
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }
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
