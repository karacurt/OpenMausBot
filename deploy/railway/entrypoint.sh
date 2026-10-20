#!/bin/bash
# Runs as root: brings up Tailscale, publishes the server to the tailnet only,
# then runs OpenMausBot as the unprivileged `maus` user. If either process
# exits, the container exits so Railway restarts it.
set -euo pipefail

TS_HOSTNAME="${TS_HOSTNAME:-maus}"
TS_STATE=/data/.tailscale
TS_SOCK=/var/run/tailscale/tailscaled.sock
OMB_PORT="${OMB_PORT:-8799}"

log() { echo "[railway-entrypoint] $*"; }

# Railway mounts the volume root-owned; HOME (/data) belongs to maus.
mkdir -p /data/.openmausbot "$TS_STATE" "$(dirname "$TS_SOCK")"
chown maus:maus /data /data/.openmausbot
# Tailscale node key: root only, never readable by the bots.
chown root:root "$TS_STATE"
chmod 0700 "$TS_STATE"

tailscaled --tun=userspace-networking --statedir="$TS_STATE" --socket="$TS_SOCK" &
TS_PID=$!

for _ in $(seq 1 60); do [ -S "$TS_SOCK" ] && break; sleep 0.5; done
[ -S "$TS_SOCK" ] || { log "tailscaled did not start"; exit 1; }

ts_state() { tailscale --socket="$TS_SOCK" status --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log(j.BackendState+" "+(j.Self&&j.Self.DNSName||"").replace(/\.$/,""))}catch{console.log("unknown ")}})'; }

# Give a persisted login a moment to reconnect before asking for a key.
for _ in $(seq 1 20); do
  state="$(ts_state)"; case "$state" in Running*|NeedsLogin*) break;; esac; sleep 0.5
done

if [[ "$(ts_state)" != Running* ]]; then
  if [ -z "${TS_AUTHKEY:-}" ]; then
    log "Tailscale is not logged in and TS_AUTHKEY is empty; set it on the Railway service"
    exit 1
  fi
  log "joining the tailnet as $TS_HOSTNAME"
  tailscale --socket="$TS_SOCK" up --auth-key="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" --accept-dns=false
fi

for _ in $(seq 1 60); do [[ "$(ts_state)" == Running* ]] && break; sleep 1; done
read -r BACKEND DNS_NAME <<<"$(ts_state)"
[ "$BACKEND" = Running ] && [ -n "${DNS_NAME:-}" ] || { log "tailscale not running (state=$BACKEND dns=${DNS_NAME:-none}); is MagicDNS on?"; exit 1; }

# Tailnet-only HTTPS -> loopback server. Tailscale adds X-Forwarded-For, so the
# server treats these requests as remote and requires pairing.
tailscale --socket="$TS_SOCK" serve --bg --https=443 "http://127.0.0.1:${OMB_PORT}"
log "tailnet address: https://${DNS_NAME}"

setpriv --reuid=maus --regid=maus --init-groups \
  env -u TS_AUTHKEY HOME=/data \
  node /app/dist-server/openmausbot.js serve --port "$OMB_PORT" --public-url "https://${DNS_NAME}" --label railway &
OMB_PID=$!

trap 'kill -TERM "$OMB_PID" "$TS_PID" 2>/dev/null; wait' TERM INT
set +e
wait -n "$OMB_PID" "$TS_PID"
code=$?
log "a process exited (code $code); stopping the container so Railway restarts it"
kill -TERM "$OMB_PID" "$TS_PID" 2>/dev/null
wait
exit "$code"
