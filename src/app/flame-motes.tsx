"use client";

import { useEffect, useRef } from "react";
import styles from "./home.module.css";

const MOTES = 90;
// A full turn of the slowest orbit takes about this long, in seconds.
const ORBIT_SECONDS = 260;
// Floating, the slowest mote takes about this long to rise up the page.
const RISE_SECONDS = 90;

// Glowing specks for the fractal-flame backgrounds: each slowly orbits the
// middle of the page (the flame's own swirl) at its own pace and distance,
// drifting in and out a little and twinkling, in the flame's colours.
// Drawn additively on a canvas covering the page; paused when the tab is
// hidden (requestAnimationFrame stops), and a single still frame under
// prefers-reduced-motion. With `float`, they instead rise slowly up the
// page like dust in still air, swaying a little as they go.
export function FlameMotes({
  colors,
  float = false,
}: {
  colors: string[];
  float?: boolean;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;

    let seed = 7;
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    const motes = Array.from({ length: MOTES }, () => ({
      angle: rnd() * Math.PI * 2,
      // Mostly out in the flame's arms, a few nearer the core.
      dist: 0.12 + Math.pow(rnd(), 0.7) * 0.75,
      speed: (0.4 + rnd() * 0.8) * (rnd() < 0.2 ? -1 : 1),
      wobble: rnd() * Math.PI * 2,
      size: 0.6 + Math.pow(rnd(), 3) * 2.4,
      twinkle: 0.4 + rnd() * 1.2,
      phase: rnd() * Math.PI * 2,
      color: colors[Math.floor(rnd() * colors.length)],
    }));

    const draw = (t: number) => {
      ctx.clearRect(0, 0, W, H);
      ctx.globalCompositeOperation = "lighter";
      const cx = W / 2;
      const cy = H / 2;
      const reach = Math.hypot(W, H) / 2;
      for (const m of motes) {
        let x: number;
        let y: number;
        if (float) {
          // Each starts at its own height (from its angle) and column
          // (from its distance), rising at its own pace, wrapping round.
          const rise =
            (m.angle / (Math.PI * 2) + (Math.abs(m.speed) * t) / RISE_SECONDS) %
            1;
          y = H + 10 - rise * (H + 20);
          x = (m.dist / 0.87) * W + 14 * m.size * Math.sin(t * 0.3 + m.wobble);
        } else {
          const a = m.angle + (m.speed * t * Math.PI * 2) / ORBIT_SECONDS;
          const d = reach * (m.dist + 0.03 * Math.sin(t * 0.21 + m.wobble));
          x = cx + Math.cos(a) * d;
          // Squashed a little, like a swirl seen at an angle.
          y = cy + Math.sin(a) * d * 0.7;
        }
        if (x < -10 || x > W + 10 || y < -10 || y > H + 10) continue;
        const glow =
          0.25 +
          0.75 * Math.pow(0.5 + 0.5 * Math.sin(t * m.twinkle + m.phase), 3);
        const r = m.size * 4;
        const g = ctx.createRadialGradient(x, y, 0, x, y, r);
        g.addColorStop(0, `rgba(${m.color},${(0.9 * glow).toFixed(3)})`);
        g.addColorStop(0.25, `rgba(${m.color},${(0.35 * glow).toFixed(3)})`);
        g.addColorStop(1, `rgba(${m.color},0)`);
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
      }
    };

    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let W = 0;
    let H = 0;
    const resize = () => {
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      W = canvas.clientWidth;
      H = canvas.clientHeight;
      canvas.width = Math.round(W * dpr);
      canvas.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      // Resizing clears the canvas; a still frame needs redrawing.
      if (still) draw(0);
    };

    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    let frame = 0;
    if (!still) {
      const start = performance.now();
      const tick = (now: number) => {
        draw((now - start) / 1000);
        frame = requestAnimationFrame(tick);
      };
      frame = requestAnimationFrame(tick);
    }
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [colors, float]);

  return (
    <canvas ref={canvasRef} className={styles.flameMotes} aria-hidden="true" />
  );
}
