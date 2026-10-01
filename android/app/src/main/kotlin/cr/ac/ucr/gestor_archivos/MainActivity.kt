// PUENTE NATIVO ANDROID. preparar.ps1 copia este archivo al paquete Kotlin del proyecto.
// Dart llama hasAccess, requestAccess, roots y dashboard mediante el canal gestor/storage.
package cr.ac.ucr.gestor_archivos

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import java.io.File
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Conserva la respuesta pendiente del diálogo de permisos en Android anterior a 11.
    private var pending: MethodChannel.Result? = null
    // Android 11+ usa acceso especial; versiones anteriores usan permiso de almacenamiento.
    private fun granted(): Boolean = if (Build.VERSION.SDK_INT >= 30) {
        Environment.isExternalStorageManager()
    } else if (Build.VERSION.SDK_INT >= 23) {
        checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    } else true

    // Una sola fuente para raíces: el explorador y el inicio muestran los mismos volúmenes.
    private fun storageRoots(): List<String> {
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
        return roots.toList()
    }

    // StatFs consulta capacidad del sistema de archivos; no suma carpetas ni lee contenidos.
    private fun storageDashboard(): Map<String, Any> {
        val volumes = storageRoots().mapIndexed { index, path ->
            val row = mutableMapOf<String, Any>("path" to path,
                "label" to if (index == 0) "Almacenamiento interno" else "SD / USB: ${File(path).name}")
            try {
                val stat = StatFs(path)
                row["totalBytes"] = stat.totalBytes
                row["freeBytes"] = stat.freeBytes
                row["availableBytes"] = stat.availableBytes
            } catch (e: Exception) {
                row["error"] = "Volumen no disponible"
            }
            row
        }
        val folders = listOf(
            Triple("downloads", "Descargas", Environment.DIRECTORY_DOWNLOADS),
            Triple("camera", "Cámara", Environment.DIRECTORY_DCIM),
            Triple("pictures", "Imágenes", Environment.DIRECTORY_PICTURES),
            Triple("documents", "Documentos", Environment.DIRECTORY_DOCUMENTS),
            Triple("music", "Música", Environment.DIRECTORY_MUSIC),
            Triple("videos", "Videos", Environment.DIRECTORY_MOVIES)
        )
        val shortcuts = folders.map { (id, label, folder) ->
            val file = Environment.getExternalStoragePublicDirectory(folder)
            mapOf("id" to id, "label" to label, "path" to file.absolutePath,
                "available" to (file.isDirectory && file.canRead()))
        }
        return mapOf("volumes" to volumes, "shortcuts" to shortcuts)
    }

    // Registra el canal después de permitir que Flutter configure los plugins.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gestor/storage")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "hasAccess" -> result.success(granted())
                        // En Android 11+ abre Ajustes; Dart comprobará el resultado al volver.
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
                        // Expone raíces del almacenamiento compartido, no directorios privados del sistema.
                        "roots" -> {
                            result.success(storageRoots())
                        }
                        "dashboard" -> {
                            if (!granted()) result.error("PERMISSION", "Se requiere acceso al almacenamiento", null)
                            else result.success(storageDashboard())
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("STORAGE", e.message, null)
                }
            }
    }
    // Completa la solicitud asíncrona de permisos de las versiones anteriores.
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 501) {
            pending?.success(granted())
            pending = null
        }
    }
}
