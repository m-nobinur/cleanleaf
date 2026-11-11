package com.bnwise.cleanleaf.camera

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.bnwise.cleanleaf.vision.ClVision

/** Detects the page in each analysis frame inside clvision; only corners leave this class. */
class CornerAnalyzer(
    private val onFrame: (CornerFrame) -> Unit,
) : ImageAnalysis.Analyzer {
    private val out = FloatArray(9)
    private val stability = StabilityTracker()

    override fun analyze(image: ImageProxy) {
        onFrame(image.use(::detect))
    }

    private fun detect(image: ImageProxy): CornerFrame {
        val (y, u, v) = image.planes
        val status =
            ClVision.detectFrame(
                y.buffer,
                u.buffer,
                v.buffer,
                image.width,
                image.height,
                y.rowStride,
                u.rowStride,
                u.pixelStride,
                image.imageInfo.rotationDegrees,
                out,
            )
        // Every other status (no page, detector not built yet, error) is reported as "no page" for this frame.
        val corners = if (status == CLV_OK) out.copyOf(8) else null
        val timestampUs = image.imageInfo.timestamp / 1000
        return CornerFrame(
            corners = corners?.map(Float::toDouble),
            confidence = if (corners == null) 0.0 else out[8].toDouble(),
            isStable = stability.update(corners, timestampUs),
            timestampUs = timestampUs,
        )
    }

    private companion object {
        const val CLV_OK = 0
    }
}
