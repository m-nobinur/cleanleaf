package com.bnwise.cleanleaf.detection

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Process
import com.bnwise.cleanleaf.MainActivity

// Runs in its own process: kills the bench process, then relaunches it fresh (ProcessPhoenix pattern).
class RestartActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Process.killProcess(intent.getIntExtra(EXTRA_PID, -1))
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
        )
        finish()
        Runtime.getRuntime().exit(0)
    }

    companion object {
        const val EXTRA_PID = "pid"
    }
}
