#!/usr/bin/env bash
#
# Build-time setup for the Hermes Web Master template.
# Runs in the agent container at deploy time (invoked from manifest `scripts.build`).
# Installs the headless browser the agent uses to look at websites, and hardens
# Chrome so browser_vision (screenshots) actually works inside the container.
#
set -euo pipefail

# --- Headless browser (agent-browser + Chrome) --------------------------------
# `npm install -g` defaults to a prefix the container won't let us write, so point
# it at $HOME first. `agent-browser install` then downloads a Chrome to drive.
npm config set prefix "$HOME/.npm-global"
npm install -g agent-browser
"$HOME/.npm-global/bin/agent-browser" install

# Hermes loads this .env at boot. Rewrite the keys we manage so a re-deploy (or a
# persisted .env from an older template) always picks up the current values.
ENV_FILE="$HERMES_HOME/.env"
touch "$ENV_FILE"
set_env() { # key value -> ensure exactly one `key=value` line in .env
  grep -v "^$1=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  printf '%s=%s\n' "$1" "$2" >> "$ENV_FILE"
}

# PATH: so the agent finds agent-browser (and other global tools) in its terminal.
grep -q '^PATH=' "$ENV_FILE" \
  || echo "PATH=$HOME/.npm-global/bin:$PATH" >> "$ENV_FILE"

# Chrome launch flags (read once when the browser daemon first starts):
#  --no-sandbox / --disable-setuid-sandbox : required to run headless in the container.
#  --disable-dev-shm-usage : THE screenshot fix. The container's /dev/shm is tiny
#      (~64MB). Chrome rasters screenshots through shared memory; on a tall or
#      image-heavy page the capture overflows /dev/shm and the renderer either
#      crashes ("CDP error: Unable to capture screenshot") or stalls until the
#      engine's 30s timeout fires. This flag moves that scratch space to /tmp.
#      Same `--full` capture that hangs in the container finishes in ~1s locally,
#      which is the fingerprint of a /dev/shm limit, not a slow page.
#  --disable-gpu : no GPU in the container; avoids slow/failed GPU-raster paths.
set_env AGENT_BROWSER_ARGS '--no-sandbox,--disable-setuid-sandbox,--disable-dev-shm-usage,--disable-gpu'

# Capture as JPEG, not PNG. A full-page PNG of a heavy site is ~2.5MB; the JPEG
# is ~0.5MB. Smaller captures mean less memory pressure during raster (fewer
# failures) and a lighter image for the vision model. Quality 85 is plenty for
# reading layout and brand colors.
set_env AGENT_BROWSER_SCREENSHOT_FORMAT jpeg
set_env AGENT_BROWSER_SCREENSHOT_QUALITY 85

# --- agent-browser shim (full-page strip + diagnostics) -----------------------
# The Hermes engine resolves the `agent-browser` CLI from $HERMES_HOME/node/bin
# first. We drop a thin wrapper there that forwards to the real binary, drops the
# full-page flag, and logs every call.
#
# Why still strip full-page: the documented workflow reads a site by screenshot +
# scroll, section by section. A viewport capture is lighter and far easier for the
# vision model than a 30000px-tall full-page image, so even with the /dev/shm fix
# above we keep captures to the viewport. We strip BOTH spellings — the old shim
# only caught `--full` and let the short alias `-f` through.
#
# Why log: when a screenshot fails we currently have zero visibility into what the
# engine actually invoked. The log writes a START line before forwarding and a
# DONE line (exit code + duration) after, so a hang/kill shows up as START with no
# DONE, and an error shows up as a non-zero exit. Inspect at $AGENT_BROWSER_SHIM_LOG
# (defaults below); set it empty to disable.
#
# Unquoted heredoc: $HOME is baked to the real install path now; the runtime vars
# (\$@, \$a, \${args[@]}) are escaped so they stay literal in the generated script.
mkdir -p "$HERMES_HOME/node/bin"
cat > "$HERMES_HOME/node/bin/agent-browser" <<WRAPPER
#!/usr/bin/env bash
log="\${AGENT_BROWSER_SHIM_LOG:-$HERMES_HOME/agent-browser-shim.log}"
args=()
stripped=0
for a in "\$@"; do
  case "\$a" in
    --full|-f) stripped=1; continue ;;
  esac
  args+=("\$a")
done
[ -n "\$log" ] && printf '%s START stripped=%s in=[%s] out=[%s]\n' \
  "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "\$stripped" "\$*" "\${args[*]}" >> "\$log" 2>/dev/null || true
start=\$SECONDS
"$HOME/.npm-global/bin/agent-browser" "\${args[@]}"
code=\$?
[ -n "\$log" ] && printf '%s DONE  exit=%s dur=%ss\n' \
  "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "\$code" "\$(( SECONDS - start ))" >> "\$log" 2>/dev/null || true
exit \$code
WRAPPER
chmod +x "$HERMES_HOME/node/bin/agent-browser"
