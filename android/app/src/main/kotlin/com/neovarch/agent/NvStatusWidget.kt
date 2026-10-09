package com.neovarch.agent

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews

/**
 * "Neovarch · Status" (2x2): the PC (online dot, name, open tasks), agents
 * working / waiting, and the last activity. Tap opens Kantor (or pairing
 * when no PC is paired). Short sizes drop the status line, then the last line.
 */
class NvStatusWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id)))
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle?) {
        manager.updateAppWidget(id, views(context, newOptions))
    }

    companion object {
        fun refresh(context: Context) {
            val m = AppWidgetManager.getInstance(context)
            for (id in m.getAppWidgetIds(ComponentName(context, NvStatusWidget::class.java))) {
                m.updateAppWidget(id, views(context, m.getAppWidgetOptions(id)))
            }
        }

        fun views(context: Context, options: Bundle?): RemoteViews {
            val s = NvWidgets.state(context)
            if (Build.VERSION.SDK_INT >= 31) {
                val sizes = listOf(SizeF(100f, 100f), SizeF(100f, 118f), SizeF(100f, 138f))
                return RemoteViews(sizes.associateWith { build(context, s, it.height.toInt()) })
            }
            return build(context, s, NvWidgets.sizeDp(options).second)
        }

        fun build(context: Context, s: NvWidgetState?, h: Int, nowMs: Long = System.currentTimeMillis()): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.nv_status_widget)
            val st = s ?: NvWidgetState.EMPTY
            val pal = NvWidgets.Palette(context)
            val variant = NvStatusVariant.of(h)
            val dot = pal.of(if (st.connected) R.color.nvw_ok else if (st.paired) R.color.nvw_warn else R.color.nvw_idle)
            NvWidgets.tint(context, v, R.id.nvs_dot, dot)
            NvWidgets.tint(context, v, R.id.nvs_halo, dot)
            v.setTextViewText(R.id.nvs_pc, if (st.paired) st.pc else "Neovarch")
            v.setTextViewText(R.id.nvs_status, NvWidgetText.statusLine(st))
            v.setViewVisibility(R.id.nvs_status, if (variant.statusLine) View.VISIBLE else View.GONE)
            v.setTextViewText(R.id.nvs_s1_num, st.working.toString())
            v.setTextViewText(R.id.nvs_s2_num, st.waiting.toString())
            NvWidgets.colorInt(context, v, R.id.nvs_s1_num, "setTextColor", pal.of(if (st.working > 0) R.color.nvw_ok else R.color.nvw_text))
            NvWidgets.colorInt(context, v, R.id.nvs_s2_num, "setTextColor", pal.of(if (st.waiting > 0) R.color.nvw_warn else R.color.nvw_text))
            v.setTextViewText(R.id.nvs_last, NvWidgetText.lastLine(st, nowMs))
            v.setViewVisibility(R.id.nvs_last, if (variant.lastLine) View.VISIBLE else View.GONE)
            v.setOnClickPendingIntent(android.R.id.background, NvWidgets.route(context, if (st.paired) "kantor" else "connect", 50))
            // "menunggu" opens the approvals sheet straight away
            v.setOnClickPendingIntent(R.id.nvs_s2, NvWidgets.route(context, if (st.waiting > 0) "approvals" else if (st.paired) "kantor" else "connect", 51))
            return v
        }
    }
}
