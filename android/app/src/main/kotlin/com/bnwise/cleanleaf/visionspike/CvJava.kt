package com.bnwise.cleanleaf.visionspike

import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfByte
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Candidate C: the shared spike algorithm through the official OpenCV Android SDK (Java API). */
object CvJava {
    private const val FRAME_LONG_SIDE = 480.0

    init {
        System.loadLibrary("opencv_java4")
    }

    fun detect(plane: ByteBuffer, w: Int, h: Int, stride: Int, out: FloatArray): Boolean {
        val src = Mat(h, w, CvType.CV_8UC1, plane, stride.toLong())
        val scale = FRAME_LONG_SIDE / max(w, h)
        val small = Mat()
        Imgproc.resize(
            src, small,
            Size((w * scale).roundToInt().toDouble(), (h * scale).roundToInt().toDouble()),
            0.0, 0.0, Imgproc.INTER_AREA,
        )
        val blurred = Mat()
        Imgproc.GaussianBlur(small, blurred, Size(5.0, 5.0), 0.0)
        val edges = Mat()
        Imgproc.Canny(blurred, edges, 50.0, 150.0)
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        val dilated = Mat()
        Imgproc.dilate(edges, dilated, kernel, Point(-1.0, -1.0), 1, Core.BORDER_REPLICATE)
        val contours = ArrayList<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(dilated, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
        val minArea = 0.1 * small.cols() * small.rows()
        var bestArea = 0.0
        var best: Array<Point>? = null
        for (c in contours) {
            val area = Imgproc.contourArea(c)
            if (area >= minArea && area > bestArea) {
                // The Java API only offers approxPolyDP on float points.
                val c2f = MatOfPoint2f(*c.toArray())
                val approx2f = MatOfPoint2f()
                Imgproc.approxPolyDP(c2f, approx2f, 0.02 * Imgproc.arcLength(c2f, true), true)
                val pts = approx2f.toArray()
                val approx = MatOfPoint(*pts)
                if (pts.size == 4 && Imgproc.isContourConvex(approx)) {
                    bestArea = area
                    best = pts
                }
                listOf(c2f, approx2f, approx).forEach { it.release() }
            }
            c.release()
        }
        listOf(src, small, blurred, edges, kernel, dilated, hierarchy).forEach { it.release() }
        val found = best ?: return false
        orderCorners(found.map { Point(it.x / scale, it.y / scale) }, out)
        return true
    }

    /** timings: decode, warp, enhance, encode (ms), output mean. [jpeg] must be direct. */
    fun still(jpeg: ByteBuffer, corners: FloatArray, outW: Int, outH: Int, timings: DoubleArray): ByteArray {
        var t = System.nanoTime()
        fun lap(): Double {
            val now = System.nanoTime()
            val ms = (now - t) / 1e6
            t = now
            return ms
        }
        val buf = Mat(1, jpeg.capacity(), CvType.CV_8UC1, jpeg)
        val src = Imgcodecs.imdecode(buf, Imgcodecs.IMREAD_COLOR)
        timings[0] = lap()
        val s = MatOfPoint2f(*Array(4) { Point(corners[2 * it].toDouble(), corners[2 * it + 1].toDouble()) })
        val d = MatOfPoint2f(
            Point(0.0, 0.0), Point(outW - 1.0, 0.0), Point(outW - 1.0, outH - 1.0), Point(0.0, outH - 1.0),
        )
        val m = Imgproc.getPerspectiveTransform(s, d)
        val warped = Mat()
        Imgproc.warpPerspective(
            src, warped, m, Size(outW.toDouble(), outH.toDouble()), Imgproc.INTER_LINEAR, Core.BORDER_REPLICATE,
        )
        timings[1] = lap()
        val enhanced = enhance(warped)
        timings[2] = lap()
        val encoded = MatOfByte()
        Imgcodecs.imencode(".jpg", enhanced, encoded)
        val bytes = encoded.toArray()
        timings[3] = lap()
        val mean = Core.mean(enhanced).`val`
        timings[4] = (mean[0] + mean[1] + mean[2]) / 3
        listOf(buf, src, s, d, m, warped, enhanced, encoded).forEach { it.release() }
        return bytes
    }

    fun buildInfo(): String = Core.getBuildInformation()

    fun numThreads(): Int = Core.getNumThreads()

    /** Shadow division: estimate the paper background on a 1/4 copy and divide. */
    private fun enhance(img: Mat): Mat {
        val small = Mat()
        Imgproc.resize(
            img, small, Size((img.cols() / 4).toDouble(), (img.rows() / 4).toDouble()), 0.0, 0.0, Imgproc.INTER_AREA,
        )
        val k = (min(small.cols(), small.rows()) / 20) or 1
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(k.toDouble(), k.toDouble()))
        val bg = Mat()
        Imgproc.morphologyEx(small, bg, Imgproc.MORPH_CLOSE, kernel, Point(-1.0, -1.0), 1, Core.BORDER_REPLICATE)
        val bgBlur = Mat()
        Imgproc.GaussianBlur(bg, bgBlur, Size(k.toDouble(), k.toDouble()), 0.0)
        val bgFull = Mat()
        Imgproc.resize(bgBlur, bgFull, img.size(), 0.0, 0.0, Imgproc.INTER_LINEAR)
        val out = Mat()
        Core.divide(img, bgFull, out, 255.0)
        listOf(small, kernel, bg, bgBlur, bgFull).forEach { it.release() }
        return out
    }

    /** TL, TR, BR, BL by coordinate sum and difference; ties keep the earlier point. */
    private fun orderCorners(p: List<Point>, out: FloatArray) {
        fun sum(a: Point) = a.x + a.y
        fun diff(a: Point) = a.x - a.y
        val ordered = listOf(
            p.reduce { a, b -> if (sum(a) <= sum(b)) a else b },
            p.reduce { a, b -> if (diff(a) >= diff(b)) a else b },
            p.reduce { a, b -> if (sum(a) >= sum(b)) a else b },
            p.reduce { a, b -> if (diff(a) <= diff(b)) a else b },
        )
        ordered.forEachIndexed { i, pt ->
            out[2 * i] = pt.x.toFloat()
            out[2 * i + 1] = pt.y.toFloat()
        }
    }
}
