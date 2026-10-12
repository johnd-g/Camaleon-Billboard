package com.camaleon.camaleon_billboard

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "camaleon_billboard/update"
    private var pendingApkPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val filePath = call.argument<String>("filePath")?.trim().orEmpty()
                if (filePath.isEmpty()) {
                    result.error("BAD_PATH", "APK path is required.", null)
                    return@setMethodCallHandler
                }

                try {
                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("MISSING_APK", "Downloaded APK does not exist.", null)
                        return@setMethodCallHandler
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()
                    ) {
                        pendingApkPath = filePath
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(
                            mapOf(
                                "opened" to true,
                                "permissionRequested" to true,
                            ),
                        )
                        return@setMethodCallHandler
                    }

                    openApkInstaller(file)
                    result.success(mapOf("opened" to true))
                } catch (error: Exception) {
                    result.error("INSTALLER_ERROR", error.message, null)
                }
            }
    }

    override fun onResume() {
        super.onResume()
        val filePath = pendingApkPath ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
        ) {
            pendingApkPath = null
            val file = File(filePath)
            if (file.exists()) openApkInstaller(file)
        }
    }

    private fun openApkInstaller(file: File) {
        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }
}
