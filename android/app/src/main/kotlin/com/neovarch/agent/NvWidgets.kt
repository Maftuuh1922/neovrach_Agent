package com.neovarch.agent

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Shared plumbing of the home-screen widgets (NvHomeWidget "Aksi cepat",
 * NvStatusWidget "Status", NvAgentsWidget "Agen"): the summary store, the
 * Kantor snapshot file, the method-channel entry points, day/night colours
 * and the `nv_route` intents.
 */
object NvWidgets {
    private const val PREFS = "nv_home_widget"
    private const val KEY = "summary"
    private const val KEY_SNAP_AT = "snapshot_at"
    const val EXTRA_ROUTE = "nv_route"
    const val ACTION_PREFIX = "com.neovarch.agent.widget."

    // ------------------------------------------------------------ channel --
    /** `updateWidget` / `saveWidgetSnapshot` / `widgetsPlaced` from Flutter. */
    fun handle(context: Context, method: String, args: Any?): Any? = when (method) {
        "updateWidget" -> {
            save(context, (args as? Map<*, *>) ?: emptyMap<String, Any?>()); true
        }
        "saveWidgetSnapshot" -> {
            val bytes = (args as? Map<*, *>)?.get("bytes") as? ByteArray
            if (bytes == null) null else saveSnapshot(context, bytes)
        }
        "widgetsPlaced" -> {
            val kind = (args as? Map<*, *>)?.get("kind") as? String
            placed(context, kind)
        }
        else -> null
    }

    /** Saves the summary from Flutter and redraws every placed widget. */
    fun save(context: Context, summary: Map<*, *>) {
        val json = JSONObject()
        for ((k, v) in summary) if (k is String) json.put(k, JSONObject.wrap(v) ?: JSONObject.NULL)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json.toString()).apply()
        refreshAll(context)
    }

    fun state(context: Context): NvWidgetState? = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            ?.let { NvWidgetState.parse(toMap(JSONObject(it))) }
    } catch (e: Exception) {
        null
    }

    fun toMap(o: JSONObject): Map<String, Any?> {
        val m = LinkedHashMap<String, Any?>()
        val keys = o.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            m[k] = unwrap(o.opt(k))
        }
        return m
    }

    private fun unwrap(v: Any?): Any? = when (v) {
        null, JSONObject.NULL -> null
        is JSONObject -> toMap(v)
        is JSONArray -> (0 until v.length()).map { unwrap(v.opt(it)) }
        else -> v
    }

    fun refreshAll(context: Context) {
        NvHomeWidget.refresh(context)
        NvStatusWidget.refresh(context)
        NvAgentsWidget.refresh(context)
    }

    fun placed(context: Context, kind: String?): Boolean {
        val m = AppWidgetManager.getInstance(context)
        fun has(c: Class<*>) = m.getAppWidgetIds(ComponentName(context, c)).isNotEmpty()
        return when (kind) {
            "quick" -> has(NvHomeWidget::class.java)
            "status" -> has(NvStatusWidget::class.java)
            "agents" -> has(NvAgentsWidget::class.java)
            else -> has(NvHomeWidget::class.java) || has(NvStatusWidget::class.java) || has(NvAgentsWidget::class.java)
        }
    }

    // ----------------------------------------------------------- snapshot --
    fun snapshotFile(context: Context) = File(File(context.filesDir, "widgets"), "kantor.jpg")

    /** Writes the Kantor 3D snapshot atomically, redraws "Aksi cepat"; returns the path. */
    fun saveSnapshot(context: Context, bytes: ByteArray): String? = try {
        val f = snapshotFile(context)
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, "kantor.jpg.tmp")
        tmp.writeBytes(bytes)
        if (!tmp.renameTo(f)) {
            f.delete(); tmp.renameTo(f)
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(KEY_SNAP_AT, System.currentTimeMillis()).apply()
        NvHomeWidget.refresh(context)
        f.absolutePath
    } catch (e: Exception) {
        null
    }

    fun snapshotAt(context: Context): Long? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_SNAP_AT, 0L).takeIf { it > 0 && snapshotFile(context).exists() }

    /**
     * The Kantor image: the saved snapshot, else the bundled art.
     * [rounded] (API < 31, launchers do not clip): centre-cropped to the
     * panel's aspect ([wDp] x [hDp]) and rounded, ≤ 300 px. Otherwise a plain
     * ≤ 360 px RGB_565 copy; the layout's clipToOutline rounds it and one
     * instance is shared by every size variant (RemoteViews bitmap cache), so
     * the update stays far below the binder limit.
     */
    fun kantorBitmap(context: Context, wDp: Float, hDp: Float, rounded: Boolean, radiusDp: Float = 18f): Bitmap? = try {
        val f = snapshotFile(context)
        val src = (if (f.exists()) BitmapFactory.decodeFile(f.absolutePath) else null)
            ?: BitmapFactory.decodeResource(context.resources, R.drawable.nvw_kantor_art)
        when {
            src == null -> null
            rounded -> roundedCrop(src, wDp, hDp, radiusDp, 300)
            else -> {
                val w = minOf(360, src.width)
                val h = (src.height.toFloat() * w / src.width).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(src, w, h, true).copy(Bitmap.Config.RGB_565, false)
            }
        }
    } catch (e: Throwable) {
        null
    }

    /** Centre-crop to aspect [wDp]:[hDp] at ≤ [maxW] px wide, corners rounded. */
    fun roundedCrop(src: Bitmap, wDp: Float, hDp: Float, radiusDp: Float, maxW: Int = 300): Bitmap {
        val aspect = (wDp / hDp).coerceIn(0.4f, 2.5f)
        val outW = minOf(maxW, src.width)
        val outH = (outW / aspect).toInt().coerceAtLeast(1)
        val out = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val scale = maxOf(outW.toFloat() / src.width, outH.toFloat() / src.height)
        val m = Matrix().apply {
            setScale(scale, scale)
            postTranslate((outW - src.width * scale) / 2f, (outH - src.height * scale) / 2f)
        }
        val shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(m) }
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply { this.shader = shader }
        val r = radiusDp * outW / wDp
        Canvas(out).drawRoundRect(RectF(0f, 0f, outW.toFloat(), outH.toFloat()), r, r, p)
        return out
    }

    // ------------------------------------------------------------ colours --
    /** One colour resource in day and night (for setColorInt on API 31+). */
    data class DayNight(val day: Int, val night: Int)

    private fun themed(context: Context, night: Boolean): Context {
        val c = Configuration(context.resources.configuration)
        c.uiMode = (c.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            (if (night) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO)
        return context.createConfigurationContext(c)
    }

    class Palette(context: Context) {
        private val day = themed(context, false)
        private val night = themed(context, true)
        fun of(res: Int) = DayNight(ContextCompat.getColor(day, res), ContextCompat.getColor(night, res))
    }

    fun isNight(context: Context) =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    /** Calls `method(int)` with the day/night pair (API 31+: follows the theme live). */
    fun colorInt(context: Context, v: RemoteViews, id: Int, method: String, c: DayNight) {
        if (Build.VERSION.SDK_INT >= 31) v.setColorInt(id, method, c.day, c.night)
        else v.setInt(id, method, if (isNight(context)) c.night else c.day)
    }

    fun tint(context: Context, v: RemoteViews, id: Int, c: DayNight) = colorInt(context, v, id, "setColorFilter", c)
    fun tint(v: RemoteViews, id: Int, color: Int) = v.setInt(id, "setColorFilter", color)

    fun statusColor(pal: Palette, status: String): DayNight = pal.of(
        when (status) {
            "working" -> R.color.nvw_ok
            "waiting-approval", "waiting" -> R.color.nvw_warn
            "error" -> R.color.nvw_accent
            else -> R.color.nvw_idle
        },
    )

    /** The app's accent when Flutter sent one, else the resource accent. */
    fun accent(pal: Palette, s: NvWidgetState?): DayNight =
        s?.accent?.let { DayNight(it, it) } ?: pal.of(R.color.nvw_accent)

    // ------------------------------------------------------------- intents --
    fun route(context: Context, route: String, code: Int): PendingIntent {
        val i = Intent(context, MainActivity::class.java)
            .setAction(ACTION_PREFIX + route)
            .putExtra(EXTRA_ROUTE, route)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /** Template for collection rows: each row fills in `nv_route=agent:<id>`. */
    fun rowTemplate(context: Context, code: Int): PendingIntent {
        val i = Intent(context, MainActivity::class.java)
            .setAction(ACTION_PREFIX + "agent")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val mutable = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT or mutable)
    }

    // --------------------------------------------------------------- sizes --
    /** Current size in dp (portrait: min width x max height), 0 when unknown. */
    fun sizeDp(options: Bundle?): Pair<Int, Int> {
        if (options == null) return Pair(0, 0)
        return Pair(
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0),
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0),
        )
    }
}
