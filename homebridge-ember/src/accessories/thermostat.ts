import { PlatformAccessory, Service } from 'homebridge';

import { AccessoryHandler, EmberPlatform } from '../platform';
import { EmberdState } from '../client';
import { MAX_C, MIN_C, currentFtoC, targetCtoF, targetFtoC } from '../temperature';

export class SaunaThermostat implements AccessoryHandler {
  private readonly service: Service;
  private currentC = 20;
  private targetC = targetFtoC(150);
  private heating = false;

  constructor(
    private readonly platform: EmberPlatform,
    accessory: PlatformAccessory,
  ) {
    const { Service, Characteristic } = platform;
    this.service =
      accessory.getService(Service.Thermostat) ?? accessory.addService(Service.Thermostat);
    this.service.setCharacteristic(Characteristic.Name, accessory.displayName);

    this.service
      .getCharacteristic(Characteristic.CurrentTemperature)
      .onGet(() => {
        this.platform.assertReachable();
        return this.currentC;
      });

    // Without these props the Home app caps the dial at 38°C / 100°F — below sauna range.
    this.service
      .getCharacteristic(Characteristic.TargetTemperature)
      .setProps({ minValue: MIN_C, maxValue: MAX_C, minStep: 0.5 })
      .onGet(() => {
        this.platform.assertReachable();
        return this.targetC;
      })
      .onSet(async (value) => {
        const f = targetCtoF(value as number);
        await this.platform.control({ targetTempF: f });
      });

    this.service
      .getCharacteristic(Characteristic.CurrentHeatingCoolingState)
      .onGet(() => {
        this.platform.assertReachable();
        return this.heating
          ? Characteristic.CurrentHeatingCoolingState.HEAT
          : Characteristic.CurrentHeatingCoolingState.OFF;
      });

    this.service
      .getCharacteristic(Characteristic.TargetHeatingCoolingState)
      .setProps({
        validValues: [
          Characteristic.TargetHeatingCoolingState.OFF,
          Characteristic.TargetHeatingCoolingState.HEAT,
        ],
      })
      .onGet(() => {
        this.platform.assertReachable();
        return this.heating
          ? Characteristic.TargetHeatingCoolingState.HEAT
          : Characteristic.TargetHeatingCoolingState.OFF;
      })
      .onSet(async (value) => {
        if (value === Characteristic.TargetHeatingCoolingState.HEAT) {
          // mirror the app's Start: heat auto-powers the cabin on
          await this.platform.control({ power: true, heater: true });
        } else {
          // mirror the app's Stop: full off. Heater-only off read as "it didn't
          // turn off" at the cabin (lights/panel stay lit); the Power switch
          // still allows lights-only power-on without heat.
          await this.platform.control({ power: false, heater: false });
        }
      });

    // The device is °F-only; report Fahrenheit and re-assert it if the Home app tries to change it.
    this.service
      .getCharacteristic(Characteristic.TemperatureDisplayUnits)
      .onGet(() => Characteristic.TemperatureDisplayUnits.FAHRENHEIT)
      .onSet(() => {
        setTimeout(() => {
          this.service.updateCharacteristic(
            Characteristic.TemperatureDisplayUnits,
            Characteristic.TemperatureDisplayUnits.FAHRENHEIT,
          );
        }, 100);
      });
  }

  applyState(state: EmberdState): void {
    const { Characteristic } = this.platform;
    if (state.currentTempF !== null) {
      this.currentC = currentFtoC(state.currentTempF);
    }
    if (state.targetTempF !== null) {
      this.targetC = targetFtoC(state.targetTempF);
    }
    this.heating = state.heater;

    this.service
      .updateCharacteristic(Characteristic.CurrentTemperature, this.currentC)
      .updateCharacteristic(Characteristic.TargetTemperature, this.targetC)
      .updateCharacteristic(
        Characteristic.CurrentHeatingCoolingState,
        this.heating
          ? Characteristic.CurrentHeatingCoolingState.HEAT
          : Characteristic.CurrentHeatingCoolingState.OFF,
      )
      .updateCharacteristic(
        Characteristic.TargetHeatingCoolingState,
        this.heating
          ? Characteristic.TargetHeatingCoolingState.HEAT
          : Characteristic.TargetHeatingCoolingState.OFF,
      );
  }
}
