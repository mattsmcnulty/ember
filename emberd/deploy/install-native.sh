#!/usr/bin/env bash
# Native (no-Docker) install of emberd as a systemd service.
# Recommended for the Homebridge Raspberry Pi image (runs Homebridge via systemd, no Docker).
# Run from inside the emberd/ folder ON THE PI:  sudo bash deploy/install-native.sh
set -euo pipefail

DEST=/opt/emberd
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
  echo "!! For Live Activities (APNs) on this native install, copy your AuthKey.p8 into $DEST and set"
  echo "   apns.p8Path to $DEST/AuthKey.p8 (the /data/... default is Docker-only)."
fi

# python venv + deps (apt: python3-venv must be present; on Raspberry Pi OS: sudo apt install -y python3-venv)
python3 -m venv "$DEST/.venv"
"$DEST/.venv/bin/pip" install --quiet --upgrade pip
"$DEST/.venv/bin/pip" install --quiet -r "$DEST/requirements.txt"

chown -R "$SVC_USER":"$SVC_USER" "$DEST"

sed "s/__USER__/$SVC_USER/" "$HERE/deploy/emberd.service" > /etc/systemd/system/emberd.service
systemctl daemon-reload
systemctl enable --now emberd

echo ">> done. status:"
systemctl --no-pager status emberd | head -12 || true
echo ">> test:  curl http://localhost:8765/state"
