package com.bnwise.cleanleaf.ocr

import android.content.Context
import com.bnwise.cleanleaf.vision.ClVision
import io.flutter.FlutterInjector
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** PP-OCRv6 small in clvision for English (decisions.md D-64): fp16, width-dynamic rec, 4 threads. */
class PpOcrEngine(
    private val context: Context,
) : OcrEngine {
    // OCR thread only. Created there so XNNPACK's workers inherit its background priority.
    private var handle = 0L
    private val cancel = ByteBuffer.allocateDirect(Int.SIZE_BYTES).order(ByteOrder.nativeOrder())

    override fun read(
        image: File,
        language: String,
        maxLongSide: Int,
        isCancelled: () -> Boolean,
    ): OcrPage? {
        if (handle == 0L) handle = create()
        cancel.putInt(0, 0)
        // A stop() before the reset above is still seen here.
        if (isCancelled()) return null
        // Auto only needs to know a page is non-Latin before Tesseract re-reads it (D-59).
        val json = ClVision.ocrRead(handle, image.readBytes(), language == "auto", cancel) ?: return null
        if (isCancelled()) return null
        val page = JSONObject(String(json, Charsets.UTF_8))
        return OcrPage(page.getString("text"), page.getString("hocr"), page.getBoolean("non_latin"))
    }

    override fun stop() {
        cancel.putInt(0, 1)
    }

    override fun release() {
        if (handle == 0L) return
        ClVision.ocrDestroy(handle)
        handle = 0L
    }

    private fun create(): Long {
        val loader = FlutterInjector.instance().flutterLoader()

        fun asset(name: String) =
            context.assets.open(loader.getLookupKeyForAsset("assets/models/$name")).use { it.readBytes() }
        val handle =
            ClVision.ocrCreate(
                asset("ppocr_v6s_det960_fp16w.tflite"),
                asset("ppocr_v6s_rec_latin_dynw_fp16w.tflite"),
                asset("ppocr_v6s_rec_latin_dict.txt"),
                true,
                THREADS,
            )
        check(handle != 0L) { "PP-OCR could not load its models" }
        return handle
    }

    companion object {
        const val ID = "ppocr"
        private const val THREADS = 4
    }
}
