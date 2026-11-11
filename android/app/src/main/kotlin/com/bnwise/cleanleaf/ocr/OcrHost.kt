package com.bnwise.cleanleaf.ocr

import android.content.Context
import android.os.Process
import com.googlecode.leptonica.android.Pix
import com.googlecode.leptonica.android.ReadFile
import com.googlecode.leptonica.android.Scale
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/** Tesseract on one low-priority thread; Dart queues the pages (decisions.md D-13a). */
class OcrHost(
    private val context: Context,
) : OcrHostApi {
    private val worker =
        Executors
            .newSingleThreadExecutor { task ->
                Thread({
                    Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                    task.run()
                }, "ocr")
            }.asCoroutineDispatcher()

    // Created on the worker so the native libraries load only once OCR runs.
    @Volatile private var tess: TessBaseAPI? = null
    private var languages: String? = null
    private val dataDir by lazy { installTessdata() }

    @Volatile private var cancelled = false

    override suspend fun recognize(
        imagePath: String,
        languages: String,
        maxLongSide: Long,
    ): OcrPage? {
        cancelled = false
        return withContext(worker) { read(imagePath, languages, maxLongSide.toInt()) }
    }

    override fun cancel() {
        cancelled = true
        tess?.stop()
    }

    private fun read(
        imagePath: String,
        languages: String,
        maxLongSide: Int,
    ): OcrPage? {
        val tess = tess ?: TessBaseAPI().also { tess = it }
        if (languages != this.languages) {
            this.languages = null
            check(tess.init(dataDir.path, languages)) { "Tesseract could not load $languages" }
            // The API defaults to a single text block; auto layout reads whole pages.
            tess.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            this.languages = languages
        }
        try {
            val pix = load(File(imagePath), maxLongSide)
            try {
                tess.setImage(pix)
            } finally {
                pix.recycle()
            }
            if (cancelled) return null
            // Only the hOCR call honours stop(), so it runs the recognition.
            val hocr = tess.getHOCRText(0)
            if (cancelled || hocr == null) return null
            return OcrPage(tess.getUTF8Text(), hocr)
        } finally {
            tess.clear()
        }
    }

    private fun load(
        file: File,
        maxLongSide: Int,
    ): Pix {
        val pix = ReadFile.readFile(file) ?: error("Unreadable image ${file.name}")
        val longSide = maxOf(pix.width, pix.height)
        if (maxLongSide <= 0 || longSide <= maxLongSide) return pix
        return Scale.scale(pix, maxLongSide.toFloat() / longSide).also { pix.recycle() }
    }

    // Copied again after each install or update, so new traineddata replaces old.
    private fun installTessdata(): File {
        val root = File(context.filesDir, "tesseract")
        val stamp = File(root, "installed")
        @Suppress("DEPRECATION")
        val installed =
            context.packageManager
                .getPackageInfo(context.packageName, 0)
                .lastUpdateTime
                .toString()
        if (stamp.isFile && stamp.readText() == installed) return root
        val tessdata = File(root, "tessdata").apply { mkdirs() }
        val loader = FlutterInjector.instance().flutterLoader()
        for (language in TESSDATA) {
            val temp = File(tessdata, "$language.tmp")
            context.assets.open(loader.getLookupKeyForAsset("assets/tessdata/$language.traineddata")).use { input ->
                FileOutputStream(temp).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            }
            check(temp.renameTo(File(tessdata, "$language.traineddata"))) { "Could not install $language" }
        }
        stamp.writeText(installed)
        return root
    }

    private companion object {
        val TESSDATA = listOf("eng", "ben")
    }
}
