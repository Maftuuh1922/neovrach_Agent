package com.neovarch.agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

/**
 * "Hey Neo" wake word (opt-in, Profil → Hey Neo). A microphone foreground
 * service runs Vosk offline with a two-entry grammar ("hey neo" / [unk]), so
 * nothing leaves the phone and nothing but the phrase is recognised. The small
 * English model (~40 MB) is downloaded the first time it is switched on. On a
 * match the app opens on the Chat dictation route (`nv_route=voice`); when
 * Android blocks the activity start from the background a heads-up
 * notification does the same on tap.
 *
 * Boot: a microphone foreground service may not be started from
 * BOOT_COMPLETED on Android 14+, and since Android 11 one started from the
 * background gets no microphone access, so [NvBootReceiver] posts a
 * notification ("ketuk untuk menyalakan lagi") instead; tapping it opens the
 * app (`nv_route=wake`), which restarts the service from the foreground.
 */
class NvWakeService : Service(), RecognitionListener {
    private var speech: SpeechService? = null
    private var model: Model? = null
    private val main = Handler(Looper.getMainLooper())
    private var lastHit = 0L
    @Volatile private var stopped = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopped = false
        startInForeground("Hey Neo menyiapkan…")
        if (speech == null) Thread { prepareAndListen() }.start()
        return START_STICKY
    }

    private fun startInForeground(text: String) {
        val n = ongoing(text)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun prepareAndListen() {
        try {
            val dir = modelDir(this)
            if (!File(dir, "am").exists() && !File(dir, "conf").exists()) {
                setState(this, "downloading")
                update("Mengunduh model suara (±40 MB)…")
                download(dir)
            }
            if (stopped) return
            val m = Model(dir.absolutePath)
            model = m
            val rec = Recognizer(m, 16000f, GRAMMAR)
            val s = SpeechService(rec, 16000f)
            speech = s
            s.startListening(this)
            setState(this, "listening")
            update("Mendengarkan \"Hey Neo\"")
        } catch (e: Exception) {
            setState(this, "error:" + (e.message ?: e.toString()))
            update("Hey Neo gagal: ${e.message ?: e}")
        }
    }

    private fun download(dir: File) {
        val tmp = File(cacheDir, "vosk-model.zip")
        val c = URL(MODEL_URL).openConnection() as HttpURLConnection
        c.connectTimeout = 20000
        c.readTimeout = 30000
        c.inputStream.use { inp -> FileOutputStream(tmp).use { out -> inp.copyTo(out) } }
        val staging = File(filesDir, "vosk-staging").apply { deleteRecursively(); mkdirs() }
        ZipInputStream(tmp.inputStream()).use { z ->
            var e = z.nextEntry
            while (e != null) {
                // drop the zip's top folder (vosk-model-small-en-us-0.15/...)
                val rel = e.name.substringAfter('/', "")
                if (rel.isNotEmpty() && !rel.contains("..")) {
                    val f = File(staging, rel)
                    if (e.isDirectory) f.mkdirs() else {
                        f.parentFile?.mkdirs()
                        FileOutputStream(f).use { z.copyTo(it) }
                    }
                }
                e = z.nextEntry
            }
        }
        tmp.delete()
        dir.deleteRecursively()
        if (!staging.renameTo(dir)) throw IllegalStateException("model tidak bisa dipasang")
    }

    private fun hit(text: String) {
        if (!matches(text)) return
        val now = System.currentTimeMillis()
        if (now - lastHit < 4000) return
        lastHit = now
        // Let the app's dictation have the microphone for a while.
        speech?.setPause(true)
        main.postDelayed({ speech?.setPause(false) }, 20000)
        val open = Intent(this, MainActivity::class.java)
            .putExtra(EXTRA_ROUTE, "voice")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        try {
            startActivity(open)
        } catch (e: Exception) {
            // background start blocked: the notification below opens it
        }
        notifyUser(this, "Hey Neo", "Ketuk untuk bicara ke agen", "voice", HIT_ID)
    }

    override fun onPartialResult(hypothesis: String?) {
        hypothesis?.let { hit(JSONObject(it).optString("partial")) }
    }

    override fun onResult(hypothesis: String?) {
        hypothesis?.let { hit(JSONObject(it).optString("text")) }
    }

    override fun onFinalResult(hypothesis: String?) {}
    override fun onError(exception: Exception?) {
        setState(this, "error:" + (exception?.message ?: "mikrofon"))
        update("Hey Neo berhenti: ${exception?.message ?: "mikrofon"}")
    }
    override fun onTimeout() {}

    override fun onDestroy() {
        stopped = true
        main.removeCallbacksAndMessages(null)
        speech?.stop()
        speech?.shutdown()
        speech = null
        model?.close()
        model = null
        if (enabled(this)) setState(this, "stopped") else setState(this, "off")
        super.onDestroy()
    }

    private fun update(text: String) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIF_ID, ongoing(text))
    }

    private fun ongoing(text: String): Notification {
        val b = builder(this, CHANNEL_QUIET, "Hey Neo", NotificationManager.IMPORTANCE_LOW)
        return b.setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setContentTitle("Hey Neo")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(openApp(this, "profile", 50))
            .build()
    }

    companion object {
        const val EXTRA_ROUTE = "nv_route"
        private const val NOTIF_ID = 7301
        private const val HIT_ID = 7302
        const val BOOT_ID = 7303
        private const val CHANNEL_QUIET = "nv_wake"
        private const val CHANNEL_ALERT = "nv_wake_alert"
        private const val PREFS = "nv_wake"
        const val MODEL_URL = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"
        /** Only the phrase (and "unknown"), so ordinary speech never matches. */
        const val GRAMMAR = "[\"hey neo\", \"[unk]\"]"

        fun matches(text: String?): Boolean = text != null && Regex("\\bhey neo\\b").containsMatchIn(text.lowercase())

        fun modelDir(c: Context) = File(c.filesDir, "vosk-model-en")
        fun enabled(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("enabled", false)
        fun setState(c: Context, s: String) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("state", s).apply()

        fun status(c: Context): Map<String, Any?> {
            val p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val d = modelDir(c)
            return mapOf(
                "enabled" to p.getBoolean("enabled", false),
                "state" to p.getString("state", "off"),
                "modelReady" to (File(d, "am").exists() || File(d, "conf").exists()),
            )
        }

        /** Switch on/off (from the app, in the foreground). */
        fun setEnabled(c: Context, on: Boolean) {
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("enabled", on).apply()
            val i = Intent(c, NvWakeService::class.java)
            if (on) {
                if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i) else c.startService(i)
            } else {
                c.stopService(i)
                setState(c, "off")
            }
        }

        fun openApp(c: Context, route: String, code: Int): PendingIntent = PendingIntent.getActivity(
            c, code,
            Intent(c, MainActivity::class.java).putExtra(EXTRA_ROUTE, route)
                .setAction("com.neovarch.agent.wake.$route")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        private fun builder(c: Context, channel: String, name: String, importance: Int): Notification.Builder =
            if (Build.VERSION.SDK_INT >= 26) {
                (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .createNotificationChannel(NotificationChannel(channel, name, importance))
                Notification.Builder(c, channel)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(c)
            }

        fun notifyUser(c: Context, title: String, body: String, route: String, id: Int) {
            val n = builder(c, CHANNEL_ALERT, "Hey Neo (panggilan)", NotificationManager.IMPORTANCE_HIGH)
                .setSmallIcon(R.mipmap.ic_launcher_foreground)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .setContentIntent(openApp(c, route, id))
                .build()
            try {
                (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(id, n)
            } catch (e: SecurityException) {
                // notifications not allowed
            }
        }
    }
}

/** After a reboot: restart Hey Neo where Android allows it, else ask with a notification. */
class NvBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED || !NvWakeService.enabled(context)) return
        if (Build.VERSION.SDK_INT >= 30) {
            // Android 14+: no microphone foreground service from BOOT_COMPLETED;
            // Android 11-13: it would start without microphone access.
            NvWakeService.setState(context, "stopped")
            NvWakeService.notifyUser(context, "Hey Neo berhenti setelah HP dinyalakan ulang",
                "Ketuk untuk menyalakan lagi", "wake", NvWakeService.BOOT_ID)
        } else {
            try {
                NvWakeService.setEnabled(context, true)
            } catch (e: Exception) {
                NvWakeService.notifyUser(context, "Hey Neo berhenti", "Ketuk untuk menyalakan lagi", "wake", NvWakeService.BOOT_ID)
            }
        }
    }
}
