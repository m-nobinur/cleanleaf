package com.bnwise.cleanleaf.ocrbench

import android.graphics.Rect
import com.googlecode.leptonica.android.ReadFile
import com.googlecode.tesseract.android.ResultIterator
import com.googlecode.tesseract.android.TessBaseAPI
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Tesseract4Android with T-030's configuration: PSM_AUTO, full-resolution page, single thread. */
class TessEngine(
    override val name: String,
    dataPath: String,
    languages: String,
) : BenchEngine {
    private val api =
        TessBaseAPI().apply {
            check(init(dataPath, languages)) { "init $dataPath $languages" }
            setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
        }

    override fun read(page: File): JSONObject {
        val t0 = System.nanoTime()
        val pix = ReadFile.readFile(page) ?: error("unreadable ${page.name}")
        api.setImage(pix)
        pix.recycle()
        val t1 = System.nanoTime()
        val native = api.getUTF8Text() ?: ""
        val t2 = System.nanoTime()
        val lines = JSONArray()
        val words = collect(TessBaseAPI.PageIteratorLevel.RIL_WORD)
        for ((text, rect, conf) in collect(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE)) {
            val inLine = words.filter { Rect.intersects(it.second, rect) && rect.contains(it.second.centerX(), it.second.centerY()) }
            lines.put(lineJson(text.trim(), quad(rect), conf, inLine.map { it.first to quad(it.second) }))
        }
        api.clear()
        return JSONObject()
            .put("lines", lines)
            .put("native", native)
            .put("stages", JSONObject().put("load_ms", (t1 - t0) / 1e6).put("recognize_ms", (t2 - t1) / 1e6))
    }

    private fun collect(level: Int): List<Triple<String, Rect, Double>> {
        val out = mutableListOf<Triple<String, Rect, Double>>()
        val it: ResultIterator = api.getResultIterator() ?: return out
        it.begin()
        do {
            val text = it.getUTF8Text(level) ?: continue
            if (text.isNotBlank()) out += Triple(text, it.getBoundingRect(level), it.confidence(level).toDouble())
        } while (it.next(level))
        it.delete()
        return out
    }

    private fun quad(r: Rect) =
        listOf(
            r.left.toFloat() to r.top.toFloat(),
            r.right.toFloat() to r.top.toFloat(),
            r.right.toFloat() to r.bottom.toFloat(),
            r.left.toFloat() to r.bottom.toFloat(),
        )

    override fun close() = api.recycle()
}
