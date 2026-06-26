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
fill in `sauna.devId` / `sauna.localKey` / `sauna.ip`. Don't have your device's key yet? See
[**Getting your `localKey`**](../README.md#getting-your-localkey) in the root README.
`options.json` is **gitignored** — it holds the localKey + apiKey.

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

### Option B — Docker (Linux host only — e.g. a stock Pi)
```
cp options.example.json options.json   # create + fill it in FIRST (else Docker makes a dir at the mount)
docker compose up -d --build
curl http://localhost:8765/state
```
Requires a **Linux** host: the container uses host networking for Tuya/Sonos multicast, which
Docker Desktop on macOS doesn't support — on a Mac, use the native uvicorn dev run below instead.

> ⚠ **Single connection:** don't run any other local Tuya client against the sauna
> (HA `tuya-local`, a second script), and keep the OEM Sun Home app closed during local use.

## Security & safety
`/control` can **turn the heater on** — treat the API as privileged:
- **Set `server.apiKey`** to a long random string. emberd then requires `Authorization: Bearer
  <apiKey>` on all mutating endpoints (`/control`, `/audio`, `/session/*`, `/activity/*`);
  `/state` and `/health` stay open. `null` = **auth off (dev only)** — anyone who can reach the
  port can power on the heater, and emberd logs a WARNING on every startup. `install-native.sh`
  generates a random key for fresh installs; the example ships `null`, and the server refuses to
  start if it sees the literal example placeholder.
- **`server.debugEndpoints`** (default `false`) gates `/debug/raw` (raw DP dump) and `/debug/set`
  (arbitrary DP write). Keep it off in production; both are also auth-gated and return 404 when off.
- emberd binds `0.0.0.0:8765`. Keep it on a trusted LAN/VLAN; firewall tcp/8765 to your subnet,
  and reach it remotely via Tailscale / a relay — **never** a port-forward.
- `targetTempF` is clamped to 60–175 °F and `timerMin` to 0–360 at the API.
- **Deadman** (`server.heaterMaxOnMinutes`, default **120**): auto-offs the heater if left on past
  that many minutes. Best-effort only — it can't fire if emberd or the LAN is down, so the sauna's
  own timer/thermostat remains the primary cutoff. Set `null` to disable.

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
| GET | `/debug/raw` | — | raw DP dump — debug-only (`server.debugEndpoints: true` + auth) |
| POST | `/debug/set` | `{dp, value}` | arbitrary DP write — debug-only (`debugEndpoints` + auth) |

`chromoColor` is a `modeN` enum — `mode`=white and `mode2`–`mode7` are the solid colors (the panel
cycle order differs; see the DP map in the root README / `schema.json`). The **exterior light is
panel-only** and not controllable.

## Live Activities (APNs) — optional, add later
Needs an Apple Developer account. Then set `apns.enabled=true` in `options.json` with:
- **`.p8` auth key** — Apple Developer → *Certificates, Identifiers & Profiles* → **Keys** → **+**,
  enable *Apple Push Notifications service*, download the `.p8` **once**. On **Docker**, mount it at
  `/data/AuthKey.p8` (uncomment the volume in `compose.yaml`); on a **native** install, copy it into
  `/opt/emberd` and set `apns.p8Path` to e.g. `/opt/emberd/AuthKey.p8` (the `/data/...` default is
  Docker-only).
- **`keyId`** — the 10-char Key ID on that key (also in the filename `AuthKey_<keyId>.p8`).
- **`teamId`** — your 10-char Apple Team ID (Membership page).
- **`bundleId`** — must exactly match the iOS app's bundle id (the one you set in `project.yml`).
- **`sandbox`** — `true` for dev/Xcode-installed builds (this project's default), `false` only for
  TestFlight/App Store. A wrong value yields silent `BadDeviceToken` 400s and no temperature updates.

emberd pushes temperature updates to registered Live Activities at `apns-priority: 5`.

## Dev / local run (Mac)
```
python -m venv .venv && .venv/bin/pip install -r requirements.txt
EMBERD_OPTIONS=./options.json .venv/bin/uvicorn app:app --port 8765
```
(`network_mode: host` is a Linux/Pi feature; for Sonos testing on a Mac run uvicorn directly.)

## Troubleshooting
- **`/state` shows `online: false`** — the device isn't answering. Confirm it's reachable on its IP
  (tcp/6668), check `sauna.localKey` + `version: 3.5`, and watch `journalctl -u emberd -f` for
  `Err 914 / ERR_KEY_OR_VER` (wrong key/version — the usual cause; it only shows in the log, not in
  `/state`).
- **Worked, then stopped** — the `localKey` probably **rotated** (re-pairing, or some OEM-app
  actions). Re-extract it (root README) and update `options.json`.
- **Intermittent / frozen values** — something else is holding the single Tuya connection. Close the
  OEM Sun Home app and any second client (HA `tuya-local`, a stray script); only emberd may talk to
  the sauna.
- **Sonos "speaker not found"** — `sonos.name` must match the room name, and emberd must share the
  speaker's L2/multicast segment (host networking — not bridged Docker or a Mac dev run).
- **401 on control** — the app's key ≠ `server.apiKey`. **404 on `/debug/*`** — set
  `server.debugEndpoints: true` to enable them.

---
Personal interoperability project, provided as-is with **no warranty** — it controls a heating
appliance, use at your own risk. Not affiliated with Sun Home Saunas, Edge Theory Labs, or Tuya.
