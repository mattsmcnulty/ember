"""Control the cabin's Sonos 'Sauna' amp directly via the local Sonos API (soco).

soco is synchronous; calls are wrapped in a thread executor. The speaker is
resolved lazily by name and cached.
"""
import asyncio
import logging
from typing import Optional

log = logging.getLogger("emberd.sonos")

try:
    import soco
except Exception:  # soco optional at import time
    soco = None


class SonosController:
    def __init__(self, name: str = "Sauna", ip: Optional[str] = None):
        self.name = name
        self.ip = ip  # static IP skips multicast discovery (unreliable across some networks)
        self._device = None

    async def _io(self, fn):
        loop = asyncio.get_running_loop()
        try:
            return await loop.run_in_executor(None, fn)
        except Exception:
            self._device = None  # cached speaker may be stale (moved IP / power-cycled)
            raise

    def _resolve(self):
        if soco is None:
            raise RuntimeError("soco not installed")
        if self._device is not None:
            return self._device
        dev = None
        if self.ip:
            try:
                cand = soco.SoCo(self.ip)
                cand.get_current_transport_info()  # cheap liveness probe
                dev = cand
            except Exception:
                log.warning("Sonos at configured ip %s unreachable; falling back to discovery", self.ip)
        if dev is None:
            dev = soco.discovery.by_name(self.name)
        if dev is None:
            # fall back to scanning all zones
            for z in (soco.discover() or []):
                if z.player_name == self.name:
                    dev = z
                    break
        if dev is None:
            raise RuntimeError(f"Sonos speaker named {self.name!r} not found on the network")
        self._device = dev
        return dev

    async def control(self, action: str, volume: Optional[int] = None) -> dict:
        def _do():
            dev = self._resolve()
            if action == "play":
                dev.play()
            elif action == "pause":
                dev.pause()
            elif action == "next":
                dev.next()
            elif action == "prev":
                dev.previous()
            elif action == "volume":
                if volume is None:
                    raise ValueError("volume action requires 'volume'")
                dev.volume = max(0, min(100, int(volume)))
            else:
                raise ValueError(f"unknown audio action {action!r}")
            return self._now_playing(dev)
        return await self._io(_do)

    async def now_playing(self) -> dict:
        return await self._io(lambda: self._now_playing(self._resolve()))

    @staticmethod
    def _now_playing(dev) -> dict:
        info = dev.get_current_track_info()
        transport = dev.get_current_transport_info()
        return {
            "speaker": dev.player_name,
            "volume": dev.volume,
            "state": transport.get("current_transport_state"),
            "title": info.get("title"),
            "artist": info.get("artist"),
            "album": info.get("album"),
            "position": info.get("position"),
            "duration": info.get("duration"),
        }
