package com.bnwise.cleanleaf.vision

import java.nio.ByteBuffer

/** JNI entry points into libclvision, the same library Dart reaches over FFI. */
object ClVision {
    init {
        System.loadLibrary("clvision")
    }

    @JvmStatic external fun opencvVersion(): String

    /** [model] is a direct buffer with the .tflite bytes; returns the `clv_status`. No-op once loaded. */
    @JvmStatic external fun loadModel(model: ByteBuffer): Int

    @JvmStatic external fun isModelLoaded(): Boolean

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

    /**
     * Reads the first code of [formats] (`clv_code_formats` bits) in an ImageProxy's direct luma plane. Returns
     * the format name, a 0 byte, then the UTF-8 text; null when there is none.
     */
    @JvmStatic external fun decodeCodes(
        y: ByteBuffer,
        width: Int,
        height: Int,
        yRowStride: Int,
        rotationDegrees: Int,
        formats: Int,
    ): ByteArray?

    /**
     * PP-OCR (`clv_ocr_create`): [det] and [rec] are the .tflite files, [dict] the rec classes as UTF-8, one per
     * line. Returns the engine handle, or 0. One [ocrRead] at a time per handle.
     */
    @JvmStatic external fun ocrCreate(
        det: ByteArray,
        rec: ByteArray,
        dict: ByteArray,
        fp16: Boolean,
        threads: Int,
    ): Long

    /**
     * The `clv_ocr_read` JSON (UTF-8) for an encoded page; null once the native-order int in [cancel] (a direct
     * buffer) turns nonzero. Throws IllegalStateException on failure.
     */
    @JvmStatic external fun ocrRead(
        ocr: Long,
        encoded: ByteArray,
        stopIfNonLatin: Boolean,
        cancel: ByteBuffer,
    ): ByteArray?

    @JvmStatic external fun ocrDestroy(ocr: Long)
}
