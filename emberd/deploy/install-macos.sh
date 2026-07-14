#!/usr/bin/env bash
# Native install of emberd as a macOS LaunchDaemon (starts at boot, no login needed).
# Run from inside the emberd/ folder ON THE MAC:  sudo bash deploy/install-macos.sh
set -euo pipefail

DEST=/opt/emberd
PLIST=/Library/LaunchDaemons/com.emberd.plist
SVC_USER="${SUDO_USER:-$(whoami)}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # the emberd/ dir

echo ">> installing emberd to $DEST (service user: $SVC_USER)"
mkdir -p "$DEST"
cp "$HERE"/*.py "$HERE"/schema.json "$HERE"/requirements.txt "$DEST"/

# options.json holds the localKey — copy if you've created it, else seed from the example
if [ -f "$HERE/options.json" ]; then
  cp "$HERE/options.json" "$DEST"/
else
  cp "$HERE/options.example.json" "$DEST/options.json"
  # generate a unique random apiKey so auth is ON by default (never ship the example placeholder)
  KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
  python3 - "$DEST/options.json" "$KEY" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
o = json.load(open(path))
o.setdefault("server", {})["apiKey"] = key
json.dump(o, open(path, "w"), indent=2)
PY
  echo "!! Edit $DEST/options.json and fill in sauna.devId / sauna.localKey before starting."
  echo "!! A random server.apiKey was generated — put this SAME key in the iOS app (Settings or Local.xcconfig):"
  echo "     $KEY"
  echo "!! For Live Activities (APNs), copy your AuthKey.p8 into $DEST and set apns.p8Path to $DEST/AuthKey.p8."
fi
if [ -f "$HERE/AuthKey.p8" ]; then
  cp "$HERE/AuthKey.p8" "$DEST"/
fi

# python venv + deps (macOS ships python3 with the Command Line Tools; brew python also works)
python3 -m venv "$DEST/.venv"
"$DEST/.venv/bin/pip" install --quiet --upgrade pip
"$DEST/.venv/bin/pip" install --quiet -r "$DEST/requirements.txt"

chown -R "$SVC_USER":staff "$DEST"
chmod 600 "$DEST/options.json"
[ -f "$DEST/AuthKey.p8" ] && chmod 600 "$DEST/AuthKey.p8"

sed "s/__USER__/$SVC_USER/" "$HERE/deploy/emberd.launchd.plist" > "$PLIST"
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

# (re)load: bootout is a no-op on first install
launchctl bootout system/com.emberd 2>/dev/null || true
launchctl bootstrap system "$PLIST"

# If the macOS Application Firewall is on, inbound :8765 needs the venv python allowed.
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
if "$FW" --getglobalstate | grep -q "enabled"; then
  PYBIN="$(readlink -f "$DEST/.venv/bin/python3" || echo "$DEST/.venv/bin/python3")"
  "$FW" --add "$PYBIN" >/dev/null || true
  "$FW" --unblockapp "$PYBIN" >/dev/null || true
  echo ">> firewall: allowed $PYBIN"
fi

echo ">> done. status:"
launchctl print system/com.emberd 2>/dev/null | grep -E "state|pid" | head -4 || true
echo ">> logs:  tail -f $DEST/emberd.log"
echo ">> test:  curl http://localhost:8765/state"
echo ">> NOTE (macOS 15+): if /state shows online:false with LAN timeouts, grant Local Network"
echo "   access to the python binary under System Settings → Privacy & Security → Local Network."
