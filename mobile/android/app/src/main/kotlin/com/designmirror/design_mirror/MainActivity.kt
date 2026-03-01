package com.designmirror.design_mirror

import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.designmirror/arcore"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkAvailability" -> checkArCoreAvailability(result)
                    "requestInstall" -> requestArCoreInstall(result)
                    "openPlayStore" -> openArCorePlayStore(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkArCoreAvailability(result: MethodChannel.Result) {
        try {
            val availability = ArCoreApk.getInstance().checkAvailability(this)
            val status = when {
                availability.isSupported -> "supported"
                availability.isTransient -> "checking"
                availability == ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE -> "unsupported"
                else -> "unknown"
            }

            val isInstalled = try {
                val installStatus = ArCoreApk.getInstance().requestInstall(this, false)
                installStatus == ArCoreApk.InstallStatus.INSTALLED
            } catch (_: Exception) {
                false
            }

            result.success(mapOf(
                "status" to status,
                "installed" to isInstalled
            ))
        } catch (e: Exception) {
            result.success(mapOf(
                "status" to "error",
                "installed" to false,
                "error" to e.message
            ))
        }
    }

    private fun requestArCoreInstall(result: MethodChannel.Result) {
        try {
            pendingResult = result
            val installStatus = ArCoreApk.getInstance().requestInstall(this, true)
            if (installStatus == ArCoreApk.InstallStatus.INSTALLED) {
                pendingResult = null
                result.success(true)
            }
        } catch (e: Exception) {
            pendingResult = null
            result.error("INSTALL_ERROR", e.message, null)
        }
    }

    private fun openArCorePlayStore(result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("https://play.google.com/store/apps/details?id=com.google.ar.core")
                setPackage("com.android.vending")
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            val webIntent = Intent(Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=com.google.ar.core"))
            startActivity(webIntent)
            result.success(true)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1) {
            pendingResult?.success(resultCode == Activity.RESULT_OK)
            pendingResult = null
        }
    }
}
