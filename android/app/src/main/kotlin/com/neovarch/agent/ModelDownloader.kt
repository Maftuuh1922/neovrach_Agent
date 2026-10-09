package com.neovarch.agent

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.zip.ZipFile

/**
 * Robust model download for the wake word: tries each URL in order (GitHub
 * mirror first), up to [ATTEMPTS] tries with backoff, follows redirects
 * (including http->https hops HttpURLConnection refuses), resumes with a
 * Range request, treats 20 s without a byte as a stall, reports progress and
 * verifies the size and that the zip opens.
 */
class ModelDownloader(private val urls: List<String>) {
    sealed class Event {
        data class Progress(val done: Long, val total: Long) : Event()
        data class Retry(val attempt: Int, val reason: String) : Event()
    }

    fun fetch(dest: File, cancelled: () -> Boolean, on: (Event) -> Unit) {
        var last: Exception? = null
        for (attempt in 1..ATTEMPTS) {
            for (u in urls) {
                if (cancelled()) return
                try {
                    once(u, dest, cancelled, on)
                    if (cancelled()) return
                    verifyZip(dest)
                    return
                } catch (e: Exception) {
                    last = e
                    if (e is BadZip) dest.delete()
                    on(Event.Retry(attempt, e.message ?: e.javaClass.simpleName))
                }
            }
            if (attempt < ATTEMPTS) Thread.sleep(backoffMs(attempt))
        }
        throw IOException("Unduhan model gagal setelah $ATTEMPTS percobaan: ${last?.message ?: last}")
    }

    private fun once(url: String, dest: File, cancelled: () -> Boolean, on: (Event) -> Unit) {
        val have = if (dest.exists()) dest.length() else 0L
        val c = open(url, have)
        try {
            val code = c.responseCode
            val resumed = code == 206 && have > 0
            if (code != 200 && code != 206) throw IOException("HTTP $code dari ${URL(url).host}")
            val len = c.getHeaderField("Content-Length")?.toLongOrNull() ?: -1L
            val total = if (len < 0) -1L else if (resumed) have + len else len
            var done = if (resumed) have else 0L
            on(Event.Progress(done, total))
            c.inputStream.use { inp -> FileOutputStream(dest, resumed).use { out -> copy(inp, out, done, total, cancelled, on) } }
            done = dest.length()
            if (total > 0 && done != total) throw IOException("ukuran tidak cocok ($done / $total byte)")
            if (total <= 0 && done < MIN_BYTES) throw IOException("file terlalu kecil ($done byte)")
        } finally {
            c.disconnect()
        }
    }

    private fun copy(inp: InputStream, out: FileOutputStream, start: Long, total: Long, cancelled: () -> Boolean, on: (Event) -> Unit) {
        val buf = ByteArray(64 * 1024)
        var done = start
        var lastTick = 0L
        while (true) {
            if (cancelled()) return
            val n = try {
                inp.read(buf)
            } catch (e: SocketTimeoutException) {
                throw IOException("Unduhan macet (tidak ada data ${STALL_MS / 1000} detik)")
            }
            if (n < 0) break
            out.write(buf, 0, n)
            done += n
            val now = System.currentTimeMillis()
            if (now - lastTick >= 500) {
                lastTick = now
                on(Event.Progress(done, total))
            }
        }
        on(Event.Progress(done, total))
    }

    /** Opens [url], following up to 5 redirects by hand (also across protocols). */
    private fun open(url: String, from: Long): HttpURLConnection {
        var u = url
        repeat(6) {
            val c = URL(u).openConnection() as HttpURLConnection
            c.instanceFollowRedirects = false
            c.connectTimeout = 30000
            c.readTimeout = STALL_MS
            c.setRequestProperty("User-Agent", "Neovarch-Agent")
            if (from > 0) c.setRequestProperty("Range", "bytes=$from-")
            val code = c.responseCode
            if (code in 300..399) {
                val loc = c.getHeaderField("Location") ?: throw IOException("redirect tanpa Location")
                c.disconnect()
                u = resolve(u, loc)
                return@repeat
            }
            if (code == 416 && from > 0) {
                // our partial file is bad / complete: start over
                c.disconnect()
                return open(url, -1).also { }
            }
            return c
        }
        throw IOException("terlalu banyak redirect")
    }

    class BadZip(msg: String) : IOException(msg)

    private fun verifyZip(f: File) {
        if (f.length() < MIN_BYTES) throw BadZip("file model rusak (${f.length()} byte)")
        try {
            ZipFile(f).use { z -> if (z.size() == 0) throw BadZip("zip kosong") }
        } catch (e: BadZip) {
            throw e
        } catch (e: Exception) {
            throw BadZip("zip rusak: ${e.message}")
        }
    }

    companion object {
        const val ATTEMPTS = 3
        const val STALL_MS = 20000
        const val MIN_BYTES = 30L * 1024 * 1024
        fun backoffMs(attempt: Int): Long = 2000L * (1L shl (attempt - 1)).coerceAtMost(8)
        fun resolve(base: String, loc: String): String = URL(URL(base), loc).toString()

        /** "Mengunduh model suara 12 / 40 MB (30%)". */
        fun progressText(done: Long, total: Long): String {
            val mb = done / 1048576
            return if (total > 0) "Mengunduh model suara $mb / ${total / 1048576} MB (${(done * 100 / total).toInt()}%)"
            else "Mengunduh model suara $mb MB"
        }
    }
}
