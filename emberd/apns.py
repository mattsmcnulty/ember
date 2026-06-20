"""APNs HTTP/2 client for ActivityKit (Live Activity) pushes.

Token-based auth (.p8, ES256 JWT). Sends Live Activity `update`, `end`, and
push-to-`start` events. See Apple: "Starting and updating Live Activities with
ActivityKit push notifications".
"""
import logging
import time
from typing import Any, Optional

import httpx
import jwt  # PyJWT

log = logging.getLogger("emberd.apns")

PROD_HOST = "https://api.push.apple.com"
SANDBOX_HOST = "https://api.sandbox.push.apple.com"


class APNsClient:
    def __init__(self, key_id: str, team_id: str, p8_path: str, bundle_id: str,
                 sandbox: bool = True):
        self.key_id = key_id
        self.team_id = team_id
        self.bundle_id = bundle_id
        self.host = SANDBOX_HOST if sandbox else PROD_HOST
        with open(p8_path) as f:
            self._signing_key = f.read()
        self._token: Optional[str] = None
        self._token_at = 0.0
        self._client = httpx.AsyncClient(http2=True, timeout=10)

    def _provider_token(self) -> str:
        # APNs provider tokens are valid up to 60 min; refresh well before.
        if self._token and (time.time() - self._token_at) < 50 * 60:
            return self._token
        self._token = jwt.encode(
            {"iss": self.team_id, "iat": int(time.time())},
            self._signing_key, algorithm="ES256", headers={"kid": self.key_id},
        )
        self._token_at = time.time()
        return self._token

    async def close(self):
        await self._client.aclose()

    async def _post(self, push_token: str, payload: dict, extra_headers: dict) -> tuple[int, str]:
        url = f"{self.host}/3/device/{push_token}"

        async def send() -> httpx.Response:
            headers = {
                "authorization": f"bearer {self._provider_token()}",
                "apns-push-type": "liveactivity",
                "apns-topic": f"{self.bundle_id}.push-type.liveactivity",
                **extra_headers,
            }
            return await self._client.post(url, json=payload, headers=headers)

        r = await send()
        if r.status_code == 403 and "ExpiredProviderToken" in r.text:
            self._token = None  # regenerate JWT and retry once
            r = await send()
        if r.status_code != 200:
            log.warning("APNs %s (apns-id=%s) token=%s…: %s",
                        r.status_code, r.headers.get("apns-id"), push_token[:8], r.text)
        return r.status_code, r.text

    async def update_activity(self, push_token: str, content_state: dict,
                              priority: int = 5, stale_after_sec: int = 120,
                              dismiss: bool = False, relevance: Optional[float] = None
                              ) -> tuple[int, str]:
        now = int(time.time())
        aps: dict[str, Any] = {
            "timestamp": now,
            "event": "end" if dismiss else "update",
            "content-state": content_state,
        }
        if dismiss:
            aps["dismissal-date"] = now  # dismiss promptly instead of lingering ~4h
        else:
            aps["stale-date"] = now + stale_after_sec
        if relevance is not None:
            aps["relevance-score"] = relevance
        headers = {
            "apns-priority": str(priority),
            # expiration 0 → APNs drops (doesn't queue/retry) a stale temperature update
            "apns-expiration": "0",
        }
        return await self._post(push_token, {"aps": aps}, headers)

    async def start_activity(self, push_to_start_token: str, attributes_type: str,
                             attributes: dict, content_state: dict,
                             stale_after_sec: int = 600) -> tuple[int, str]:
        """Push-to-start (iOS 17.2+): begin a Live Activity while the app is closed."""
        now = int(time.time())
        aps = {
            "timestamp": now,
            "event": "start",
            "attributes-type": attributes_type,
            "attributes": attributes,
            "content-state": content_state,
            "stale-date": now + stale_after_sec,
        }
        return await self._post(push_to_start_token, {"aps": aps},
                                {"apns-priority": "10", "apns-expiration": "0"})
