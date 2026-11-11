package com.bnwise.cleanleaf

import com.bnwise.cleanleaf.camera.CameraHost
import com.bnwise.cleanleaf.camera.CameraHostApi
import com.bnwise.cleanleaf.camera.CornerFramesStreamHandler
import com.bnwise.cleanleaf.vision.VisionHost
import com.bnwise.cleanleaf.vision.VisionHostApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/** Registers every app-owned Pigeon API on the engine. */
class CleanleafPlugin :
    FlutterPlugin,
    ActivityAware {
    private var camera: CameraHost? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        val camera = CameraHost(binding.applicationContext, binding.textureRegistry)
        this.camera = camera
        CameraHostApi.setUp(messenger, camera)
        CornerFramesStreamHandler.register(messenger, camera.cornerFrames)
        VisionHostApi.setUp(messenger, VisionHost())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        CameraHostApi.setUp(messenger, null)
        VisionHostApi.setUp(messenger, null)
        camera = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        camera?.attach(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        camera?.detach()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        camera?.attach(binding)
    }

    override fun onDetachedFromActivity() {
        camera?.detach()
    }
}
