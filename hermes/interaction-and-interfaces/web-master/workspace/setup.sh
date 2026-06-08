#!/usr/bin/env bash
#
# Build-time setup for the Hermes Web Master template.
# Runs in the agent container at deploy time (invoked from manifest `scripts.build`).
# Installs the headless browser the agent uses to look at websites, and works
# around a Hermes engine bug that makes browser_vision (screenshots) time out.
#
set -euo pipefail

# --- Headless browser (agent-browser + Chrome) --------------------------------
# `npm install -g` defaults to a prefix the container won't let us write, so point
# it at $HOME first. `agent-browser install` then downloads a Chrome to drive.
npm config set prefix "$HOME/.npm-global"
npm install -g agent-browser
"$HOME/.npm-global/bin/agent-browser" install

# Hermes loads this .env at boot.
#  - PATH: so the agent can find agent-browser (and other global tools) in its terminal.
#  - AGENT_BROWSER_ARGS: Chrome needs no-sandbox to run headless inside the container.
grep -q '^PATH=' "$HERMES_HOME/.env" 2>/dev/null \
  || echo "PATH=$HOME/.npm-global/bin:$PATH" >> "$HERMES_HOME/.env"
grep -q '^AGENT_BROWSER_ARGS=' "$HERMES_HOME/.env" 2>/dev/null \
  || echo 'AGENT_BROWSER_ARGS=--no-sandbox,--disable-setuid-sandbox' >> "$HERMES_HOME/.env"

# --- browser_vision fix (engine workaround) -----------------------------------
# The Hermes engine resolves the `agent-browser` CLI from $HERMES_HOME/node/bin
# first, and may pass a `--full` flag to its `screenshot` command. On heavy JS
# pages `--full` can make Chrome's full-page capture hang, so browser_vision
# times out at 30s. We can't edit the engine (it's a separate Docker build), so
# we drop a thin shim on that lookup path: it forwards every call to the real
# agent-browser and strips `--full`. Remove this once the engine stops sending
# `--full`.
#
# Unquoted heredoc: $HOME is baked to the real install path now; the runtime vars
# (\$@, \$a, \${args[@]}) are escaped so they stay literal in the generated script.
mkdir -p "$HERMES_HOME/node/bin"
cat > "$HERMES_HOME/node/bin/agent-browser" <<WRAPPER
#!/usr/bin/env bash
args=()
for a in "\$@"; do
  [ "\$a" = "--full" ] && continue
  args+=("\$a")
done
exec "$HOME/.npm-global/bin/agent-browser" "\${args[@]}"
WRAPPER
chmod +x "$HERMES_HOME/node/bin/agent-browser"
