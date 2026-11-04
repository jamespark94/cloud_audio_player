package com.example.cloud_media_player.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import com.example.cloud_media_player.MainActivity
import com.example.cloud_media_player.R
import java.io.File

/**
 * 갤럭시 S26+ (One UI 7/8) 위젯 스택(Widget Stack)에 올라가는
 * 4x1 슬림 위젯 및 4x2 표준 스택 위젯의 상태를 통합 관리하고 렌더링합니다.
 *
 * [핵심 설계]
 * - 위젯 스택의 좌/우 스와이프 전환 제스처와 충돌하지 않도록 드래그 SeekBar 대신
 *   읽기 전용 ProgressBar + 명확한 탭 PendingIntent 버튼을 사용합니다.
 * - 화면이 꺼져 있거나 앱 UI가 닫혀 있을 때도 MediaButtonReceiver 폴백 및
 *   Flutter MethodChannel을 동시에 트리거하여 백그라운드 재생을 즉시 제어합니다.
 */
object CloudAudioWidgetManager {
    private const val PREFS_NAME = "cloud_audio_s26_widget_prefs"
    const val ACTION_WIDGET_CONTROL = "com.example.cloud_audio_player.ACTION_WIDGET_CONTROL"
    const val EXTRA_CONTROL_CMD = "extra_control_cmd"

    fun saveAndBroadcastWidgetState(
        context: Context,
        title: String,
        artist: String,
        cloudBadge: String,
        isPlaying: Boolean,
        progress: Int,
        positionText: String,
        durationText: String,
        isShuffle: Boolean,
        repeatMode: String,
        coverPath: String
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString("title", title)
            .putString("artist", artist)
            .putString("cloudBadge", cloudBadge)
            .putBoolean("isPlaying", isPlaying)
            .putInt("progress", progress)
            .putString("positionText", positionText)
            .putString("durationText", durationText)
            .putBoolean("isShuffle", isShuffle)
            .putString("repeatMode", repeatMode)
            .putString("coverPath", coverPath)
            .apply()

        updateAllWidgets(context)
    }

    fun updateAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)

        val smallIds = manager.getAppWidgetIds(
            ComponentName(context, CloudAudioWidgetSmall::class.java)
        )
        for (id in smallIds) {
            updateSingleWidget(context, manager, id, isMedium = false)
        }

        val mediumIds = manager.getAppWidgetIds(
            ComponentName(context, CloudAudioWidgetMedium::class.java)
        )
        for (id in mediumIds) {
            updateSingleWidget(context, manager, id, isMedium = true)
        }
    }

    fun updateSingleWidget(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        isMedium: Boolean
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val title = prefs.getString("title", "재생 중인 곡 없음") ?: "재생 중인 곡 없음"
        val artist = prefs.getString("artist", "폴더를 선택해 음악을 재생하세요") ?: ""
        val cloudBadge = prefs.getString("cloudBadge", "Cloud Audio Player") ?: "Cloud Audio"
        val isPlaying = prefs.getBoolean("isPlaying", false)
        val progress = prefs.getInt("progress", 0)
        val positionText = prefs.getString("positionText", "00:00") ?: "00:00"
        val durationText = prefs.getString("durationText", "00:00") ?: "00:00"
        val isShuffle = prefs.getBoolean("isShuffle", false)
        val repeatMode = prefs.getString("repeatMode", "all") ?: "all"
        val coverPath = prefs.getString("coverPath", "") ?: ""

        val layoutRes = if (isMedium) R.layout.widget_audio_medium else R.layout.widget_audio_small
        val views = RemoteViews(context.packageName, layoutRes)

        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(
            R.id.widget_artist,
            if (isMedium) artist else "$artist • $cloudBadge"
        )
        views.setProgressBar(R.id.widget_progress, 100, progress, false)

        // 재생 / 일시정지 아이콘 전환
        views.setImageViewResource(
            R.id.btn_play_pause,
            if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        )

        // 앨범 커버 이미지 설정 (로컬 캐시 파일이 있으면 비트맵 적용, 없으면 기본 음표 아이콘)
        var bitmapLoaded = false
        if (coverPath.isNotEmpty()) {
            try {
                val file = File(coverPath)
                if (file.exists()) {
                    val bmp = BitmapFactory.decodeFile(file.absolutePath)
                    if (bmp != null) {
                        views.setImageViewBitmap(R.id.widget_album_art, bmp)
                        bitmapLoaded = true
                    }
                }
            } catch (_: Exception) {
            }
        }
        if (!bitmapLoaded) {
            views.setImageViewResource(R.id.widget_album_art, R.mipmap.ic_launcher)
        }

        if (isMedium) {
            views.setTextViewText(R.id.widget_cloud_badge, cloudBadge)
            views.setTextViewText(R.id.widget_time, "$positionText / $durationText")
            views.setTextViewText(
                R.id.btn_shuffle,
                if (isShuffle) "🔀 ON" else "🔀"
            )
            val repeatLabel = when (repeatMode) {
                "one" -> "🔂 1곡"
                "off" -> "➡️ 끔"
                else -> "🔁 전체"
            }
            views.setTextViewText(R.id.btn_repeat, repeatLabel)

            views.setOnClickPendingIntent(
                R.id.btn_shuffle,
                buildControlPendingIntent(context, "ACTION_SHUFFLE", 104)
            )
            views.setOnClickPendingIntent(
                R.id.btn_repeat,
                buildControlPendingIntent(context, "ACTION_REPEAT", 105)
            )
        }

        // 공통 버튼 PendingIntent 연결
        views.setOnClickPendingIntent(
            R.id.btn_prev,
            buildControlPendingIntent(context, "ACTION_PREV", 101)
        )
        views.setOnClickPendingIntent(
            R.id.btn_play_pause,
            buildControlPendingIntent(context, "ACTION_PLAY_PAUSE", 102)
        )
        views.setOnClickPendingIntent(
            R.id.btn_next,
            buildControlPendingIntent(context, "ACTION_NEXT", 103)
        )

        // 위젯 본체/앨범아트 클릭 시 앱 열기
        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val openPending = PendingIntent.getActivity(context, 100, openAppIntent, flags)
        views.setOnClickPendingIntent(R.id.widget_root_container, openPending)

        manager.updateAppWidget(appWidgetId, views)
    }

    private fun buildControlPendingIntent(
        context: Context,
        cmd: String,
        reqCode: Int
    ): PendingIntent {
        val intent = Intent(context, CloudAudioWidgetSmall::class.java).apply {
            action = ACTION_WIDGET_CONTROL
            putExtra(EXTRA_CONTROL_CMD, cmd)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, reqCode, intent, flags)
    }

    fun handleBroadcastControl(context: Context, cmd: String) {
        // 1. Flutter 엔진이 살아있으면 MethodChannel로 즉시 전달
        val channel = MainActivity.widgetMethodChannel
        if (channel != null) {
            channel.invokeMethod("onWidgetAction", cmd)
            return
        }

        // 2. 앱 UI가 닫혀 있거나 백그라운드 MediaSessionService만 동작 중인 경우 MediaButton 인텐트 전송
        val keyCode = when (cmd) {
            "ACTION_PLAY_PAUSE" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "ACTION_NEXT" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "ACTION_PREV" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> null
        }
        if (keyCode != null) {
            val downIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setPackage(context.packageName)
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            context.sendBroadcast(downIntent)

            val upIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setPackage(context.packageName)
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, keyCode))
            }
            context.sendBroadcast(upIntent)
        }
    }
}
