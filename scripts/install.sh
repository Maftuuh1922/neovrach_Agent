#!/bin/sh
# Neovarch Agent installer (Linux x86_64).
#
#   curl -fsSL https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.sh | sh
#
# Options (pass after `sh -s --` when piping):
#   --uninstall        remove Neovarch Agent
#   --help             show help
# Environment:
#   NEOVARCH_VERSION   release tag to install (e.g. v1.1.0). Default: latest.
#
# Installs to ~/.local/share/neovarch-agent, links ~/.local/bin/neovarch and
# adds a desktop menu entry. No root needed.

set -eu

REPO="Maftuuh1922/neovrach_Agent"
RELEASES_URL="https://github.com/$REPO/releases"
ASSET="neovarch-agent-linux-x64.tar.gz"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA_HOME/neovarch-agent"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/neovarch"
APPS_DIR="$DATA_HOME/applications"
DESKTOP_FILE="$APPS_DIR/neovarch-agent.desktop"

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
  NEOVARCH_VERSION   Release tag to install, e.g. v1.1.0 (default: latest)
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
  has_lib libsecret-1.so.0 || missing="$missing libsecret"
  [ -z "$missing" ] && { ok "runtime libraries found (GTK 3, libsecret)"; return 0; }

  warn "missing runtime libraries:$missing"
  if have apt-get; then
    say "      install with: sudo apt-get install -y libgtk-3-0 libsecret-1-0"
  elif have dnf; then
    say "      install with: sudo dnf install -y gtk3 libsecret"
  elif have pacman; then
    say "      install with: sudo pacman -S --needed gtk3 libsecret"
  elif have zypper; then
    say "      install with: sudo zypper install gtk3 libsecret-1-0"
  else
    say "      install GTK 3 and libsecret with your package manager"
  fi
}

# ----------------------------------------------------------- uninstall ---
uninstall() {
  banner
  step "Removing Neovarch Agent"
  removed=0
  if [ -L "$BIN_LINK" ] || [ -e "$BIN_LINK" ]; then rm -f "$BIN_LINK"; ok "removed $BIN_LINK"; removed=1; fi
  if [ -e "$DESKTOP_FILE" ]; then rm -f "$DESKTOP_FILE"; ok "removed $DESKTOP_FILE"; removed=1; fi
  if [ -d "$INSTALL_DIR" ]; then rm -rf "$INSTALL_DIR"; ok "removed $INSTALL_DIR"; removed=1; fi
  refresh_menu
  if [ "$removed" -eq 0 ]; then
    say "Neovarch Agent is not installed."
  else
    say ""
    say "Neovarch Agent uninstalled. Your chats and settings were left in place."
  fi
}

# ------------------------------------------------------------- install ---
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
  tar -xzf "$tmp/$ASSET" -C "$tmp" || die "could not unpack $ASSET"
  [ -x "$tmp/neovarch-agent/neovarch-agent" ] || die "archive layout unexpected (no neovarch-agent/neovarch-agent)"

  mkdir -p "$DATA_HOME" "$BIN_DIR" "$APPS_DIR"
  rm -rf "$INSTALL_DIR"
  mv "$tmp/neovarch-agent" "$INSTALL_DIR"
  ok "installed to $INSTALL_DIR"

  ln -sf "$INSTALL_DIR/neovarch-agent" "$BIN_LINK"
  ok "linked $BIN_LINK"

  icon="$INSTALL_DIR/neovarch-agent.png"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Neovarch Agent
Comment=Autonomous AI agent
Exec=$INSTALL_DIR/neovarch-agent
Icon=$icon
Path=$INSTALL_DIR
Terminal=false
Categories=Development;Utility;
StartupWMClass=com.neovarch.agent
EOF
  chmod 644 "$DESKTOP_FILE"
  refresh_menu
  ok "added menu entry $DESKTOP_FILE"

  check_deps

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
