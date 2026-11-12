package com.bnwise.cleanleaf.ocrbench

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.util.Log
import com.bnwise.cleanleaf.vision.ClVision
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * T-038 phone benchmark (probe only): PP-OCR in clvision on LiteRT. Every engine lives on its own thread at the
 * priority its spec names, created there so the XNNPACK workers inherit it. Pages run interleaved across engines
 * (thermal drift); outputs use T-032's layout so its scorer and phone.py run unchanged.
 */
class OcrBenchHost(
    private val context: Context,
) : OcrBenchHostApi {
    override suspend fun run(dir: String): String = withContext(Dispatchers.Default) { bench(File(dir)) }

    private fun log(line: String) {
        Log.i(TAG, line)
    }

    private fun bench(root: File): String {
        val go = JSONObject(File(root, "go.json").readText())
        val out = File(root, "out").apply { mkdirs() }
        fun files(key: String) = go.optJSONArray(key)?.strings()?.map { File(root, "pages/$it") } ?: emptyList()
        val pages = files("pages")
        val latency = files("latency_pages")
        val repeats = go.optInt("repeats", 3)
        log("start device=${Build.MODEL} sdk=${Build.VERSION.SDK_INT} cpus=${Runtime.getRuntime().availableProcessors()} pages=${pages.size} latency=${latency.size}x$repeats ${thermal()}")
        fun createAll(key: String) =
            go.optJSONArray(key)?.strings()?.mapNotNull { spec ->
                val before = rssKb()
                val t0 = SystemClock.elapsedRealtime()
                try {
                    PpOcrLiteEngine(spec, File(root, "models")).also {
                        log("init engine=${it.name} ms=${SystemClock.elapsedRealtime() - t0} rss_delta_mb=${(rssKb() - before) / 1024} spec=$spec")
                    }
                } catch (e: Throwable) {
                    log("init FAILED spec=$spec ${e.stackTraceToString().take(4000)}")
                    null
                }
            } ?: emptyList()
        val engines = createAll("engines")
        val latencyOnly = createAll("lat_engines")
        val summary = JSONArray()
        fun runOne(
            engine: PpOcrLiteEngine,
            page: File,
            phase: String,
            run: Int,
        ) {
            val sampler = RssSampler().apply { start() }
            val t0 = SystemClock.elapsedRealtimeNanos()
            val result =
                try {
                    engine.read(page)
                } catch (e: Throwable) {
                    log("FAILED engine=${engine.name} page=${page.name} ${e.javaClass.simpleName}: ${e.message}")
                    null
                }
            val ms = (SystemClock.elapsedRealtimeNanos() - t0) / 1e6
            val (base, peak) = sampler.stop()
            if (result == null) return
            result.put("ms", ms).put("rss_base_mb", base / 1024.0).put("rss_peak_mb", peak / 1024.0)
            val id = page.nameWithoutExtension
            if (phase == "acc" || run == 0) {
                File(out, "${engine.name}/$phase").mkdirs()
                File(out, "${engine.name}/$phase/$id.json").writeText(result.toString())
            }
            val row =
                JSONObject()
                    .put("engine", engine.name)
                    .put("page", id)
                    .put("phase", phase)
                    .put("run", run)
                    .put("ms", ms)
                    .put("rss_peak_delta_mb", (peak - base) / 1024.0)
                    .put("rss_peak_mb", peak / 1024.0)
                    .put("lines", result.getJSONArray("lines").length())
                    .put("thermal", thermalStatus())
                    .put("battery_temp_c", batteryTemp())
                    .put("stages", result.getJSONObject("stages"))
            summary.put(row)
            File(root, "summary.jsonl").appendText("$row\n")
            log("page engine=${engine.name} page=$id phase=$phase run=$run ms=${"%.0f".format(ms)} rss_peak_delta_mb=${"%.0f".format((peak - base) / 1024.0)} lines=${row.getInt("lines")} ${result.getJSONObject("stages")}")
        }
        for (page in pages) {
            log("accuracy page=${page.name} ${thermal()}")
            for (engine in engines) runOne(engine, page, "acc", 0)
        }
        for (page in latency) {
            for (run in 0 until repeats) {
                log("latency page=${page.name} run=$run ${thermal()}")
                for (engine in engines + latencyOnly) runOne(engine, page, "lat", run)
            }
        }
        (engines + latencyOnly).forEach { it.close() }
        return "engines=${engines.size + latencyOnly.size} rows=${summary.length()} ${thermal()}"
    }

    private fun thermalStatus(): Int =
        if (Build.VERSION.SDK_INT >= 29) context.getSystemService(PowerManager::class.java).currentThermalStatus else -1

    private fun batteryTemp(): Double =
        (context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10.0

    private fun thermal() = "thermal=${thermalStatus()} battery_c=${batteryTemp()}"

    private companion object {
        const val TAG = "CLBENCH"
    }
}

/**
 * Spec `ppl:<name>:<bg|fg>:<fp16 0|1>:<threads>:<det file>:<rec file>[,<rec file>...]`, files in [models];
 * one rec file is the width-dynamic model, several are static width buckets in ascending width.
 */
class PpOcrLiteEngine(
    spec: String,
    models: File,
) {
    val name: String
    private val thread: ExecutorService
    private val handle: Long

    init {
        val parts = spec.split(":")
        require(parts.size == 7 && parts[0] == "ppl") { "bad spec $spec" }
        name = parts[1]
        val priority = if (parts[2] == "bg") Process.THREAD_PRIORITY_BACKGROUND else Process.THREAD_PRIORITY_DEFAULT
        thread =
            Executors.newSingleThreadExecutor { task ->
                Thread({
                    Process.setThreadPriority(priority)
                    task.run()
                }, "ocr-$name")
            }
        fun direct(file: String): ByteBuffer {
            val bytes = File(models, file).readBytes()
            return ByteBuffer.allocateDirect(bytes.size).put(bytes).apply { rewind() }
        }
        val dict = JSONArray(File(models, "ppocr_v6s_rec_latin_dict.json").readText()).strings().joinToString("\n")
        val det = direct(parts[5])
        val recs = parts[6].split(",").map { direct(it) }.toTypedArray()
        handle =
            thread
                .submit(
                    Callable {
                        ClVision.ocrCreate(det, recs, dict.toByteArray(Charsets.UTF_8), parts[3] == "1", parts[4].toInt())
                    },
                ).get()
        check(handle != 0L) { "ocrCreate failed for $spec" }
    }

    fun read(page: File): JSONObject {
        val bytes = page.readBytes()
        val json = thread.submit(Callable { ClVision.ocrRead(handle, bytes) }).get() ?: error("ocrRead failed")
        val result = JSONObject(String(json, Charsets.UTF_8))
        val lines = result.getJSONArray("lines")
        return result.put("native", (0 until lines.length()).joinToString("\n") { lines.getJSONObject(it).getString("text") })
    }

    fun close() {
        thread.submit(Callable { ClVision.ocrDestroy(handle) }).get()
        thread.shutdown()
    }
}

fun JSONArray.strings() = (0 until length()).map { getString(it) }

fun rssKb(): Long =
    File("/proc/self/status").readLines().first { it.startsWith("VmRSS:") }.split(Regex("\\s+"))[1].toLong()

/** Peak resident set size while an engine runs, sampled every 10 ms on its own thread. */
class RssSampler {
    @Volatile private var running = true
    private var base = 0L
    private var peak = 0L
    private val thread =
        Thread {
            while (running) {
                peak = maxOf(peak, rssKb())
                Thread.sleep(10)
            }
        }

    fun start() {
        base = rssKb()
        peak = base
        thread.start()
    }

    fun stop(): Pair<Long, Long> {
        running = false
        thread.join()
        return base to maxOf(peak, rssKb())
    }
}
