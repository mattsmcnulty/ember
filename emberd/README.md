# emberd — Sun Home Eclipse 2 bridge

Tiny always-on service that owns the sauna's single Tuya LAN connection and exposes
a simple HTTP API for the **ember** iOS app. Also controls the cabin **Sonos** ("Sauna")
and pushes **Live Activity** updates via **APNs**. Designed to run as a Docker container
on the **Homebridge Raspberry Pi**.

## Why a bridge
iOS can't poll a LAN device in the background often enough to drive a live Lock-Screen
temperature, and APNs (the only reliable background path for Live Activities) can't be
reached on the LAN. emberd polls the sauna and pushes updates; it's also the **sole owner**
of the Tuya connection (the device allows only one local connection at a time).

## Setup

First, on any machine: copy `emberd/` to the Pi, then `cp options.example.json options.json` and
fill in `sauna.devId` / `sauna.localKey` (from Phase 0; see repo `tools/phase0/devices.json`).
`options.json` is **gitignored** — it holds the localKey.

### Option A — native systemd (recommended for the Homebridge Pi)
The official **Homebridge Raspberry Pi image runs natively (systemd), with no Docker**, so don't
assume `docker` is present (`which docker` to check). Run emberd as a plain systemd service
alongside Homebridge — lighter, and co-located for the future Homebridge→HomeKit plugin:
```
sudo apt install -y python3-venv     # if needed
sudo bash deploy/install-native.sh   # creates /opt/emberd venv + enables the emberd.service
curl http://localhost:8765/state
```
Manage it: `systemctl status|restart|stop emberd`, logs via `journalctl -u emberd -f`.

### Option B — Docker (for a stock Pi / the AdGuard box, if you prefer containers)
```
docker compose up -d --build
curl http://localhost:8765/state
```

> ⚠ **Single connection:** don't run any other local Tuya client against the sauna
> (HA `tuya-local`, a second script), and keep the OEM Sun Home app closed during local use.

## HTTP API
| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/state` | — | normalized state (temps, power, heater, timer, lights, online) |
| POST | `/control` | `{power?,heater?,targetTempF?,timerMin?,chromoColor?,chromoCycle?,footwell?}` | only writable DPs |
| POST | `/audio` | `{action: play\|pause\|next\|prev\|volume, volume?}` | "Sauna" Sonos |
| POST | `/session/start` / `/session/end` | — | `end` returns `{durationSec, peakTempF}` |
| POST | `/activity/token` | `{pushToken}` | register a Live Activity for APNs updates |
| POST | `/activity/start-token` | `{pushToken}` | push-to-start token (iOS 17.2+) |
| GET | `/health` | — | liveness + online flag |

`chromoColor` ∈ `mode, mode1…mode8` (see `schema.json`). The **exterior light is panel-only**
and not controllable.

## Live Activities (APNs) — optional, add later
Needs an Apple Developer account. Create an APNs **Auth Key (.p8)**, then in `options.json`
set `apns.enabled=true` with `keyId`, `teamId`, `bundleId`, and mount the `.p8` at
`/data/AuthKey.p8` (uncomment the volume in `compose.yaml`). emberd pushes temperature
updates to registered Live Activities at `apns-priority: 5`.

## Dev / local run (Mac)
```
python -m venv .venv && .venv/bin/pip install -r requirements.txt
EMBERD_OPTIONS=./options.json .venv/bin/uvicorn app:app --port 8765
```
(`network_mode: host` is a Linux/Pi feature; for Sonos testing on a Mac run uvicorn directly.)
