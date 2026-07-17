import { PlatformAccessory, Service } from 'homebridge';

import { AccessoryHandler, EmberPlatform } from '../platform';
import { ControlBody, EmberdState } from '../client';
import { nearestSolid, solidFor } from '../colors';

/** Interior lights (DP113 = all interior) as a color bulb whose picks snap to the
 *  sauna's 7 real chroma solids, plus an optional linked "Rainbow" switch (DP101). */
export class SaunaLights implements AccessoryHandler {
  private readonly bulb: Service;
  private readonly rainbow?: Service;

  private on = false;
  private hue = 37.5;
  private sat = 8;
  private cycleOn = false;

  // The Home app fires Hue/Saturation (and sometimes On) as separate set events
  // within milliseconds — coalesce them into ONE /control call.
  private pending: { hue?: number; sat?: number } = {};
  private flushTimer?: NodeJS.Timeout;

  constructor(
    private readonly platform: EmberPlatform,
    accessory: PlatformAccessory,
  ) {
    const { Service, Characteristic } = platform;

    this.bulb = accessory.getService(Service.Lightbulb) ?? accessory.addService(Service.Lightbulb);
    this.bulb.setCharacteristic(Characteristic.Name, accessory.displayName);
    this.bulb.setPrimaryService(true);

    this.bulb
      .getCharacteristic(Characteristic.On)
      .onGet(() => {
        this.platform.assertReachable();
        return this.on;
      })
      .onSet(async (value) => {
        await this.platform.control({ footwell: value as boolean });
      });

    // The color-picker UX assumes a Brightness characteristic; the hardware has none.
    // Report 100 always; a 0 set means "off", anything else is ignored.
    this.bulb
      .getCharacteristic(Characteristic.Brightness)
      .onGet(() => 100)
      .onSet(async (value) => {
        if ((value as number) === 0) {
          await this.platform.control({ footwell: false });
        } else {
          setTimeout(() => this.bulb.updateCharacteristic(Characteristic.Brightness, 100), 100);
        }
      });

    this.bulb
      .getCharacteristic(Characteristic.Hue)
      .onGet(() => {
        this.platform.assertReachable();
        return this.hue;
      })
      .onSet((value) => this.queueColor({ hue: value as number }));

    this.bulb
      .getCharacteristic(Characteristic.Saturation)
      .onGet(() => {
        this.platform.assertReachable();
        return this.sat;
      })
      .onSet((value) => this.queueColor({ sat: value as number }));

    if (platform.config.exposeRainbowSwitch ?? true) {
      this.rainbow =
        accessory.getServiceById(Service.Switch, 'rainbow') ??
        accessory.addService(Service.Switch, 'Rainbow', 'rainbow');
      this.rainbow.addOptionalCharacteristic(Characteristic.ConfiguredName);
      this.rainbow.setCharacteristic(Characteristic.ConfiguredName, 'Rainbow');
      this.bulb.addLinkedService(this.rainbow);

      this.rainbow
        .getCharacteristic(Characteristic.On)
        .onGet(() => {
          this.platform.assertReachable();
          return this.cycleOn;
        })
        .onSet(async (value) => {
          if (value as boolean) {
            await this.platform.control({ footwell: true, chromoCycle: true });
          } else {
            // cycle-off resets the LEDs to white; the next poll updates the swatch
            await this.platform.control({ chromoCycle: false });
          }
        });
    } else {
      const existing = accessory.getServiceById(Service.Switch, 'rainbow');
      if (existing) {
        accessory.removeService(existing);
      }
    }
  }

  private queueColor(patch: { hue?: number; sat?: number }): void {
    Object.assign(this.pending, patch);
    clearTimeout(this.flushTimer);
    this.flushTimer = setTimeout(() => void this.flushColor(), 150);
  }

  private async flushColor(): Promise<void> {
    const p = this.pending;
    this.pending = {};
    const solid = nearestSolid(p.hue ?? this.hue, p.sat ?? this.sat);

    // lights must be on for a color to stick, and picking a color exits rainbow;
    // emberd applies footwell -> cycle -> color in the right order server-side
    const body: ControlBody = { chromoColor: solid.mode, footwell: true };
    if (this.cycleOn) {
      body.chromoCycle = false;
    }
    try {
      await this.platform.control(body);
    } catch {
      return; // logged by the platform; poll will restore truth
    }
    // snap the Home app swatch to the actual solid the sauna can produce
    const { Characteristic } = this.platform;
    this.bulb
      .updateCharacteristic(Characteristic.Hue, solid.hue)
      .updateCharacteristic(Characteristic.Saturation, solid.sat);
  }

  applyState(state: EmberdState): void {
    const { Characteristic } = this.platform;
    this.on = state.footwell;
    this.cycleOn = state.chromoCycle;

    // While the rainbow cycle runs, DP21 (and therefore the swatch) simply holds its
    // last solid — don't chase the animation.
    const solid = solidFor(state.chromoColor);
    this.hue = solid.hue;
    this.sat = solid.sat;

    this.bulb
      .updateCharacteristic(Characteristic.On, this.on)
      .updateCharacteristic(Characteristic.Hue, this.hue)
      .updateCharacteristic(Characteristic.Saturation, this.sat);
    this.rainbow?.updateCharacteristic(Characteristic.On, this.cycleOn);
  }
}
