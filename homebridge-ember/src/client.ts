/** Thin fetch client for the emberd HTTP API (zero dependencies, node >= 18). */

export interface EmberdState {
  power: boolean;
  heater: boolean;
  currentTempF: number | null;
  targetTempF: number | null;
  timerSetMin: number | null;
  timerRemainingMin: number | null;
  chromoColor: string | null;
  chromoCycle: boolean;
  footwell: boolean;
  unit: string;
  online: boolean;
  updatedAt: number;
}

export interface ControlBody {
  power?: boolean;
  heater?: boolean;
  targetTempF?: number;
  timerMin?: number;
  chromoColor?: string;
  chromoCycle?: boolean;
  footwell?: boolean;
}

export class AuthError extends Error {
  constructor() {
    super('emberd rejected the API key (401)');
  }
}

export class EmberdClient {
  constructor(
    private readonly baseUrl: string,
    private readonly apiKey?: string,
  ) {}

  async getState(): Promise<EmberdState> {
    const res = await fetch(`${this.baseUrl}/state`, { signal: AbortSignal.timeout(4000) });
    if (!res.ok) {
      throw new Error(`GET /state ${res.status}`);
    }
    return (await res.json()) as EmberdState;
  }

  /** POST /control does real Tuya round-trips (reconnect per write) — generous timeout. */
  async control(body: ControlBody): Promise<EmberdState> {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.apiKey) {
      headers.Authorization = `Bearer ${this.apiKey}`;
    }
    const res = await fetch(`${this.baseUrl}/control`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
    if (res.status === 401) {
      throw new AuthError();
    }
    if (!res.ok) {
      throw new Error(`POST /control ${res.status}`);
    }
    return (await res.json()) as EmberdState;
  }
}
