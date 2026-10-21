package tech.zb.v2ex.maui.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.provider.MediaStore
import java.io.File
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingImageSave: Pair<String, MethodChannel.Result>? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mv2/media")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveImage") {
                    result.notImplemented()
                } else {
                    val path = call.argument<String>("path")
                    if (path == null || !File(path).isFile) {
                        result.error("invalid_image", "Invalid image file", null)
                    } else if (Build.VERSION.SDK_INT < 29 &&
                        checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                        if (pendingImageSave != null) {
                            result.error("save_busy", "A save request is already pending", null)
                        } else {
                            pendingImageSave = path to result
                            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4701)
                        }
                    } else {
                        saveImage(path, result)
                    }
                }
            }
        // Google OAuth 在应用内 WebView 完成后会话 cookie（PB3_SESSION，
        // HttpOnly）只存在于系统 WebView 的 CookieManager，JS 读不到。
        // Dart 侧 `WebCookieBridge` 在登录结束时来这里取原始 Cookie 头。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mv2/web_cookies")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCookies" -> {
                        val url = call.argument<String>("url")
                        result.success(CookieManager.getInstance().getCookie(url))
                    }
                    "clearCookies" -> {
                        // android.webkit.CookieManager 没有按域删除的 API；本 app
                        // 的 WebView 只用于登录与视频播放，清空整个 jar 代价可忽略。
                        val manager = CookieManager.getInstance()
                        manager.removeAllCookies {
                            manager.flush()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Android 没有 iOS 那种粘贴确认弹窗，剪贴板检测保持原有每次读取行为：
        // changeCount 无对应 API 返回 -1（Dart 归一为 null → 跳过计数闸门），
        // hasProbableWebURL 恒 true（直接读取）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mv2/clipboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "changeCount" -> result.success(-1)
                    "hasProbableWebURL" -> result.success(true)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4701) return
        val pending = pendingImageSave ?: return
        pendingImageSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveImage(pending.first, pending.second)
        } else {
            pending.second.error("photo_permission_denied", "Photo access denied", null)
        }
    }

    private fun saveImage(path: String, result: MethodChannel.Result) {
        Thread {
            var inserted: android.net.Uri? = null
            try {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, options)
                val mime = options.outMimeType ?: throw IllegalArgumentException("Invalid image")
                val extension = when (mime) {
                    "image/png" -> "png"
                    "image/gif" -> "gif"
                    "image/webp" -> "webp"
                    "image/heif", "image/heic" -> "heic"
                    "image/avif" -> "avif"
                    else -> "jpg"
                }
                val name = "MV2_${System.currentTimeMillis()}_${java.util.UUID.randomUUID()}.$extension"
                if (Build.VERSION.SDK_INT >= 29) {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, name)
                        put(MediaStore.Images.Media.MIME_TYPE, mime)
                        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/MV2")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Cannot create image")
                    inserted = uri
                    val output = contentResolver.openOutputStream(uri)
                        ?: throw IllegalStateException("Cannot write image")
                    output.use { target -> File(path).inputStream().use { it.copyTo(target) } }
                    contentResolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
                    runOnUiThread { result.success(null) }
                } else {
                    val folder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "MV2")
                    if (!folder.exists() && !folder.mkdirs()) throw IllegalStateException("Cannot create album")
                    val saved = File(folder, name)
                    try { File(path).copyTo(saved) }
                    catch (error: Exception) { saved.delete(); throw error }
                    MediaScannerConnection.scanFile(this, arrayOf(saved.absolutePath), arrayOf(mime)) { _, _ ->
                        runOnUiThread { result.success(null) }
                    }
                }
            } catch (error: Exception) {
                inserted?.let { contentResolver.delete(it, null, null) }
                runOnUiThread { result.error("save_failed", "Unable to save image", null) }
            }
        }.start()
    }

    /**
     * FCM renders a `notification` payload through the channel named by
     * `com.google.firebase.messaging.default_notification_channel_id`. Creating
     * it here means the first push lands in 通知 instead of the nameless
     * fallback channel Android invents when the id is unknown.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.mv2_notification_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = getString(R.string.mv2_notification_channel_description)
            }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private companion object {
        const val CHANNEL_ID = "mv2_default"
    }
}
