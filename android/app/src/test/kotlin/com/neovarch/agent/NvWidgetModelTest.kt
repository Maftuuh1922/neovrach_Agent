package com.neovarch.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure widget logic (no Android): payload parsing, texts, size variants. */
class NvWidgetModelTest {
    private val now = 1_791_500_000_000L

    private fun payload(paired: Boolean = true, connected: Boolean = true) = mapOf<String, Any?>(
        "v" to 2, "pc" to "PC Kantor", "paired" to paired, "connected" to connected,
        "status" to if (connected) "terhubung" else "terputus",
        "working" to 2, "waiting" to 1, "waitingAgents" to 1, "agentCount" to 3, "tasks" to 4,
        "task" to "Raka: Rapikan folder Unduhan", "accent" to 0xFFEE1C1C,
        "agents" to listOf(
            mapOf("id" to "session:s1", "name" to "Raka", "initial" to "R", "coat" to 0xFF3A4A6E, "status" to "working", "task" to "Rapikan folder Unduhan"),
            mapOf("id" to "kanban:writer", "name" to "writer", "status" to "idle", "task" to null),
        ),
        "lastName" to "Raka", "lastText" to "menjalankan move_files", "lastAt" to now - 180_000,
    )

    @Test fun parsesV2() {
        val s = NvWidgetState.parse(payload())
        assertEquals("PC Kantor", s.pc)
        assertTrue(s.paired && s.connected)
        assertEquals(2, s.working)
        assertEquals(0xFFEE1C1C.toInt(), s.accent)
        assertEquals(2, s.agents.size)
        assertEquals(0xFF3A4A6E.toInt(), s.agents[0].coat)
        // missing coat / initial: computed with the shared hash and the name
        assertEquals(0xFF8A6A3A.toInt(), s.agents[1].coat)
        assertEquals("W", s.agents[1].initial)
        assertNull(s.agents[1].task)
    }

    @Test fun parsesV1From144() {
        val s = NvWidgetState.parse(mapOf("pc" to "PC", "connected" to false, "status" to "terputus", "working" to 0, "waiting" to 0, "tasks" to 1, "task" to null))
        assertTrue(s.paired) // had a PC
        assertFalse(s.connected)
        assertTrue(s.agents.isEmpty())
        val unpaired = NvWidgetState.parse(mapOf("pc" to "Neovarch", "connected" to false, "status" to "belum dipasangkan"))
        assertFalse(unpaired.paired)
        assertFalse(NvWidgetState.parse(null).paired)
    }

    @Test fun coatHashMatchesSpec() {
        assertEquals(0xFF3A4A6E.toInt(), NvWidgetText.coatFor("session:s1"))
        assertEquals(0xFF7A2E2E.toInt(), NvWidgetText.coatFor("session:s2"))
        assertEquals(0xFF8A6A3A.toInt(), NvWidgetText.coatFor("kanban:writer"))
        assertEquals("?", NvWidgetText.initialOf("  "))
        assertEquals("É", NvWidgetText.initialOf("élan"))
    }

    @Test fun ago() {
        assertEquals("", NvWidgetText.ago(null, now))
        assertEquals("baru saja", NvWidgetText.ago(now - 10_000, now))
        assertEquals("1 mnt lalu", NvWidgetText.ago(now - 50_000, now))
        assertEquals("3 mnt lalu", NvWidgetText.ago(now - 180_000, now))
        assertEquals("2 jam lalu", NvWidgetText.ago(now - 2 * 3_600_000L, now))
        assertEquals("4 hari lalu", NvWidgetText.ago(now - 4 * 86_400_000L, now))
    }

    @Test fun textsByState() {
        val on = NvWidgetState.parse(payload())
        assertEquals("PC online", NvWidgetText.pcChip(on))
        assertEquals("Kantor · 2 bekerja", NvWidgetText.kantorTitle(on))
        assertEquals("Raka: Rapikan folder Unduhan", NvWidgetText.kantorSub(on))
        assertEquals("online · 4 tugas terbuka", NvWidgetText.statusLine(on))
        assertEquals("Raka · 3 mnt lalu", NvWidgetText.lastLine(on, now))
        assertEquals("PC Kantor · 2 bekerja", NvWidgetText.agentsSub(on))

        val off = NvWidgetState.parse(payload(connected = false))
        assertEquals("PC offline", NvWidgetText.pcChip(off))
        assertEquals("Kantor · PC offline", NvWidgetText.kantorTitle(off))
        assertEquals("offline", NvWidgetText.statusLine(off))
        assertEquals("PC Kantor · offline", NvWidgetText.agentsSub(off))

        val none = NvWidgetState.EMPTY
        assertEquals("Belum terhubung", NvWidgetText.pcChip(none))
        assertEquals("Hubungkan PC untuk melihat kantormu", NvWidgetText.kantorSub(none))
        assertEquals("Ketuk untuk memasangkan", NvWidgetText.lastLine(none, now))
    }

    @Test fun agentLabels() {
        val a = NvWidgetAgent("id", "Ayu", "A", 0, "waiting-approval", null)
        assertEquals("menunggu", NvWidgetText.statusLabel(a.status))
        assertEquals("menunggu persetujuan", NvWidgetText.agentTask(a))
        assertEquals("santai", NvWidgetText.statusLabel("idle"))
        assertEquals("galat", NvWidgetText.statusLabel("error"))
    }

    @Test fun variants() {
        assertEquals(NvQuickVariant(tall = true, panel = true), NvQuickVariant.of(320, 180))
        assertEquals(NvQuickVariant(tall = false, panel = true), NvQuickVariant.of(250, 110))
        assertEquals(NvQuickVariant(tall = true, panel = false), NvQuickVariant.of(180, 160))
        assertEquals(NvQuickVariant(tall = true, panel = true), NvQuickVariant.of(0, 0))
        val (pw, ph) = NvQuickVariant.panelSize(320, 170)
        assertEquals(137.04f, pw, 0.05f)
        assertEquals(146f, ph, 0.01f)
        assertFalse(NvStatusVariant.of(110).lastLine)
        assertTrue(NvStatusVariant.of(150).lastLine)
        assertFalse(NvStatusVariant.of(105).statusLine)
    }
}
