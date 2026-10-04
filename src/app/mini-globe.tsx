"use client";

import { geoOrthographic, geoPath } from "d3-geo";
import { useEffect, useRef } from "react";
import { landShapes } from "./land-shapes";
import styles from "./home.module.css";

export type MiniGlobeRoute = {
  startLat: number;
  startLng: number;
  endLat: number;
  endLng: number;
};

/** Where the globe last faced, kept by the caller so a new globe (the tour
 * card is rebuilt for every flight) turns on from there. */
export type MiniGlobeView = { lat: number; lon: number } | null;

const TURN_MS = 1100;
const DRAW_MS = 900;
const FLIGHT_MS = 3600;
const RAD = Math.PI / 180;

// The Flight Map globe's colours (flight-globe.tsx): the map style's water,
// and land left clear over the page's dark ground.
const WATER = "rgb(158, 189, 255)";
const LAND = "#020304";

let land: GeoJSON.MultiPolygon | null = null;

type Vec = [number, number, number];
const toVec = (lat: number, lon: number): Vec => [
  Math.cos(lat * RAD) * Math.cos(lon * RAD),
  Math.cos(lat * RAD) * Math.sin(lon * RAD),
  Math.sin(lat * RAD),
];
const toLatLon = ([x, y, z]: Vec) => ({
  lat: Math.atan2(z, Math.hypot(x, y)) / RAD,
  lon: Math.atan2(y, x) / RAD,
});
// Spherical interpolation between two unit vectors.
function slerp(a: Vec, b: Vec, t: number): Vec {
  const dot = Math.max(
    -1,
    Math.min(1, a[0] * b[0] + a[1] * b[1] + a[2] * b[2]),
  );
  const omega = Math.acos(dot);
  if (omega < 1e-6) return a;
  const sa = Math.sin((1 - t) * omega) / Math.sin(omega);
  const sb = Math.sin(t * omega) / Math.sin(omega);
  return [sa * a[0] + sb * b[0], sa * a[1] + sb * b[1], sa * a[2] + sb * b[2]];
}
const ease = (t: number) => 1 - Math.pow(1 - Math.min(1, Math.max(0, t)), 3);

// A small globe for the landing page's example-flight tour, in the Flight
// Map's style (light blue seas, dark land), the current flight's route as a
// glowing great-circle arc
// between its two airports, drawn in as each flight arrives, with a spark
// flying along it. The globe turns to face each new route. Canvas 2D (no
// map library); holds still, without the turning or the spark, under
// prefers-reduced-motion.
export function MiniGlobe({
  route,
  color,
  viewRef,
}: {
  route: MiniGlobeRoute;
  color: string;
  viewRef: React.RefObject<MiniGlobeView>;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const a = toVec(route.startLat, route.startLng);
    const b = toVec(route.endLat, route.endLng);
    // Face the middle of the route (tipped a little towards the equator,
    // which reads better than looking straight down on a pole).
    const mid = toLatLon(slerp(a, b, 0.5));
    const target = toVec(mid.lat * 0.8, mid.lon);
    const from = viewRef.current
      ? toVec(viewRef.current.lat, viewRef.current.lon)
      : target;
    const path = Array.from({ length: 65 }, (_, i) => slerp(a, b, i / 64));
    const start = performance.now();

    const draw = (now: number) => {
      const size = canvas.clientWidth;
      // Not laid out yet (or hidden): nothing to draw.
      if (size < 16) return;
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      if (canvas.width !== Math.round(size * dpr)) {
        canvas.width = Math.round(size * dpr);
        canvas.height = Math.round(size * dpr);
      }
      const elapsed = still ? Infinity : now - start;
      const centre = toLatLon(slerp(from, target, ease(elapsed / TURN_MS)));
      viewRef.current = centre;
      const lat0 = centre.lat * RAD;
      const lon0 = centre.lon * RAD;
      const sin0 = Math.sin(lat0);
      const cos0 = Math.cos(lat0);
      const w = canvas.width;
      const r = w / 2 - 2 * dpr;
      const c = w / 2;
      // Orthographic projection; z > 0 is the facing hemisphere.
      const project = (lat: number, lon: number) => {
        const cl = Math.cos(lat);
        const dl = lon - lon0;
        return {
          x: c + r * cl * Math.sin(dl),
          y: c - r * (cos0 * Math.sin(lat) - sin0 * cl * Math.cos(dl)),
          z: sin0 * Math.sin(lat) + cos0 * cl * Math.cos(dl),
        };
      };

      ctx.clearRect(0, 0, w, w);
      // The sphere's seas, then the land on them, clipped at the horizon.
      const projection = geoOrthographic()
        .rotate([-centre.lon, -centre.lat])
        .scale(r)
        .translate([c, c])
        .clipAngle(90);
      const shape = geoPath(projection, ctx);
      ctx.fillStyle = WATER;
      ctx.beginPath();
      shape({ type: "Sphere" });
      ctx.fill();
      land ??= landShapes();
      ctx.fillStyle = LAND;
      ctx.beginPath();
      shape(land);
      ctx.fill();

      // The route, drawn in from the departure airport, the far side hidden.
      const drawn = ease((elapsed - TURN_MS * 0.5) / DRAW_MS);
      const upto = Math.round(drawn * (path.length - 1));
      const pts = path.map((v) => {
        const { lat, lon } = toLatLon(v);
        return project(lat * RAD, lon * RAD);
      });
      const stroke = (width: number, alpha: number) => {
        ctx.strokeStyle = color;
        ctx.globalAlpha = alpha;
        ctx.lineWidth = width * dpr;
        ctx.lineCap = "round";
        ctx.beginPath();
        let pen = false;
        for (let i = 0; i <= upto; i++) {
          const p = pts[i];
          if (p.z <= 0) {
            pen = false;
            continue;
          }
          if (pen) ctx.lineTo(p.x, p.y);
          else ctx.moveTo(p.x, p.y);
          pen = true;
        }
        ctx.stroke();
      };
      if (upto > 0) {
        stroke(5, 0.22);
        stroke(1.6, 1);
      }
      ctx.globalAlpha = 1;
      for (const p of [pts[0], pts[pts.length - 1]]) {
        if (p.z <= 0) continue;
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(p.x, p.y, 2.6 * dpr, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = "white";
        ctx.beginPath();
        ctx.arc(p.x, p.y, 1.1 * dpr, 0, Math.PI * 2);
        ctx.fill();
      }
      // Once drawn, a spark flies the route, over and over.
      if (!still && drawn >= 1) {
        const t = ((elapsed - TURN_MS * 0.5 - DRAW_MS) % FLIGHT_MS) / FLIGHT_MS;
        const p = pts[Math.round(t * (pts.length - 1))];
        if (p.z > 0) {
          const glow = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, 6 * dpr);
          glow.addColorStop(0, "rgba(255, 255, 255, 0.95)");
          glow.addColorStop(1, "rgba(255, 255, 255, 0)");
          ctx.fillStyle = glow;
          ctx.beginPath();
          ctx.arc(p.x, p.y, 6 * dpr, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    };

    if (still) {
      draw(performance.now());
      return;
    }
    let frame = 0;
    const tick = (now: number) => {
      draw(now);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [route, color, viewRef]);

  return (
    <canvas ref={canvasRef} className={styles.miniGlobe} aria-hidden="true" />
  );
}
