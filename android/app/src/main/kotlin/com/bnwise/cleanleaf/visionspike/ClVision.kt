package com.bnwise.cleanleaf.visionspike

import java.nio.ByteBuffer

/** Candidate B from Kotlin: JNI into the same libclvision.so that Dart reaches over FFI. */
object ClVision {
    init {
        System.loadLibrary("clvision")
    }

    @JvmStatic external fun detect(plane: ByteBuffer, w: Int, h: Int, stride: Int, out: FloatArray): Boolean

    /** timings: decode, warp, enhance, encode (ms), output mean. [jpeg] must be direct. */
    @JvmStatic external fun stillJpeg(
        jpeg: ByteBuffer,
        corners: FloatArray,
        outW: Int,
        outH: Int,
        timings: DoubleArray,
    ): ByteArray

    @JvmStatic external fun buildInfo(): String

    @JvmStatic external fun numThreads(): Int
}
