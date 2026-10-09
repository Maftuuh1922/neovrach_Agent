package com.neovarch.agent

/**
 * Home-screen widgets: the state every provider draws from, parsed from the
 * summary Flutter pushes (`updateWidget`, lib/remote/home_widget.dart), plus
 * the pure text/size decisions. No Android imports, so it is unit-tested on
 * the JVM (src/test/.../NvWidgetModelTest.kt).
 */
data class NvWidgetAgent(
    val id: String,
    val name: String,
    val initial: String,
    val coat: Int,
    val status: String,
    val task: String?,
)

data class NvWidgetState(
    val pc: String,
    val paired: Boolean,
    val connected: Boolean,
    val status: String,
    val working: Int,
    val waiting: Int,
    val waitingAgents: Int,
    val agentCount: Int,
    val tasks: Int,
    val task: String?,
    val accent: Int?,
    val agents: List<NvWidgetAgent>,
    val lastName: String?,
    val lastText: String?,
    val lastAt: Long?,
) {
    companion object {
        /** Nothing pushed yet (fresh install / app never opened since). */
        val EMPTY = NvWidgetState(
            pc = "Neovarch", paired = false, connected = false, status = "belum dipasangkan",
            working = 0, waiting = 0, waitingAgents = 0, agentCount = 0, tasks = 0, task = null,
            accent = null, agents = emptyList(), lastName = null, lastText = null, lastAt = null,
        )

        /**
         * From the channel map (or its JSON copy). Tolerates the v1 payload of
         * 1.4.4 (no `paired` / `agents`): paired is then inferred from status.
         */
        fun parse(m: Map<String, Any?>?): NvWidgetState {
            if (m == null) return EMPTY
            val status = str(m["status"]) ?: ""
            val paired = (m["paired"] as? Boolean) ?: (status != "belum dipasangkan" && m.containsKey("pc"))
            val agents = (m["agents"] as? List<*>)?.mapNotNull { a ->
                @Suppress("UNCHECKED_CAST")
                val am = a as? Map<String, Any?> ?: return@mapNotNull null
                val id = str(am["id"]) ?: return@mapNotNull null
                val name = str(am["name"]) ?: id
                NvWidgetAgent(
                    id = id,
                    name = name,
                    initial = str(am["initial"]) ?: initialOf(name),
                    coat = num(am["coat"])?.toInt() ?: coatFor(id),
                    status = str(am["status"]) ?: "idle",
                    task = str(am["task"]),
                )
            } ?: emptyList()
            return NvWidgetState(
                pc = str(m["pc"]) ?: "Neovarch",
                paired = paired,
                connected = m["connected"] == true,
                status = status,
                working = num(m["working"])?.toInt() ?: 0,
                waiting = num(m["waiting"])?.toInt() ?: 0,
                waitingAgents = num(m["waitingAgents"])?.toInt() ?: agents.count { it.status == "waiting-approval" },
                agentCount = num(m["agentCount"])?.toInt() ?: agents.size,
                tasks = num(m["tasks"])?.toInt() ?: 0,
                task = str(m["task"]),
                accent = num(m["accent"])?.toLong()?.toInt(),
                agents = agents,
                lastName = str(m["lastName"]),
                lastText = str(m["lastText"]),
                lastAt = num(m["lastAt"])?.toLong(),
            )
        }

        private fun str(v: Any?): String? = (v as? String)?.takeIf { it.isNotBlank() }
        private fun num(v: Any?): Number? = v as? Number
    }
}

object NvWidgetText {
    /** Coats + hash shared with the app and desktop (agent-identity-spec.md). */
    val COATS = intArrayOf(
        0xFF3A4A6E.toInt(), 0xFF7A2E2E.toInt(), 0xFF3E5A4A.toInt(),
        0xFF6A5A8C.toInt(), 0xFF8A6A3A.toInt(), 0xFF45434A.toInt(),
    )

    /** "baru saja" / "3 mnt lalu" / "2 jam lalu" / "4 hari lalu" (as agoId in Dart). */
    fun ago(atMs: Long?, nowMs: Long): String {
        if (atMs == null) return ""
        val s = (nowMs - atMs) / 1000
        if (s < 45) return "baru saja"
        val m = s / 60
        if (m < 60) return "${maxOf(1, m)} mnt lalu"
        val h = m / 60
        if (h < 24) return "$h jam lalu"
        return "${h / 24} hari lalu"
    }

    fun statusLabel(status: String): String = when (status) {
        "working" -> "bekerja"
        "waiting-approval", "waiting" -> "menunggu"
        "error" -> "galat"
        else -> "santai"
    }

    /** Header chip of "Aksi cepat". */
    fun pcChip(s: NvWidgetState): String = when {
        !s.paired -> "Belum terhubung"
        s.connected -> "PC online"
        s.status == "menyambung…" -> "Menyambung…"
        else -> "PC offline"
    }

    /** Caption over the Kantor image: "Kantor · 2 bekerja". */
    fun kantorTitle(s: NvWidgetState): String = when {
        !s.paired -> "Kantor"
        !s.connected -> "Kantor · PC offline"
        s.working > 0 -> "Kantor · ${s.working} bekerja"
        s.waitingAgents > 0 -> "Kantor · ${s.waitingAgents} menunggu"
        s.agentCount > 0 -> "Kantor · semua santai"
        else -> "Kantor · sepi"
    }

    fun kantorSub(s: NvWidgetState): String = when {
        !s.paired -> "Hubungkan PC untuk melihat kantormu"
        !s.connected -> "Terakhir: ${s.pc}"
        s.task != null -> s.task
        s.waiting > 0 -> "${s.waiting} persetujuan menunggu"
        s.tasks > 0 -> "${s.tasks} tugas terbuka"
        else -> "Tidak ada tugas berjalan"
    }

    /** Status widget second line. */
    fun statusLine(s: NvWidgetState): String = when {
        !s.paired -> "Hubungkan PC di aplikasi"
        !s.connected -> if (s.status == "menyambung…") "menyambung…" else "offline"
        s.tasks > 0 -> "online · ${s.tasks} tugas terbuka"
        else -> "online"
    }

    /** "Raka · 3 mnt lalu" (status widget bottom line). */
    fun lastLine(s: NvWidgetState, nowMs: Long): String = when {
        !s.paired -> "Ketuk untuk memasangkan"
        s.lastName != null && s.lastAt != null -> "${s.lastName} · ${ago(s.lastAt, nowMs)}"
        s.lastName != null -> s.lastName
        else -> "Belum ada aktivitas"
    }

    /** "Agen" widget subtitle. */
    fun agentsSub(s: NvWidgetState): String = when {
        !s.paired -> "Belum ada PC terhubung"
        !s.connected -> "${s.pc} · offline"
        s.working > 0 -> "${s.pc} · ${s.working} bekerja"
        else -> "${s.pc} · ${s.agentCount} agen"
    }

    fun agentTask(a: NvWidgetAgent): String = a.task?.takeIf { it.isNotBlank() } ?: when (a.status) {
        "waiting-approval", "waiting" -> "menunggu persetujuan"
        "working" -> "bekerja"
        else -> "santai"
    }

    fun coatFor(id: String): Int {
        var h = 0L
        for (c in id) h = (h * 31 + c.code) and 0xFFFFFFFFL
        return COATS[(h % COATS.size).toInt()]
    }

    fun initialOf(name: String): String {
        val t = name.trim()
        if (t.isEmpty()) return "?"
        val cp = t.codePointAt(0)
        return String(Character.toChars(cp)).uppercase()
    }
}

private fun coatFor(id: String) = NvWidgetText.coatFor(id)
private fun initialOf(name: String) = NvWidgetText.initialOf(name)

/** Which "Aksi cepat" layout fits a size (dp): tiles tall or compact, image panel or not. */
data class NvQuickVariant(val tall: Boolean, val panel: Boolean) {
    companion object {
        const val TALL_MIN_H = 160
        const val PANEL_MIN_W = 230

        fun of(widthDp: Int, heightDp: Int) = NvQuickVariant(
            tall = heightDp <= 0 || heightDp >= TALL_MIN_H,
            panel = widthDp <= 0 || widthDp >= PANEL_MIN_W,
        )

        /**
         * Image panel size (dp) inside a widget of [widthDp] x [heightDp]:
         * padding 12, gap 10, panel weight 0.92 against the tiles' 1.
         */
        fun panelSize(widthDp: Int, heightDp: Int): Pair<Float, Float> {
            val w = if (widthDp > 0) widthDp else 320
            val h = if (heightDp > 0) heightDp else 170
            val inner = (w - 24 - 10).toFloat()
            return Pair(inner * 0.92f / 1.92f, (h - 24).toFloat())
        }
    }
}

/** What the status widget hides when short. */
data class NvStatusVariant(val statusLine: Boolean, val lastLine: Boolean) {
    companion object {
        fun of(heightDp: Int) = NvStatusVariant(
            statusLine = heightDp <= 0 || heightDp >= 118,
            lastLine = heightDp <= 0 || heightDp >= 138,
        )
    }
}
