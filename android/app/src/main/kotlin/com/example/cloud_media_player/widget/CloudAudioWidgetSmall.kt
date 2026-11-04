package com.example.cloud_media_player.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent

/**
 * 갤럭시 S26+ 위젯 스택용 4x1 컴팩트 오디오 위젯 Provider
 */
class CloudAudioWidgetSmall : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            CloudAudioWidgetManager.updateSingleWidget(
                context = context,
                manager = appWidgetManager,
                appWidgetId = appWidgetId,
                isMedium = false
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == CloudAudioWidgetManager.ACTION_WIDGET_CONTROL) {
            val cmd = intent.getStringExtra(CloudAudioWidgetManager.EXTRA_CONTROL_CMD) ?: return
            CloudAudioWidgetManager.handleBroadcastControl(context, cmd)
        }
    }
}
