package com.bnwise.cleanleaf.ocrbench

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** One OCR engine under test; returns the scorer's page JSON (lines with quads, native text). */
interface BenchEngine {
    val name: String

    fun read(page: File): JSONObject

    fun close() {}
}

/** T-032 spike: runs every configured engine on every page, interleaved per page (thermal drift). */
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
        val pages = go.getJSONArray("pages").strings().map { File(root, "pages/$it") }
        val latency = go.optJSONArray("latency_pages")?.strings()?.map { File(root, "pages/$it") } ?: emptyList()
        val repeats = go.optInt("repeats", 3)
        log("start device=${Build.MODEL} sdk=${Build.VERSION.SDK_INT} cpus=${Runtime.getRuntime().availableProcessors()} pages=${pages.size} latency=${latency.size}x$repeats ${thermal()}")
        val engines = mutableListOf<BenchEngine>()
        val net = mutableMapOf<String, Long>()
        for (spec in go.getJSONArray("engines").strings()) {
            val before = rssKb()
            val t0 = SystemClock.elapsedRealtime()
            try {
                engines += create(spec, root)
                log("init engine=$spec ms=${SystemClock.elapsedRealtime() - t0} rss_delta_mb=${(rssKb() - before) / 1024}")
            } catch (e: Throwable) {
                log("init FAILED engine=$spec ${e.javaClass.simpleName}: ${e.message}")
            }
        }
        val summary = JSONArray()
        fun runOne(
            engine: BenchEngine,
            page: File,
            phase: String,
            run: Int,
        ) {
            val sampler = RssSampler().apply { start() }
            val rx = TrafficStats.getUidRxBytes(Process.myUid())
            val tx = TrafficStats.getUidTxBytes(Process.myUid())
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
            val bytes = TrafficStats.getUidRxBytes(Process.myUid()) - rx + TrafficStats.getUidTxBytes(Process.myUid()) - tx
            net[engine.name] = (net[engine.name] ?: 0) + bytes
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
                    .put("lines", result.getJSONArray("lines").length())
                    .put("thermal", thermalStatus())
                    .put("battery_temp_c", batteryTemp())
            result.optJSONObject("stages")?.let { row.put("stages", it) }
            summary.put(row)
            File(root, "summary.jsonl").appendText("$row\n")
            log("page engine=${engine.name} page=$id phase=$phase run=$run ms=${"%.0f".format(ms)} rss_peak_delta_mb=${"%.0f".format((peak - base) / 1024.0)} lines=${row.getInt("lines")} net_bytes=$bytes ${result.optJSONObject("stages") ?: ""}")
        }
        for (page in pages) {
            log("accuracy page=${page.name} ${thermal()}")
            for (engine in engines) runOne(engine, page, "acc", 0)
        }
        for (page in latency) {
            for (run in 0 until repeats) {
                log("latency page=${page.name} run=$run ${thermal()}")
                for (engine in engines) runOne(engine, page, "lat", run)
            }
        }
        for ((name, bytes) in net) log("network engine=$name bytes=$bytes")
        engines.forEach { it.close() }
        return "engines=${engines.size} rows=${summary.length()} ${thermal()}"
    }

    private fun create(
        spec: String,
        root: File,
    ): BenchEngine {
        val parts = spec.split(":")
        return when (parts[0]) {
            // tess:<name>:<tessdata parent dir>:<langs>
            "tess" -> TessEngine(parts[1], File(root, parts[2]).path, parts[3])
            "mlkit" -> MlKitEngine(context)
            // pp:<name>:<det dir>:<rec dir>:<limit type>:<limit>:<ep xnnpack|cpu>
            "pp" ->
                PpOcrEngine(
                    parts[1],
                    File(root, "models/${parts[2]}"),
                    File(root, "models/${parts[3]}"),
                    parts[4],
                    parts[5].toInt(),
                    parts[6],
                )
            else -> error("unknown engine $spec")
        }
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

fun quadJson(points: List<Pair<Float, Float>>) = JSONArray(points.map { JSONArray(listOf(it.first.toDouble(), it.second.toDouble())) })

fun lineJson(
    text: String,
    quad: List<Pair<Float, Float>>,
    conf: Double,
    words: List<Pair<String, List<Pair<Float, Float>>>>,
): JSONObject =
    JSONObject()
        .put("text", text)
        .put("quad", quadJson(quad))
        .put("conf", conf)
        .put("words", JSONArray(words.map { (t, q) -> JSONObject().put("text", t).put("quad", quadJson(q)) }))
