# Security

ember controls a **heating appliance** over your LAN. Worth knowing:

## No secrets ship here
- The Tuya `localKey`, the emberd `server.apiKey`, and the APNs `.p8` are per-user config kept in
  **gitignored** files (`emberd/options.json`, `ember/Local.xcconfig`, `*.p8`). Each user supplies
  their own; none are committed or bundled.
- The iOS app contains no reverse-engineered or proprietary code.

## Running emberd safely
- Set a long random `server.apiKey` (the native installer generates one). With `apiKey: null`, auth
  is **off** and anyone who can reach tcp/8765 can power on the heater — only do that on a trusted
  dev LAN.
- Keep emberd on a trusted LAN/VLAN and firewall tcp/8765 to your subnet. Reach it remotely via
  Tailscale or an authenticated outbound relay — **never** a raw port-forward.
- Leave `server.debugEndpoints: false` in production (it exposes a raw DP dump and arbitrary DP
  writes).
- The heater deadman (`server.heaterMaxOnMinutes`) is a best-effort backstop, **not** a safety
  cutoff — the sauna's own timer/thermostat is the primary control.

## Reporting
This is a personal project with no formal support and no warranty. For a security issue, open a
GitHub issue, or for something sensitive contact the maintainer via the GitHub profile.
