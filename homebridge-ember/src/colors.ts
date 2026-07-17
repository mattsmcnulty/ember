/** The Eclipse 2's real chromotherapy palette (DP21) in HomeKit hue/sat terms.
 *  Mirrors ember/Shared/ChromaPalette.swift — only these 7 values produce a solid;
 *  mode1 is a no-op and mode8/mode9 read back as white. */

export interface Solid {
  mode: string;
  name: string;
  hue: number; // 0-360
  sat: number; // 0-100
}

export const WHITE: Solid = { mode: 'mode', name: 'White', hue: 37.5, sat: 8 };

export const CHROMATIC: Solid[] = [
  { mode: 'mode3', name: 'Red', hue: 3, sat: 81 },
  { mode: 'mode2', name: 'Yellow', hue: 48.7, sat: 90 },
  { mode: 'mode7', name: 'Green', hue: 133.5, sat: 75.6 },
  { mode: 'mode6', name: 'Teal', hue: 177.1, sat: 74.1 },
  { mode: 'mode5', name: 'Blue', hue: 212, sat: 90 },
  { mode: 'mode4', name: 'Pink', hue: 332.6, sat: 70 },
];

const hueDistance = (a: number, b: number): number => {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
};

/** Snap a HomeKit color pick to the nearest real solid. Low saturation is the wheel's
 *  whitish center — treat it as White regardless of hue. The chromatic solids are
 *  >= 46° apart in hue, so hue-only distance is unambiguous. */
export function nearestSolid(hue: number, sat: number): Solid {
  if (sat < 25) {
    return WHITE;
  }
  let best = CHROMATIC[0];
  for (const s of CHROMATIC) {
    if (hueDistance(hue, s.hue) < hueDistance(hue, best.hue)) {
      best = s;
    }
  }
  return best;
}

/** Device -> HomeKit: unknown / mode1 / mode8 / mode9 all render as white. */
export function solidFor(mode: string | null | undefined): Solid {
  return CHROMATIC.find((s) => s.mode === mode) ?? WHITE;
}
