package com.bnwise.cleanleaf.ocr

import android.content.Context
import android.os.Process
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.Executors

/**
 * Runs engines on one low-priority thread; Dart queues the pages and picks the engine (decisions.md D-13a, D-64).
 * Only one engine is loaded at a time.
 */
class OcrHost(
    context: Context,
) : OcrHostApi {
    private val engines: Map<String, OcrEngine> =
        mapOf(TesseractEngine.ID to TesseractEngine(context), PpOcrEngine.ID to PpOcrEngine(context))
    private val worker =
        Executors
            .newSingleThreadExecutor { task ->
                Thread({
                    Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                    task.run()
                }, "ocr")
            }.asCoroutineDispatcher()

    // Main thread only, like every Pigeon call.
    private var current: OcrEngine? = null

    @Volatile private var cancelled = false

    override suspend fun recognize(
        engine: String,
        imagePath: String,
        language: String,
        maxLongSide: Long,
    ): OcrPage? {
        val reader = engines[engine] ?: throw FlutterError("unknownEngine", "No OCR engine $engine", null)
        current = reader
        cancelled = false
        return try {
            withContext(worker) {
                engines.values.forEach { if (it !== reader) it.release() }
                reader.read(File(imagePath), language, maxLongSide.toInt()) { cancelled }
            }
        } finally {
            current = null
        }
    }

    override fun cancel() {
        cancelled = true
        current?.stop()
    }

    override suspend fun release() = withContext(worker) { engines.values.forEach { it.release() } }
}
