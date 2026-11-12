package com.bnwise.cleanleaf.ocr

import android.content.Context
import com.googlecode.leptonica.android.Pix
import com.googlecode.leptonica.android.ReadFile
import com.googlecode.leptonica.android.Scale
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import java.io.File
import java.io.FileOutputStream

/** Tesseract4Android with tessdata_fast eng and tessdata_best ben (decisions.md D-13a, D-60). */
class TesseractEngine(
    private val context: Context,
) : OcrEngine {
    // Created on the OCR thread so the native libraries load only once OCR runs.
    @Volatile private var tess: TessBaseAPI? = null
    private var languages: String? = null
    private val dataDir by lazy { installTessdata() }

    override fun read(
        image: File,
        language: String,
        maxLongSide: Int,
        isCancelled: () -> Boolean,
    ): OcrPage? {
        val tess = tess ?: TessBaseAPI().also { tess = it }
        val languages = LANGUAGES[language] ?: error("Unsupported OCR language $language")
        if (languages != this.languages) {
            this.languages = null
            check(tess.init(dataDir.path, languages)) { "Tesseract could not load $languages" }
            // The API defaults to a single text block; auto layout reads whole pages.
            tess.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            this.languages = languages
        }
        try {
            val pix = load(image, maxLongSide)
            try {
                tess.setImage(pix)
            } finally {
                pix.recycle()
            }
            if (isCancelled()) return null
            // Only the hOCR call honours stop(), so it runs the recognition.
            val hocr = tess.getHOCRText(0)
            if (isCancelled()) return null
            checkNotNull(hocr) { "Tesseract returned no result" }
            return OcrPage(tess.getUTF8Text(), hocr)
        } finally {
            tess.clear()
        }
    }

    override fun stop() {
        tess?.stop()
    }

    override fun release() {
        tess?.recycle()
        tess = null
        languages = null
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
        for (code in listOf("eng", "ben")) {
            val temp = File(tessdata, "$code.tmp")
            context.assets.open(loader.getLookupKeyForAsset("assets/tessdata/$code.traineddata")).use { input ->
                FileOutputStream(temp).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            }
            check(temp.renameTo(File(tessdata, "$code.traineddata"))) { "Could not install $code" }
        }
        stamp.writeText(installed)
        return root
    }

    companion object {
        const val ID = "tesseract"

        // Dart OcrLanguage names to Tesseract language strings.
        private val LANGUAGES = mapOf("auto" to "eng+ben", "english" to "eng", "bangla" to "ben")
    }
}
