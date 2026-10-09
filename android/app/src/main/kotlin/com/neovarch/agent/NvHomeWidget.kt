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
 * "Neovarch · Aksi cepat" (4x2). Same class as the 1.4.4 widget, so a widget
 * already on the home screen keeps working and simply takes the new look.
 * Left: header (icon, Neovarch, PC chip) and a 2x2 grid of tiles — Chat,
 * Suara (dictation), + Tugas, Kantor (or "Hubungkan PC" without a paired
 * PC). Right: the latest Kantor 3D snapshot with a caption. Android 12+ gets
 * one RemoteViews per size (tall/compact tiles, panel or not); older
 * launchers get the variant for the current size from the widget options.
 */
class NvHomeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id)))
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle?) {
        manager.updateAppWidget(id, views(context, newOptions))
    }

    companion object {
        const val EXTRA_ROUTE = NvWidgets.EXTRA_ROUTE

        /** Kept for MainActivity of 1.4.4 (`updateWidget`). */
        fun save(context: Context, summary: Map<*, *>) = NvWidgets.save(context, summary)

        fun refresh(context: Context) {
            val m = AppWidgetManager.getInstance(context)
            for (id in m.getAppWidgetIds(ComponentName(context, NvHomeWidget::class.java))) {
                m.updateAppWidget(id, views(context, m.getAppWidgetOptions(id)))
            }
        }

        fun views(context: Context, options: Bundle?): RemoteViews {
            val s = NvWidgets.state(context)
            if (Build.VERSION.SDK_INT >= 31) {
                // the launcher picks the largest entry that fits the cell size
                val sizes = listOf(SizeF(110f, 110f), SizeF(230f, 110f), SizeF(110f, 160f), SizeF(230f, 160f))
                val img = NvWidgets.kantorBitmap(context, 0f, 0f, rounded = false)
                return RemoteViews(sizes.associateWith { build(context, s, it.width.toInt(), it.height.toInt(), image = img) })
            }
            val (w, h) = NvWidgets.sizeDp(options)
            return build(context, s, w, h)
        }

        /** One variant for a widget of [w] x [h] dp (0 = unknown → full). */
        fun build(
            context: Context,
            s: NvWidgetState?,
            w: Int,
            h: Int,
            nowMs: Long = System.currentTimeMillis(),
            image: android.graphics.Bitmap? = null,
        ): RemoteViews {
            val variant = NvQuickVariant.of(w, h)
            val v = RemoteViews(context.packageName, if (variant.tall) R.layout.nv_quick_widget else R.layout.nv_quick_widget_compact)
            val st = s ?: NvWidgetState.EMPTY
            val pal = NvWidgets.Palette(context)
            val accent = NvWidgets.accent(pal, s)

            // header chip
            v.setTextViewText(R.id.nvq_pc, NvWidgetText.pcChip(st))
            NvWidgets.tint(context, v, R.id.nvq_dot, pal.of(if (st.connected) R.color.nvw_ok else if (st.paired) R.color.nvw_warn else R.color.nvw_idle))

            // tiles: accent wash + icon; the fourth is Kantor or "Hubungkan PC"
            for (wash in intArrayOf(R.id.nvq_t1_wash, R.id.nvq_t2_wash, R.id.nvq_t3_wash, R.id.nvq_t4_wash)) NvWidgets.tint(context, v, wash, accent)
            for (ic in intArrayOf(R.id.nvq_t1_ic, R.id.nvq_t2_ic, R.id.nvq_t4_ic)) NvWidgets.tint(context, v, ic, accent)
            val kantor = st.paired
            v.setImageViewResource(R.id.nvq_t4_ic, if (kantor) R.drawable.nvw_ic_office else R.drawable.nvw_ic_link)
            v.setTextViewText(R.id.nvq_t4_label, if (kantor) "Kantor" else "Hubungkan PC")

            v.setOnClickPendingIntent(android.R.id.background, NvWidgets.route(context, if (kantor) "chat" else "connect", 40))
            v.setOnClickPendingIntent(R.id.nvq_t1, NvWidgets.route(context, "chat", 41))
            v.setOnClickPendingIntent(R.id.nvq_t2, NvWidgets.route(context, "voice", 42))
            v.setOnClickPendingIntent(R.id.nvq_t3, NvWidgets.route(context, "newtask", 43))
            v.setOnClickPendingIntent(R.id.nvq_t4, NvWidgets.route(context, if (kantor) "kantor" else "connect", 44))

            // image panel
            if (!variant.panel) {
                v.setViewVisibility(R.id.nvq_panel, View.GONE)
            } else {
                v.setViewVisibility(R.id.nvq_panel, View.VISIBLE)
                val bmp = image ?: NvQuickVariant.panelSize(w, h).let { (pw, ph) -> NvWidgets.kantorBitmap(context, pw, ph, rounded = true) }
                bmp?.let { v.setImageViewBitmap(R.id.nvq_img, it) }
                v.setTextViewText(R.id.nvq_title, NvWidgetText.kantorTitle(st))
                v.setTextViewText(R.id.nvq_sub, NvWidgetText.kantorSub(st))
                val snapAt = NvWidgets.snapshotAt(context)
                v.setTextViewText(R.id.nvq_age, if (snapAt == null) "3D" else "3D · " + NvWidgetText.ago(snapAt, nowMs))
                v.setOnClickPendingIntent(R.id.nvq_panel, NvWidgets.route(context, if (kantor) "kantor" else "connect", 45))
            }
            return v
        }
    }
}
