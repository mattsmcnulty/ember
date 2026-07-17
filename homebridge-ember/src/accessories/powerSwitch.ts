import { PlatformAccessory, Service } from 'homebridge';

import { AccessoryHandler, EmberPlatform } from '../platform';
import { EmberdState } from '../client';

/** Cabin power as an independent switch. Off mirrors the app's Stop (power + heater
 *  off — the device cascades anyway; sending both keeps every tile consistent
 *  in the same beat). */
export class SaunaPower implements AccessoryHandler {
  private readonly service: Service;
  private on = false;

  constructor(
    private readonly platform: EmberPlatform,
    accessory: PlatformAccessory,
  ) {
    const { Service, Characteristic } = platform;
    this.service = accessory.getService(Service.Switch) ?? accessory.addService(Service.Switch);
    this.service.setCharacteristic(Characteristic.Name, accessory.displayName);

    this.service
      .getCharacteristic(Characteristic.On)
      .onGet(() => {
        this.platform.assertReachable();
        return this.on;
      })
      .onSet(async (value) => {
        if (value as boolean) {
          await this.platform.control({ power: true });
        } else {
          await this.platform.control({ power: false, heater: false });
        }
      });
  }

  applyState(state: EmberdState): void {
    this.on = state.power;
    this.service.updateCharacteristic(this.platform.Characteristic.On, this.on);
  }
}
