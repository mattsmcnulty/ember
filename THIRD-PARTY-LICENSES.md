# Third-party licenses

ember's own source is MIT (see [LICENSE](LICENSE)). It builds on the third-party projects below,
each under its own license. ember does **not redistribute** them — emberd's deps are `pip install`ed
by the user and the iOS frameworks ship with iOS — so this list is for credit and clarity.

## emberd (Python — direct deps from `emberd/requirements.txt`)

| Package | License |
|---|---|
| [tinytuya](https://github.com/jasonacox/tinytuya) | MIT |
| [FastAPI](https://github.com/fastapi/fastapi) | MIT |
| [Uvicorn](https://github.com/encode/uvicorn) | BSD-3-Clause |
| [httpx](https://github.com/encode/httpx) | BSD-3-Clause |
| [PyJWT](https://github.com/jpadilla/pyjwt) | MIT |
| [soco](https://github.com/SoCo/SoCo) | MIT |

Key transitive deps and their licenses: Starlette (BSD-3), pydantic / pydantic-core (MIT),
anyio (MIT), h2 / hpack / hyperframe (MIT), cryptography (Apache-2.0 OR BSD-3), requests
(Apache-2.0), certifi (MPL-2.0), urllib3 / idna (MIT / BSD-3). Run `pip-licenses` in the emberd
venv for the full resolved tree. All are permissive (MIT / BSD / Apache / MPL-file-level) — no
copyleft obligation, since nothing is redistributed as a binary.

## ember (iOS)

No third-party Swift packages. Built entirely on Apple's SDK frameworks — **SwiftUI, ActivityKit,
WidgetKit, HealthKit, SwiftData** — under the Apple SDK license.

## homebridge-ember (Homebridge plugin)

**Zero runtime dependencies** — talks to emberd over plain HTTP with Node's built-in `fetch`.
Dev-only: [Homebridge](https://github.com/homebridge/homebridge) (Apache-2.0),
[TypeScript](https://github.com/microsoft/TypeScript) (Apache-2.0), `@types/node` (MIT).

## Tooling (build / dev only — not shipped)

- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — MIT (generates the Xcode project).
- [Frida](https://frida.re) — dynamic-instrumentation toolkit, used only for one-time `localKey`
  extraction; not part of the app or the bridge.
