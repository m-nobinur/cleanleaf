package com.bnwise.cleanleaf.camera

import android.content.Context
import android.util.Range
import android.util.Size
import android.view.Surface
import androidx.camera.core.Camera
import androidx.camera.core.CameraControl
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraState
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.core.takePicture
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.concurrent.futures.await
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executors

/**
 * Runs one CameraX session at a time: 4:3 preview into a Flutter texture, 640×480 colour analysis frames into
 * clvision, and full-resolution stills. All three use cases are pinned to the device's natural orientation.
 */
class CameraController(
    private val context: Context,
    private val textures: TextureRegistry,
    private val frames: CornerFrameStream,
) {
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private var generation = 0
    private var session: Session? = null

    /** `clv_code_formats` bits the analyzer reads instead of detecting pages; 0 detects pages. */
    @Volatile var codeFormats = 0

    private class Session(
        val owner: LifecycleOwner,
        val provider: ProcessCameraProvider,
        val producer: TextureRegistry.SurfaceProducer,
        val camera: Camera,
        val analysis: ImageAnalysis,
        val capture: ImageCapture,
        val releaseOnPause: DefaultLifecycleObserver,
    )

    suspend fun start(owner: LifecycleOwner): CameraSession {
        stop()
        val current = generation
        val provider = ProcessCameraProvider.awaitInstance(context)
        if (current != generation) throw FlutterError("notStarted", "The camera was stopped while starting", null)
        val producer = textures.createSurfaceProducer()
        val preview = previewUseCase(producer)
        val analysis = analysisUseCase(current)
        val capture = captureUseCase()
        val camera =
            try {
                provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis, capture)
            } catch (e: RuntimeException) {
                analysis.clearAnalyzer()
                producer.release()
                throw FlutterError("unavailable", e.message, null)
            }
        val releaseOnPause =
            object : DefaultLifecycleObserver {
                override fun onPause(owner: LifecycleOwner) = stop()
            }
        owner.lifecycle.addObserver(releaseOnPause)
        camera.cameraInfo.cameraState.observe(owner) { state ->
            state.error?.let { frames.fail(errorCode(it.code), "Camera error ${it.code}") }
        }
        session = Session(owner, provider, producer, camera, analysis, capture, releaseOnPause)

        val previewSize = preview.resolutionInfo?.resolution ?: NO_SIZE
        val analysisSize = analysis.resolutionInfo?.resolution ?: NO_SIZE
        val captureSize = capture.resolutionInfo?.resolution ?: NO_SIZE
        return CameraSession(
            textureId = producer.id(),
            previewWidth = previewSize.width.toLong(),
            previewHeight = previewSize.height.toLong(),
            analysisWidth = analysisSize.width.toLong(),
            analysisHeight = analysisSize.height.toLong(),
            captureWidth = captureSize.width.toLong(),
            captureHeight = captureSize.height.toLong(),
            sensorRotation = camera.cameraInfo.sensorRotationDegrees.toLong(),
            handlesCropAndRotation = producer.handlesCropAndRotation(),
        )
    }

    fun stop() {
        generation++
        val session = session ?: return
        this.session = null
        session.owner.lifecycle.removeObserver(session.releaseOnPause)
        session.camera.cameraInfo.cameraState.removeObservers(session.owner)
        session.analysis.clearAnalyzer()
        session.provider.unbindAll()
        session.producer.release()
    }

    suspend fun capture(): String {
        val capture = requireSession().capture
        val dir = File(context.cacheDir, "capture").apply { mkdirs() }
        val file = File.createTempFile("still", ".jpg", dir)
        try {
            capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build())
        } catch (e: ImageCaptureException) {
            file.delete()
            throw FlutterError("captureFailed", e.message, null)
        }
        return file.absolutePath
    }

    suspend fun setTorch(enabled: Boolean) {
        requireSession().camera.cameraControl.enableTorch(enabled).await()
    }

    suspend fun focusAt(
        x: Double,
        y: Double,
    ): Boolean {
        val camera = requireSession().camera
        val (sensorX, sensorY) = uprightToSensor(x.toFloat(), y.toFloat(), camera.cameraInfo.sensorRotationDegrees)
        val point = SurfaceOrientedMeteringPointFactory(1f, 1f).createPoint(sensorX, sensorY)
        val action = FocusMeteringAction.Builder(point, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE).build()
        return try {
            camera.cameraControl.startFocusAndMetering(action).await().isFocusSuccessful
        } catch (e: CameraControl.OperationCanceledException) {
            false
        }
    }

    private fun requireSession() = session ?: throw FlutterError("notStarted", "The camera is not started", null)

    private fun previewUseCase(producer: TextureRegistry.SurfaceProducer) =
        Preview
            .Builder()
            .setResolutionSelector(resolution())
            // The range is session-wide; full-resolution capture caps this sensor at 20 fps (decisions.md D-12).
            .setTargetFrameRate(FRAME_RATE)
            .setTargetRotation(Surface.ROTATION_0)
            .build()
            .apply {
                setSurfaceProvider { request ->
                    producer.setSize(request.resolution.width, request.resolution.height)
                    request.provideSurface(producer.surface, mainExecutor) {}
                }
            }

    private fun analysisUseCase(generation: Int) =
        ImageAnalysis
            .Builder()
            .setResolutionSelector(
                resolution(ResolutionStrategy(ANALYSIS_SIZE, ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)),
            ).setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetRotation(Surface.ROTATION_0)
            .build()
            .apply { setAnalyzer(analysisExecutor, CornerAnalyzer({ codeFormats }) { frame -> deliver(generation, frame) }) }

    private fun captureUseCase() =
        ImageCapture
            .Builder()
            .setResolutionSelector(resolution(ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY))
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .setTargetRotation(Surface.ROTATION_0)
            .build()

    private fun resolution(strategy: ResolutionStrategy? = null) =
        ResolutionSelector
            .Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
            .apply { strategy?.let(::setResolutionStrategy) }
            .build()

    private fun deliver(
        generation: Int,
        frame: CornerFrame,
    ) = mainExecutor.execute { if (generation == this.generation) frames.send(frame) }

    private fun errorCode(code: Int) =
        when (code) {
            CameraState.ERROR_CAMERA_IN_USE, CameraState.ERROR_MAX_CAMERAS_IN_USE -> "inUse"
            CameraState.ERROR_CAMERA_DISABLED, CameraState.ERROR_DO_NOT_DISTURB_MODE_ENABLED -> "disabled"
            else -> "unavailable"
        }

    private companion object {
        val ANALYSIS_SIZE = Size(640, 480)
        val FRAME_RATE = Range(15, 20)
        val NO_SIZE = Size(0, 0)
    }
}

/** Maps a normalized point in the upright preview to the sensor-oriented frame that CameraX meters in. */
internal fun uprightToSensor(
    x: Float,
    y: Float,
    rotationDegrees: Int,
): Pair<Float, Float> =
    when (rotationDegrees) {
        90 -> y to 1 - x
        180 -> 1 - x to 1 - y
        270 -> 1 - y to x
        else -> x to y
    }
