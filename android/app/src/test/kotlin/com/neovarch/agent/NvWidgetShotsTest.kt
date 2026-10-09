package com.neovarch.agent

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RemoteViews
import androidx.test.core.app.ApplicationProvider
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.io.FileOutputStream

/**
 * Renders the real widget RemoteViews (the providers' own build code on the
 * real layouts) to PNGs, day and night: the widget picker previewImage files
 * and the screenshots. Runs only with NVW_SHOTS_DIR set:
 *   NVW_SHOTS_DIR=/path ./gradlew :app:testDebugUnitTest --tests '*NvWidgetShotsTest*'
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-xxhdpi")
class NvWidgetShotsTest {
    private val out: File? = System.getenv("NVW_SHOTS_DIR")?.let { File(it) }
    private val now = 1_791_500_000_000L

    private fun sample(paired: Boolean = true, connected: Boolean = true) = NvWidgetState.parse(
        mapOf(
            "v" to 2, "pc" to "PC Kantor", "paired" to paired, "connected" to connected,
            "status" to if (connected) "terhubung" else "terputus",
            "working" to 2, "waiting" to 1, "waitingAgents" to 1, "agentCount" to 5, "tasks" to 4,
            "task" to "Raka: Rapikan folder Unduhan",
            "agents" to listOf(
                agent("session:s1", "Raka", "working", "Rapikan folder Unduhan"),
                agent("kanban:writer", "writer", "working", "Draf laporan mingguan"),
                agent("session:s2", "Ayu", "waiting-approval", "Hapus cache lama"),
                agent("session:c", "Citra", "idle", null),
                agent("session:d", "Dimas", "idle", null),
            ),
            "lastName" to "Raka", "lastText" to "menjalankan move_files", "lastAt" to now - 180_000,
        ),
    )

    private fun agent(id: String, name: String, status: String, task: String?) =
        mapOf("id" to id, "name" to name, "status" to status, "task" to task)

    private fun render(ctx: Context, rv: RemoteViews, wDp: Int, hDp: Int, name: String, fill: ((View) -> Unit)? = null) {
        val d = ctx.resources.displayMetrics.density
        val w = (wDp * d).toInt()
        val h = (hDp * d).toInt()
        val parent = FrameLayout(ctx)
        val v = rv.apply(ctx, parent)
        fill?.invoke(v)
        parent.addView(v, FrameLayout.LayoutParams(w, h))
        parent.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        parent.layout(0, 0, w, h)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        parent.draw(Canvas(bmp))
        out!!.mkdirs()
        FileOutputStream(File(out, "$name.png")).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    /** Collection rows can't be bound without a launcher: put the real row views in by hand. */
    private fun fillAgents(ctx: Context, s: NvWidgetState): (View) -> Unit = { root ->
        val list = root.findViewById<View>(R.id.nva_list)
        val box = list.parent as ViewGroup
        val col = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        val pal = NvWidgets.Palette(ctx)
        val d = ctx.resources.displayMetrics.density
        s.agents.forEachIndexed { i, a ->
            val row = NvAgentsWidget.row(ctx, pal, a).apply(ctx, col)
            col.addView(row, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, (58 * d).toInt()).apply { if (i > 0) topMargin = (6 * d).toInt() })
        }
        list.visibility = View.GONE
        box.addView(col, 0, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    @Test
    fun shots() {
        assumeTrue(out != null)
        for (night in listOf(false, true)) {
            RuntimeEnvironment.setQualifiers(if (night) "+night" else "+notnight")
            val ctx = ApplicationProvider.getApplicationContext<Context>()
            val m = if (night) "dark" else "light"
            val s = sample()
            // a real Kantor 3D snapshot (taken with the page's widgetSnapshot) when given
            val snap = System.getenv("NVW_SNAPSHOT_DIR")?.let { File(it, if (night) "kantor_true.jpg" else "kantor_false.jpg") }
            val file = NvWidgets.snapshotFile(ctx)
            if (snap != null && snap.exists()) NvWidgets.saveSnapshot(ctx, snap.readBytes())
            render(ctx, NvHomeWidget.build(ctx, s, 340, 176, now), 340, 176, "quick_$m")
            render(ctx, NvHomeWidget.build(ctx, s, 300, 120, now), 300, 120, "quick_compact_$m")
            file.delete() // no snapshot yet: the bundled art (empty room)
            render(ctx, NvHomeWidget.build(ctx, NvWidgetState.EMPTY, 340, 176, now), 340, 176, "quick_unpaired_$m")
            if (snap != null && snap.exists()) NvWidgets.saveSnapshot(ctx, snap.readBytes())
            render(ctx, NvHomeWidget.build(ctx, sample(connected = false), 340, 176, now), 340, 176, "quick_offline_$m")
            render(ctx, NvStatusWidget.build(ctx, s, 165, now), 165, 165, "status_$m")
            render(ctx, NvStatusWidget.build(ctx, sample(connected = false), 165, now), 165, 165, "status_offline_$m")
            render(ctx, NvAgentsWidget.views(ctx, 1, s), 340, 360, "agents_$m", fillAgents(ctx, s))
            render(ctx, NvAgentsWidget.views(ctx, 1, NvWidgetState.EMPTY), 340, 250, "agents_unpaired_$m")
            render(ctx, NvAgentsWidget.views(ctx, 1, sample(connected = false).copy(agents = emptyList())), 340, 250, "agents_offline_$m")
        }
    }
}
