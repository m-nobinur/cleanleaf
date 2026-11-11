package com.bnwise.cleanleaf.camera

import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import android.os.Handler
import android.os.Looper
import android.util.Size
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.concurrent.futures.await
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

class CameraProbe(
    private val activity: FlutterActivity,
    private val textures: TextureRegistry,
) : CameraProbeHostApi {
    private val main = Handler(Looper.getMainLooper())
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val inFlight = AtomicBoolean(false)
    private val delivered = AtomicLong()
    private val dropped = AtomicLong()
    private val copyNanos = AtomicLong()

    private var provider: ProcessCameraProvider? = null
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var camera: Camera? = null
    private lateinit var analysis: ImageAnalysis
    private lateinit var capture: ImageCapture

    @Volatile
    private var sink: PigeonEventSink<FrameMsg>? = null

    val frames =
        object : FramesStreamHandler() {
            override fun onListen(p0: Any?, sink: PigeonEventSink<FrameMsg>) {
                this@CameraProbe.sink = sink
            }

            override fun onCancel(p0: Any?) {
                sink = null
            }
        }

    override suspend fun open(analysisWidth: Long, analysisHeight: Long): CameraInfoMsg {
        val provider = ProcessCameraProvider.getInstance(activity).await()
        this.provider = provider
        val producer = textures.createSurfaceProducer()
        this.producer = producer

        val ratio43 = AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY
        val preview =
            Preview.Builder()
                .setResolutionSelector(ResolutionSelector.Builder().setAspectRatioStrategy(ratio43).build())
                .build()
        analysis =
            ImageAnalysis.Builder()
                .setResolutionSelector(
                    ResolutionSelector.Builder()
                        .setAspectRatioStrategy(ratio43)
                        .setResolutionStrategy(
                            ResolutionStrategy(
                                Size(analysisWidth.toInt(), analysisHeight.toInt()),
                                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                            ),
                        ).build(),
                ).setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
        // Same capture mode as camera_android_camerax 0.7.6: CameraX default (minimize latency), no ZSL.
        capture =
            ImageCapture.Builder()
                .setResolutionSelector(
                    ResolutionSelector.Builder()
                        .setAspectRatioStrategy(ratio43)
                        .setResolutionStrategy(ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY)
                        .build(),
                ).build()

        preview.setSurfaceProvider { request ->
            producer.setSize(request.resolution.width, request.resolution.height)
            request.provideSurface(producer.surface, ContextCompat.getMainExecutor(activity)) {}
        }

        provider.unbindAll()
        val camera =
            provider.bindToLifecycle(activity, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis, capture)
        this.camera = camera

        val c2 = Camera2CameraInfo.from(camera.cameraInfo)
        val level = c2.getCameraCharacteristic(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)
        val tsSource = c2.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE)
        val jpegSizes =
            c2
                .getCameraCharacteristic(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(ImageFormat.JPEG)
                ?.sortedByDescending { it.width * it.height }
                ?.take(3)
        val pixelArray = c2.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)

        val p = preview.resolutionInfo?.resolution
        val a = analysis.resolutionInfo?.resolution
        val s = capture.resolutionInfo?.resolution
        return CameraInfoMsg(
            textureId = producer.id(),
            previewWidth = (p?.width ?: 0).toLong(),
            previewHeight = (p?.height ?: 0).toLong(),
            analysisWidth = (a?.width ?: 0).toLong(),
            analysisHeight = (a?.height ?: 0).toLong(),
            captureWidth = (s?.width ?: 0).toLong(),
            captureHeight = (s?.height ?: 0).toLong(),
            handlesCropAndRotation = producer.handlesCropAndRotation(),
            sensorRotation = camera.cameraInfo.sensorRotationDegrees.toLong(),
            details =
                "hwLevel=$level tsSource=$tsSource pixelArray=$pixelArray jpegTop=$jpegSizes " +
                    "zsl=${camera.cameraInfo.isZslSupported}",
        )
    }

    override fun startStream() {
        analysis.setAnalyzer(analysisExecutor) { image ->
            val stampUs = System.nanoTime() / 1000
            image.use {
                val sink = sink
                if (sink == null || !inFlight.compareAndSet(false, true)) {
                    dropped.incrementAndGet()
                    return@use
                }
                val t0 = System.nanoTime()
                val plane = it.planes[0]
                val buffer = plane.buffer
                val w = it.width
                val h = it.height
                val stride = plane.rowStride
                val y = ByteArray(w * h)
                if (stride == w) {
                    buffer.get(y)
                } else {
                    for (row in 0 until h) {
                        buffer.position(row * stride)
                        buffer.get(y, row * w, w)
                    }
                }
                copyNanos.addAndGet(System.nanoTime() - t0)
                val frame = FrameMsg(y, w.toLong(), h.toLong(), w.toLong(), stampUs)
                main.post {
                    sink.success(frame)
                    delivered.incrementAndGet()
                    inFlight.set(false)
                }
            }
        }
    }

    override fun stopStream() = analysis.clearAnalyzer()

    override suspend fun takePicture(): String {
        val file = File.createTempFile("probe", ".jpg", activity.cacheDir)
        val options = ImageCapture.OutputFileOptions.Builder(file).build()
        return suspendCancellableCoroutine { cont ->
            capture.takePicture(
                options,
                ContextCompat.getMainExecutor(activity),
                object : ImageCapture.OnImageSavedCallback {
                    override fun onImageSaved(output: ImageCapture.OutputFileResults) = cont.resume(file.absolutePath)

                    override fun onError(exception: ImageCaptureException) = cont.resumeWithException(exception)
                },
            )
        }
    }

    override suspend fun focus(x: Double, y: Double): String {
        val point = SurfaceOrientedMeteringPointFactory(1f, 1f).createPoint(x.toFloat(), y.toFloat())
        val action = FocusMeteringAction.Builder(point, FocusMeteringAction.FLAG_AF).build()
        val result = camera!!.cameraControl.startFocusAndMetering(action).await()
        return "focused=${result.isFocusSuccessful}"
    }

    override suspend fun torch(on: Boolean) {
        camera!!.cameraControl.enableTorch(on).await()
    }

    override suspend fun lockExposure(locked: Boolean) {
        val options =
            CaptureRequestOptions.Builder()
                .setCaptureRequestOption(CaptureRequest.CONTROL_AE_LOCK, locked)
                .build()
        Camera2CameraControl.from(camera!!.cameraControl).addCaptureRequestOptions(options).await()
    }

    override fun monotonicNowUs(): Long = System.nanoTime() / 1000

    override fun stats(): String {
        val n = delivered.get()
        val copyMs = if (n == 0L) 0.0 else copyNanos.get() / 1e6 / n
        return "delivered=$n dropped=${dropped.get()} kotlinCopyMs=${"%.3f".format(copyMs)}"
    }

    override fun close() {
        analysis.clearAnalyzer()
        provider?.unbindAll()
        producer?.release()
    }
}
