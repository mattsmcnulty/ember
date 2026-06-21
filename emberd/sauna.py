"""Sun Home Eclipse 2 client — sole owner of the single Tuya LAN connection.

All device I/O is serialized through one asyncio.Lock and pinned to a dedicated
single-thread executor (tinytuya is synchronous and not thread-safe). A background
task polls status so API reads are served from a cache. DP map mirrors schema.json.

tinytuya returns error *dicts* (e.g. {"Err":"905"}) rather than raising on device
failures, so we detect those explicitly and force a reconnect.
"""
import asyncio
import concurrent.futures
import contextlib
import logging
import time
from typing import Any, Optional

import tinytuya

log = logging.getLogger("emberd.sauna")

# Writable controls (DP numbers from schema.json).
# NB: power (110), heater (114), footwell (113) and chromo-cycle (101) are *momentary
# toggles* — a write flips the current state regardless of the value sent — so they go
# through _set_bool (read current, write only when it must change). Power's real on/off
# status is DP_POWER_STATUS (20); DP_POWER (110) is just the toggle "button".
DP_POWER = "110"
DP_HEATER = "114"
DP_TARGET_F = "106"
DP_TIMER_SET = "116"
DP_FOOTWELL = "113"
DP_CHROMO = "21"
DP_CHROMO_CYCLE = "101"
# Read-only
DP_POWER_STATUS = "20"
DP_CURRENT_F = "104"
DP_CURRENT_C = "103"
DP_TARGET_C = "109"
DP_TIMER_REMAINING = "105"
DP_UNIT = "108"

CHROMO_VALUES = ["mode", "mode1", "mode2", "mode3", "mode4", "mode5", "mode6", "mode7", "mode8"]

POLL_CEILING_SEC = 25.0          # keep well under the Tuya idle-drop (~30s); poll = keepalive
FATAL_ERR = "914"                # ERR_KEY_OR_VER — wrong localKey/protocol version


def _err_code(st: Any) -> Optional[str]:
    """tinytuya returns {'Err': '905', 'Error': '...'} on failure instead of raising."""
    if isinstance(st, dict) and ("Err" in st or "Error" in st):
        return str(st.get("Err", "?"))
    return None


class SaunaClient:
    def __init__(self, ip: str, dev_id: str, local_key: str,
                 version: float = 3.5, poll_interval: float = 5.0):
        self.ip = ip
        self.dev_id = dev_id
        self.local_key = local_key
        self.version = version
        self.poll_interval = min(float(poll_interval), POLL_CEILING_SEC)
        # one dedicated worker thread → device calls never land on different threads
        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=1, thread_name_prefix="sauna-io")
        self._dev: Optional[tinytuya.Device] = None
        self._lock: Optional[asyncio.Lock] = None  # created in start() under the running loop
        self._raw: dict[str, Any] = {}
        self._online = False
        self._updated = 0.0
        self._temp_history: list[tuple[float, int]] = []  # (ts, currentTempF)
        self._task: Optional[asyncio.Task] = None

    # ---- connection / io ----
    def _connect(self) -> tinytuya.Device:
        d = tinytuya.Device(self.dev_id, self.ip, self.local_key, version=self.version)
        d.set_socketPersistent(True)
        d.set_socketTimeout(5)
        d.set_socketRetryLimit(1)  # a dead device can't hold the lock for retries*timeout
        return d

    async def _io(self, fn):
        """Run a sync device call under the lock, pinned to the single io thread."""
        loop = asyncio.get_running_loop()
        async with self._lock:
            if self._dev is None:
                self._dev = await loop.run_in_executor(self._executor, self._connect)
            try:
                return await loop.run_in_executor(self._executor, lambda: fn(self._dev))
            except Exception:
                self._dev = None  # python-level error → drop socket, reconnect next call
                raise

    async def _drop_connection(self):
        """Close + null the device so the next _io reconnects (after an error dict)."""
        loop = asyncio.get_running_loop()
        async with self._lock:
            dev, self._dev = self._dev, None
        if dev is not None:
            with contextlib.suppress(Exception):
                await loop.run_in_executor(self._executor, dev.close)

    def _handle_error(self, code: str, st: Any) -> None:
        self._online = False
        if code == FATAL_ERR:
            log.error("sauna FATAL error %s (check localKey/version): %s", code, st)
        else:
            log.warning("sauna device error %s: %s", code, st)

    # ---- lifecycle ----
    async def start(self):
        self._lock = asyncio.Lock()  # bind to the running loop
        try:
            await self.refresh()  # prime the cache (best effort)
        except Exception as e:
            log.warning("initial refresh failed: %s", e)
        self._task = asyncio.create_task(self._poll_loop())

    async def stop(self):
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
        if self._lock is not None:
            loop = asyncio.get_running_loop()
            async with self._lock:
                dev, self._dev = self._dev, None
            if dev is not None:
                with contextlib.suppress(Exception):
                    await loop.run_in_executor(self._executor, dev.close)
        self._executor.shutdown(wait=False)

    async def _poll_loop(self):
        while True:
            try:
                await self.refresh()
            except asyncio.CancelledError:
                raise
            except Exception as e:
                self._online = False
                log.warning("poll error: %s", e)
            await asyncio.sleep(self.poll_interval)

    # ---- state ----
    async def refresh(self) -> dict:
        st = await self._io(lambda d: d.status())
        code = _err_code(st)
        if code:
            self._handle_error(code, st)
            await self._drop_connection()  # any device error → force reconnect
            return self.state()
        dps = st.get("dps") if isinstance(st, dict) else None
        if not dps:
            self._online = False
            log.debug("status returned no dps: %s", st)
            return self.state()
        self._raw.update(dps)
        self._online = True
        self._updated = time.time()
        cf = self._raw.get(DP_CURRENT_F)
        if isinstance(cf, int):
            self._temp_history.append((self._updated, cf))
            self._temp_history = self._temp_history[-5000:]
        return self.state()

    def state(self) -> dict:
        r = self._raw
        return {
            "power": bool(r.get(DP_POWER_STATUS, False)),
            "heater": bool(r.get(DP_HEATER, False)),
            "currentTempF": r.get(DP_CURRENT_F),
            "currentTempC": r.get(DP_CURRENT_C),
            "targetTempF": r.get(DP_TARGET_F),
            "targetTempC": r.get(DP_TARGET_C),
            "timerSetMin": r.get(DP_TIMER_SET),
            "timerRemainingMin": r.get(DP_TIMER_REMAINING),
            "chromoColor": r.get(DP_CHROMO),
            "chromoCycle": bool(r.get(DP_CHROMO_CYCLE, False)),
            "footwell": bool(r.get(DP_FOOTWELL, False)),
            "unit": r.get(DP_UNIT, "f"),
            "online": self._online,
            "updatedAt": self._updated,
        }

    def overlay_bools(self, *, power=None, heater=None, footwell=None, chromo_cycle=None) -> None:
        """Reflect just-commanded toggle states onto the cache so the immediate /control
        response isn't stale: a status DP can trail its toggle by a beat (power's DP20
        lags ~2s, and a later write's refresh can re-read it pre-settle). The background
        poll reconciles if a write didn't actually take. Booleans only — no clamping risk
        (target/timer keep the device's actual, possibly clamped, value)."""
        for dp, v in ((DP_POWER_STATUS, power), (DP_HEATER, heater),
                      (DP_FOOTWELL, footwell), (DP_CHROMO_CYCLE, chromo_cycle)):
            if v is not None:
                self._raw[dp] = v
        self._updated = time.time()

    def peak_since(self, ts: float) -> Optional[int]:
        hist = list(self._temp_history)  # snapshot — poll loop may append concurrently
        vals = [t for (s, t) in hist if s >= ts and isinstance(t, int)]
        return max(vals) if vals else None

    # ---- controls ----
    async def set_dp(self, dp: str, value: Any) -> dict:
        st = await self._io(lambda d: d.set_value(dp, value))
        code = _err_code(st)
        if code:
            self._handle_error(code, st)
            await self._drop_connection()
            raise RuntimeError(f"device rejected write (Err {code})")
        # the device's status right after a write is often stale/partial, so trust the
        # accepted write for the immediate response; the background poll reconciles.
        await asyncio.sleep(0.3)
        await self.refresh()
        self._raw[str(dp)] = value
        self._updated = time.time()
        return self.state()

    async def _set_bool(self, write_dp: str, status_dp: str, desired: bool) -> dict:
        """Toggle-style controls: a write flips the current state regardless of the value
        sent. Read the current state and only write when it must change — which is also
        correct if the DP turns out to be a plain level. Avoids e.g. Start toggling an
        already-on sauna back off."""
        await self.refresh()
        if bool(self._raw.get(status_dp, False)) == desired:
            return self.state()
        await self.set_dp(write_dp, desired)  # flips it to `desired`
        if status_dp != write_dp:
            self._raw[status_dp] = desired
            self._updated = time.time()
        return self.state()

    async def set_power(self, on: bool):
        return await self._set_bool(DP_POWER, DP_POWER_STATUS, bool(on))

    async def set_heater(self, on: bool):
        return await self._set_bool(DP_HEATER, DP_HEATER, bool(on))

    async def set_target_temp(self, temp_f: int):
        return await self.set_dp(DP_TARGET_F, int(temp_f))

    async def set_timer(self, minutes: int):
        return await self.set_dp(DP_TIMER_SET, int(minutes))

    async def set_chromo_color(self, value: str):
        if value not in CHROMO_VALUES:
            raise ValueError(f"chromoColor must be one of {CHROMO_VALUES}")
        return await self.set_dp(DP_CHROMO, value)

    async def set_chromo_cycle(self, on: bool):
        return await self._set_bool(DP_CHROMO_CYCLE, DP_CHROMO_CYCLE, bool(on))

    async def set_footwell(self, on: bool):
        return await self._set_bool(DP_FOOTWELL, DP_FOOTWELL, bool(on))
