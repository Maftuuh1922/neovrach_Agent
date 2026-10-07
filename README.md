# Neovarch Agent (Flutter · Android & iOS)

Aplikasi agen AI **mandiri** dari NeovarchLabs untuk Android dan iPhone, dibangun di atas runtime
Hermes Agent (Nous Research, MIT) — seperti *Hermes Desktop*, tapi di ponsel.
Agent berjalan langsung di HP: chat streaming dengan alat dan memori, sesi, skill, berkas workspace, proyek,
suara, plus kantor virtual isometrik, papan Kanban, rapat multi-agent, dan cron. Tanpa PC, tanpa server.

Opsional, aplikasi juga bisa tersambung ke:

* **Gateway jarak jauh** — backend `hermes serve` (tui_gateway, JSON-RPC lewat WebSocket) di VPS/PC.
* **Server kantor** — server Next.js *Hermes Virtual Office* (`/api/hermes/*`) yang menjalankan CLI `hermes`.
* **Demo offline** — papan contoh tanpa jaringan (port dari `src/lib/offline-mock.ts`).

UI berbahasa Indonesia, Material 3.

### Identitas visual

* **Warna**: merah datar `#C8101A` sebagai dasar, teks tulang `#F2EDE4`; kartu, sheet dan dialog berupa
  "kertas" tulang `#F2EDE4` dengan teks hampir-hitam `#140607` dan aksen merah. Garis bingkai tipis 1px,
  tampilan cetak datar — tanpa gradien, glow, atau scrim. Mode gelap = varian hampir-hitam `#0A0A0A`
  dengan aksen crimson `#E0262F` (teks merah kecil `#F2555C`). Pilihan Sistem/Terang/Gelap tetap ada.
* **Logo**: wordmark **NEOVARCHAGENT** (serif kondensasi tinggi) dengan cincin halo tipis di atas huruf
  pertama; monogram N + halo untuk ikon. Ilustrasi kartu gadis manga hitam-putih milik NeovarchLabs.
* **Huruf**: Big Shoulders Display (judul), Barlow (teks), IBM Plex Mono (label) — semua SIL OFL, dibundel.
* **Animasi**: intro 4 slide pertama kali (seni duotone merah/tulang), pembuka logo setiap start,
  indikator berpikir & aktivitas alat streaming ala Hermes Desktop, navbar mengambang.

---

## Fitur

| Area | Isi |
|---|---|
| **Chat** (layar utama) | Balasan *streaming*, aktivitas alat langsung + ringkasan terstruktur per alat (bisa dibuka: argumen & keluaran), blok penalaran, Markdown + *syntax highlighting*, lampiran gambar (galeri/kamera, untuk model vision), antrean prompt saat agent masih menjawab, tombol Stop, kartu galat yang menyebut lapisan yang gagal (Coba lagi / Ganti penyedia / Salin detail), salin & bacakan per pesan, status bar (mode · tok/s · konteks). |
| **Sesi** | Daftar, cari (judul/id), ganti nama, hapus, kelompokkan per proyek, saring per profil, buka percakapan terakhir saat mulai. Judul otomatis dari pesan pertama. |
| **Pratinjau** | Panel pratinjau (bottom sheet): halaman web via `webview_flutter`, berkas markdown/kode/teks, keluaran alat. Tidak pernah terbuka sendiri — alat hanya *menawarkan* tombol pratinjau. |
| **Berkas** | Penjelajah workspace aplikasi: telusuri folder, pratinjau, buat/sunting/hapus berkas & folder. Agent menulis ke sini dengan `file_write`. |
| **Suara** | Dikte (`speech_to_text`) di composer, bacakan balasan (`flutter_tts`) otomatis atau per pesan, pilihan bahasa & kecepatan. |
| **Intro & onboarding** | Intro animasi 4 slide (pertama kali) → sambutan → pilih koneksi → pilih penyedia/model/kunci (atau "pilih penyedia nanti") → izin perangkat → pesan pertama. |
| **Thinking** | Aktif/mati, tingkat usaha (rendah–maksimum), budget token, tampilkan/ciutkan blok berpikir — sebagai bawaan (Lainnya → Chat, thinking & suara) atau per sesi. |
| **Izin perangkat** | Lainnya → Izin perangkat: status & tombol izinkan untuk notifikasi, kamera, mikrofon, foto/video/audio, lokasi, kontak, kalender, akses semua file. |
| **Penyedia & model** | Preset OpenRouter, Nous Portal (`https://inference-api.nousresearch.com/v1`), OpenAI, Ollama, LM Studio, kustom. Kunci API per penyedia di `flutter_secure_storage`. Ambil daftar model (`/models`), cari, bintangi favorit, **Uji** memanggil `/chat/completions` sungguhan. |
| **Alat** | Aktif/nonaktifkan tiap alat: memori, berkas, papan, `web_fetch`, `skill_load`; kantor (`office_view` — agen melihat gambar kantor, `office_status`, tugas, rapat, cron, agent); perangkat (info, clipboard, intent, notifikasi, lokasi, kontak, kalender, aplikasi, penyimpanan, dokumen, kamera). |
| **Skill** | Lihat/buat/sunting/hapus skill (dokumen instruksi markdown) + pratinjau. Katalog skill aktif masuk ke system prompt; agent memuat isinya dengan `skill_load`. |
| **Memori** | Penampil/penyunting catatan memori — bersama atau per agent; agent menulis via `memory_write`. |
| **Profil (agent)** | Nama, peran, deskripsi, persona/system prompt (SOUL), model khusus; jadikan default; keluarkan dari kantor; hapus. |
| **Proyek** | Mengelompokkan sesi dan memiliki folder workspace; agent di sesi proyek menyimpan berkas ke folder itu. |
| **Kantor** | Kantor isometrik 2.5D (CustomPainter, ringan): 8 meja, meja rapat, lounge, dinding Kanban. Avatar beranimasi sesuai status (kerja di meja, rapat di meja bundar, santai di lounge, terhambat dengan tanda `!`), gelembung bicara saat rapat. Ketuk agent/meja → "intip layar" (log langsung tiap 5 dtk, riwayat run, Steer/Hentikan, buka chat). Ketuk dinding Kanban → Papan. Cubit untuk zoom, geser untuk pan. |
| **Papan** | Kolom TODO / JALAN / REVIEW / SELESAI dengan jumlah, kartu dengan prioritas, avatar penanggung, lencana asal (rapat/cron/agent); geser antar kolom di HP, 4 kolom di tablet; tarik untuk segarkan; FAB "+ Tugas"; detail tugas (uraian, hasil worker, riwayat run, log). Mode Mandiri: Setujui / Minta revisi / Jalankan sekarang / Pindahkan / Hapus. |
| **Rapat** | 2–4 agent bergiliran lewat LLM (mode auto/directed/manual), transkrip langsung, notulen (Keputusan / TINDAK LANJUT / Risiko), salin notulen, **tindak lanjut → tugas** dengan pemilih penanggung. |
| **Cron** | Prompt terjadwal (`30m`, `every 2h`, ekspresi cron 5 kolom). Dibuat dalam keadaan *pause* secara default; setiap aksi minta konfirmasi; riwayat eksekusi; hasil disimpan ke `cron/` di Berkas; job yang gagal bisa dijadikan tugas. |
| **Tampilan** | **Neovarch Red** (bawaan), plus preset ala Desktop: GitHub, Classic, Catppuccin, Everforest, Solarized, Midnight, Ember, Mono, Cyberpunk, Slate, Kantor Teal. Mode Sistem/Terang/Gelap, pilihan huruf, ukuran teks chat. |
| **Tentang** | Versi, cek pembaruan dari GitHub Releases (isi `pemilik/repo`), kosongkan papan, ulangi onboarding. |

Notifikasi: saat tugas pindah ke REVIEW atau TERHAMBAT muncul snackbar (padanan Notification di web).
Pintasan keyboard (tablet/keyboard fisik): `Alt+N` tugas baru, `Alt+M` rapat, `Alt+C` chat, `Alt+1/2` kantor/papan.

---

## Menjalankan

Prasyarat: Flutter **3.38+** (diuji dengan 3.47.6 stable), Android SDK (lewat Android Studio), JDK 17+.

```bash
cd hermes_office_flutter
flutter pub get
flutter run                # HP/emulator Android tersambung
```

Folder `android/` dan `web/` sudah disertakan. Kalau ingin membuat ulang platform lain:
`flutter create . --platforms=android,ios,web --org com.neovarch --project-name neovarch_agent`
(lalu kembalikan `android/app/src/main/AndroidManifest.xml` dan `android/app/build.gradle.kts` dari paket ini).

### Membuat APK

```bash
flutter build apk --release          # build/app/outputs/flutter-apk/app-release.apk
# atau per-ABI, lebih kecil:
flutter build apk --release --split-per-abi
```

`applicationId` = **com.neovarch.agent**, nama aplikasi **Neovarch Agent**. Build rilis saat ini ditandatangani
dengan kunci debug (lihat `buildTypes.release` di `android/app/build.gradle.kts`); untuk Play Store buat
keystore sendiri dan isi `signingConfig`.

Izin Android yang dipakai (sudah ada di `AndroidManifest.xml`):

* `INTERNET`, `ACCESS_NETWORK_STATE` — penyedia LLM, gateway, server kantor, alat `web_fetch`.
* `RECORD_AUDIO` — dikte suara; `CAMERA` — foto untuk chat / alat `camera_capture`.
* `READ_MEDIA_IMAGES/VIDEO/AUDIO` (+ `READ_MEDIA_VISUAL_USER_SELECTED`, `READ_EXTERNAL_STORAGE` ≤ Android 12),
  `MANAGE_EXTERNAL_STORAGE` — media & berkas di penyimpanan bersama.
* `POST_NOTIFICATIONS`, `ACCESS_FINE/COARSE_LOCATION`, `READ_CONTACTS`, `READ_CALENDAR`, `QUERY_ALL_PACKAGES`, `VIBRATE` — alat perangkat.
  Semua izin runtime diminta dari layar **Izin perangkat** atau saat pertama dipakai.
* `android:usesCleartextTraffic="true"` — agar bisa ke `http://` di LAN (Ollama, LM Studio, server Next.js, `hermes serve` di Tailscale).
* `<queries>` untuk `RecognitionService`, `TTS_SERVICE`, dan `VIEW https` (Android 11+ wajib agar plugin suara & tautan berfungsi).

### Build APK via GitHub Actions

Tidak punya Android SDK di komputer? Gunakan workflow yang sudah disertakan di
`.github/workflows/build-apk.yml`:

1. Unggah (push) folder proyek ini ke repositori GitHub (boleh privat).
2. Workflow **Build APK** berjalan otomatis setiap push ke `main`/`master`, atau jalankan manual
   dari tab **Actions → Build APK → Run workflow**.
3. Setelah selesai (±5–10 menit), buka run tersebut dan unduh artefak **neovarch-agent-apk**.
   Isinya `app-release.apk` (universal) serta `app-arm64-v8a-release.apk`,
   `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`. Untuk HP Android modern pilih
   `app-arm64-v8a-release.apk`.

Workflow memakai Java 17 (Temurin) dan Flutter channel stable; APK ditandatangani dengan kunci
debug, jadi cocok untuk dipasang langsung (sideload), bukan untuk Play Store.

### iOS (butuh macOS + Xcode)

Folder `ios/` sudah siap: bundle id **com.neovarch.agent**, nama tampilan **Neovarch Agent**, set AppIcon
lengkap, layar peluncuran merah, dan teks izin (kamera, mikrofon, pengenalan suara, foto, lokasi, kontak,
kalender, jaringan lokal) di `ios/Runner/Info.plist`.

```bash
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace      # pilih Team di Signing & Capabilities
flutter build ipa                # atau: flutter run -d <iphone>
```

Workflow `.github/workflows/build-ios.yml` membuat IPA tanpa tanda tangan di runner macOS.

---

## Mode koneksi

Ubah di **Lainnya → Koneksi** (atau saat onboarding).

### 1. Mandiri (bawaan)

Tidak butuh PC. Buka **Lainnya → Penyedia & model**, pilih preset, tempel kunci API, pilih model
(tombol *Ambil daftar model*), tekan **Uji koneksi**, lalu **Simpan & aktifkan**.

* **Nous Portal**: base URL `https://inference-api.nousresearch.com/v1`, kunci dari portal.nousresearch.com.
* **OpenRouter**: `https://openrouter.ai/api/v1`, mis. model `nousresearch/hermes-4-70b`.
* **Ollama / LM Studio di PC**: jalankan server di `0.0.0.0`, pakai IP LAN PC (emulator: `10.0.2.2`), mis. `http://192.168.1.10:11434/v1`.

Semua data (sesi, transkrip, memori, skill, proyek, papan, cron, rapat, berkas) disimpan sebagai JSON di
direktori dokumen aplikasi; kunci API di keystore Android (`flutter_secure_storage`).

### 2. Gateway jarak jauh (`hermes serve`)

Di server:

```bash
hermes serve --host 0.0.0.0 --port 9119     # sebaiknya hanya di jaringan tepercaya / Tailscale
```

Di aplikasi: URL `http://<host>:9119`, **token sesi**, profil (opsional) dan header tambahan
(mis. `CF-Access-Client-Id: …` untuk Cloudflare Access). Aplikasi membuka WebSocket ke
`ws(s)://<host>/api/ws?token=…` (juga mengirim `Authorization: Bearer`) dan memakai metode JSON-RPC
`session.list / create / resume / title / delete / interrupt`, `prompt.submit`, `approval.respond`,
serta event `message.delta`, `reasoning.delta`, `tool.start`, `tool.complete`, `message.complete`,
`session.title`, `error`. Login OAuth (Nous Portal) dan alur *sign-in* username/password milik Desktop
belum didukung — isi token secara manual.

### 3. Server kantor (Next.js)

Server Next.js tetap menjadi backend (ia memanggil CLI `hermes`). Jalankan agar bisa dijangkau dari HP:

```bash
cd hermes-phone-main
npm install
npm run dev -- -H 0.0.0.0          # atau: npm run build && npm start -- -H 0.0.0.0
```

Di aplikasi isi URL server:

* **Emulator Android**: `http://10.0.2.2:3000` (10.0.2.2 = localhost PC dari dalam emulator).
* **HP fisik**: `http://<IP-LAN-PC>:3000`, HP dan PC di Wi-Fi yang sama; izinkan port 3000 di firewall.

Semua endpoint web dipakai sama persis: `GET/POST /api/hermes/tasks`, `GET/POST /api/hermes/tasks/{id}`,
`GET/POST /api/hermes/agents`, `GET/POST /api/hermes/meeting`, `GET /api/hermes/meeting/actions`,
`GET/POST /api/hermes/cron`, `GET /api/hermes/cron/actions`, `GET/POST/DELETE /api/hermes/chat`.
Papan dipolling tiap 4 dtk (bisa diubah), log "intip layar" tiap 5 dtk — sama seperti versi web.
Pesan galat memakai aturan `readJson` dari `src/lib/api.ts` (mis. *"server membalas halaman HTML, bukan JSON (HTTP 502) — biasanya proxy atau backend mati"*).

> **Build web Flutter + server di origin lain** butuh CORS. Aplikasi Android tidak terpengaruh.
> Bila perlu, salin `backend-patch/middleware.ts` ke `hermes-phone-main/src/middleware.ts`.

### 4. Demo offline

Papan contoh (jun, sari, bimo, rani, dewi) tanpa jaringan; rapat disimulasikan, balasan chat berlabel demo.

---

## Struktur kode

```
lib/
  main.dart                 bootstrap, tema, gerbang onboarding
  models/models.dart        Task, Agent, Meeting, CronJob, Profile, Skill, ChatMsg, ToolActivity, …
  data/
    api_result.dart         port readJson() dari src/lib/api.ts
    office_backend.dart     antarmuka /api/hermes/* + ServerBackend (HTTP ke Next.js)
    demo_backend.dart       port src/lib/offline-mock.ts
    local_backend.dart      backend Mandiri: papan + worker tugas, rapat LLM, cron
    local_store.dart        penyimpanan lokal (profil, sesi, memori, skill, proyek, papan, berkas)
    kv_store.dart (+ kv_backend_*.dart)   JSON per kunci: berkas di Android, shared_preferences di web
    llm_client.dart         klien OpenAI-compatible: SSE streaming + tool calls
    agent_runtime.dart      loop agent + alat aman di perangkat
    chat_engine.dart        mesin chat: Lokal / Gateway / Kantor
    gateway_client.dart     JSON-RPC 2.0 lewat WebSocket ke hermes serve
    cron_schedule.dart      parser jadwal (interval & cron 5 kolom)
  state/                    SettingsController, AppController, OfficeController (polling),
                            ChatController (streaming, antrean, persetujuan), VoiceService
  theme/                    tema Neovarch Red (+ kertas tulang) & preset ala Desktop → ThemeData Material 3
  ui/
    app_shell.dart          navbar mengambang (HP) / NavigationRail (lebar)
    screens/                chat/, kantor, papan, rapat, agent, cron, skill, memori, berkas,
                            proyek, onboarding, settings/
    widgets/                brand.dart (logo, wordmark, PaperScope, bingkai, halftone), office_painter.dart
                            (kantor isometrik), office_snapshot.dart (gambar kantor untuk agen), markdown_view.dart,
                            preview_sheet.dart, action_items.dart, common.dart
```

State memakai **flutter_riverpod** (ChangeNotifierProvider), HTTP memakai **http**, WebSocket memakai
**web_socket_channel**.

---

## Batasan yang diketahui

* **Cron di mode Mandiri hanya berjalan selama aplikasi terbuka** (timer 30 dtk). Belum memakai
  WorkManager/AlarmManager untuk eksekusi di latar belakang.
* Alat Mandiri sengaja dibatasi (tanpa terminal/shell, tanpa pencarian web berbayar). `web_fetch` hanya
  membaca halaman publik.
* Gateway: belum ada login OAuth/password otomatis, belum ada lampiran gambar, persetujuan perintah
  ditangani "sebaik mungkin" (event `approval.request`).
* Unduh transkrip/notulen = salin ke papan klip (di mode Mandiri notulen juga otomatis tersimpan ke `rapat/` di Berkas).
* Belum ada: terminal, review Git/worktree, HUD, Quick Entry, Memory Graph, Messaging/Bot Mode, impor
  tema VS Code, perintah palet, multi-jendela — fitur khas desktop.
* Parameter `?preview=1&mode=demo&tab=1&theme=nous&dark=1` hanya berlaku di build web (untuk tangkapan layar/demo).
