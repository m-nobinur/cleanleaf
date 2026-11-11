package com.bnwise.cleanleaf.detection

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.Locale
import kotlin.math.roundToInt

object Affinity {
    init {
        System.loadLibrary("clbench")
    }

    external fun pin(mask: Int): Int
}

private const val TAG = "CLBENCH"
private const val IN = 256
private const val HM = 128
private const val A55 = 0x3F
private const val A76 = 0xC0
private const val PAD_ZERO = "lc100_fp16_padzero.tflite"
private const val PLAIN = "lc100_fp16.tflite"

private data class Config(
    val name: String,
    val model: String,
    val threads: Int,
    val mask: Int = 0,
    val xnnpack: Boolean = true,
    val fp16: Boolean = false,
    val runs: Int = 30,
)

private class Detection(val peaks: FloatArray, val corners: FloatArray?)

class DetectionBench(private val context: Context) {
    @Volatile
    var interrupted = false

    private val configs = listOf(
        Config("all_t1", PAD_ZERO, 1),
        Config("all_t2", PAD_ZERO, 2),
        Config("all_t4", PAD_ZERO, 4),
        Config("a55_t1", PAD_ZERO, 1, A55),
        Config("a55_t2", PAD_ZERO, 2, A55),
        Config("a55_t4", PAD_ZERO, 4, A55),
        Config("a76_t1", PAD_ZERO, 1, A76),
        Config("a76_t2", PAD_ZERO, 2, A76),
        Config("a55_t4_fp16", PAD_ZERO, 4, A55, fp16 = true),
        Config("a55_t1_plain", PLAIN, 1, A55),
        Config("a55_t4_plain", PLAIN, 4, A55),
        Config("all_t4_noxnn", PAD_ZERO, 4, xnnpack = false, runs = 8),
    )

    fun run() {
        log("start model=${Build.MODEL} soc=${soc()} sdk=${Build.VERSION.SDK_INT} thermal=${thermal()}")
        val models = mapOf(PAD_ZERO to loadModel(PAD_ZERO), PLAIN to loadModel(PLAIN))
        val doc = tensorFromBgr("bench_doc_256.bgr")
        val nodoc = tensorFromBgr("bench_nodoc_256.bgr")
        parityAndPostTiming(models.getValue(PAD_ZERO), doc, nodoc)
        preprocessTiming()
        for (pass in 1..2) {
            for (cfg in if (pass == 1) configs else configs.reversed()) {
                onFreshThread { bench(cfg, models.getValue(cfg.model), doc, pass) }
                Thread.sleep(300)
            }
        }
        log("end thermal=${thermal()} interrupted=$interrupted")
        log("DONE")
    }

    private fun bench(cfg: Config, model: ByteBuffer, input: ByteBuffer, pass: Int) {
        val before = threadIds()
        val pinRc = if (cfg.mask != 0) Affinity.pin(cfg.mask) else 0
        val options = Interpreter.Options().setNumThreads(cfg.threads).setUseXNNPACK(cfg.xnnpack)
        if (cfg.fp16) options.setAllowFp16PrecisionForFp32(true)
        val t0 = System.nanoTime()
        val interpreter = Interpreter(model, options)
        val createMs = ms(t0)
        val output = newOutput()
        val t1 = System.nanoTime()
        infer(interpreter, input, output)
        val firstMs = ms(t1)
        repeat(4) { infer(interpreter, input, output) }
        val wall = DoubleArray(cfg.runs)
        val native = DoubleArray(cfg.runs)
        for (i in 0 until cfg.runs) {
            val s = System.nanoTime()
            infer(interpreter, input, output)
            wall[i] = ms(s)
            native[i] = (interpreter.lastNativeInferenceDurationNanoseconds ?: 0L) / 1e6
        }
        val peaks = postprocess(output, IN, IN).peaks
        val spawned = (threadIds() - before).sorted().map(::describe)
        interpreter.close()
        log(
            "cfg=${cfg.name} pass=$pass model=${cfg.model} threads=${cfg.threads} " +
                "mask=0x${Integer.toHexString(cfg.mask)} pin_rc=$pinRc xnnpack=${cfg.xnnpack} fp16=${cfg.fp16} " +
                "create_ms=${f(createMs)} first_ms=${f(firstMs)} n=${cfg.runs} " +
                "p50=${f(pct(wall, 50))} p90=${f(pct(wall, 90))} mean=${f(wall.average())} " +
                "min=${f(wall.min())} max=${f(wall.max())} native_p50=${f(pct(native, 50))} " +
                "peaks=${peaks.joinToString(",") { f(it.toDouble(), 3) }} thermal=${thermal()} interrupted=$interrupted",
        )
        log("threads cfg=${cfg.name} pass=$pass self=${describe(Process.myTid())} spawned=${spawned.size} ${spawned.joinToString(" ")}")
    }

    private fun parityAndPostTiming(model: ByteBuffer, doc: ByteBuffer, nodoc: ByteBuffer) {
        val interpreter = Interpreter(model, Interpreter.Options().setNumThreads(1))
        val output = newOutput()
        for ((name, input) in listOf("doc" to doc, "nodoc" to nodoc)) {
            infer(interpreter, input, output)
            val d = postprocess(output, IN, IN)
            val corners = d.corners?.joinToString(",") { f(it.toDouble(), 2) } ?: "none"
            log("parity input=$name peaks=${d.peaks.joinToString(",") { f(it.toDouble(), 4) }} corners_256=$corners")
        }
        infer(interpreter, doc, output)
        repeat(5) { postprocess(output, 1200, 1600) }
        val t = DoubleArray(50) {
            val s = System.nanoTime()
            postprocess(output, 1200, 1600)
            ms(s)
        }
        log("post_ms p50=${f(pct(t, 50), 2)} p90=${f(pct(t, 90), 2)}")
        interpreter.close()
    }

    private fun preprocessTiming() {
        val frame = context.assets.open("bench_frame.jpg").use { BitmapFactory.decodeStream(it) }
        val live = Bitmap.createScaledBitmap(frame, 480, 640, true)
        val buffer = newInput()
        val pixels = IntArray(IN * IN)
        for ((name, bmp) in listOf("still_${frame.width}x${frame.height}" to frame, "live_480x640" to live)) {
            repeat(3) { preprocess(bmp, buffer, pixels) }
            val t = DoubleArray(20) {
                val s = System.nanoTime()
                preprocess(bmp, buffer, pixels)
                ms(s)
            }
            log("pre_ms src=$name p50=${f(pct(t, 50), 2)} p90=${f(pct(t, 90), 2)}")
        }
    }

    // Stretch-resize to 256x256, BGR, /255, NHWC: DocAligner's preprocessing.
    private fun preprocess(bmp: Bitmap, out: ByteBuffer, pixels: IntArray) {
        val scaled = Bitmap.createScaledBitmap(bmp, IN, IN, true)
        scaled.getPixels(pixels, 0, IN, 0, 0, IN, IN)
        if (scaled !== bmp) scaled.recycle()
        out.rewind()
        val fb = out.asFloatBuffer()
        for (p in pixels) {
            fb.put((p and 0xFF) / 255f)
            fb.put(((p shr 8) and 0xFF) / 255f)
            fb.put(((p shr 16) and 0xFF) / 255f)
        }
    }

    // Per channel: threshold 0.3, centroid of the largest 8-connected blob, mapped to image pixels.
    private fun postprocess(output: ByteBuffer, width: Int, height: Int): Detection {
        output.rewind()
        val hm = FloatArray(HM * HM * 4)
        output.asFloatBuffer().get(hm)
        val peaks = FloatArray(4)
        val corners = FloatArray(8)
        val mask = BooleanArray(HM * HM)
        val seen = BooleanArray(HM * HM)
        val stack = IntArray(HM * HM)
        var found = true
        for (k in 0 until 4) {
            var peak = 0f
            for (i in 0 until HM * HM) {
                val v = hm[i * 4 + k]
                if (v > peak) peak = v
                mask[i] = v >= 0.3f
            }
            peaks[k] = peak
            seen.fill(false)
            var bestN = 0
            var bestX = 0.0
            var bestY = 0.0
            for (start in 0 until HM * HM) {
                if (!mask[start] || seen[start]) continue
                var sp = 0
                stack[sp++] = start
                seen[start] = true
                var n = 0
                var sx = 0.0
                var sy = 0.0
                while (sp > 0) {
                    val p = stack[--sp]
                    val x = p % HM
                    val y = p / HM
                    n++
                    sx += x
                    sy += y
                    for (dy in -1..1) {
                        for (dx in -1..1) {
                            val nx = x + dx
                            val ny = y + dy
                            if (nx < 0 || ny < 0 || nx >= HM || ny >= HM) continue
                            val q = ny * HM + nx
                            if (mask[q] && !seen[q]) {
                                seen[q] = true
                                stack[sp++] = q
                            }
                        }
                    }
                }
                if (n > bestN) {
                    bestN = n
                    bestX = sx / n
                    bestY = sy / n
                }
            }
            if (bestN == 0) {
                found = false
                continue
            }
            corners[2 * k] = ((bestX + 0.5) * width / HM - 0.5).toFloat()
            corners[2 * k + 1] = ((bestY + 0.5) * height / HM - 0.5).toFloat()
        }
        return Detection(peaks, if (found) corners else null)
    }

    private fun infer(interpreter: Interpreter, input: ByteBuffer, output: ByteBuffer) {
        input.rewind()
        output.rewind()
        interpreter.run(input, output)
    }

    private fun loadModel(asset: String): ByteBuffer =
        runCatching {
            context.assets.openFd(asset).use { fd ->
                FileInputStream(fd.fileDescriptor).channel.use { ch ->
                    ch.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
                }
            }
        }.getOrElse {
            log("model $asset not mmappable (${it.javaClass.simpleName}), copying")
            val bytes = context.assets.open(asset).use { s -> s.readBytes() }
            ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).put(bytes).also { b -> b.rewind() }
        }

    private fun tensorFromBgr(asset: String): ByteBuffer {
        val bytes = context.assets.open(asset).use { it.readBytes() }
        val buffer = newInput()
        val fb = buffer.asFloatBuffer()
        for (b in bytes) fb.put((b.toInt() and 0xFF) / 255f)
        return buffer
    }

    private fun newInput() = ByteBuffer.allocateDirect(IN * IN * 3 * 4).order(ByteOrder.nativeOrder())

    private fun newOutput() = ByteBuffer.allocateDirect(HM * HM * 4 * 4).order(ByteOrder.nativeOrder())

    private fun onFreshThread(block: () -> Unit) {
        val t = Thread(block, "clbench-cfg")
        t.start()
        t.join()
    }

    private fun threadIds(): Set<Int> =
        File("/proc/self/task").list()?.mapNotNull { it.toIntOrNull() }?.toSet() ?: emptySet()

    private fun describe(tid: Int): String {
        val dir = "/proc/self/task/$tid"
        val name = runCatching { File("$dir/comm").readText().trim() }.getOrDefault("?")
        val allowed = runCatching {
            File("$dir/status").readLines().first { it.startsWith("Cpus_allowed_list:") }.substringAfter(":").trim()
        }.getOrDefault("?")
        val lastCpu = runCatching { File("$dir/stat").readText().substringAfterLast(")").trim().split(" ")[36] }.getOrDefault("?")
        return "$tid/$name/cpus=$allowed/last=$lastCpu"
    }

    private fun thermal(): String {
        if (Build.VERSION.SDK_INT < 29) return "n/a"
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.currentThermalStatus.toString()
    }

    private fun soc(): String = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else Build.HARDWARE

    private fun log(msg: String) {
        Log.i(TAG, msg)
    }
}

private fun ms(start: Long) = (System.nanoTime() - start) / 1e6

private fun pct(a: DoubleArray, p: Int): Double {
    val s = a.sorted()
    return s[((s.size - 1) * p / 100.0).roundToInt()]
}

private fun f(v: Double, digits: Int = 1) = String.format(Locale.US, "%.${digits}f", v)
