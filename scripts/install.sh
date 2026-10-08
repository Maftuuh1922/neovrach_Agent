#!/bin/sh
# Neovarch Agent installer (Linux x86_64) — installs the desktop app (Electron).
#
#   curl -fsSL https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.sh | sh
#
# Options (pass after `sh -s --` when piping):
#   --uninstall        remove Neovarch Agent
#   --help             show help
# Environment:
#   NEOVARCH_VERSION   release tag to install (e.g. v1.2.1). Default: latest.
#
# Installs to ~/.local/share/neovarch-agent, links ~/.local/bin/neovarch to the
# app executable and adds a desktop menu entry. No root needed.
#
# The Neovarch core (Hermes Agent, Python) is not installed by this script:
# on first launch the app itself offers to install it (Hermes Agent's own
# installer, pinned to the revision the app was built against) or to connect
# to an existing Hermes gateway. An existing `hermes` install is used as is.

set -eu

REPO="Maftuuh1922/neovrach_Agent"
RELEASES_URL="https://github.com/$REPO/releases"
ASSET="neovarch-agent-linux-x64.tar.gz"
EXE="neovarch-agent"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA_HOME/neovarch-agent"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/neovarch"
APPS_DIR="$DATA_HOME/applications"
DESKTOP_FILE="$APPS_DIR/neovarch-agent.desktop"
ICON_DIR="$DATA_HOME/icons/hicolor/512x512/apps"
ICON_FILE="$ICON_DIR/neovarch-agent.png"

# ---------------------------------------------------------------- output ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$(printf '\033[31m'); C_GRN=$(printf '\033[32m'); C_YLW=$(printf '\033[33m')
  C_BLD=$(printf '\033[1m');  C_DIM=$(printf '\033[2m');  C_RST=$(printf '\033[0m')
else
  C_RED=''; C_GRN=''; C_YLW=''; C_BLD=''; C_DIM=''; C_RST=''
fi

say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$C_RED$C_BLD" "$C_RST" "$*"; }
ok()   { printf '%s ok%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YLW" "$C_RST" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$C_RED$C_BLD" "$C_RST" "$*" >&2; exit 1; }

banner() {
  printf '\n%sNeovarch Agent%s %sinstaller%s\n\n' "$C_RED$C_BLD" "$C_RST" "$C_DIM" "$C_RST"
}

usage() {
  cat <<EOF
Neovarch Agent installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/install.sh | sh -s -- --uninstall

Options:
  --uninstall   Remove Neovarch Agent from this machine
  -h, --help    Show this help

Environment:
  NEOVARCH_VERSION   Release tag to install, e.g. v1.2.1 (default: latest)
EOF
}

# ------------------------------------------------------------- helpers ---
have() { command -v "$1" >/dev/null 2>&1; }

download() { # url dest
  if have curl; then
    if [ -t 2 ]; then
      curl -fL --retry 3 --progress-bar -o "$2" "$1"
    else
      curl -fsSL --retry 3 -o "$2" "$1"
    fi
  elif have wget; then
    wget -q --show-progress -O "$2" "$1" 2>/dev/null || wget -O "$2" "$1"
  else
    die "need curl or wget to download Neovarch Agent"
  fi
}

has_lib() { # soname
  if have ldconfig && ldconfig -p 2>/dev/null | grep -q "$1"; then
    return 0
  fi
  for d in /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/local/lib; do
    [ -e "$d/$1" ] && return 0
  done
  return 1
}

refresh_menu() {
  if have update-desktop-database; then
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
  fi
}

check_deps() {
  missing=''
  has_lib libgtk-3.so.0 || missing="$missing gtk3"
  has_lib libnss3.so || missing="$missing nss"
  has_lib libasound.so.2 || missing="$missing alsa"
  has_lib libsecret-1.so.0 || missing="$missing libsecret"
  [ -z "$missing" ] && { ok "runtime libraries found (GTK 3, NSS, ALSA, libsecret)"; return 0; }

  warn "missing runtime libraries:$missing"
  if have apt-get; then
    say "      install with: sudo apt-get install -y libgtk-3-0 libnss3 libasound2 libsecret-1-0"
  elif have dnf; then
    say "      install with: sudo dnf install -y gtk3 nss alsa-lib libsecret"
  elif have pacman; then
    say "      install with: sudo pacman -S --needed gtk3 nss alsa-lib libsecret"
  elif have zypper; then
    say "      install with: sudo zypper install gtk3 mozilla-nss libasound2 libsecret-1-0"
  else
    say "      install GTK 3, NSS, ALSA and libsecret with your package manager"
  fi
}

# Chromium needs either a root-owned setuid chrome-sandbox or unprivileged
# user namespaces. Ubuntu 23.10+ restricts the latter by default, so check and
# fall back to --no-sandbox for the menu entry when neither is available.
sandbox_ok() { # app dir
  sb="$1/chrome-sandbox"
  [ -e "$sb" ] || return 0
  if [ -u "$sb" ] && [ "$(stat -c %u "$sb" 2>/dev/null)" = "0" ]; then return 0; fi
  if have unshare && unshare --user --map-root-user true >/dev/null 2>&1; then return 0; fi
  return 1
}

core_note() {
  if have hermes; then
    ok "Neovarch core (Hermes Agent) found: $(command -v hermes)"
  else
    say "    The Neovarch core (Hermes Agent) is not installed yet. On first launch the"
    say "    app offers to install it for you, or to connect to an existing gateway."
  fi
}

# ----------------------------------------------------------- uninstall ---
uninstall() {
  banner
  step "Removing Neovarch Agent"
  removed=0
  if [ -L "$BIN_LINK" ] || [ -e "$BIN_LINK" ]; then rm -f "$BIN_LINK"; ok "removed $BIN_LINK"; removed=1; fi
  if [ -e "$DESKTOP_FILE" ]; then rm -f "$DESKTOP_FILE"; ok "removed $DESKTOP_FILE"; removed=1; fi
  if [ -e "$ICON_FILE" ]; then rm -f "$ICON_FILE"; fi
  if [ -d "$INSTALL_DIR" ]; then rm -rf "$INSTALL_DIR"; ok "removed $INSTALL_DIR"; removed=1; fi
  refresh_menu
  if [ "$removed" -eq 0 ]; then
    say "Neovarch Agent is not installed."
  else
    say ""
    say "Neovarch Agent uninstalled. Your chats, settings and the Neovarch core"
    say "(Hermes Agent, in ~/.hermes) were left in place."
  fi
}

# ------------------------------------------------------------- install ---
write_desktop_entry() { # icon exec_flags
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Neovarch Agent
Comment=Neovarch Agent desktop
Exec="$INSTALL_DIR/$EXE"$2 %U
Icon=$1
Path=$INSTALL_DIR
Terminal=false
Categories=Development;Utility;
StartupWMClass=Neovarch Agent
EOF
  chmod 644 "$DESKTOP_FILE"
}

install_linux_x64() {
  version="${NEOVARCH_VERSION:-}"
  if [ -n "$version" ]; then
    case "$version" in v*) ;; *) version="v$version" ;; esac
    url="$RELEASES_URL/download/$version/$ASSET"
    label="$version"
  else
    url="$RELEASES_URL/latest/download/$ASSET"
    label="latest"
  fi

  have tar || die "need tar to unpack Neovarch Agent"

  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t neovarch)
  trap 'rm -rf "$tmp"' EXIT INT TERM

  step "Downloading Neovarch Agent ($label)"
  say "    $C_DIM$url$C_RST"
  download "$url" "$tmp/$ASSET" || die "download failed. Check the tag or see $RELEASES_URL"

  step "Unpacking"
  mkdir -p "$tmp/x"
  tar -xzf "$tmp/$ASSET" -C "$tmp/x" || die "could not unpack $ASSET"
  src=$(find "$tmp/x" -maxdepth 3 -type f -name "$EXE" 2>/dev/null | head -n 1)
  [ -n "$src" ] || die "archive layout unexpected (no $EXE executable)"
  src=$(dirname "$src")
  chmod 755 "$src/$EXE"

  # Close a running copy so its files can be replaced.
  if have pkill; then pkill -f "$INSTALL_DIR/$EXE" >/dev/null 2>&1 || true; fi

  mkdir -p "$DATA_HOME" "$BIN_DIR" "$APPS_DIR" "$ICON_DIR"
  rm -rf "$INSTALL_DIR"
  mv "$src" "$INSTALL_DIR"
  ok "installed to $INSTALL_DIR"

  ln -sf "$INSTALL_DIR/$EXE" "$BIN_LINK"
  ok "linked $BIN_LINK -> $INSTALL_DIR/$EXE"

  icon="neovarch-agent"
  if [ -f "$INSTALL_DIR/resources/app.asar.unpacked/dist/apple-touch-icon.png" ]; then
    cp "$INSTALL_DIR/resources/app.asar.unpacked/dist/apple-touch-icon.png" "$ICON_FILE"
  elif ! download "https://raw.githubusercontent.com/$REPO/main/assets/brand/app_icon.png" "$ICON_FILE" >/dev/null 2>&1; then
    icon="utilities-terminal"
  fi

  exec_flags=''
  if ! sandbox_ok "$INSTALL_DIR"; then
    exec_flags=' --no-sandbox'
    warn "the Chromium sandbox is unavailable here (user namespaces restricted, chrome-sandbox not setuid root)"
    say "      the menu entry starts the app with --no-sandbox; from a terminal run: neovarch --no-sandbox"
    say "      to keep the sandbox instead (needs sudo once):"
    say "        sudo chown root:root '$INSTALL_DIR/chrome-sandbox' && sudo chmod 4755 '$INSTALL_DIR/chrome-sandbox'"
  fi

  write_desktop_entry "$icon" "$exec_flags"
  refresh_menu
  ok "added menu entry $DESKTOP_FILE"

  check_deps
  core_note

  case ":${PATH:-}:" in
    *":$BIN_DIR:"*) ;;
    *)
      warn "$BIN_DIR is not in your PATH"
      say "      add this to your shell profile (~/.bashrc, ~/.zshrc):"
      say "        export PATH=\"\$HOME/.local/bin:\$PATH\""
      ;;
  esac

  say ""
  say "${C_BLD}Neovarch Agent is installed.${C_RST} Run ${C_RED}${C_BLD}neovarch${C_RST} or open it from your app menu."
  say "Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/install.sh | sh -s -- --uninstall"
}

not_available() { # platform
  banner
  say "Neovarch Agent for $1 is not available yet."
  say "Builds for Linux x86_64, Windows x64 and Android are on the releases page:"
  say "  $RELEASES_URL/latest"
  exit 1
}

# ---------------------------------------------------------------- main ---
main() {
  action=install
  for arg in "$@"; do
    case "$arg" in
      --uninstall) action=uninstall ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $arg (try --help)" ;;
    esac
  done

  if [ "$action" = uninstall ]; then
    uninstall
    exit 0
  fi

  os=$(uname -s 2>/dev/null || echo unknown)
  arch="${NEOVARCH_FORCE_ARCH:-$(uname -m 2>/dev/null || echo unknown)}"

  case "$os" in
    Linux)
      case "$arch" in
        x86_64|amd64) banner; install_linux_x64 ;;
        aarch64|arm64) not_available "Linux ARM64" ;;
        *) not_available "Linux $arch" ;;
      esac
      ;;
    Darwin) not_available "macOS" ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
      banner
      say "On Windows, run this in PowerShell instead:"
      say "  irm https://raw.githubusercontent.com/$REPO/main/scripts/install.ps1 | iex"
      exit 1
      ;;
    *) not_available "$os" ;;
  esac
}

main "$@"
