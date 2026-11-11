package com.bnwise.cleanleaf.vision

class VisionHost : VisionHostApi {
    override fun opencvVersion(): String = ClVision.opencvVersion()
}
