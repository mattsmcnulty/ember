import {
  API,
  Characteristic,
  DynamicPlatformPlugin,
  Logging,
  PlatformAccessory,
  PlatformConfig,
  Service,
} from 'homebridge';

import { PLATFORM_NAME, PLUGIN_NAME } from './settings';
import { AuthError, ControlBody, EmberdClient, EmberdState } from './client';
import { SaunaThermostat } from './accessories/thermostat';
import { SaunaLights } from './accessories/lights';
import { SaunaPower } from './accessories/powerSwitch';

interface EmberConfig extends PlatformConfig {
  baseUrl?: string;
  apiKey?: string;
  pollSeconds?: number;
  exposePowerSwitch?: boolean;
  exposeLights?: boolean;
  exposeRainbowSwitch?: boolean;
}

export interface AccessoryHandler {
  applyState(state: EmberdState): void;
}

export class EmberPlatform implements DynamicPlatformPlugin {
  public readonly Service: typeof Service;
  public readonly Characteristic: typeof Characteristic;
  public readonly client: EmberdClient;

  /** Last polled state; null until the first successful poll. */
  public state: EmberdState | null = null;
  public reachable = true; // optimistic at startup so tiles don't flash "No Response"

  private readonly cached = new Map<string, PlatformAccessory>();
  private readonly handlers: AccessoryHandler[] = [];
  private pollFailures = 0;
  private wasOffline = false;
  private authErrorLogged = false;
  private controlChain: Promise<unknown> = Promise.resolve();
  // Bumped when a control starts AND when it finishes: a poll that began before
  // either point may carry pre-control state and must not repaint the tiles
  // (the same stale-poll race the iOS store guards against with its epoch).
  private controlEpoch = 0;

  constructor(
    public readonly log: Logging,
    public readonly config: EmberConfig,
    public readonly api: API,
  ) {
    this.Service = api.hap.Service;
    this.Characteristic = api.hap.Characteristic;
    this.client = new EmberdClient(
      (config.baseUrl ?? 'http://localhost:8765').replace(/\/+$/, ''),
      config.apiKey,
    );

    api.on('didFinishLaunching', () => this.setup());
  }

  configureAccessory(accessory: PlatformAccessory): void {
    this.cached.set(accessory.UUID, accessory);
  }

  private setup(): void {
    const wanted: Array<{ kind: string; name: string; make: (acc: PlatformAccessory) => AccessoryHandler }> = [
      { kind: 'thermostat', name: this.config.name ?? 'Sauna', make: (a) => new SaunaThermostat(this, a) },
    ];
    if (this.config.exposeLights ?? true) {
      wanted.push({ kind: 'lights', name: `${this.config.name ?? 'Sauna'} Lights`, make: (a) => new SaunaLights(this, a) });
    }
    if (this.config.exposePowerSwitch ?? true) {
      wanted.push({ kind: 'power', name: `${this.config.name ?? 'Sauna'} Power`, make: (a) => new SaunaPower(this, a) });
    }

    const wantedUUIDs = new Set<string>();
    for (const w of wanted) {
      const uuid = this.api.hap.uuid.generate(`ember:${w.kind}`);
      wantedUUIDs.add(uuid);
      let accessory = this.cached.get(uuid);
      if (!accessory) {
        accessory = new this.api.platformAccessory(w.name, uuid);
        this.api.registerPlatformAccessories(PLUGIN_NAME, PLATFORM_NAME, [accessory]);
        this.cached.set(uuid, accessory);
      }
      accessory
        .getService(this.Service.AccessoryInformation)!
        .setCharacteristic(this.Characteristic.Manufacturer, 'Sun Home / ember')
        .setCharacteristic(this.Characteristic.Model, 'Eclipse 2 (emberd)')
        .setCharacteristic(this.Characteristic.SerialNumber, `ember-${w.kind}`);
      this.handlers.push(w.make(accessory));
    }

    // drop accessories disabled by expose flags
    for (const [uuid, accessory] of this.cached) {
      if (!wantedUUIDs.has(uuid)) {
        this.api.unregisterPlatformAccessories(PLUGIN_NAME, PLATFORM_NAME, [accessory]);
        this.cached.delete(uuid);
      }
    }

    const pollSeconds = Math.min(60, Math.max(2, this.config.pollSeconds ?? 5));
    void this.poll();
    setInterval(() => void this.poll(), pollSeconds * 1000);
    this.log.info('Ember platform ready (%d accessories, polling %ds)', this.handlers.length, pollSeconds);
  }

  private async poll(): Promise<void> {
    const epoch = this.controlEpoch;
    try {
      const state = await this.client.getState();
      this.pollFailures = 0;
      this.reachable = true;
      if (epoch !== this.controlEpoch) {
        return; // a control ran while this poll was in flight — its fresh state wins
      }
      if (this.wasOffline) {
        this.log.info('emberd recovered');
        this.wasOffline = false;
      }
      if (!state.online) {
        this.log.debug('sauna offline (Tuya not answering); serving last-known state');
      }
      this.applyAll(state);
    } catch (e) {
      this.pollFailures += 1;
      if (this.pollFailures >= 3 && !this.wasOffline) {
        this.reachable = false;
        this.wasOffline = true;
        this.log.warn('emberd unreachable (%s) — accessories will show No Response', String(e));
      }
    }
  }

  public applyAll(state: EmberdState): void {
    this.state = state;
    for (const h of this.handlers) {
      h.applyState(state);
    }
  }

  /** Serialized /control so bursts (scenes) hit emberd in deterministic order.
   *  Applies the returned fresh state to every handler — emberd's sticky command
   *  overlay guarantees the next polls won't revert it. */
  public control(body: ControlBody): Promise<void> {
    const run = this.controlChain.then(async () => {
      this.controlEpoch += 1;
      try {
        const fresh = await this.client.control(body);
        this.controlEpoch += 1;
        this.applyAll(fresh);
        this.authErrorLogged = false;
      } catch (e) {
        if (e instanceof AuthError) {
          if (!this.authErrorLogged) {
            this.log.error('emberd rejected the API key — check the apiKey in the plugin config');
            this.authErrorLogged = true;
          }
        } else {
          this.log.warn('control failed: %s', String(e));
        }
        throw new this.api.hap.HapStatusError(this.api.hap.HAPStatus.SERVICE_COMMUNICATION_FAILURE);
      }
    });
    this.controlChain = run.catch(() => undefined); // keep the chain alive after failures
    return run;
  }

  /** For onGet handlers: cached reads only; surface sustained outages as No Response. */
  public assertReachable(): void {
    if (!this.reachable) {
      throw new this.api.hap.HapStatusError(this.api.hap.HAPStatus.SERVICE_COMMUNICATION_FAILURE);
    }
  }
}
