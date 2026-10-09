<p align="center">
  <img src="docs/assets/logo.png" alt="Logo Neovarch Agent" width="160" height="160">
</p>

<h1 align="center">Neovarch Agent</h1>

<p align="center">
  <a href="https://maftuuh1922.github.io/neorachAgent_lp/">Situs</a> ·
  <a href="https://maftuuh1922.github.io/neorachAgent_lp/docs/">Dokumentasi</a> ·
  <a href="https://github.com/Maftuuh1922/neovrach_Agent/releases/latest">Unduh</a> ·
  <a href="docs/remote-protocol.md">Protokol remote</a> ·
  <a href="CONTRIBUTING.md">Kontribusi</a>
</p>

<p align="center">
  <a href="https://maftuuh1922.github.io/neorachAgent_lp/docs/"><img src="https://img.shields.io/badge/docs-situs-C8101A" alt="Dokumentasi"></a>
  <a href="https://github.com/Maftuuh1922/neovrach_Agent/releases/latest"><img src="https://img.shields.io/github/v/release/Maftuuh1922/neovrach_Agent?label=rilis&color=C8101A" alt="Rilis terbaru"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/lisensi-MIT-informational" alt="Lisensi MIT"></a>
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20Android-0A0A0A" alt="Platform">
</p>

**Agen AI dari NeovarchLabs yang bekerja di PC kamu sendiri (Windows, Linux) dan bisa kamu kendalikan dari HP Android.
Desktop adalah intinya: chat dengan alat, sesi, skill, memori, dan papan Kanban, semua datanya di `~/.neovarch`.
HP hanya remote: dipasangkan lewat QR, lalu mengendalikan agen di PC.**

Pakai model apa pun yang kompatibel dengan OpenAI `/chat/completions`: OpenAI, OpenRouter, Groq, DeepSeek, Ollama,
atau endpoint kustom (termasuk server lokal). Pilih penyedia dengan `neovarch setup`; API key disimpan di
`~/.neovarch/.env`.

<table>
  <tr>
    <td><b>Inti di PC sendiri</b></td>
    <td>Aplikasi desktop Electron menjalankan inti Neovarch (Python, perintah <code>neovarch</code>); data tetap di komputermu.</td>
  </tr>
  <tr>
    <td><b>Remote dari HP</b></td>
    <td>Pasangkan HP lewat QR, lalu chat, setujui perintah, dan pantau tugas serta status PC lewat LAN atau Tailscale.</td>
  </tr>
  <tr>
    <td><b>Chat dengan alat</b></td>
    <td>Streaming dengan alat <code>shell</code>, <code>read_file</code>, <code>write_file</code>, <code>edit_file</code>, <code>web_fetch</code>, <code>memory</code>, dan <code>skill</code>.</td>
  </tr>
  <tr>
    <td><b>Persetujuan perintah</b></td>
    <td>Perintah berbahaya menunggu izinmu (mode <code>ask</code> / <code>off</code>), juga dari notifikasi Android.</td>
  </tr>
  <tr>
    <td><b>Sesi, skill, memori, Kanban</b></td>
    <td>Chat tersimpan dan bisa dilanjutkan, skill lokal, memori catatan, dan papan Kanban untuk tugas.</td>
  </tr>
  <tr>
    <td><b>Gateway terkunci token</b></td>
    <td>Akses remote memakai gateway terpisah yang dikunci token; buat token baru untuk mencabut akses semua HP.</td>
  </tr>
</table>

---

## Quick Install

**Linux (x86_64):**

```bash
curl -fsSL https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.sh | sh
```

**Windows (x64), PowerShell:**

```powershell
irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1 | iex
```

**Android:** unduh `neovarch-agent-android-arm64.apk` (kebanyakan HP modern) atau
`neovarch-agent-android-universal.apk` dari [Releases](https://github.com/Maftuuh1922/neovrach_Agent/releases/latest).

Installer Windows `.exe`, AppImage/`.deb` Linux, dan peluncur npm juga ada di Releases. macOS dan Linux ARM64 belum tersedia.

---

## Getting Started

```bash
neovarch setup              # pilih penyedia model dan simpan API key
neovarch                    # chat di terminal
neovarch -q "halo"          # jalankan satu prompt lalu keluar
neovarch --resume <id>      # lanjutkan sesi
neovarch sessions           # daftar, lihat, atau hapus chat tersimpan
neovarch config show        # lihat atau ubah config.yaml
neovarch desktop            # buka aplikasi desktop
neovarch update             # cara memperbarui Neovarch
neovarch version            # tampilkan versi
```

Pasangkan HP: di PC buka **Pengaturan ▸ Remote / Perangkat ▸ Aktifkan akses remote**, lalu di HP pilih
**Pindai QR dari PC**.

Panduan lengkap (konfigurasi model, pairing HP, build dari source): <https://maftuuh1922.github.io/neorachAgent_lp/docs/>

---

## License

MIT, © 2026 Maftuuh1922 / NeovarchLabs. Lihat [`LICENSE`](LICENSE) dan [`NOTICE`](NOTICE).
