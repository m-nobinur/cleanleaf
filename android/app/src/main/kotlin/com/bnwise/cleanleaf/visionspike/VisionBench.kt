package com.bnwise.cleanleaf.visionspike

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.random.Random

/**
 * T-003 probe. Runs on launch with no taps: synthesizes a 12 MP page photo and a 480x640 Y frame,
 * then times the same algorithm through A (opencv_dart isolate), B-FFI (C++ from a Dart isolate),
 * B-JNI (same C++ from Kotlin) and C (OpenCV Java), interleaved by round. Logs to CLBENCH.
 */
class VisionBench(private val channel: MethodChannel, private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val dir = context.getExternalFilesDir(null) ?: context.filesDir
    private val quad = floatArrayOf(420f, 520f, 2620f, 380f, 2780f, 3560f, 300f, 3700f)
    private val paths = listOf("A", "B-FFI", "B-JNI", "C")
    private val failed = mutableSetOf<String>()

    fun start() {
        thread(name = "clbench-analyzer") {
            try {
                run()
            } catch (t: Throwable) {
                log("FATAL ${t.stackTraceToString()}")
            }
            log("CLBENCH DONE")
        }
    }

    private fun run() {
        val soc = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else "?"
        log("device ${Build.MANUFACTURER} ${Build.MODEL} soc=$soc sdk=${Build.VERSION.SDK_INT} " +
            "cpus=${Runtime.getRuntime().availableProcessors()} thermal=${thermal()} out=$dir")
        val t0 = System.nanoTime()
        val bmp = synthesize()
        val jpegBytes = ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }.toByteArray()
        File(dir, "synthetic.jpg").writeBytes(jpegBytes)
        val plane = yPlane(Bitmap.createScaledBitmap(bmp, FW, FH, true))
        bmp.recycle()
        val jpeg = ByteBuffer.allocateDirect(jpegBytes.size).put(jpegBytes).also { it.flip() }
        val outW = max(dist(0, 1), dist(3, 2)).roundToInt()
        val outH = max(dist(0, 3), dist(1, 2)).roundToInt()
        log("synthetic ${W}x$H jpeg=${jpegBytes.size} B; frame ${FW}x$FH stride=$STRIDE; out ${outW}x$outH; " +
            "gen ${f(ms(t0))} ms")
        callDart("setup", mapOf("jpeg" to jpegBytes, "dir" to dir.path))
        logBuildInfo()

        val expected = FloatArray(8) { quad[it] * FW / W }
        val totals = paths.associateWith { ArrayList<Double>() }
        val computes = paths.associateWith { ArrayList<Double>() }
        for (round in 0 until ROUNDS) {
            for (p in paths) {
                repeat(FRAMES) { i ->
                    val r = guarded(p) { frame(p, plane) } ?: return@repeat
                    if (round > 0) {
                        totals.getValue(p).add(r.first)
                        computes.getValue(p).add(r.second)
                    } else if (i == 0) {
                        logCorners(p, r.third, expected)
                    }
                }
            }
        }
        for (p in paths) {
            val tot = totals.getValue(p)
            val cmp = computes.getValue(p)
            if (tot.isEmpty()) continue
            log("FRAME $p n=${tot.size} total med=${f(pct(tot, 50))} p95=${f(pct(tot, 95))} mean=${f(tot.average())} " +
                "| compute med=${f(pct(cmp, 50))} p95=${f(pct(cmp, 95))} | handoff med=${f(pct(tot, 50) - pct(cmp, 50))} ms")
        }

        val stills = paths.associateWith { ArrayList<DoubleArray>() }
        for (round in 0 until STILL_ROUNDS) {
            for (p in paths) {
                val r = guarded(p) { still(p, jpeg, outW, outH, save = round == STILL_ROUNDS - 1) } ?: continue
                log("still $p round=$round decode=${f(r[0])} warp=${f(r[1])} enhance=${f(r[2])} encode=${f(r[3])} " +
                    "mean=${f(r[4])} jpeg=${r[5].toInt()}")
                if (round > 0) stills.getValue(p).add(r)
            }
        }
        for (p in paths) {
            val rs = stills.getValue(p)
            if (rs.isEmpty()) continue
            fun med(i: Int) = pct(rs.map { it[i] }, 50)
            val warpEnhance = rs.map { it[1] + it[2] }
            val all = rs.map { it[0] + it[1] + it[2] + it[3] }
            log("STILL $p n=${rs.size} decode=${f(med(0))} warp=${f(med(1))} enhance=${f(med(2))} " +
                "encode=${f(med(3))} | warp+enhance med=${f(pct(warpEnhance, 50))} max=${f(warpEnhance.max())} " +
                "| decode..encode med=${f(pct(all, 50))} ms | mean=${f(med(4))}")
        }
        log("thermal end=${thermal()} failed=$failed")
    }

    /** Kotlin holds the Y plane until corners are on the Dart UI isolate and Dart has replied. */
    private fun frame(path: String, plane: ByteBuffer): Triple<Double, Double, FloatArray?> {
        val t0 = System.nanoTime()
        if (path == "A" || path == "B-FFI") {
            // Copy out of the direct buffer, as the camera plugin does before posting to Dart.
            val bytes = ByteArray(plane.capacity())
            plane.duplicate().get(bytes)
            val r = callDart(
                "frame", mapOf("path" to path, "plane" to bytes, "w" to FW, "h" to FH, "stride" to STRIDE),
            ) as List<*>
            return Triple(ms(t0), (r[0] as Number).toDouble(), r[1] as FloatArray?)
        }
        val out = FloatArray(8)
        val found = if (path == "B-JNI") {
            ClVision.detect(plane, FW, FH, STRIDE, out)
        } else {
            CvJava.detect(plane, FW, FH, STRIDE, out)
        }
        val compute = ms(t0)
        callDart("corners", if (found) out else null)
        return Triple(ms(t0), compute, if (found) out else null)
    }

    /** decode, warp, enhance, encode (ms), mean, jpeg bytes. */
    private fun still(path: String, jpeg: ByteBuffer, outW: Int, outH: Int, save: Boolean): DoubleArray {
        if (path == "A" || path == "B-FFI") {
            val args = mapOf("path" to path, "corners" to quad, "outW" to outW, "outH" to outH, "save" to save)
            return callDart("still", args) as DoubleArray
        }
        val t = DoubleArray(5)
        val bytes = if (path == "B-JNI") {
            ClVision.stillJpeg(jpeg, quad, outW, outH, t)
        } else {
            CvJava.still(jpeg, quad, outW, outH, t)
        }
        if (save) File(dir, "out_$path.jpg").writeBytes(bytes)
        return t + bytes.size.toDouble()
    }

    private fun <T> guarded(path: String, block: () -> T): T? {
        if (path in failed) return null
        return try {
            block()
        } catch (t: Throwable) {
            failed += path
            log("PATH $path FAILED: ${t.stackTraceToString()}")
            null
        }
    }

    private fun callDart(method: String, args: Any?): Any? {
        val latch = CountDownLatch(1)
        var result: Any? = null
        var error: String? = null
        main.post {
            channel.invokeMethod(method, args, object : MethodChannel.Result {
                override fun success(r: Any?) {
                    result = r
                    latch.countDown()
                }

                override fun error(code: String, message: String?, details: Any?) {
                    error = "$code: $message"
                    latch.countDown()
                }

                override fun notImplemented() {
                    error = "notImplemented"
                    latch.countDown()
                }
            })
        }
        check(latch.await(120, TimeUnit.SECONDS)) { "Dart did not answer $method" }
        error?.let { throw IllegalStateException(it) }
        return result
    }

    private fun logBuildInfo() {
        val dart = guarded("info") { callDart("info", null) as Map<*, *> } ?: emptyMap<Any, Any>()
        val infos = listOf(
            Triple("A", dart["A"] as String?, dart["A_threads"]),
            Triple("B-FFI", dart["B"] as String?, dart["B_threads"]),
            Triple("B-JNI", guarded("B-JNI") { ClVision.buildInfo() }, guarded("B-JNI") { ClVision.numThreads() }),
            Triple("C", guarded("C") { CvJava.buildInfo() }, guarded("C") { CvJava.numThreads() }),
        )
        val keep = Regex(
            "General configuration|Version control|Parallel framework|Baseline|requested|Dispatched|HAL|" +
                "KleidiCV|carotene|C\\+\\+ flags \\(Release\\)|JPEG:|Extra dependencies",
        )
        for ((name, info, threads) in infos) {
            log("INFO $name threads=$threads")
            info?.lines()?.filter { keep.containsMatchIn(it) }?.forEach { log("INFO $name | ${it.trim()}") }
        }
    }

    private fun logCorners(path: String, c: FloatArray?, expected: FloatArray) {
        if (c == null) {
            log("corners $path NOT FOUND")
            return
        }
        val maxErr = (0 until 4).maxOf { hypot(c[2 * it] - expected[2 * it], c[2 * it + 1] - expected[2 * it + 1]) }
        val diag = hypot(FW.toFloat(), FH.toFloat())
        log("corners $path ${c.joinToString(",") { f(it.toDouble()) }} maxErr=${f(maxErr.toDouble())} px " +
            "(${f(100.0 * maxErr / diag)}% diag)")
    }

    /** Textured background (soft grain, hard blobs off the page), perspective page with text, shadow. */
    private fun synthesize(): Bitmap {
        val bmp = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.rgb(122, 92, 64))
        val rnd = Random(42)
        val p = Paint()
        repeat(6000) {
            val d = rnd.nextInt(-8, 9)
            p.color = Color.rgb(122 + d, 92 + d, 64 + d)
            val x = rnd.nextFloat() * W
            val y = rnd.nextFloat() * H
            c.drawRect(x, y, x + 10 + rnd.nextInt(120), y + 4 + rnd.nextInt(20), p)
        }
        var blobs = 0
        while (blobs < 300) {
            val s = 20f + rnd.nextInt(60)
            val x = rnd.nextFloat() * (W - s)
            val y = rnd.nextFloat() * (H - s)
            val offPage = x + s < 240 || x > 2840 || y + s < 320 || y > 3760
            if (!offPage) continue
            p.color = if (rnd.nextBoolean()) Color.rgb(230, 220, 200) else Color.rgb(30, 25, 20)
            c.drawRect(x, y, x + s, y + s * (0.5f + rnd.nextFloat()), p)
            blobs++
        }
        val pageW = 2100f
        val pageH = 2970f
        val m = Matrix()
        m.setPolyToPoly(floatArrayOf(0f, 0f, pageW, 0f, pageW, pageH, 0f, pageH), 0, quad, 0, 4)
        c.save()
        c.concat(m)
        p.color = Color.rgb(242, 239, 230)
        c.drawRect(0f, 0f, pageW, pageH, p)
        p.color = Color.rgb(40, 40, 48)
        var y = 220f
        while (y < pageH - 200) {
            var x = 180f
            while (x < pageW - 260) {
                val len = 60f + rnd.nextInt(180)
                c.drawRect(x, y - 34, x + len, y, p)
                x += len + 28
            }
            y += 70
        }
        c.restore()
        val shadow = Paint()
        shadow.shader = LinearGradient(
            0f, 0f, W * 0.7f, H * 0.3f, Color.argb(130, 0, 0, 0), Color.argb(0, 0, 0, 0), Shader.TileMode.CLAMP,
        )
        c.drawRect(0f, 0f, W.toFloat(), H.toFloat(), shadow)
        return bmp
    }

    /** Luma into a direct buffer with padded rows, like a CameraX Y plane. */
    private fun yPlane(frame: Bitmap): ByteBuffer {
        val px = IntArray(FW * FH)
        frame.getPixels(px, 0, FW, 0, 0, FW, FH)
        frame.recycle()
        val buf = ByteBuffer.allocateDirect(STRIDE * FH)
        for (y in 0 until FH) {
            for (x in 0 until FW) {
                val c = px[y * FW + x]
                val luma = (77 * Color.red(c) + 150 * Color.green(c) + 29 * Color.blue(c)) shr 8
                buf.put(y * STRIDE + x, luma.toByte())
            }
        }
        return buf
    }

    private fun dist(i: Int, j: Int) = hypot(quad[2 * i] - quad[2 * j], quad[2 * i + 1] - quad[2 * j + 1])

    private fun thermal(): Int =
        if (Build.VERSION.SDK_INT >= 29) {
            (context.getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus
        } else {
            -1
        }

    private fun log(msg: String) = Log.i(TAG, msg)

    companion object {
        private const val TAG = "CLBENCH"
        private const val W = 3000
        private const val H = 4000
        private const val FW = 480
        private const val FH = 640
        private const val STRIDE = 544
        private const val ROUNDS = 6
        private const val FRAMES = 40
        private const val STILL_ROUNDS = 4

        private fun ms(t0: Long) = (System.nanoTime() - t0) / 1e6

        private fun f(v: Double) = String.format(Locale.US, "%.2f", v)

        private fun pct(xs: List<Double>, p: Int): Double {
            val s = xs.sorted()
            return s[((s.size - 1) * p / 100.0).roundToInt()]
        }
    }
}
