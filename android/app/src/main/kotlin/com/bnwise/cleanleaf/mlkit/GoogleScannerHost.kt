package com.bnwise.cleanleaf.mlkit

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.mlkit.common.MlKit
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

// Process-wide: MlKitInitProvider is removed from the manifest so nothing runs while the gate is off.
private var mlKitInitialized = false

/** Google ML Kit Document Scanner, the optional second engine (decisions.md D-02a). */
class GoogleScannerHost(
    private val context: Context,
) : GoogleScannerHostApi,
    PluginRegistry.ActivityResultListener {
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingScan: Continuation<Uri?>? = null

    fun attach(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    fun detach() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        pendingScan?.resumeWithException(FlutterError("detached", "The activity went away during the scan"))
        pendingScan = null
    }

    override fun isAvailable(): Boolean =
        GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

    override suspend fun scan(): String? {
        val activity = activityBinding?.activity ?: throw FlutterError("no-activity", "No activity to scan from")
        if (pendingScan != null) throw FlutterError("busy", "A scan is already running")
        if (!mlKitInitialized) {
            MlKit.initialize(context.applicationContext)
            mlKitInitialized = true
        }
        val sender = startIntent(activity)
        val uri =
            suspendCancellableCoroutine<Uri?> { continuation ->
                pendingScan = continuation
                continuation.invokeOnCancellation { pendingScan = null }
                try {
                    activity.startIntentSenderForResult(sender, SCAN_REQUEST, null, 0, 0, 0)
                } catch (e: IntentSender.SendIntentException) {
                    pendingScan = null
                    continuation.resumeWithException(FlutterError("launch-failed", e.message))
                }
            } ?: return null
        if (uri.scheme == ContentResolver.SCHEME_FILE) return uri.path
        return withContext(Dispatchers.IO) { copyToCache(uri) }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != SCAN_REQUEST) return false
        val continuation = pendingScan ?: return true
        pendingScan = null
        val uri =
            if (resultCode == Activity.RESULT_OK) {
                GmsDocumentScanningResult.fromActivityResultIntent(data)?.pages?.firstOrNull()?.imageUri
            } else {
                null
            }
        continuation.resume(uri)
        return true
    }

    // Fails when Play Services can't provide the scanner module (e.g. first use while offline).
    private suspend fun startIntent(activity: Activity): IntentSender =
        suspendCancellableCoroutine { continuation ->
            GmsDocumentScanning
                .getClient(OPTIONS)
                .getStartScanIntent(activity)
                .addOnSuccessListener { continuation.resume(it) }
                .addOnFailureListener {
                    continuation.resumeWithException(FlutterError("unavailable", it.message))
                }
        }

    private fun copyToCache(uri: Uri): String {
        val target = File(context.cacheDir, "mlkit-scan-${System.currentTimeMillis()}.jpg")
        val input = context.contentResolver.openInputStream(uri) ?: throw FlutterError("read-failed", "Cannot open $uri")
        input.use { source -> target.outputStream().use { source.copyTo(it) } }
        return target.path
    }

    private companion object {
        const val SCAN_REQUEST = 0x5ca1
        val OPTIONS: GmsDocumentScannerOptions =
            GmsDocumentScannerOptions
                .Builder()
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .setGalleryImportAllowed(true)
                .setPageLimit(1)
                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                .build()
    }
}
