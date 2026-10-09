package com.neovarch.agent

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * Home-screen widget: the paired PC at a glance (connection, agents working,
 * approvals waiting, open Kanban tasks, the current task) and three buttons
 * that open the app on a route (`nv_route`): chat, voice (dictation) and
 * newtask. Day/night comes from values / values-night colours, so it follows
 * the system theme. Flutter pushes the summary over "neovarch/device"
 * (`updateWidget`, see lib/remote/home_widget.dart); it is kept in
 * SharedPreferences so a launcher restart redraws the last state.
 */
class NvHomeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private const val PREFS = "nv_home_widget"
        private const val KEY = "summary"
        const val EXTRA_ROUTE = "nv_route"

        /** Saves the summary from Flutter and redraws every placed widget. */
        fun save(context: Context, summary: Map<*, *>) {
            val json = JSONObject()
            for ((k, v) in summary) if (k is String) json.put(k, v ?: JSONObject.NULL)
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json.toString()).apply()
            refresh(context)
        }

        fun refresh(context: Context) {
            val m = AppWidgetManager.getInstance(context)
            val ids = m.getAppWidgetIds(ComponentName(context, NvHomeWidget::class.java))
            for (id in ids) m.updateAppWidget(id, views(context))
        }

        private fun summary(context: Context): JSONObject? = try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)?.let { JSONObject(it) }
        } catch (e: Exception) {
            null
        }

        private fun route(context: Context, route: String, code: Int): PendingIntent {
            val i = Intent(context, MainActivity::class.java)
                .setAction("com.neovarch.agent.widget.$route")
                .putExtra(EXTRA_ROUTE, route)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun views(context: Context): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.nv_home_widget)
            val s = summary(context)
            if (s == null) {
                v.setTextViewText(R.id.nvw_pc, "Neovarch")
                v.setTextViewText(R.id.nvw_status, "buka aplikasi untuk memasangkan PC")
                v.setViewVisibility(R.id.nvw_counts, View.GONE)
                v.setViewVisibility(R.id.nvw_task, View.GONE)
            } else {
                val connected = s.optBoolean("connected", false)
                v.setTextViewText(R.id.nvw_pc, s.optString("pc", "Neovarch"))
                v.setTextViewText(R.id.nvw_status, s.optString("status", ""))
                v.setInt(R.id.nvw_dot, "setColorFilter", androidx.core.content.ContextCompat.getColor(context, if (connected) R.color.nvw_ok else R.color.nvw_muted))
                v.setViewVisibility(R.id.nvw_counts, View.VISIBLE)
                v.setTextViewText(R.id.nvw_working, s.optInt("working", 0).toString())
                v.setTextViewText(R.id.nvw_waiting, s.optInt("waiting", 0).toString())
                v.setTextViewText(R.id.nvw_tasks, s.optInt("tasks", 0).toString())
                val task = if (s.isNull("task")) null else s.optString("task")
                if (task.isNullOrBlank()) {
                    v.setViewVisibility(R.id.nvw_task, View.GONE)
                } else {
                    v.setViewVisibility(R.id.nvw_task, View.VISIBLE)
                    v.setTextViewText(R.id.nvw_task, task)
                }
            }
            v.setOnClickPendingIntent(R.id.nvw_root, route(context, "chat", 40))
            v.setOnClickPendingIntent(R.id.nvw_chat, route(context, "chat", 41))
            v.setOnClickPendingIntent(R.id.nvw_voice, route(context, "voice", 42))
            v.setOnClickPendingIntent(R.id.nvw_newtask, route(context, "newtask", 43))
            return v
        }
    }
}
