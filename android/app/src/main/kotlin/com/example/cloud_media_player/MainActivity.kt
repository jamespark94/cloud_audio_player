package com.example.cloud_media_player

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.example.cloud_media_player.widget.CloudAudioWidgetManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 화면이 꺼진 상태(Screen-Off / Doze 모드)에서도 클라우드 오디오 스트리밍을 유지하기 위해
 * AudioServiceActivity를 상속하고, CPU Partial WakeLock + High-Performance Wi-Fi Lock 및
 * 갤럭시 S26+ (One UI 7/8) 위젯 스택 브로드캐스트 채널을 관리합니다.
 */
class MainActivity : AudioServiceActivity() {
    companion object {
        private const val BATTERY_CHANNEL = "com.example.cloud_audio_player/battery"
        private const val BATTERY_LEGACY_CHANNEL = "com.example.cloud_media_player/battery"
        private const val WINDOW_CHANNEL = "com.example.cloud_media_player/window"
        private const val WIDGET_CHANNEL = "com.example.cloud_audio_player/widget"

        var widgetMethodChannel: MethodChannel? = null
    }

    private var isFullScreenRequested = false
    private var cpuWakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        // 1. 갤럭시 S26+ 위젯 스택 (4x1 & 4x2) 동기화 채널
        val wChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
        widgetMethodChannel = wChannel
        wChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateAudioWidget" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        CloudAudioWidgetManager.saveAndBroadcastWidgetState(
                            context = applicationContext,
                            title = args["title"] as? String ?: "재생 중인 곡 없음",
                            artist = args["artist"] as? String ?: "클라우드 오디오 플레이어",
                            cloudBadge = args["cloudBadge"] as? String ?: "Cloud Audio",
                            isPlaying = args["isPlaying"] as? Boolean ?: false,
                            progress = (args["progress"] as? Number)?.toInt() ?: 0,
                            positionText = args["positionText"] as? String ?: "00:00",
                            durationText = args["durationText"] as? String ?: "00:00",
                            isShuffle = args["isShuffle"] as? Boolean ?: false,
                            repeatMode = args["repeatMode"] as? String ?: "all",
                            coverPath = args["coverPath"] as? String ?: ""
                        )
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 2. 배터리 최적화 예외 + 백그라운드 스트리밍 WakeLock/WifiLock 채널
        val batteryHandler = MethodChannel.MethodCallHandler { call, result ->
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            when (call.method) {
                "isPowerSaveMode" -> {
                    val isPowerSave = powerManager?.isPowerSaveMode ?: false
                    result.success(isPowerSave)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                    } else {
                        true
                    }
                    result.success(isIgnoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("ERROR", ex.message, null)
                        }
                    }
                }
                "setBackgroundStreamingLock" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    updateBackgroundStreamingLocks(enable)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler(batteryHandler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_LEGACY_CHANNEL)
            .setMethodCallHandler(batteryHandler)

        // 3. 윈도우 방향/풀스크린 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WINDOW_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setFullScreen" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    isFullScreenRequested = enable
                    applyFullScreen(enable)
                    result.success(true)
                }
                "setOrientation" -> {
                    val mode = call.argument<String>("mode") ?: "unspecified"
                    requestedOrientation = when (mode) {
                        "landscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                        "portrait" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                        "sensor" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR
                        else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 화면이 꺼진 상태에서도 LocalStreamProxy(127.0.0.1)와 클라우드 소켓이 끊기지 않도록
     * CPU Partial WakeLock 및 고성능 Wi-Fi Lock을 획득하거나 해제합니다.
     */
    private fun updateBackgroundStreamingLocks(enable: Boolean) {
        try {
            if (enable) {
                if (cpuWakeLock == null) {
                    val pm = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                    cpuWakeLock = pm?.newWakeLock(
                        PowerManager.PARTIAL_WAKE_LOCK,
                        "CloudAudioPlayer::BackgroundAudioWakeLock"
                    )?.apply {
                        setReferenceCounted(false)
                    }
                }
                if (cpuWakeLock?.isHeld == false) {
                    cpuWakeLock?.acquire(6 * 60 * 60 * 1000L) // 최대 6시간 연속 재생 보호
                }

                if (wifiLock == null) {
                    val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                    val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                    } else {
                        @Suppress("DEPRECATION")
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF
                    }
                    wifiLock = wm?.createWifiLock(
                        lockMode,
                        "CloudAudioPlayer::BackgroundAudioWifiLock"
                    )?.apply {
                        setReferenceCounted(false)
                    }
                }
                if (wifiLock?.isHeld == false) {
                    wifiLock?.acquire()
                }
            } else {
                if (cpuWakeLock?.isHeld == true) {
                    cpuWakeLock?.release()
                }
                if (wifiLock?.isHeld == true) {
                    wifiLock?.release()
                }
            }
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        updateBackgroundStreamingLocks(false)
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && isFullScreenRequested) {
            applyFullScreen(true)
        }
    }

    private fun applyFullScreen(enable: Boolean) {
        runOnUiThread {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }

            val insetsController = WindowCompat.getInsetsController(window, window.decorView)
            insetsController.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

            if (enable) {
                insetsController.hide(WindowInsetsCompat.Type.systemBars())
                @Suppress("DEPRECATION")
                window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            } else {
                @Suppress("DEPRECATION")
                window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
                insetsController.show(WindowInsetsCompat.Type.systemBars())
            }
        }
    }
}
