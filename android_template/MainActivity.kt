package cr.ac.ucr.gestor_archivos

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private fun granted(): Boolean = if (Build.VERSION.SDK_INT >= 30) {
        Environment.isExternalStorageManager()
    } else if (Build.VERSION.SDK_INT >= 23) {
        checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    } else true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gestor/storage")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "hasAccess" -> result.success(granted())
                        "requestAccess" -> {
                            if (granted()) result.success(true)
                            else if (Build.VERSION.SDK_INT >= 30) {
                                try {
                                    startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                        Uri.parse("package:$packageName")))
                                } catch (e: android.content.ActivityNotFoundException) {
                                    startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                                }
                                result.success(false)
                            } else if (Build.VERSION.SDK_INT >= 23) {
                                if (pending != null) result.error("BUSY", "Permiso pendiente", null)
                                else {
                                    pending = result
                                    requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE,
                                        Manifest.permission.WRITE_EXTERNAL_STORAGE), 501)
                                }
                            } else result.success(true)
                        }
                        "roots" -> {
                            val roots = linkedSetOf(Environment.getExternalStorageDirectory().absolutePath)
                            if (Build.VERSION.SDK_INT >= 30) {
                                val manager = getSystemService(STORAGE_SERVICE) as StorageManager
                                manager.storageVolumes.forEach { volume ->
                                    volume.directory?.let { roots.add(it.absolutePath) }
                                }
                            } else {
                                getExternalFilesDirs(null).filterNotNull().forEach {
                                    roots.add(it.absolutePath.substringBefore("/Android/"))
                                }
                            }
                            result.success(roots.toList())
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("STORAGE", e.message, null)
                }
            }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 501) {
            pending?.success(granted())
            pending = null
        }
    }
}
