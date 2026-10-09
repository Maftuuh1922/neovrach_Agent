<p align="center">
  <img src="docs/assets/logo.png" alt="Neovarch Agent logo" width="160" height="160">
</p>

<h1 align="center">Neovarch Agent</h1>

<p align="center">
  <a href="https://maftuuh1922.github.io/neorachAgent_lp/">Website</a> ·
  <a href="https://maftuuh1922.github.io/neorachAgent_lp/docs/">Docs</a> ·
  <a href="https://github.com/Maftuuh1922/neovrach_Agent/releases/latest">Download</a> ·
  <a href="docs/remote-protocol.md">Remote protocol</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <a href="https://maftuuh1922.github.io/neorachAgent_lp/docs/"><img src="https://img.shields.io/badge/docs-website-C8101A" alt="Docs"></a>
  <a href="https://github.com/Maftuuh1922/neovrach_Agent/releases/latest"><img src="https://img.shields.io/github/v/release/Maftuuh1922/neovrach_Agent?label=release&color=C8101A" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-informational" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20Android-0A0A0A" alt="Platform">
</p>

**An AI agent by NeovarchLabs that runs on your own PC (Windows, Linux) and that you can control from your Android phone.
The desktop is the core: chat with tools, sessions, skills, memory, and a Kanban board, with all data kept in `~/.neovarch`.
The phone is just a remote: pair it with a QR code and drive the agent on your PC.**

Use any model that speaks the OpenAI `/chat/completions` API: OpenAI, OpenRouter, Groq, DeepSeek, Ollama,
or a custom endpoint (including a local server). Pick a provider with `neovarch setup`; API keys are stored in
`~/.neovarch/.env`.

<table>
  <tr>
    <td><b>Core on your own PC</b></td>
    <td>The Electron desktop app runs the Neovarch core (Python, the <code>neovarch</code> command); your data stays on your machine.</td>
  </tr>
  <tr>
    <td><b>Phone remote</b></td>
    <td>Pair your phone by QR, then chat, approve commands, and watch tasks and PC status over LAN or Tailscale.</td>
  </tr>
  <tr>
    <td><b>Chat with tools</b></td>
    <td>Streaming chat with the <code>shell</code>, <code>read_file</code>, <code>write_file</code>, <code>edit_file</code>, <code>web_fetch</code>, <code>memory</code>, and <code>skill</code> tools.</td>
  </tr>
  <tr>
    <td><b>Command approvals</b></td>
    <td>Risky commands wait for your OK (<code>ask</code> / <code>off</code> modes), including from an Android notification.</td>
  </tr>
  <tr>
    <td><b>Sessions, skills, memory, Kanban</b></td>
    <td>Saved chats you can resume, local skills, note-based memory, and a Kanban board for tasks.</td>
  </tr>
  <tr>
    <td><b>Token-locked gateway</b></td>
    <td>Remote access goes through a separate token-locked gateway; generate a new token to revoke every paired phone.</td>
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

**Android:** download `neovarch-agent-android-arm64.apk` (most modern phones) or
`neovarch-agent-android-universal.apk` from [Releases](https://github.com/Maftuuh1922/neovrach_Agent/releases/latest).

The Windows `.exe` installer, Linux AppImage/`.deb`, and the npm launcher are on Releases too. macOS and Linux ARM64 are not available yet.

---

## Getting Started

```bash
neovarch setup              # pick a model provider and save your API key
neovarch                    # chat in the terminal
neovarch -q "hello"         # run a single prompt and exit
neovarch --resume <id>      # resume a session
neovarch sessions           # list, view, or delete saved chats
neovarch config show        # view or edit config.yaml
neovarch desktop            # open the desktop app
neovarch update             # how to update Neovarch
neovarch version            # print the version
```

Pair your phone: on the PC open **Pengaturan ▸ Remote / Perangkat ▸ Aktifkan akses remote** (Settings ▸ Remote / Devices ▸ Enable remote access), then on the phone choose
**Pindai QR dari PC** (Scan QR from PC).

Full guide (model setup, phone pairing, building from source): <https://maftuuh1922.github.io/neorachAgent_lp/docs/>

---

## Acknowledgements

Inspired by [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research.

---

## License

MIT, © 2026 Maftuuh1922 / NeovarchLabs. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
