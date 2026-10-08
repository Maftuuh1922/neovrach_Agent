#!/bin/bash
# Neovarch <-> Hermes isolation test (Linux).
#
#   scripts/isolation-test/run.sh setup    fake ~/.hermes (config, profiles, skills, memory, install,
#                                          receipt, updater, desktop-plugins), `hermes` shims on PATH,
#                                          HERMES_HOME exported, a fake gateway on :9119; snapshot
#   scripts/isolation-test/run.sh install  run THIS checkout's scripts/install.sh --core-only
#   (then launch the desktop: desktop/tests-js/isolation/neovarch-isolation.mts)
#   scripts/isolation-test/run.sh verify   re-snapshot + compare; check the Hermes port/process/CLI
#   scripts/isolation-test/run.sh uninstall  install.sh --uninstall, then compare again
#
# Everything lives under $ISO (default /tmp/neovarch-iso); HOME is $ISO/home.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
ISO=${ISO:-/tmp/neovarch-iso}
FAKE_HOME=$ISO/home
HERMES_PORT=${HERMES_PORT:-9119}
PY=${PYTHON:-python3}
curlq() { curl -fsS --noproxy "*" "$@"; }

# What a co-installed Hermes leaves in the environment. Neovarch must ignore it.
hermes_env() {
  export HOME=$FAKE_HOME
  export HERMES_HOME=$FAKE_HOME/.hermes
  export PATH="$FAKE_HOME/.local/bin:$PATH"
  unset NEOVARCH_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME || true
}

protected_paths() {
  echo "$FAKE_HOME/.hermes" "$FAKE_HOME/.local/bin/hermes" "$FAKE_HOME/.local/bin/hermes-acp" \
       "$FAKE_HOME/.local/state/hermes" "$FAKE_HOME/.config/Hermes"
}

setup() {
  rm -rf "$ISO"; mkdir -p "$FAKE_HOME"
  local H=$FAKE_HOME/.hermes
  mkdir -p "$H/profiles/work/skills/demo" "$H/profiles/personal" "$H/skills/notes" "$H/memories" \
           "$H/hermes-agent/venv/bin" "$H/hermes-agent/hermes_cli" "$H/bin" "$H/desktop-plugins/hello" \
           "$H/logs" "$FAKE_HOME/.local/bin" "$FAKE_HOME/.local/state/hermes/gateway-locks" "$FAKE_HOME/.config/Hermes"
  cat > "$H/config.yaml" <<'Y'
model:
  default: hermes-4-405b
  provider: nous
agent:
  personality: "You are Hermes Agent, built by Nous Research."
telemetry:
  shared_metrics: {enabled: true, send: true}
Y
  printf 'NOUS_API_KEY=fake-hermes-key\n' > "$H/.env"
  printf 'You are Hermes Agent, built by Nous Research.\n' > "$H/SOUL.md"
  printf 'model:\n  default: work-model\n' > "$H/profiles/work/config.yaml"
  printf -- '---\nname: demo\n---\nHermes work-profile skill\n' > "$H/profiles/work/skills/demo/SKILL.md"
  printf 'model:\n  default: personal-model\n' > "$H/profiles/personal/config.yaml"
  printf 'work\n' > "$H/active_profile"
  printf 'Hermes long-term memory entry\n' > "$H/memories/MEMORY.md"
  printf -- '---\nname: notes\n---\nHermes skill\n' > "$H/skills/notes/SKILL.md"
  printf '{"schemaVersion":1,"pinnedCommit":"61b7f957bac7fa25c7c22d54e4b215fa446e5331","pinnedBranch":"main"}\n' \
    > "$H/hermes-agent/.hermes-bootstrap-complete"
  printf '# fake hermes core\n' > "$H/hermes-agent/hermes_cli/main.py"
  printf '#!/bin/sh\necho "fake hermes updater"\n' > "$H/bin/hermes-updater"; chmod 755 "$H/bin/hermes-updater"
  printf '{"name":"hello"}\n' > "$H/desktop-plugins/hello/package.json"
  printf 'hermes gateway log line\n' > "$H/logs/gateway.log"
  printf '{"window":"hermes"}\n' > "$FAKE_HOME/.config/Hermes/window-state.json"
  printf '#!/bin/sh\necho "Hermes Agent v2026.9.24 (fake, from ~/.hermes)"\n' > "$H/hermes-agent/venv/bin/hermes"
  chmod 755 "$H/hermes-agent/venv/bin/hermes"
  ln -s "$H/hermes-agent/venv/bin/hermes" "$FAKE_HOME/.local/bin/hermes"
  printf '#!/bin/sh\necho fake hermes-acp\n' > "$FAKE_HOME/.local/bin/hermes-acp"; chmod 755 "$FAKE_HOME/.local/bin/hermes-acp"
  cp "$HERE/fake_hermes_gateway.py" "$H/hermes-agent/fake_gateway.py"

  # The "running Hermes gateway" starts before the snapshot and never writes afterwards.
  ( hermes_env; cd "$H"; nohup setsid "$PY" "$H/hermes-agent/fake_gateway.py" "$HERMES_PORT" >/dev/null 2>&1 & echo $! > "$H/gateway.pid" )
  for _ in $(seq 1 50); do curlq "http://127.0.0.1:$HERMES_PORT/" >/dev/null 2>&1 && break; sleep 0.2; done
  local pid; pid=$(cat "$H/gateway.pid")
  echo "fake Hermes gateway pid $pid on :$HERMES_PORT -> $(curlq "http://127.0.0.1:$HERMES_PORT/")"
  echo "$pid $(awk '{print $22}' /proc/"$pid"/stat) $(tr '\0' ' ' < /proc/"$pid"/cmdline)" > "$ISO/hermes-proc.before"
  ( hermes_env; hermes ) > "$ISO/hermes-cli.before"
  sleep 1
  # shellcheck disable=SC2046
  "$PY" "$HERE/snapshot.py" "$ISO/hermes.before.json" $(protected_paths) | tee "$ISO/snapshot.before.txt"
}

install() {
  ( hermes_env
    cd /
    sh "$REPO/scripts/install.sh" --core-only ) 2>&1 | tee "$ISO/install.log"
}

verify() {
  local fail=0 pid owner resp
  # shellcheck disable=SC2046
  "$PY" "$HERE/snapshot.py" "$ISO/hermes.after.json" $(protected_paths) | tee "$ISO/snapshot.after.txt"
  if cmp -s "$ISO/hermes.before.json" "$ISO/hermes.after.json"; then
    echo "PASS ~/.hermes + hermes shims byte-identical (sha256, mode, size, mtime, ctime of every entry)"
  else
    echo "FAIL ~/.hermes changed:"; diff "$ISO/hermes.before.json" "$ISO/hermes.after.json" | head -40; fail=1
  fi
  pid=$(awk '{print $1}' "$ISO/hermes-proc.before")
  echo "$pid $(awk '{print $22}' /proc/"$pid"/stat 2>/dev/null || echo gone) $(tr '\0' ' ' < /proc/"$pid"/cmdline 2>/dev/null)" > "$ISO/hermes-proc.after"
  if cmp -s "$ISO/hermes-proc.before" "$ISO/hermes-proc.after"; then
    echo "PASS Hermes gateway pid $pid alive, same start time + cmdline: $(cut -d' ' -f3- "$ISO/hermes-proc.after")"
  else
    echo "FAIL Hermes gateway process changed"; cat "$ISO/hermes-proc.before" "$ISO/hermes-proc.after"; fail=1
  fi
  owner=$("$PY" "$HERE/port_owner.py" "$HERMES_PORT")
  if [ "$owner" = "$pid" ]; then echo "PASS :$HERMES_PORT still owned by the Hermes gateway only (pid $owner)"
  else echo "FAIL :$HERMES_PORT owner is '${owner:-none}', expected $pid"; fail=1; fi
  resp=$(curlq "http://127.0.0.1:$HERMES_PORT/" || true)
  echo "     Hermes gateway answers: $resp"
  ( hermes_env; hermes ) > "$ISO/hermes-cli.after"
  if cmp -s "$ISO/hermes-cli.before" "$ISO/hermes-cli.after"; then echo "PASS \`hermes\` still the Hermes shim: $(cat "$ISO/hermes-cli.after")"
  else echo "FAIL \`hermes\` output changed"; fail=1; fi
  if ( hermes_env; command -v neovarch ) >/dev/null; then
    echo "PASS neovarch on PATH: $( (hermes_env; command -v neovarch) ) -> $(readlink "$FAKE_HOME/.local/bin/neovarch")"
    echo "     $( (hermes_env; neovarch --version) | head -n1)"
  else echo "FAIL neovarch not on PATH"; fail=1; fi
  if ls "$FAKE_HOME/.neovarch/neovarch-agent/venv/bin/" | grep -q '^hermes'; then echo "FAIL a hermes* entry point was installed"; fail=1
  else echo "PASS no hermes* entry point in the Neovarch venv"; fi
  return $fail
}

uninstall() {
  local fail=0
  ( hermes_env; cd /; sh "$REPO/scripts/install.sh" --uninstall ) 2>&1 | tee "$ISO/uninstall.log"
  if [ -e "$FAKE_HOME/.neovarch" ] || [ -L "$FAKE_HOME/.local/bin/neovarch" ]; then echo "FAIL Neovarch files left behind"; fail=1
  else echo "PASS uninstall removed ~/.neovarch and the neovarch shim"; fi
  # shellcheck disable=SC2046
  "$PY" "$HERE/snapshot.py" "$ISO/hermes.after-uninstall.json" $(protected_paths)
  if cmp -s "$ISO/hermes.before.json" "$ISO/hermes.after-uninstall.json"; then echo "PASS ~/.hermes + hermes shims byte-identical after uninstall"
  else echo "FAIL uninstall changed Hermes files"; diff "$ISO/hermes.before.json" "$ISO/hermes.after-uninstall.json" | head -20; fail=1; fi
  [ "$("$PY" "$HERE/port_owner.py" "$HERMES_PORT")" = "$(awk '{print $1}' "$ISO/hermes-proc.before")" ] \
    && echo "PASS Hermes gateway still owns :$HERMES_PORT after uninstall" || { echo "FAIL Hermes gateway gone after uninstall"; fail=1; }
  return $fail
}

case "${1:-}" in
  setup) setup ;;
  uninstall) uninstall ;;
  install) install ;;
  verify) verify ;;
  stop) pkill -f "$FAKE_HOME/.hermes/hermes-agent/fake_gateway.py" || true ;;
  *) echo "usage: $0 setup|install|verify|uninstall|stop"; exit 2 ;;
esac
