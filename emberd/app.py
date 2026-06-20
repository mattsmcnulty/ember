"""emberd — local bridge for the Sun Home Eclipse 2.

Owns the single Tuya LAN connection (sauna.py), exposes a small HTTP API for the
ember iOS app, controls the 'Sauna' Sonos (sonos.py), and pushes Live Activity
updates to APNs (apns.py). Runs as a Docker container on the Homebridge Pi.
"""
import asyncio
import contextlib
import logging
import time
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

import config
from sauna import SaunaClient
from sonos import SonosController

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("emberd")

OPTS = config.load()
_s = OPTS["sauna"]
sauna = SaunaClient(
    ip=_s["ip"], dev_id=_s["devId"], local_key=_s["localKey"],
    version=float(_s.get("version", 3.5)),
    poll_interval=float(OPTS.get("server", {}).get("pollIntervalSec", 5)),
)
sonos = SonosController(OPTS.get("sonos", {}).get("name", "Sauna"))

# APNs is optional — only wired up once you have an Apple Developer .p8
apns = None
_apns_cfg = OPTS.get("apns", {})
if _apns_cfg.get("enabled"):
    from apns import APNsClient
    apns = APNsClient(
        key_id=_apns_cfg["keyId"], team_id=_apns_cfg["teamId"],
        p8_path=_apns_cfg["p8Path"], bundle_id=_apns_cfg["bundleId"],
        sandbox=_apns_cfg.get("sandbox", True),
    )

# in-memory state
_activity_tokens: set[str] = set()       # per-activity APNs push tokens
_push_to_start_token: Optional[str] = None
_session: Optional[dict] = None          # {"start": ts}
_last_pushed_temp: Optional[int] = None


# ---------- request models ----------
class ControlBody(BaseModel):
    power: Optional[bool] = None
    heater: Optional[bool] = None
    targetTempF: Optional[int] = None
    timerMin: Optional[int] = None
    chromoColor: Optional[str] = None
    chromoCycle: Optional[bool] = None
    footwell: Optional[bool] = None


class AudioBody(BaseModel):
    action: str            # play | pause | next | prev | volume
    volume: Optional[int] = None


class TokenBody(BaseModel):
    pushToken: str


# ---------- lifespan ----------
@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    await sauna.start()
    push_task = asyncio.create_task(_push_loop())
    log.info("emberd started (sauna %s, APNs %s)", _s["ip"], "on" if apns else "off")
    try:
        yield
    finally:
        push_task.cancel()
        await sauna.stop()
        if apns:
            await apns.close()


app = FastAPI(title="emberd", lifespan=lifespan)


# ---------- endpoints ----------
@app.get("/health")
async def health():
    return {"ok": True, "online": sauna.state()["online"]}


@app.get("/state")
async def get_state():
    st = sauna.state()
    if _session:
        st["session"] = {
            "active": True,
            "startedAt": _session["start"],
            "elapsedSec": int(time.time() - _session["start"]),
        }
    return st


@app.post("/control")
async def control(body: ControlBody):
    st = sauna.state()
    try:
        if body.power is not None:
            st = await sauna.set_power(body.power)
        if body.targetTempF is not None:
            st = await sauna.set_target_temp(body.targetTempF)
        if body.timerMin is not None:
            st = await sauna.set_timer(body.timerMin)
        if body.heater is not None:
            st = await sauna.set_heater(body.heater)
        if body.chromoColor is not None:
            st = await sauna.set_chromo_color(body.chromoColor)
        if body.chromoCycle is not None:
            st = await sauna.set_chromo_cycle(body.chromoCycle)
        if body.footwell is not None:
            st = await sauna.set_footwell(body.footwell)
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        raise HTTPException(502, f"sauna control failed: {e}")
    return st


@app.post("/audio")
async def audio(body: AudioBody):
    try:
        return await sonos.control(body.action, body.volume)
    except Exception as e:
        raise HTTPException(502, f"sonos control failed: {e}")


@app.post("/session/start")
async def session_start():
    global _session
    _session = {"start": time.time()}
    return {"active": True, "startedAt": _session["start"]}


@app.post("/session/end")
async def session_end():
    global _session
    if not _session:
        raise HTTPException(400, "no active session")
    start = _session["start"]
    end = time.time()
    peak = sauna.peak_since(start)
    _session = None
    return {
        "startedAt": start,
        "endedAt": end,
        "durationSec": int(end - start),
        "peakTempF": peak,
    }


@app.post("/activity/token")
async def register_activity_token(body: TokenBody):
    _activity_tokens.add(body.pushToken)
    return {"registered": len(_activity_tokens)}


@app.post("/activity/start-token")
async def register_push_to_start(body: TokenBody):
    global _push_to_start_token
    _push_to_start_token = body.pushToken
    return {"ok": True}


# ---------- background APNs push ----------
async def _push_loop():
    """Push temperature updates to registered Live Activities when it changes."""
    global _last_pushed_temp
    while True:
        try:
            await asyncio.sleep(float(OPTS.get("server", {}).get("pollIntervalSec", 5)))
            if not apns or not _activity_tokens:
                continue
            st = sauna.state()
            temp = st.get("currentTempF")
            if temp is None or temp == _last_pushed_temp:
                continue
            _last_pushed_temp = temp
            content = {
                "currentTempF": temp,
                "targetTempF": st.get("targetTempF"),
                "heater": st.get("heater"),
                "power": st.get("power"),
                "timerRemainingMin": st.get("timerRemainingMin"),
                "online": st.get("online"),
            }
            dead = set()
            for tok in list(_activity_tokens):
                code = await apns.update_activity(tok, content, priority=5)
                if code in (400, 410):  # bad/expired token
                    dead.add(tok)
            _activity_tokens.difference_update(dead)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            log.warning("push loop error: %s", e)
