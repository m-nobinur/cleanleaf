package com.bnwise.cleanleaf.ocrbench

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONArray
import org.json.JSONObject
import org.opencv.android.OpenCVLoader
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.RotatedRect
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * PP-OCR det (DB) + rec (CTC) on onnxruntime, a line-by-line port of the host reference
 * (.local/fixtures/ocr-en-v0/tools/ppocr_ref.py) so phone and host outputs can be compared.
 */
class PpOcrEngine(
    override val name: String,
    detDir: File,
    recDir: File,
    private val limitType: String,
    private val limit: Int,
    ep: String,
) : BenchEngine {
    private val env = OrtEnvironment.getEnvironment()
    private val det: OrtSession
    private val rec: OrtSession
    private val chars: List<String>

    init {
        check(OpenCVLoader.initLocal()) { "OpenCV" }
        fun session(dir: File): OrtSession {
            val options = OrtSession.SessionOptions()
            if (ep == "xnnpack") {
                // ORT's guidance for XNNPACK: one intra-op thread, the pool lives in the EP.
                options.setIntraOpNumThreads(1)
                options.addXnnpack(mapOf("intra_op_num_threads" to THREADS.toString()))
            } else {
                options.setIntraOpNumThreads(THREADS)
            }
            return env.createSession(File(dir, "inference.onnx").path, options)
        }
        det = session(detDir)
        rec = session(recDir)
        chars = listOf("blank") + JSONArray(File(recDir, "dict.json").readText()).strings() + listOf(" ")
    }

    override fun read(page: File): JSONObject {
        val t0 = System.nanoTime()
        val img = Imgcodecs.imread(page.path)
        check(!img.empty()) { "unreadable ${page.name}" }
        val (boxes, detStages) = detect(img)
        val t1 = System.nanoTime()
        val lines = JSONArray()
        var recInferNs = 0L
        for (q in boxes) {
            val (crop, rotated) = crop(img, q)
            val (input, rw, imgW) = recInput(crop)
            val ti = System.nanoTime()
            val probs =
                OnnxTensor.createTensor(env, input, longArrayOf(1, 3, 48, imgW.toLong())).use { x ->
                    rec.run(mapOf("x" to x)).use { r ->
                        val t = r[0] as OnnxTensor
                        val shape = t.info.shape
                        Triple(t.floatBuffer.let { b -> FloatArray(b.remaining()).also { b.get(it) } }, shape[1].toInt(), shape[2].toInt())
                    }
                }
            recInferNs += System.nanoTime() - ti
            val (text, score, steps) = ctcDecode(probs.first, probs.second, probs.third)
            val words = wordBoxes(text, steps, probs.second, rw, imgW, q, rotated)
            lines.put(lineJson(text, q.map { it.x.toFloat() to it.y.toFloat() }, score, words))
            crop.release()
        }
        val t2 = System.nanoTime()
        img.release()
        val native = (0 until lines.length()).joinToString("\n") { lines.getJSONObject(it).getString("text") }
        return JSONObject()
            .put("lines", lines)
            .put("native", native)
            .put(
                "stages",
                detStages
                    .put("det_total_ms", (t1 - t0) / 1e6)
                    .put("rec_total_ms", (t2 - t1) / 1e6)
                    .put("rec_infer_ms", recInferNs / 1e6)
                    .put("boxes", boxes.size),
            )
    }

    private fun detResize(
        h: Int,
        w: Int,
    ): Pair<Int, Int> {
        val r =
            when (limitType) {
                "max" -> if (max(h, w) > limit) limit.toDouble() / max(h, w) else 1.0
                "min" -> if (min(h, w) < limit) limit.toDouble() / min(h, w) else 1.0
                else -> limit.toDouble() / max(h, w)
            }
        var rh = (h * r).toInt()
        var rw = (w * r).toInt()
        if (max(rh, rw) > MAX_SIDE) {
            val r2 = MAX_SIDE.toDouble() / max(rh, rw)
            rh = (rh * r2).toInt()
            rw = (rw * r2).toInt()
        }
        // Python round() is half-to-even, like Math.rint.
        return max((Math.rint(rh / 32.0) * 32).toInt(), 32) to max((Math.rint(rw / 32.0) * 32).toInt(), 32)
    }

    private fun detect(img: Mat): Pair<List<List<Point>>, JSONObject> {
        val t0 = System.nanoTime()
        val h = img.rows()
        val w = img.cols()
        val (rh, rw) = detResize(h, w)
        val resized = Mat()
        Imgproc.resize(img, resized, Size(rw.toDouble(), rh.toDouble()))
        val f = Mat()
        resized.convertTo(f, CvType.CV_32FC3, 1 / 255.0)
        val planes = ArrayList<Mat>()
        Core.split(f, planes)
        val n = rh * rw
        val input = FloatBuffer.allocate(3 * n)
        val plane = FloatArray(n)
        for (c in 0 until 3) {
            Core.subtract(planes[c], Scalar(MEAN[c]), planes[c])
            Core.divide(planes[c], Scalar(STD[c]), planes[c])
            planes[c].get(0, 0, plane)
            input.put(plane)
        }
        input.rewind()
        val t1 = System.nanoTime()
        val pred = Mat(rh, rw, CvType.CV_32F)
        OnnxTensor.createTensor(env, input, longArrayOf(1, 3, rh.toLong(), rw.toLong())).use { x ->
            det.run(mapOf("x" to x)).use { r ->
                val b = (r[0] as OnnxTensor).floatBuffer
                pred.put(0, 0, FloatArray(b.remaining()).also { b.get(it) })
            }
        }
        val t2 = System.nanoTime()
        val boxes = sortBoxes(filterBoxes(dbPostprocess(pred, h, w), h, w))
        val t3 = System.nanoTime()
        listOf(resized, f, pred).forEach { it.release() }
        planes.forEach { it.release() }
        return boxes to
            JSONObject()
                .put("det_pre_ms", (t1 - t0) / 1e6)
                .put("det_infer_ms", (t2 - t1) / 1e6)
                .put("det_post_ms", (t3 - t2) / 1e6)
                .put("det_h", rh)
                .put("det_w", rw)
    }

    private fun miniBox(points: MatOfPoint2f): Pair<List<Point>, Double> {
        val rect = Imgproc.minAreaRect(points)
        val pts = rectPoints(rect).sortedBy { it.x }
        val (i1, i4) = if (pts[1].y > pts[0].y) 0 to 1 else 1 to 0
        val (i2, i3) = if (pts[3].y > pts[2].y) 2 to 3 else 3 to 2
        return listOf(pts[i1], pts[i2], pts[i3], pts[i4]) to min(rect.size.width, rect.size.height)
    }

    private fun rectPoints(rect: RotatedRect): List<Point> {
        val m = Mat()
        Imgproc.boxPoints(rect, m)
        val out = (0 until 4).map { Point(m.get(it, 0)[0], m.get(it, 1)[0]) }
        m.release()
        return out
    }

    private fun boxScore(
        pred: Mat,
        box: List<Point>,
    ): Double {
        val h = pred.rows()
        val w = pred.cols()
        val xmin = floor(box.minOf { it.x }).toInt().coerceIn(0, w - 1)
        val xmax = ceil(box.maxOf { it.x }).toInt().coerceIn(0, w - 1)
        val ymin = floor(box.minOf { it.y }).toInt().coerceIn(0, h - 1)
        val ymax = ceil(box.maxOf { it.y }).toInt().coerceIn(0, h - 1)
        val mask = Mat.zeros(ymax - ymin + 1, xmax - xmin + 1, CvType.CV_8U)
        // numpy astype(int32) truncates toward zero.
        val poly = MatOfPoint(*box.map { Point((it.x - xmin).toInt().toDouble(), (it.y - ymin).toInt().toDouble()) }.toTypedArray())
        Imgproc.fillPoly(mask, listOf(poly), Scalar(1.0))
        val roi = pred.submat(ymin, ymax + 1, xmin, xmax + 1)
        val score = Core.mean(roi, mask).`val`[0]
        mask.release()
        return score
    }

    private fun unclip(box: List<Point>): List<Point> {
        val m = MatOfPoint2f(*box.toTypedArray())
        val area = Math.abs(Imgproc.contourArea(m))
        val length = Imgproc.arcLength(m, true)
        val d = area * UNCLIP / length
        val rect = Imgproc.minAreaRect(m)
        return rectPoints(RotatedRect(rect.center, Size(rect.size.width + 2 * d, rect.size.height + 2 * d), rect.angle))
    }

    private fun dbPostprocess(
        pred: Mat,
        srcH: Int,
        srcW: Int,
    ): List<List<Point>> {
        val bin = Mat()
        Imgproc.threshold(pred, bin, THRESH, 255.0, Imgproc.THRESH_BINARY)
        bin.convertTo(bin, CvType.CV_8U)
        val contours = ArrayList<MatOfPoint>()
        Imgproc.findContours(bin, contours, Mat(), Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)
        val h = pred.rows()
        val w = pred.cols()
        val out = mutableListOf<List<Point>>()
        for (c in contours.take(MAX_CANDIDATES)) {
            val (pts, sside) = miniBox(MatOfPoint2f(*c.toArray().map { Point(it.x, it.y) }.toTypedArray()))
            if (sside < 3) continue
            if (boxScore(pred, pts) < BOX_THRESH) continue
            val (box, sside2) = miniBox(MatOfPoint2f(*unclip(pts).toTypedArray()))
            if (sside2 < 5) continue
            out += box.map { Point(Math.rint(it.x / w * srcW).coerceIn(0.0, srcW.toDouble()), Math.rint(it.y / h * srcH).coerceIn(0.0, srcH.toDouble())) }
        }
        bin.release()
        return out
    }

    private fun orderQuad(p: List<Point>): List<Point> {
        val sums = p.map { it.x + it.y }
        val tl = sums.indices.minBy { sums[it] }
        val br = sums.indices.maxBy { sums[it] }
        val rest = p.indices.filter { it != tl && it != br }
        val d = rest.map { p[it].y - p[it].x }
        val tr = rest[d.indices.minBy { d[it] }]
        val bl = rest[d.indices.maxBy { d[it] }]
        return listOf(p[tl], p[tr], p[br], p[bl])
    }

    private fun filterBoxes(
        boxes: List<List<Point>>,
        h: Int,
        w: Int,
    ) = boxes.mapNotNull { raw ->
        val b = orderQuad(raw).map { Point(it.x.coerceIn(0.0, w - 1.0), it.y.coerceIn(0.0, h - 1.0)) }
        val rw = dist(b[0], b[1]).toInt()
        val rh = dist(b[0], b[3]).toInt()
        if (rw <= 3 || rh <= 3) null else b
    }

    private fun sortBoxes(boxes: List<List<Point>>): List<List<Point>> {
        val b = boxes.sortedWith(compareBy({ it[0].y }, { it[0].x })).toMutableList()
        for (i in 0 until b.size - 1) {
            for (j in i downTo 0) {
                if (Math.abs(b[j + 1][0].y - b[j][0].y) < 10 && b[j + 1][0].x < b[j][0].x) {
                    val t = b[j]
                    b[j] = b[j + 1]
                    b[j + 1] = t
                } else {
                    break
                }
            }
        }
        return b
    }

    private fun crop(
        img: Mat,
        q: List<Point>,
    ): Pair<Mat, Boolean> {
        val w = max(dist(q[0], q[1]), dist(q[2], q[3])).toInt()
        val h = max(dist(q[0], q[3]), dist(q[1], q[2])).toInt()
        val m =
            Imgproc.getPerspectiveTransform(
                MatOfPoint2f(*q.toTypedArray()),
                MatOfPoint2f(Point(0.0, 0.0), Point(w.toDouble(), 0.0), Point(w.toDouble(), h.toDouble()), Point(0.0, h.toDouble())),
            )
        val c = Mat()
        Imgproc.warpPerspective(img, c, m, Size(w.toDouble(), h.toDouble()), Imgproc.INTER_CUBIC, Core.BORDER_REPLICATE)
        m.release()
        if (c.rows().toDouble() / max(c.cols(), 1) < 1.5) return c to false
        val r = Mat()
        Core.rotate(c, r, Core.ROTATE_90_COUNTERCLOCKWISE)
        c.release()
        return r to true
    }

    private fun recInput(c: Mat): Triple<FloatBuffer, Int, Int> {
        val ratio = c.cols().toDouble() / c.rows()
        val imgW = max(320, (48 * ratio).toInt())
        val rw = min(imgW, ceil(48 * ratio).toInt())
        val r = Mat()
        Imgproc.resize(c, r, Size(rw.toDouble(), 48.0))
        r.convertTo(r, CvType.CV_32FC3, 2 / 255.0, -1.0)
        val planes = ArrayList<Mat>()
        Core.split(r, planes)
        val buf = FloatBuffer.allocate(3 * 48 * imgW)
        val row = FloatArray(rw)
        for (ch in 0 until 3) {
            for (y in 0 until 48) {
                planes[ch].get(y, 0, row)
                buf.position(ch * 48 * imgW + y * imgW)
                buf.put(row)
            }
        }
        buf.rewind()
        r.release()
        planes.forEach { it.release() }
        return Triple(buf, rw, imgW)
    }

    private fun ctcDecode(
        probs: FloatArray,
        t: Int,
        classes: Int,
    ): Triple<String, Double, List<Int>> {
        val sb = StringBuilder()
        val scores = mutableListOf<Float>()
        val steps = mutableListOf<Int>()
        var prev = -1
        for (s in 0 until t) {
            var best = 0
            var bestP = probs[s * classes]
            for (k in 1 until classes) {
                val p = probs[s * classes + k]
                if (p > bestP) {
                    bestP = p
                    best = k
                }
            }
            if (best != prev && best != 0) {
                sb.append(chars.getOrElse(best) { "" })
                scores += bestP
                steps += s
            }
            prev = best
        }
        return Triple(sb.toString(), if (scores.isEmpty()) 0.0 else scores.average(), steps)
    }

    private fun wordBoxes(
        text: String,
        steps: List<Int>,
        t: Int,
        rw: Int,
        imgW: Int,
        q: List<Point>,
        rotated: Boolean,
    ): List<Pair<String, List<Pair<Float, Float>>>> {
        if (rotated || text.isEmpty() || text.length != steps.size) return emptyList()
        val words = mutableListOf<List<Pair<Char, Int>>>()
        var cur = mutableListOf<Pair<Char, Int>>()
        text.forEachIndexed { i, ch ->
            if (ch == ' ') {
                if (cur.isNotEmpty()) words += cur
                cur = mutableListOf()
            } else {
                cur += ch to steps[i]
            }
        }
        if (cur.isNotEmpty()) words += cur
        val stepPx = imgW.toDouble() / t
        fun at(
            a: Double,
            b: Double,
        ) = (q[0].x + (q[1].x - q[0].x) * a + (q[3].x - q[0].x) * b).toFloat() to (q[0].y + (q[1].y - q[0].y) * a + (q[3].y - q[0].y) * b).toFloat()
        return words.map { wd ->
            val x0 = (wd.first().second * stepPx / rw).coerceIn(0.0, 1.0)
            val x1 = (min(rw.toDouble(), (wd.last().second + 1) * stepPx) / rw).coerceIn(0.0, 1.0)
            wd.map { it.first }.joinToString("") to listOf(at(x0, 0.0), at(x1, 0.0), at(x1, 1.0), at(x0, 1.0))
        }
    }

    private fun dist(
        a: Point,
        b: Point,
    ) = hypot(a.x - b.x, a.y - b.y)

    override fun close() {
        det.close()
        rec.close()
    }

    private companion object {
        const val THREADS = 4
        const val MAX_SIDE = 4000
        const val THRESH = 0.3
        const val BOX_THRESH = 0.6
        const val UNCLIP = 1.5
        const val MAX_CANDIDATES = 1000
        val MEAN = doubleArrayOf(0.485, 0.456, 0.406)
        val STD = doubleArrayOf(0.229, 0.224, 0.225)
    }
}
