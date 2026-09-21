package tech.zb.v2ex.maui.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        CookieManager.getInstance().removeAllCookies(null)
                        CookieManager.getInstance().flush()
                        result.success(null)
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
