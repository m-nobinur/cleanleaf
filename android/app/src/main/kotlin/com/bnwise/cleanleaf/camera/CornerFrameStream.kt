package com.bnwise.cleanleaf.camera

/** The Dart side of `cornerFrames`. Call only on the main thread. */
class CornerFrameStream : CornerFramesStreamHandler() {
    private var sink: PigeonEventSink<CornerFrame>? = null

    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<CornerFrame>,
    ) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        sink = null
    }

    fun send(frame: CornerFrame) {
        sink?.success(frame)
    }

    fun fail(
        code: String,
        message: String,
    ) {
        sink?.error(code, message, null)
    }
}
