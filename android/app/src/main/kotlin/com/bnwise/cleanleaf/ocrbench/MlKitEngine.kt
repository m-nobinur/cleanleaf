package com.bnwise.cleanleaf.ocrbench

import android.content.Context
import android.graphics.BitmapFactory
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Bundled ML Kit Latin recognizer, initialized manually (MlKitInitProvider is removed, D-37). */
class MlKitEngine(
    context: Context,
) : BenchEngine {
    override val name = "mlkit"

    private val recognizer = create(context.applicationContext)

    // With MlKitInitProvider removed (D-37), MlKit.initialize's manifest discovery never registered the
    // text component (getClient NPE on the KM6), so the context is built from explicit registrars.
    private fun create(context: Context): TextRecognizer {
        val registrars =
            listOf(
                "com.google.mlkit.common.internal.CommonComponentRegistrar",
                "com.google.mlkit.vision.common.internal.VisionCommonRegistrar",
                "com.google.mlkit.vision.text.internal.TextRegistrar",
            ).map { Class.forName(it).getDeclaredConstructor().newInstance() }
        Class
            .forName("com.google.mlkit.common.sdkinternal.MlKitContext")
            .getMethod("initialize", Context::class.java, List::class.java)
            .invoke(null, context, registrars)
        return TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    override fun read(page: File): JSONObject {
        val t0 = System.nanoTime()
        val bitmap = BitmapFactory.decodeFile(page.path) ?: error("unreadable ${page.name}")
        val t1 = System.nanoTime()
        val text = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)))
        val t2 = System.nanoTime()
        bitmap.recycle()
        val lines = JSONArray()
        for (block in text.textBlocks) {
            for (line in block.lines) {
                val corners = line.cornerPoints ?: continue
                lines.put(
                    lineJson(
                        line.text,
                        corners.map { it.x.toFloat() to it.y.toFloat() },
                        line.confidence.toDouble(),
                        line.elements.mapNotNull { e -> e.cornerPoints?.let { c -> e.text to c.map { it.x.toFloat() to it.y.toFloat() } } },
                    ),
                )
            }
        }
        return JSONObject()
            .put("lines", lines)
            .put("native", text.text)
            .put("stages", JSONObject().put("decode_ms", (t1 - t0) / 1e6).put("recognize_ms", (t2 - t1) / 1e6))
    }

    override fun close() = recognizer.close()
}
