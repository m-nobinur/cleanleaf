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

// LiteRT's C API through our JNI shim, to control XNNPACK's thread count directly.
object NativeBench {
    init {
        System.loadLibrary("tensorflowlite_jni")
        System.loadLibrary("clbench")
    }

    external fun create(model: ByteBuffer, threads: Int, explicitXnnpack: Boolean, flags: Int): Long

    external fun run(handle: Long, input: ByteBuffer, output: ByteBuffer): Int

    external fun destroy(handle: Long)
}

private const val TAG = "CLBENCH"
private const val IN = 256
private const val HM = 128
private const val A55 = 0x3F
private const val A76 = 0xC0
private const val PAD_ZERO = "lc100_fp16_padzero.tflite"

private enum class Api { JAVA, C_API, C_XNNPACK }

private const val XNNPACK_FORCE_FP16 = 0x4

private data class Config(
    val name: String,
    val api: Api,
    val threads: Int,
    val mask: Int = 0,
    val fp16: Boolean = false,
    val runs: Int = 30,
)

// One step per process: XNNPACK's thread pool may be fixed by the first interpreter a process creates.
private val steps: List<Config?> = listOf(
    Config("xnn_a55_t4", Api.C_XNNPACK, 4, A55),
    Config("xnn_a55_t1_fp16", Api.C_XNNPACK, 1, A55, fp16 = true),
    Config("xnn_a55_t2_fp16", Api.C_XNNPACK, 2, A55, fp16 = true),
    Config("xnn_a55_t4_fp16", Api.C_XNNPACK, 4, A55, fp16 = true),
    Config("xnn_a55_t6_fp16", Api.C_XNNPACK, 6, A55, fp16 = true),
    Config("xnn_all_t4_fp16", Api.C_XNNPACK, 4, fp16 = true),
    Config("xnn_a55_t4_again", Api.C_XNNPACK, 4, A55),
)

private class Detection(val peaks: FloatArray, val corners: FloatArray?)

private interface Engine : AutoCloseable {
    fun infer(input: ByteBuffer, output: ByteBuffer)
}

private class JavaEngine(model: ByteBuffer, threads: Int) : Engine {
    private val interpreter = Interpreter(model, Interpreter.Options().setNumThreads(threads).setUseXNNPACK(true))

    override fun infer(input: ByteBuffer, output: ByteBuffer) {
        input.rewind()
        output.rewind()
        interpreter.run(input, output)
    }

    override fun close() = interpreter.close()
}

private class NativeEngine(model: ByteBuffer, threads: Int, explicitXnnpack: Boolean, flags: Int = 0) : Engine {
    // Heap pointers are tagged on arm64 Android (negative as Long); errors are -1..-20.
    private val handle = NativeBench.create(model, threads, explicitXnnpack, flags).also {
        check(it !in -20L..0L) { "native create failed: $it" }
    }

    override fun infer(input: ByteBuffer, output: ByteBuffer) {
        val rc = NativeBench.run(handle, input, output)
        check(rc == 0) { "native run failed: $rc" }
    }

    override fun close() = NativeBench.destroy(handle)
}

class DetectionBench(private val context: Context) {
    @Volatile
    private var foreground = false

    @Volatile
    private var pauses = 0

    private val logFile = File(context.getExternalFilesDir(null), "clbench.log")

    fun onForeground(value: Boolean) {
        if (!value) pauses++
        foreground = value
    }

    /** Runs this process's step. Returns true when another step follows (the caller restarts the process). */
    fun runStep(): Boolean {
        val prefs = context.getSharedPreferences("clbench", Context.MODE_PRIVATE)
        val step = prefs.getInt("step", 0)
        if (step == 0) {
            logFile.delete()
            log("start model=${Build.MODEL} soc=${soc()} sdk=${Build.VERSION.SDK_INT} thermal=${thermal()} steps=${steps.size}")
        }
        val model = loadModel(PAD_ZERO)
        val doc = tensorFromBgr("bench_doc_256.bgr")
        val cfg = steps[step]
        if (cfg == null) {
            val nodoc = tensorFromBgr("bench_nodoc_256.bgr")
            measured("parity") { parityAndPostTiming(model, doc, nodoc) }
            measured("pre") { preprocessTiming() }
        } else {
            measured("cfg=${cfg.name}") { onFreshThread { bench(cfg, model, doc) } }
        }
        val more = step + 1 < steps.size
        prefs.edit().putInt("step", if (more) step + 1 else 0).commit()
        if (!more) {
            log("end thermal=${thermal()}")
            log("DONE")
        }
        return more
    }

    // A paused app may be frozen or descheduled; such numbers are discarded and re-measured.
    private fun measured(label: String, block: () -> Unit) {
        repeat(3) { attempt ->
            if (!foreground) {
                log("waiting for foreground before $label")
                while (!foreground) Thread.sleep(200)
                Thread.sleep(1000)
            }
            val before = pauses
            block()
            if (pauses == before) return
            log("$label invalid: paused during run (attempt ${attempt + 1})")
        }
    }

    private fun bench(cfg: Config, model: ByteBuffer, input: ByteBuffer) {
        val before = threadIds()
        val pinRc = if (cfg.mask != 0) Affinity.pin(cfg.mask) else 0
        val output = newOutput()
        val t0 = System.nanoTime()
        val engine = when (cfg.api) {
            Api.JAVA -> JavaEngine(model, cfg.threads)
            Api.C_API -> NativeEngine(model, cfg.threads, explicitXnnpack = false)
            Api.C_XNNPACK -> NativeEngine(model, cfg.threads, true, if (cfg.fp16) XNNPACK_FORCE_FP16 else 0)
        }
        val createMs = ms(t0)
        val t1 = System.nanoTime()
        engine.infer(input, output)
        val firstMs = ms(t1)
        repeat(4) { engine.infer(input, output) }
        val wall = DoubleArray(cfg.runs)
        for (i in 0 until cfg.runs) {
            val s = System.nanoTime()
            engine.infer(input, output)
            wall[i] = ms(s)
        }
        val detection = postprocess(output, IN, IN)
        val spawned = (threadIds() - before).sorted().map(::describe)
        engine.close()
        log(
            "cfg=${cfg.name} pid=${Process.myPid()} api=${cfg.api} threads=${cfg.threads} " +
                "mask=0x${Integer.toHexString(cfg.mask)} pin_rc=$pinRc " +
                "create_ms=${f(createMs)} first_ms=${f(firstMs)} n=${cfg.runs} " +
                "p50=${f(pct(wall, 50))} p90=${f(pct(wall, 90))} mean=${f(wall.average())} " +
                "min=${f(wall.min())} max=${f(wall.max())} " +
                "fp16=${cfg.fp16} peaks=${detection.peaks.joinToString(",") { f(it.toDouble(), 4) }} " +
                "corners_256=${detection.corners?.joinToString(",") { f(it.toDouble(), 2) } ?: "none"} " +
                "thermal=${thermal()} pauses=$pauses",
        )
        log("threads cfg=${cfg.name} self=${describe(Process.myTid())} spawned=${spawned.size} ${spawned.joinToString(" ")}")
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
        runCatching { logFile.appendText("${System.currentTimeMillis()} ${Process.myPid()} $msg\n") }
    }
}

private fun ms(start: Long) = (System.nanoTime() - start) / 1e6

private fun pct(a: DoubleArray, p: Int): Double {
    val s = a.sorted()
    return s[((s.size - 1) * p / 100.0).roundToInt()]
}

private fun f(v: Double, digits: Int = 1) = String.format(Locale.US, "%.${digits}f", v)
