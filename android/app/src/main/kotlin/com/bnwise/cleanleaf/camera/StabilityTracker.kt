package com.bnwise.cleanleaf.camera

import kotlin.math.hypot

/**
 * A page is stable once every corner stays within [tolerance] (normalized units) of where it settled for at least
 * [holdUs]. A frame without corners, or one that moves past the tolerance, starts the wait over.
 */
class StabilityTracker(
    private val tolerance: Float = 0.02f,
    private val holdUs: Long = 500_000,
) {
    private var anchor: FloatArray? = null
    private var anchorUs = 0L

    fun update(
        corners: FloatArray?,
        timestampUs: Long,
    ): Boolean {
        val anchor = anchor
        if (corners == null) {
            this.anchor = null
            return false
        }
        if (anchor == null || maxShift(anchor, corners) > tolerance) {
            this.anchor = corners.copyOf()
            anchorUs = timestampUs
            return false
        }
        return timestampUs - anchorUs >= holdUs
    }

    private fun maxShift(
        a: FloatArray,
        b: FloatArray,
    ): Float = (0 until 8 step 2).maxOf { hypot(a[it] - b[it], a[it + 1] - b[it + 1]) }
}
