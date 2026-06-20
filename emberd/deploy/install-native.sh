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
  echo "!! Edit $DEST/options.json and fill in sauna.devId / sauna.localKey before starting."
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
