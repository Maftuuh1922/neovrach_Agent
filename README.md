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
`~/.neovarch/.env` (`%LOCALAPPDATA%\neovarch\.env` on Windows).

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

## Documentation

A plain-language guide for people who have never used a tool like this before. No coding knowledge needed.

**Contents:** [What is it?](#what-is-neovarch-agent) · [What you need](#what-you-need) ·
[Step 1: Install](#step-1-install-on-your-pc) · [Step 2: API key](#step-2-get-an-api-key) ·
[Step 3: First chat](#step-3-run-setup-and-start-your-first-chat) · [Step 4: Phone](#step-4-connect-your-phone-optional) ·
[Approvals](#approving-commands) · [Update & uninstall](#updating-and-uninstalling) · [FAQ](#faq-and-troubleshooting)

### What is Neovarch Agent?

Neovarch Agent is an AI helper that lives on your own computer. You type what you want in normal words
("make a folder and write a list of ideas in it"), and it does the work on your PC: it can run commands,
read and write files, and fetch web pages.

- **Your PC is the brain.** The agent, your chats, and your settings all stay on your computer.
- **Your phone is a remote.** The Android app does not run the agent itself. It connects to your PC so you can
  chat, approve actions, and check on tasks from the couch. Your PC must be on for the phone to work.

There is no Neovarch server. The only thing that leaves your PC is the conversation sent to the AI model you choose.

### What you need

- **A PC** running **Windows (64-bit, x64)** or **Linux (64-bit, x86_64)**. macOS and Linux ARM64 are not available yet.
- **An internet connection** to download the app and to talk to an online AI model.
- **An API key** from a model provider (explained in [Step 2](#step-2-get-an-api-key)), *or* a free model running on your own PC with Ollama.
- **Optional:** an **Android phone**, if you want to use it as a remote.

You do not need to install Python or anything else first. The installer brings everything it needs.

A few words you will see:

- **Terminal** (called **PowerShell** on Windows): a window where you type commands instead of clicking buttons.
- **Command**: one line of text you paste into the terminal and run by pressing **Enter**.
- **Provider**: the company (or program) that runs the AI model, for example OpenAI or OpenRouter.
- **API key**: a long secret password that lets Neovarch use your account at that provider.

### Step 1: Install on your PC

**On Windows**

1. Click **Start**, type `PowerShell`, and open **Windows PowerShell**. You do not need "Run as administrator".
2. Copy this line, paste it into the window (right-click pastes), and press **Enter**:

   ```powershell
   irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1 | iex
   ```

3. Wait until it says **Neovarch Agent is installed.**
4. Close PowerShell and open a **new** one. The `neovarch` command only works in windows opened after the install.

If Windows shows a blue "Windows protected your PC" (SmartScreen) screen, click **More info** and then **Run anyway**.
This appears because the app is not code-signed yet.

**On Linux**

1. Open a terminal (on most desktops: search for "Terminal" in the app menu).
2. Copy this line, paste it into the terminal (usually **Ctrl+Shift+V**), and press **Enter**:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.sh | sh
   ```

3. Wait until it says **Neovarch Agent is installed.**, then open a new terminal.
4. If the installer warns that some libraries are missing (GTK 3, NSS, ALSA, libsecret), it prints the exact
   `apt`, `dnf`, or `pacman` command to fix it. Run that command, which may ask for your password.

Nothing needs administrator rights except that optional library command: Neovarch installs for your user only.

**Prefer a normal installer?** Download a file from [Releases](https://github.com/Maftuuh1922/neovrach_Agent/releases/latest)
and open it:

| Your PC | File to download |
|---|---|
| Windows | `neovarch-agent-windows-x64-setup.exe` (installer) or `neovarch-agent-windows-x64.zip` (portable) |
| Linux | `neovarch-agent-linux-x64.AppImage` (make it executable, then run), `.deb` (Debian/Ubuntu), or `.tar.gz` |

The first time you open the app, it installs the Neovarch core by itself if it is missing.

### Step 2: Get an API key

The agent needs an AI model to think with. Most models live online, and the company running them gives you an
**API key**: a secret code that proves the requests come from your account (and lets them bill you, if the model is paid).

1. Pick a provider. Neovarch has these built in: **OpenAI**, **OpenRouter**, **Groq**, **DeepSeek**, and **Ollama**,
   plus **custom** for any other service that speaks the OpenAI chat API.
2. Create an account on the provider's website and create an API key there. Copy it.
3. Keep it for Step 3, where Neovarch asks you to paste it.

**Free option, no key:** [Ollama](https://ollama.com) runs a model on your own PC. Install Ollama, download a model,
then choose `ollama` in setup. Neovarch talks to it at `http://127.0.0.1:11434/v1`. A powerful PC helps here.

**Where is my key stored?** In a file named `.env` inside Neovarch's data folder: `~/.neovarch/.env` on Linux, and
`%LOCALAPPDATA%\neovarch\.env` on Windows. It is not put in `config.yaml`.

**Keep it secret.** Anyone with your key can use your provider account and spend your money. Don't paste it in chats,
screenshots, or public code. If it leaks, delete it on the provider's website and make a new one.

### Step 3: Run setup and start your first chat

1. In a new terminal (or PowerShell), run:

   ```bash
   neovarch setup
   ```

2. Type the number of your provider and press **Enter**.
3. Press **Enter** to accept the suggested model, or type another model name. For **custom**, it also asks for the
   provider's **Base URL** (an address ending in `/v1`).
4. Paste your API key and press **Enter**. Nothing shows while you paste; that is normal, it hides the key.
5. You will see `saved … (provider …, model …)`. Setup is done.

Now pick how you want to chat:

- **Desktop app (easiest):** open **Neovarch Agent** from the Start menu (Windows) or app menu (Linux), or run
  `neovarch desktop`. Click **Sesi baru** (New session) and type your request.
- **In the terminal:** run `neovarch` and type after the `›` sign. Type `/new` for a fresh chat and `/exit` to quit.

Try something like: *"Make a folder called test-neovarch, write a file notes.md with 3 project ideas, then show it."*
You will see the agent use its tools step by step and then answer. Every chat is saved, so you can come back to it later.

### Step 4: Connect your phone (optional)

**Install the app**

1. On your phone, open [Releases](https://github.com/Maftuuh1922/neovrach_Agent/releases/latest) and download
   `neovarch-agent-android-arm64.apk` (most modern phones). If that one won't install, use `neovarch-agent-android-universal.apk`.
2. Open the downloaded file. Android will ask you to allow **installing unknown apps** for your browser or file manager.
   Allow it, then tap **Install**. (An APK is an Android app file from outside the Play Store. Android may show a
   warning because this one is signed with a test key.)

**Pair it with your PC**

1. Put the phone and the PC on the **same Wi-Fi**. (Away from home? Install [Tailscale](https://tailscale.com) on both,
   a free private network app, and use the PC's Tailscale address, which starts with `100.`.)
2. On the PC, in the desktop app, open **Pengaturan ▸ Remote / Perangkat** (Settings ▸ Remote / Devices) and switch on
   **Aktifkan akses remote** (Enable remote access). A QR code, an address, and a token (a one-time pairing password) appear.
3. On the phone, open Neovarch Agent and tap **Pindai QR dari PC** (Scan QR from PC), then point the camera at the QR code.
   No camera? Tap **Masukkan alamat & token** (Enter address & token) and type the address (like `192.168.1.5:9319`)
   and the token shown on the PC, then tap **Hubungkan** (Connect).
4. Done. The phone remembers your PC. Its tabs are **Chat**, **Tugas** (Tasks, the Kanban board),
   **Setujui** (Approve), and **PC** (status, switch or forget the PC).

**Lost your phone?** On the PC press **Buat token baru** (Create new token). Every paired phone is disconnected and
must scan the new QR code. Treat the QR code like a password: it gives full control of the agent on your PC.

### Approving commands

The agent works with real tools on your real PC, so Neovarch checks every terminal command before it runs.
Risky ones (for example deleting files with `rm -rf`, `sudo`, formatting disks, shutting down, force-pushing with git,
or running a script straight from the internet) **wait for your OK**. Normal commands run right away.

When the agent asks, you choose:

| Choice | What happens |
|---|---|
| **Once** | Run this command one time. |
| **This session** | Allow this exact command for the rest of this chat without asking again. |
| **Deny** | Don't run it. The agent is told you said no. |

- In the desktop app the question appears inside the chat. On the phone it appears in the **Setujui** tab and as an
  Android notification. Answering on one device closes it on the other.
- In the terminal it looks like `Allow? [o]nce / [s]ession / [N]o`. Pressing **Enter** alone means no.
- If nobody answers within **5 minutes**, the command is denied.

This is the default `ask` mode and it is what keeps you in control. You can switch it off with
`neovarch config set approvals.mode off` (everything runs without asking), but that is only sensible on a test machine.
Switch it back with `neovarch config set approvals.mode ask`.

### Updating and uninstalling

**Update:** run the same install command from [Step 1](#step-1-install-on-your-pc) again. It replaces the app and core
with the latest release and keeps your chats and settings. (`neovarch update` prints these commands for you.)

**Uninstall** removes the app, the `neovarch` command, and Neovarch's data folder, including your chats and API keys:

- Linux:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.sh | sh -s -- --uninstall
  ```

- Windows (PowerShell):

  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1))) -Uninstall
  ```

- Phone: uninstall it like any other Android app.

### FAQ and troubleshooting

<details>
<summary><b>"neovarch" is not recognized / command not found</b></summary>

Close the terminal and open a new one; the command is only available in windows opened after installing.
On Linux, if it still fails, the installer will have warned that `~/.local/bin` is not in your PATH (the list of folders
your terminal searches). Add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` (or `~/.zshrc`) and open a new terminal.
</details>

<details>
<summary><b>Windows blocks the installer ("Windows protected your PC")</b></summary>

The builds are not code-signed yet, so SmartScreen warns about them. Click <b>More info</b>, then <b>Run anyway</b>.
</details>

<details>
<summary><b>The agent doesn't answer, or shows "HTTP 401"</b></summary>

Your API key is wrong, expired, or missing. Run <code>neovarch setup</code> again and paste a fresh key from your provider.
</details>

<details>
<summary><b>Error "provider returned HTTP 404"</b></summary>

The provider couldn't find what Neovarch asked for. This usually means the model name or the Base URL is wrong.
Run <code>neovarch setup</code> again and check both: the model name must be spelled exactly as your provider lists it,
and a custom Base URL normally ends in <code>/v1</code>. Use <code>neovarch config show</code> to see what is saved now.
</details>

<details>
<summary><b>"Add model" in the desktop app doesn't work</b></summary>

This is a known issue in v1.3.0. Use <code>neovarch setup</code> in the terminal instead (see Step 3).
</details>

<details>
<summary><b>My phone can't connect to the PC</b></summary>

1. Make sure the phone and PC are on the same Wi-Fi, or both on Tailscale.
2. Make sure the desktop app is open on the PC and <b>Aktifkan akses remote</b> is on.
3. Allow port <b>9319</b> through your PC's firewall (the PC's built-in security that blocks incoming connections).
   Never open this port to the whole internet.
4. Check that the address is your PC's home network address (often <code>192.168.x.x</code>). If the PC has several,
   pick another one on the Remote screen.
5. If it worked before and now says it's refused, the token was probably renewed. Scan the new QR code.
</details>

<details>
<summary><b>Android refuses to install the APK</b></summary>

Allow "install unknown apps" for the app you used to open the file (your browser or file manager). If you already have
an older Neovarch APK installed and the update fails, uninstall the old one first.
</details>

<details>
<summary><b>The Linux desktop app won't open</b></summary>

Install the libraries the installer listed (GTK 3, NSS, ALSA, libsecret). For the AppImage, make the file executable first
(<code>chmod +x</code> on the file).
</details>

Still stuck? Open an [issue on GitHub](https://github.com/Maftuuh1922/neovrach_Agent/issues). The full docs (in Indonesian)
are at <https://maftuuh1922.github.io/neorachAgent_lp/docs/>.

---

## Acknowledgements

Inspired by [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research.

---

## License

MIT, © 2026 Maftuuh1922 / NeovarchLabs. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
