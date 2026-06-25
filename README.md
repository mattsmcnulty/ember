# ember 🔥

A bespoke, native **iOS app + local bridge** that fully controls a **Sun Home Eclipse 2**
infrared sauna — replacing the cloud-only OEM "Sun Home" app with a polished, private,
**local-first** experience: live Lock-Screen temperature (Live Activity), one-screen
heat / light / timer / audio control, get-in/get-out session logging, and Apple Health.

> Personal project. ember controls **one specific sauna on its owner's own network**.
> Nothing reverse-engineered ships in the app; the device key is per-user config kept out
> of git. See [Legal & scope](#legal--scope).

---

## Status

| Area | State |
|---|---|
| Local control (power, heater, target, timer, chromotherapy, interior lights, Sonos) | ✅ working on device (iPhone 16 Pro Max, iOS 26) |
| Live Activity (Lock Screen + Dynamic Island) — live temp via APNs, heat dial, status, chroma accent, session counter | ✅ |
| Session logging + Apple Health (`HKWorkout`) | ✅ |
| Remote access away from home | 🔜 next: outbound **MQTT relay** (no VPN, no open ports) |
| Illustrated sauna hero art · HealthKit→WHOOP single-source · TestFlight distribution | ⏸ deferred |

The full phased plan lives in `/.claude/plans/` (or ask). The reverse-engineering scratch
(`tools/phase0/`) is gitignored and kept only as a re-extraction safety net.

---

## Why it exists

The stock Sun Home app (a rebrand of the Edge Theory Labs / Tuya OEM app) is **cloud-only**
and lacks a Live Activity, logging, Health, scheduling, and any unified control of the
sauna's lighting alongside the cabin's new Sonos audio. ember does all of that **without
depending on Sun Home's cloud** — control happens locally over your LAN, and only the
background temperature push rides the internet (via Apple's APNs).

---

## Architecture

Three components. The iOS app **never speaks Tuya** — it only talks to `emberd` over HTTP.

```
┌────────────┐   HTTP/JSON (LAN; MQTT relay later)   ┌─────────────────────┐  Tuya LAN v3.5   ┌──────────┐
│  ember     │  GET /state   POST /control           │  emberd             │  TCP 6668        │  Sauna   │
│  iOS app   │ ───────────────────────────────────▶  │  Python on the      │  (single conn,   │  Tuya    │
│ (SwiftUI)  │ ◀───────────────────────────────────  │  Homebridge Pi      │  reconnect/poll) │  ESP32   │
└────┬───────┘   POST /activity/token (push token)    └──────────┬──────────┘ ───────────────▶ │ @ .1.12  │
     │                                                           │ HTTP/2 + APNs .p8            └──────────┘
     │  Live Activity (Lock Screen / Dynamic Island)             ▼
     │ ◀──────────────────────  APNs  ◀───────────────  api.push.apple.com
     ▼
  On-device session counter (Text(timerInterval:)) — self-updating, no network
```

- **`ember/`** — SwiftUI app (iOS 26, Swift 6). Talks only to emberd; renders the Live Activity.
- **`emberd/`** — Python (FastAPI + [tinytuya](https://github.com/jasonacox/tinytuya)) bridge on
  the Raspberry Pi. **Sole owner** of the sauna's single Tuya LAN socket; exposes a small HTTP
  API; pushes Live Activity updates via APNs; controls the cabin **Sonos** ("Sauna") via `soco`.
  Full setup + API in [`emberd/README.md`](emberd/README.md).
- **The sauna** — a Tuya Wi-Fi controller speaking the **Tuya LAN protocol v3.5** (AES-GCM,
  session-key handshake), on TCP port 6668.

**Why a bridge at all:** iOS won't let an app poll a LAN device in the background often enough
to drive a live readout, and APNs (the only reliable background path for a Live Activity) can't
be reached peer-to-peer on the LAN. emberd polls the sauna and pushes updates — and because the
device allows **only one** local connection at a time, having a single always-on owner is
mandatory, not optional. It also keeps the shipped app pure-Swift with **no Tuya crypto**.

---

## The hard parts (where the work actually was)

This device did not want to be controlled. Roughly in the order we fought them:

### 1. Getting the `localKey` (the gate)
Tuya LAN control is impossible without the device's 16-byte `localKey`, and the sauna **never
appears in Smart Life** (it's provisioned to the OEM app's isolated Tuya account). cert-pinned,
app-encrypted traffic killed the proxy approach. What worked: an **Android emulator + Frida**,
hooking the live `com.thingclips.smart.sdk.bean.DeviceBean` inside the Sun Home APK to read the
key out of runtime memory — **no re-pair**, so the OEM account/app stayed intact. The key + the
~8 GB toolchain stay out of the app entirely; the key is per-user config in a gitignored file.

### 2. Tuya LAN protocol v3.5
v3.5 isn't the simpler 3.3 — it does an AES-GCM session-key handshake. `tinytuya` handles it,
but it means emberd must hold a live, authenticated socket and can't just fire-and-forget.

### 3. The device lies about its own state (momentary toggles)
**`power` (DP110) and `heater` (DP114) are momentary toggles, not levels** — *writing* them
flips the current state regardless of the value sent. In early mapping we only ever sent the
opposite value, so they looked like normal booleans. The bug surfaced as "tap **Start** → sauna
turns *off*": Start sent `power: true` while power was already on, which toggled it off. Fix:
emberd drives by **desired state** — it reads the real status (`power`'s true status is the
read-only **DP20**, not DP110) and only writes when the state must change.

### 4. The persistent socket drifts stale
A long-lived Tuya socket on this device starts returning **stale/partial frames** — the
temperature would update while `power`/`heater` froze at an old value, so the app faithfully
showed "off" while the sauna was on and heating. A *fresh* connection always reads correctly,
so emberd now **reconnects every poll** (still single-owner, never two sockets at once).

### 5. Poll-vs-control races
The app polls `/state` every 2 s and also issues optimistic control writes. A poll already in
flight when you tapped a button would land a beat later and overwrite the fresh result with
stale data. Fixed with a **control epoch** (a poll whose epoch changed mid-flight is discarded)
plus a **busy guard** and emberd **optimistically reflecting accepted writes** so `/control`
never returns a transiently-stale value.

### 6. The chromotherapy palette: panel order ≠ DP values
The ceiling LED's panel **cycle order is not the DP21 value order** — which sent us in circles
mapping it by ear. The real DP21 map (verified hands-on, below) has only 7 solid colors;
`mode1` is a no-op and `mode8`/`mode9` read back white. The app now ships the true palette and a
shared `ChromaPalette` used by both the app and the Live Activity accent.

### 7. "Footwell" is actually all interior lights
Over the **LAN**, writing **DP113 toggles *all* interior lights** (ceiling chroma + footwell)
together — but the **panel's** footwell button (same DP) only affects the footwell, as hardware.
So there's no footwell-only control via the API; the app surfaces DP113 as **"Interior."**

### 8. Power and heat are two independent things
The UI originally mushed them into one "Start Heating / Stop." They're independent and both are
stable states, so the app now has a small **Power** toggle (top-left) plus the big **Heat**
button: Start auto-powers on, Stop fully powers off, and Power is the independent override.

### 9. We mapped it all hands-on with an in-app Debug tab
Once it was clear the device's behavior was subtle, we shipped a temporary **Debug DP tab**
(every raw DP live + a generic "set DP N = value" pad) so the human at the sauna could poke and
annotate directly. That's how the palette, DP113, and the toggle behavior were nailed down. It
stays in the app until everything's confirmed, then gets removed.

Also handled along the way: APNs token-auth Live Activities (`.p8` / ES256 JWT, per-activity +
push-to-start tokens), Swift 6 strict-concurrency around ActivityKit, and a heater "deadman"
safety option in emberd.

---

## DP map (reference)

Verified live, 2026-06. Full detail + types in [`emberd/schema.json`](emberd/schema.json).

| DP | Meaning | Type | Notes |
|---|---|---|---|
| **110** | power (control) | bool — **momentary toggle** | a write *flips* power; drive by desired state |
| **20** | power **status** | bool, read-only | the real on/off (use this to read power) |
| **114** | heater | bool — momentary toggle | the heating element |
| **106** / 109 | target temp °F / °C | int | setpoint (109 is the °C mirror) |
| **104** / 103 | current temp °F / °C | int, read-only | |
| **116** | timer set | int (min) | writable |
| **105** | timer remaining | int (min), read-only | counts down while heating |
| **108** | unit | enum `f`/`c` | |
| **113** | interior lights | bool | LAN write = **all interior** (chroma + footwell); panel button = footwell-only |
| **21** | chroma color | enum | `mode`=white · `mode2`=yellow · `mode3`=red · `mode4`=pink · `mode5`=blue · `mode6`=teal · `mode7`=green (`mode1` no-op, `mode8/9` white) |
| **101** | rainbow | bool | slow morphing scene; turning it off resets to white |
| 111 | *(vestigial)* | int | old Bluetooth-audio volume; unused (audio is via Sonos) — ignore |
| — | exterior light | — | **panel-only — not in the Tuya protocol**, can't be controlled |

---

## Repo layout

```
ember/                         # iOS app (SwiftUI, iOS 26, Swift 6) — xcodegen project
├── project.yml                #   xcodegen spec (targets, signing, entitlements)
├── Sources/
│   ├── App/emberApp.swift
│   ├── Views/                 #   RootTabView (Control · Log · Debug), Control/Log/Settings/DebugView
│   ├── Models/                #   SaunaState, SaunaStore (@Observable polling + optimistic + epoch guard),
│   │                          #   AppSettings (UserDefaults), SaunaSession (SwiftData)
│   ├── Net/EmberClient.swift  #   async URLSession client to emberd
│   ├── Activity/              #   SaunaActivityController — Live Activity + APNs token registration
│   ├── Health/                #   HealthKitManager (HKWorkout)
│   └── Design/Theme.swift     #   warm dark design system
├── Shared/                    #   SaunaActivityAttributes (ContentState), ChromaPalette  (app + widget)
├── Widget/emberWidget.swift   #   Live Activity UI (Lock Screen + Dynamic Island)
└── Assets.xcassets            #   AppIcon

emberd/                        # Python bridge (FastAPI + tinytuya + soco + APNs) — see emberd/README.md
├── app.py  sauna.py  apns.py  sonos.py  config.py  schema.json
├── options.example.json       #   template; real options.json (localKey, apiKey, APNs) is gitignored
└── deploy/                     #   install-native.sh + emberd.service (systemd on the Pi)
```

Secrets — the `localKey`, the server `apiKey`, and the APNs `.p8` — live in **gitignored**
files (`emberd/options.json`, `tools/phase0/devices.json`, `*.p8`). Never committed.

---

## Build & run

### emberd (the bridge)
See [`emberd/README.md`](emberd/README.md). Short version: copy `emberd/` to the Pi, fill in
`options.json` (`sauna.devId` / `sauna.localKey`, a long random `server.apiKey`, and optionally
the APNs block), then `sudo bash deploy/install-native.sh` and `curl http://localhost:8765/state`.

### ember (the iOS app)
Requires Xcode 26, [xcodegen](https://github.com/yonaskolb/XcodeGen), and an Apple Developer
account (for on-device runs + APNs). The `.xcodeproj` is generated (gitignored).

```bash
cd ember
export DEVELOPMENT_TEAM=YOURTEAMID          # your Apple Developer Team ID — xcodegen reads it
xcodegen generate
# build + install to a connected, Developer-Mode-enabled iPhone (automatic signing):
xcodebuild -project ember.xcodeproj -scheme ember \
  -destination 'platform=iOS,id=<DEVICE_UDID>' -allowProvisioningUpdates -derivedDataPath build build
xcrun devicectl device install app --device <DEVICE_ID> build/Build/Products/Debug-iphoneos/ember.app
```

**Build it yourself:** set `DEVELOPMENT_TEAM` (above — add it to your shell profile or use direnv
so you don't repeat it), and change the bundle-id prefix in `project.yml` (`com.mattmcnulty` → your
own reverse-domain). Then sign into your Apple ID in Xcode, enable **Developer Mode** on the iPhone
(Settings → Privacy & Security), trust the developer profile, and in the app's **Settings** point it
at emberd's address + paste the `apiKey`.

> Because this is a **development** build, the iPhone needs **Developer Mode** on to install
> *and* run it, and the signing profile expires periodically. The planned escape hatch is
> **TestFlight** (runs without Developer Mode; 90-day build refresh).

---

## Remote access (planned)

Live temperature (the Live Activity) **already works anywhere** — APNs delivers it over the
internet with nothing exposed. Interactive *control* away from home is the next phase: an
**outbound MQTT relay** (emberd dials out to a free TLS broker; the app talks to the broker;
nothing inbound is opened, no VPN, no domain), with the app preferring the snappy LAN path when
home and falling back to the relay when away. Design is in the plan file.

---

## Legal & scope

This is a **personal interoperability project** for a device its owner owns, on their own
network — much like the local-control tooling thousands of Home Assistant users run. The shipped
iOS app contains **no reverse-engineered or proprietary code**: it's clean original Swift, emberd
uses the open-source `tinytuya`, and the `localKey` is per-user config you supply (extracted from
your *own* device), never bundled. It is **not** an App Store product — that would require an
official Tuya/Sun Home integration path, since OEM-locked devices can't be linked to a
third-party Tuya cloud project. Don't use Sun Home / Tuya / Eclipse names or logos in any
distributed build.

**⚠️ Safety & no warranty.** ember controls a **heating appliance**. It's provided as-is under the
MIT license with **no warranty** — use at your own risk, and never rely on it as a safety cutoff
(the sauna's own timer and thermostat remain the primary controls). Not affiliated with, endorsed
by, or connected to Sun Home Saunas, Edge Theory Labs, or Tuya.

---

## Roadmap

1. **Phase 2 — MQTT relay** for secure remote control (next).
2. **Phase 3** — illustrated sauna hero on the Control tab (needs art).
3. **Phase 4** — HealthKit single-source so WHOOP imports sessions cleanly (one `HKWorkout`,
   no Mindful Minutes, with a Settings toggle).
4. **Wrap-up** — TestFlight distribution (so Developer Mode can be turned back off); remove the
   Debug tab; optional Homebridge plugin to expose the sauna to Apple Home + Siri.
```
