# Neovarch Agent

Agen AI dari NeovarchLabs dengan dua aplikasi:

* **Desktop (Windows, Linux) — inti.** Aplikasi Electron + Vite + React/TypeScript di folder [`desktop/`](desktop/),
  turunan dari **Hermes Desktop** milik Nous Research (lisensi MIT, lihat `desktop/LICENSE` dan `desktop/NOTICE`)
  dengan identitas Neovarch (tema merah, ikon, nama). Aplikasi ini menjalankan dan mengendalikan inti
  **Hermes Agent** (Python): chat dengan alat, sesi, skill, memori, proyek, terminal, Kanban, cron, dan lain-lain.
  Saat pertama dibuka, aplikasi memasang inti Hermes Agent bila belum ada, atau tersambung ke gateway Hermes yang sudah berjalan.
* **HP (Android, iOS) — remote.** Aplikasi Flutter di repo ini (`lib/`). Tidak menjalankan agen sendiri:
  ia dipasangkan dengan PC lewat QR lalu mengendalikan agen di PC — obrolan, persetujuan perintah, dan papan Kanban.

UI berbahasa Indonesia.

### Identitas visual

* **Warna**: crimson `#E0262F` / merah `#C8101A` di atas hampir-hitam `#0A0A0A`, teks tulang `#F2EDE4`; tampilan cetak datar
  tanpa gradien atau glow. Tema "Neovarch" adalah bawaan di desktop; preset Hermes lain tetap tersedia.
* **Logo**: wordmark **NEOVARCHAGENT** dengan cincin halo di atas huruf pertama; monogram N + halo untuk ikon.

---

## Install

**Linux (x86_64)** — terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.sh | sh
```

Memasang ke `~/.local/share/neovarch-agent`, membuat perintah `neovarch` di `~/.local/bin`, dan menambahkan
entri menu aplikasi. Butuh GTK 3, NSS, ALSA dan libsecret (installer memberi tahu perintah `apt`/`dnf`/`pacman` bila belum ada).
Pilih versi tertentu: `curl -fsSL …/install.sh | NEOVARCH_VERSION=v1.2.0 sh`.
Hapus: `curl -fsSL …/install.sh | sh -s -- --uninstall`.

**Windows (x64)** — PowerShell:

```powershell
irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1 | iex
```

Menjalankan installer `neovarch-agent-windows-x64-setup.exe` secara senyap per pengguna (tanpa admin) ke
`%LOCALAPPDATA%\Programs\NeovarchAgent` dan membuat perintah `neovarch`. Versi portabel (zip): tambahkan `-Portable`.
Hapus: `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1))) -Uninstall`.

**npm (Node.js 18+, Linux x64 / Windows x64)**:

```bash
npm i -g https://github.com/Maftuuh1922/neovrach_Agent/releases/latest/download/neovarch-agent-npm.tgz
neovarch
```

Aplikasi diunduh ke `~/.neovarch/app`. Setelah paket diterbitkan di registry npm, `npm i -g neovarch-agent`
juga bisa dipakai (saat ini belum diterbitkan).

**Android** — unduh APK dari [rilis terbaru](https://github.com/Maftuuh1922/neovrach_Agent/releases/latest):
`neovarch-agent-android-arm64.apk` (kebanyakan HP modern) atau `neovarch-agent-android-universal.apk`.

macOS dan Linux ARM64 belum tersedia. Semua unduhan: <https://github.com/Maftuuh1922/neovrach_Agent/releases/latest>.

---

## Remote dari HP

1. Di PC: **Pengaturan ▸ Remote / Perangkat ▸ Aktifkan akses remote**. Aplikasi menjalankan gateway kedua
   (`hermes serve --host 0.0.0.0 --port 9119`) yang dikunci dengan token, lalu menampilkan QR, alamat, dan token.
2. Di HP: buka Neovarch Agent ▸ **Pindai QR dari PC** (atau isi alamat `IP-PC:9119` + token secara manual).
3. HP dan PC harus di jaringan yang sama (Wi‑Fi/LAN) atau terhubung lewat Tailscale/WireGuard. Izinkan port 9119 di firewall.
4. **Buat token baru** di PC mencabut akses semua HP (harus memindai ulang).

Tab di HP: **Chat** (daftar sesi PC, chat streaming dengan aktivitas alat), **Tugas** (papan Kanban PC), **Setujui**
(persetujuan perintah, juga notifikasi Android), **PC** (status, ganti/lupakan PC). Protokolnya: [`docs/remote-protocol.md`](docs/remote-protocol.md).

Token memberi kendali penuh atas agen di PC. Di Wi‑Fi umum gunakan VPN; jangan buka port 9119 ke internet.

---

## Struktur repo

```
desktop/                      aplikasi desktop (Electron), workspace npm (npm 11)
  apps/desktop/               Electron main (electron/), renderer React (src/), electron-builder
  apps/desktop/electron/neovarch-remote.ts   gateway LAN + token untuk HP
  HERMES_CORE_COMMIT          revisi inti Hermes Agent yang dipakai
lib/                          aplikasi HP (Flutter)
  remote/                     pairing (QR/manual), klien gateway, transkrip, UI remote
  data/gateway_client.dart    JSON-RPC 2.0 lewat WebSocket
test/remote_gateway_test.dart tes klien remote terhadap gateway tiruan
docs/remote-protocol.md       protokol HP ↔ desktop
scripts/install.sh, install.ps1   installer satu baris
npm/                          peluncur npm
```

Folder `linux/` dan `windows/` adalah sisa build desktop Flutter lama (v1.1.0) dan tidak lagi dirilis.

---

## Membangun

**Desktop** (Node 22, npm 11):

```bash
cd desktop
npm ci
npm run build --workspace apps/desktop
cd apps/desktop && npx electron-builder --config electron-builder.config.cjs --linux AppImage tar.gz deb --x64
```

Rilis dibuat oleh `.github/workflows/desktop-electron.yml` (Windows NSIS + zip, Linux AppImage + tar.gz + deb) saat tag `v*` didorong.

**HP** (Flutter 3.38+, diuji 3.47.6, JDK 17):

```bash
flutter pub get
flutter test test/remote_gateway_test.dart
flutter build apk --release --split-per-abi
```

`applicationId`/bundle id = **com.neovarch.agent**. APK rilis ditandatangani dengan kunci debug (cocok untuk sideload).
APK dibuat oleh `.github/workflows/build-release.yml` pada tag `v*`. iOS butuh macOS + Xcode (`flutter build ipa`).

---

## Lisensi

Aplikasi desktop diturunkan dari Hermes Desktop / Hermes Agent © Nous Research, lisensi MIT (lihat `desktop/LICENSE`, `desktop/NOTICE`).
