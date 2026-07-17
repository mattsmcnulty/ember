/** HomeKit is Celsius-internal; the device is whole-°F (60-175). These helpers keep the
 *  round-trip stable: dial → whole °F → back to the 0.5 °C step grid, no jitter. */

export const MIN_F = 60;
export const MAX_F = 175;

// Aligned to the 0.5 °C step grid that TargetTemperature uses (60°F=15.56, 175°F=79.44).
export const MIN_C = 15.5;
export const MAX_C = 79.5;

export const f2c = (f: number): number => ((f - 32) * 5) / 9;
export const c2f = (c: number): number => (c * 9) / 5 + 32;

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));

/** HomeKit set → device: land on a whole °F in range. */
export const targetCtoF = (c: number): number => clamp(Math.round(c2f(c)), MIN_F, MAX_F);

/** Device → HomeKit target: quantize to the 0.5 °C characteristic step. */
export const targetFtoC = (f: number): number => clamp(Math.round(f2c(f) * 2) / 2, MIN_C, MAX_C);

/** Device → HomeKit current reading: 0.1 °C is plenty. */
export const currentFtoC = (f: number): number => Math.round(f2c(f) * 10) / 10;
