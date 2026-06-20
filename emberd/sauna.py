"""Sun Home Eclipse 2 client — sole owner of the single Tuya LAN connection.

All device I/O is serialized through one asyncio.Lock and run in a thread executor
(tinytuya is synchronous and not thread-safe). A background task polls status so
API reads are served from a cache. DP map mirrors emberd/schema.json.
"""
import asyncio
import logging
import time
from typing import Any, Optional

import tinytuya

log = logging.getLogger("emberd.sauna")

# Writable controls (DP numbers from schema.json)
DP_POWER = "110"
DP_HEATER = "114"
DP_TARGET_F = "106"
DP_TIMER_SET = "116"
DP_FOOTWELL = "113"
DP_CHROMO = "21"
DP_CHROMO_CYCLE = "101"
# Read-only
DP_CURRENT_F = "104"
DP_CURRENT_C = "103"
DP_TARGET_C = "109"
DP_TIMER_REMAINING = "105"
DP_UNIT = "108"

CHROMO_VALUES = ["mode", "mode1", "mode2", "mode3", "mode4", "mode5", "mode6", "mode7", "mode8"]


class SaunaClient:
    def __init__(self, ip: str, dev_id: str, local_key: str,
                 version: float = 3.5, poll_interval: float = 5.0):
        self.ip = ip
        self.dev_id = dev_id
        self.local_key = local_key
        self.version = version
        self.poll_interval = poll_interval
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
        return d

    async def _io(self, fn):
        """Run a sync device call under the lock (serializes the single connection)."""
        loop = asyncio.get_running_loop()
        async with self._lock:
            if self._dev is None:
                self._dev = await loop.run_in_executor(None, self._connect)
            try:
                return await loop.run_in_executor(None, lambda: fn(self._dev))
            except Exception:
                # drop the socket so the next call reconnects
                self._dev = None
                raise

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
        async with self._lock:
            self._dev = None

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
            "power": bool(r.get(DP_POWER, False)),
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

    def peak_since(self, ts: float) -> Optional[int]:
        vals = [t for (s, t) in self._temp_history if s >= ts and isinstance(t, int)]
        return max(vals) if vals else None

    # ---- controls ----
    async def set_dp(self, dp: str, value: Any) -> dict:
        await self._io(lambda d: d.set_value(dp, value))
        # the device often returns a partial status after a write; do a clean refresh
        await asyncio.sleep(0.3)
        return await self.refresh()

    async def set_power(self, on: bool):
        return await self.set_dp(DP_POWER, bool(on))

    async def set_heater(self, on: bool):
        return await self.set_dp(DP_HEATER, bool(on))

    async def set_target_temp(self, temp_f: int):
        return await self.set_dp(DP_TARGET_F, int(temp_f))

    async def set_timer(self, minutes: int):
        return await self.set_dp(DP_TIMER_SET, int(minutes))

    async def set_chromo_color(self, value: str):
        if value not in CHROMO_VALUES:
            raise ValueError(f"chromoColor must be one of {CHROMO_VALUES}")
        return await self.set_dp(DP_CHROMO, value)

    async def set_chromo_cycle(self, on: bool):
        return await self.set_dp(DP_CHROMO_CYCLE, bool(on))

    async def set_footwell(self, on: bool):
        return await self.set_dp(DP_FOOTWELL, bool(on))
