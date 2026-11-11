package com.bnwise.cleanleaf.ocr

import java.io.File

/** One native OCR engine; it answers in hOCR so Dart parses every engine alike. */
interface OcrEngine {
    /** Runs on the OCR thread; returns null once [isCancelled] turns true. */
    fun read(
        image: File,
        language: String,
        maxLongSide: Int,
        isCancelled: () -> Boolean,
    ): OcrPage?

    /** Interrupts a running [read]; called from the main thread. */
    fun stop()
}
