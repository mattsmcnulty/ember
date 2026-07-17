# homebridge-ember

HomeKit control for a **Sun Home Eclipse 2** infrared sauna, via the
[emberd](https://github.com/mattsmcnulty/ember) local bridge. Part of the
[ember](https://github.com/mattsmcnulty/ember) project.

Adds three accessories to the Home app:

| Accessory | Service | What it does |
|---|---|---|
| **Sauna** | Thermostat | Live temperature, target dial (60–175 °F), heat on/off. "Hey Siri, set the sauna to 155 degrees." Heat mirrors the ember app's Start (powers the cabin on and heats); Off mirrors Stop (full off — power and heater). |
| **Sauna Lights** | Lightbulb (+ linked "Rainbow" switch) | Interior lights on/off and color. The sauna supports exactly 7 solid colors, so any pick on the HomeKit color wheel **snaps to the nearest real color** (low saturation = white). The Rainbow switch runs the sauna's slow color cycle. |
| **Sauna Power** | Switch | The independent cabin-power toggle. Off = full stop (power + heater), like the ember app's Stop. |

## Requirements

- A running [emberd](https://github.com/mattsmcnulty/ember/tree/main/emberd) reachable from the
  Homebridge host (same machine is ideal: `http://localhost:8765`)
- Homebridge ≥ 1.8, Node ≥ 18

## Install

Not published to npm (single-user project) — install from a packed tarball:

```bash
cd homebridge-ember
npm install && npm run build && npm pack     # → homebridge-ember-x.y.z.tgz
sudo npm -g install ./homebridge-ember-*.tgz # on the Homebridge host
```

## Config

Via the Homebridge UI (the plugin ships a settings form), or in `config.json`:

```json
{
  "platform": "Ember",
  "name": "Sauna",
  "baseUrl": "http://localhost:8765",
  "apiKey": "<emberd server.apiKey>",
  "pollSeconds": 5,
  "exposePowerSwitch": true,
  "exposeLights": true,
  "exposeRainbowSwitch": true
}
```

## ⚠️ Safety

This exposes a **heating appliance** to HomeKit automations — an automation can turn the
heater on with nobody home. Set `server.heaterMaxOnMinutes` in emberd's `options.json`
(e.g. `180`) so the bridge force-stops a heater left on too long. The plugin deliberately
does not expose the sauna's session timer.

## Notes

- Zero runtime dependencies; talks plain HTTP to emberd (which owns the sauna's single
  Tuya LAN socket — this plugin is just another client of the bridge, alongside the iOS app).
- HomeKit is Celsius-internal; the plugin widens the thermostat's range
  (default HomeKit thermostats stop at 38 °C / 100 °F) and keeps the dial stable on a
  0.5 °C grid while the device itself works in whole °F.
