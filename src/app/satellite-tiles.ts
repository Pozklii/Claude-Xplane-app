// Esri World Imagery for the landing page's mini globe (mini-globe.tsx),
// which draws on a plain 2D canvas rather than through a map library: its
// Web Mercator tiles are fetched as needed, kept as pixels, and sampled
// pixel by pixel onto the globe's orthographic view.

const TILE = 256;
const MIN_LEVEL = 2;
const MAX_LEVEL = 18;

export const SATELLITE_CREDIT =
  "Esri, Maxar, Earthstar Geographics, and the GIS User Community";

const tileUrl = (z: number, x: number, y: number) =>
  `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${z}/${y}/${x}`;

type Entry = Uint8ClampedArray | "loading" | "failed";
const tiles = new Map<string, Entry>();
const listeners = new Set<() => void>();

/** Calls `listener` whenever another tile arrives; returns an unsubscribe. */
export function onTileLoad(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function request(z: number, x: number, y: number, key: string) {
  tiles.set(key, "loading");
  const image = new Image();
  // Esri serves its tiles with CORS headers, so their pixels can be read.
  image.crossOrigin = "anonymous";
  image.onload = () => {
    try {
      const canvas = document.createElement("canvas");
      canvas.width = TILE;
      canvas.height = TILE;
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      if (!ctx) throw new Error("no 2d context");
      ctx.drawImage(image, 0, 0, TILE, TILE);
      tiles.set(key, ctx.getImageData(0, 0, TILE, TILE).data);
    } catch {
      tiles.set(key, "failed");
    }
    for (const listener of listeners) listener();
  };
  image.onerror = () => tiles.set(key, "failed");
  image.src = tileUrl(z, x, y);
}

function tile(z: number, x: number, y: number, load: boolean) {
  const key = `${z}/${x}/${y}`;
  const entry = tiles.get(key);
  if (entry instanceof Uint8ClampedArray) return entry;
  if (entry === undefined && load) request(z, x, y, key);
  return null;
}

/** The tile level whose detail matches a sphere `radius` device pixels
 * across (its equator about as many pixels round as the level's world). */
export function imageryLevel(radius: number) {
  const level = Math.floor(Math.log2((2 * Math.PI * radius) / TILE));
  return Math.min(MAX_LEVEL, Math.max(MIN_LEVEL, level));
}

let prefetched = false;
/** The whole world at the lowest level (16 tiles), so there's always
 * something to fall back on while closer tiles load. */
export function prefetchWorld() {
  if (prefetched) return;
  prefetched = true;
  const n = 2 ** MIN_LEVEL;
  for (let x = 0; x < n; x++)
    for (let y = 0; y < n; y++) tile(MIN_LEVEL, x, y, true);
}

const RAD = Math.PI / 180;
const MAX_LAT = 85.0511;

export type ImageryView = {
  /** Canvas size, in device pixels (square). */
  size: number;
  /** The sphere's radius and the round window's, in device pixels. */
  radius: number;
  windowRadius: number;
  /** Where the globe faces, in degrees. */
  lat: number;
  lon: number;
  level: number;
};

// Calls `visit(level, tileX, tileY, px, py)` with the Mercator position (at
// `level`) of each canvas pixel on the visible sphere, every `step` pixels.
function eachPoint(
  view: ImageryView,
  step: number,
  visit: (index: number, wx: number, wy: number) => void,
) {
  const { size, radius, windowRadius, lat, lon, level } = view;
  const c = size / 2;
  const sin0 = Math.sin(lat * RAD);
  const cos0 = Math.cos(lat * RAD);
  const world = 2 ** level;
  const maxY = Math.log(Math.tan(Math.PI / 4 + (MAX_LAT * RAD) / 2));
  const w2 = windowRadius * windowRadius;
  for (let py = 0; py < size; py += step) {
    const dy = c - (py + 0.5);
    for (let px = 0; px < size; px += step) {
      const dx = px + 0.5 - c;
      if (dx * dx + dy * dy > w2) continue;
      const x = dx / radius;
      const y = dy / radius;
      const rho2 = x * x + y * y;
      if (rho2 >= 1) continue;
      // Inverse orthographic projection.
      const z = Math.sqrt(1 - rho2);
      const phi = Math.asin(Math.max(-1, Math.min(1, z * sin0 + y * cos0)));
      const lambda = lon * RAD + Math.atan2(x, z * cos0 - y * sin0);
      // Web Mercator, in tiles at this level.
      const merc = Math.max(
        -maxY,
        Math.min(maxY, Math.log(Math.tan(Math.PI / 4 + phi / 2))),
      );
      let u = (lambda / (2 * Math.PI) + 0.5) % 1;
      if (u < 0) u += 1;
      const v = (1 - merc / Math.PI) / 2;
      visit(py * size + px, u * world, Math.min(world - 1e-9, v * world));
    }
  }
}

/** Asks for the tiles a view will need (sampled on a coarse grid), ahead of
 * turning to it. */
export function prefetchView(view: ImageryView) {
  const step = Math.max(4, Math.floor(view.size / 24));
  eachPoint(view, step, (_, wx, wy) => {
    tile(view.level, Math.floor(wx), Math.floor(wy), true);
  });
}

/** Draws the imagery for a view into `out` (the canvas's size): opaque
 * where a tile (or, until it arrives, a lower level's) covers the pixel,
 * clear elsewhere, so whatever is drawn underneath shows through. Fetches
 * missing tiles at the view's level when `load` is set. */
export function renderImagery(
  out: ImageData,
  view: ImageryView,
  load: boolean,
) {
  const data = out.data;
  data.fill(0);
  // The last tile looked up, since neighbouring pixels nearly always share
  // one.
  let lastX = -1;
  let lastY = -1;
  let lastTile: Uint8ClampedArray | null = null;
  let lastScale = 1;
  eachPoint(view, 1, (index, wx, wy) => {
    const tx = Math.floor(wx);
    const ty = Math.floor(wy);
    if (tx !== lastX || ty !== lastY) {
      lastX = tx;
      lastY = ty;
      lastTile = tile(view.level, tx, ty, load);
      lastScale = 1;
      // Not here yet: the closest lower level that is.
      for (let up = 1; !lastTile && view.level - up >= MIN_LEVEL; up++) {
        lastScale = 2 ** up;
        lastTile = tile(
          view.level - up,
          Math.floor(tx / lastScale),
          Math.floor(ty / lastScale),
          false,
        );
      }
    }
    if (!lastTile) return;
    const sx = Math.min(
      TILE - 1,
      Math.floor(((((wx / lastScale) % 1) + 1) % 1) * TILE),
    );
    const sy = Math.min(
      TILE - 1,
      Math.floor(((((wy / lastScale) % 1) + 1) % 1) * TILE),
    );
    const from = (sy * TILE + sx) * 4;
    const to = index * 4;
    data[to] = lastTile[from];
    data[to + 1] = lastTile[from + 1];
    data[to + 2] = lastTile[from + 2];
    data[to + 3] = 255;
  });
}
