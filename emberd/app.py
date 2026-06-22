"""emberd — local bridge for the Sun Home Eclipse 2.

Owns the single Tuya LAN connection (sauna.py), exposes a small HTTP API for the
ember iOS app, controls the 'Sauna' Sonos (sonos.py), and pushes Live Activity
updates via APNs (apns.py). Runs natively (systemd) on the Homebridge Pi, or in Docker.
"""
import asyncio
import contextlib
import logging
import time
from typing import Optional

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

import config
from sauna import SaunaClient
from sonos import SonosController

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("emberd")

# Runtime singletons — constructed in lifespan (no import-time I/O).
sauna: Optional[SaunaClient] = None
sonos: Optional[SonosController] = None
apns = None
_api_key: Optional[str] = None
_heater_max_on_sec: Optional[int] = None
_poll_interval = 5.0

# In-memory state
_activity_tokens: set[str] = set()
_push_to_start_token: Optional[str] = None
_session: Optional[dict] = None
_last_pushed_temp: Optional[int] = None
_last_push_at = 0.0
_heater_on_since: Optional[float] = None

STALE_AFTER_SEC = 120
KEEPALIVE_SEC = 90  # re-push before the Live Activity goes stale, even if temp unchanged


# ---------- request models ----------
class ControlBody(BaseModel):
    power: Optional[bool] = None
    heater: Optional[bool] = None
    targetTempF: Optional[int] = Field(None, ge=60, le=175)   # Eclipse 2 tops out ~165°F
    timerMin: Optional[int] = Field(None, ge=0, le=360)
    chromoColor: Optional[str] = None
    chromoCycle: Optional[bool] = None
    footwell: Optional[bool] = None


class AudioBody(BaseModel):
    action: str
    volume: Optional[int] = Field(None, ge=0, le=100)


class TokenBody(BaseModel):
    pushToken: str


# ---------- auth ----------
async def require_auth(authorization: Optional[str] = Header(None)):
    """Bearer-token gate on mutating endpoints. Disabled if server.apiKey is unset."""
    if _api_key is None:
        return
    if authorization != f"Bearer {_api_key}":
        raise HTTPException(401, "unauthorized")


# ---------- lifespan ----------
@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    global sauna, sonos, apns, _api_key, _heater_max_on_sec, _poll_interval
    opts = config.load()
    s = opts["sauna"]
    srv = opts.get("server", {})
    _api_key = srv.get("apiKey") or None
    _poll_interval = float(srv.get("pollIntervalSec", 5))
    mins = srv.get("heaterMaxOnMinutes")
    _heater_max_on_sec = int(mins) * 60 if mins else None

    sauna = SaunaClient(ip=s["ip"], dev_id=s["devId"], local_key=s["localKey"],
                        version=float(s.get("version", 3.5)), poll_interval=_poll_interval)
    sonos = SonosController(opts.get("sonos", {}).get("name", "Sauna"))
    acfg = opts.get("apns", {})
    if acfg.get("enabled"):
        from apns import APNsClient
        apns = APNsClient(key_id=acfg["keyId"], team_id=acfg["teamId"], p8_path=acfg["p8Path"],
                          bundle_id=acfg["bundleId"], sandbox=acfg.get("sandbox", True))

    await sauna.start()
    tasks = [asyncio.create_task(_push_loop()), asyncio.create_task(_heater_watchdog())]
    log.info("emberd started (sauna %s, APNs %s, auth %s, deadman %s)",
             s["ip"], "on" if apns else "off", "on" if _api_key else "OFF",
             f"{_heater_max_on_sec // 60}min" if _heater_max_on_sec else "off")
    try:
        yield
    finally:
        for t in tasks:
            t.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await t
        await sauna.stop()
        if apns:
            await apns.close()


app = FastAPI(title="emberd", lifespan=lifespan)


# ---------- endpoints ----------
@app.get("/health")
async def health():
    return {"ok": True, "online": sauna.state()["online"] if sauna else False}


@app.get("/state")
async def get_state():
    st = sauna.state()
    if _session:
        st["session"] = {"active": True, "startedAt": _session["start"],
                         "elapsedSec": int(time.time() - _session["start"])}
    return st


@app.get("/debug/raw")
async def debug_raw():
    r = sauna._raw if sauna else {}
    items = sorted(r.items(), key=lambda kv: int(kv[0]) if str(kv[0]).isdigit() else 999)
    return {"raw": {k: str(v) for k, v in items}, "online": sauna._online if sauna else False}


@app.post("/debug/set", dependencies=[Depends(require_auth)])
async def debug_set(body: dict):
    try:
        return await sauna.set_dp(str(body["dp"]), body["value"])
    except KeyError:
        raise HTTPException(400, "need {dp, value}")
    except Exception:
        log.exception("debug_set failed")
        raise HTTPException(502, "set failed")


@app.post("/control", dependencies=[Depends(require_auth)])
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
    except Exception:
        log.exception("control failed")
        raise HTTPException(502, "sauna control failed")
    # reflect commanded toggles so the response isn't transiently stale from a lagging
    # status DP (e.g. power's DP20); the poll reconciles real device state.
    sauna.overlay_bools(power=body.power, heater=body.heater,
                        footwell=body.footwell, chromo_cycle=body.chromoCycle)
    return sauna.state()


@app.post("/audio", dependencies=[Depends(require_auth)])
async def audio(body: AudioBody):
    try:
        return await sonos.control(body.action, body.volume)
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception:
        log.exception("audio failed")
        raise HTTPException(502, "sonos control failed")


@app.post("/session/start", dependencies=[Depends(require_auth)])
async def session_start():
    global _session
    if _session:  # idempotent — don't clobber an active session's accounting
        return {"active": True, "startedAt": _session["start"], "alreadyActive": True}
    _session = {"start": time.time()}
    return {"active": True, "startedAt": _session["start"]}


@app.post("/session/end", dependencies=[Depends(require_auth)])
async def session_end():
    global _session
    if not _session:
        raise HTTPException(400, "no active session")
    start = _session["start"]
    end = time.time()
    peak = sauna.peak_since(start)
    _session = None
    return {"startedAt": start, "endedAt": end, "durationSec": int(end - start), "peakTempF": peak}


@app.post("/activity/token", dependencies=[Depends(require_auth)])
async def register_activity_token(body: TokenBody):
    _activity_tokens.add(body.pushToken)
    return {"registered": len(_activity_tokens)}


@app.post("/activity/start-token", dependencies=[Depends(require_auth)])
async def register_push_to_start(body: TokenBody):
    global _push_to_start_token
    _push_to_start_token = body.pushToken
    return {"ok": True}


# ---------- background tasks ----------
async def _push_loop():
    """Push temperature to Live Activities on change, plus a keep-alive before stale."""
    global _last_pushed_temp, _last_push_at
    while True:
        try:
            await asyncio.sleep(_poll_interval)
            if not apns or not _activity_tokens:
                continue
            st = sauna.state()
            temp = st.get("currentTempF")
            if temp is None:
                continue
            now = time.time()
            if temp == _last_pushed_temp and (now - _last_push_at) < KEEPALIVE_SEC:
                continue
            content = {
                "currentTempF": temp,
                "targetTempF": st.get("targetTempF"),
                "heater": st.get("heater"),
                "power": st.get("power"),
                "chromoColor": st.get("chromoColor"),
                "timerRemainingMin": st.get("timerRemainingMin"),
                "online": st.get("online"),
            }
            sent_ok = False
            dead: set[str] = set()
            for tok in list(_activity_tokens):
                try:
                    status, text = await apns.update_activity(
                        tok, content, priority=5, stale_after_sec=STALE_AFTER_SEC)
                    sent_ok = sent_ok or status == 200
                    if status == 410 or (status == 400 and
                                         ("BadDeviceToken" in text or "DeviceTokenNotForTopic" in text)):
                        dead.add(tok)
                except Exception as e:
                    log.warning("APNs send failed for %s…: %s", tok[:8], e)
            _activity_tokens.difference_update(dead)
            if sent_ok:  # only advance dedupe after a successful round
                _last_pushed_temp = temp
                _last_push_at = now
        except asyncio.CancelledError:
            raise
        except Exception as e:
            log.warning("push loop error: %s", e)


async def _heater_watchdog():
    """Optional safety deadman: auto-off the heater if left on past server.heaterMaxOnMinutes."""
    global _heater_on_since
    if _heater_max_on_sec is None:
        return  # disabled by default
    while True:
        try:
            await asyncio.sleep(30)
            on = sauna.state().get("heater")
            if not on:
                _heater_on_since = None
                continue
            if _heater_on_since is None:
                _heater_on_since = time.time()
            elif time.time() - _heater_on_since >= _heater_max_on_sec:
                log.warning("heater on > %ss — deadman auto-off", _heater_max_on_sec)
                with contextlib.suppress(Exception):
                    await sauna.set_heater(False)
                _heater_on_since = None
        except asyncio.CancelledError:
            raise
        except Exception as e:
            log.warning("watchdog error: %s", e)
