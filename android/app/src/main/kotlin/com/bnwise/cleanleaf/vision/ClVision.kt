package com.bnwise.cleanleaf.vision

import java.nio.ByteBuffer

/** JNI entry points into libclvision, the same library Dart reaches over FFI. */
object ClVision {
    init {
        System.loadLibrary("clvision")
    }

    @JvmStatic external fun opencvVersion(): String

    /**
     * Planes are an ImageProxy's direct YUV_420_888 buffers. On status 0 (`CLV_OK`), [out] holds TL, TR, BR, BL
     * normalized to the upright frame, then the confidence (9 floats).
     */
    @JvmStatic external fun detectFrame(
        y: ByteBuffer,
        u: ByteBuffer,
        v: ByteBuffer,
        width: Int,
        height: Int,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        rotationDegrees: Int,
        out: FloatArray,
    ): Int
}
