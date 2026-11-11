package com.bnwise.cleanleaf.camera

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

class CameraHost(
    private val context: Context,
    textures: TextureRegistry,
) : CameraHostApi,
    PluginRegistry.RequestPermissionsResultListener {
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: Continuation<CameraPermissionStatus>? = null

    val cornerFrames = CornerFrameStream()
    private val controller = CameraController(context, textures, cornerFrames)

    fun attach(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    fun detach() {
        val binding = activityBinding ?: return
        binding.removeRequestPermissionsResultListener(this)
        activityBinding = null
        controller.stop()
        // A config change re-delivers the result to the next activity; a real teardown never answers.
        if (!binding.activity.isChangingConfigurations) {
            pendingPermission?.resume(if (isGranted()) CameraPermissionStatus.GRANTED else CameraPermissionStatus.DENIED)
            pendingPermission = null
        }
    }

    override suspend fun requestPermission(): CameraPermissionStatus {
        if (isGranted()) return CameraPermissionStatus.GRANTED
        val activity = checkNotNull(activityBinding?.activity) { "No activity to ask for the camera permission" }
        check(pendingPermission == null) { "A camera permission request is already pending" }
        return suspendCancellableCoroutine { continuation ->
            pendingPermission = continuation
            continuation.invokeOnCancellation { pendingPermission = null }
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val continuation = pendingPermission ?: return true
        pendingPermission = null
        val activity = activityBinding?.activity
        val status =
            when {
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED -> CameraPermissionStatus.GRANTED
                activity != null &&
                    ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.CAMERA) ->
                    CameraPermissionStatus.DENIED
                else -> CameraPermissionStatus.PERMANENTLY_DENIED
            }
        continuation.resume(status)
        return true
    }

    override fun openAppSettings() {
        val intent =
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    // Read through Camera2 so it needs neither the permission nor an open camera.
    override fun capabilities(): CameraCapabilities? {
        val manager = context.getSystemService(CameraManager::class.java)
        val characteristics =
            manager.cameraIdList
                .map(manager::getCameraCharacteristics)
                .firstOrNull { it.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK }
                ?: return null
        val pixels = characteristics.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
        return CameraCapabilities(
            sensorWidth = (pixels?.width ?: 0).toLong(),
            sensorHeight = (pixels?.height ?: 0).toLong(),
            hardwareLevel = hardwareLevel(characteristics.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)),
            hasTorch = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true,
            sensorOrientation = (characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0).toLong(),
        )
    }

    override suspend fun start(): CameraSession {
        if (!isGranted()) throw FlutterError("permissionDenied", "The camera permission is not granted", null)
        val owner =
            activityBinding?.activity as? LifecycleOwner
                ?: throw FlutterError("unavailable", "No activity to bind the camera to", null)
        return controller.start(owner)
    }

    override fun stop() = controller.stop()

    override suspend fun capture() = controller.capture()

    override suspend fun setTorch(enabled: Boolean) = controller.setTorch(enabled)

    override suspend fun focusAt(
        x: Double,
        y: Double,
    ) = controller.focusAt(x, y)

    private fun isGranted() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun hardwareLevel(level: Int?) =
        when (level) {
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> CameraHardwareLevel.LIMITED
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> CameraHardwareLevel.FULL
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> CameraHardwareLevel.LEVEL3
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL -> CameraHardwareLevel.EXTERNAL
            else -> CameraHardwareLevel.LEGACY
        }

    private companion object {
        const val PERMISSION_REQUEST = 0x0CA1
    }
}
