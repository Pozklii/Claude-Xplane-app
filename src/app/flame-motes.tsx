"use client";

import { useEffect, useRef } from "react";
import styles from "./home.module.css";

const MOTES = 90;
// A full turn of the slowest orbit takes about this long, in seconds.
const ORBIT_SECONDS = 260;

// Glowing specks for the fractal-flame backgrounds: each slowly orbits the
// middle of the page (the flame's own swirl) at its own pace and distance,
// drifting in and out a little and twinkling, in the flame's colours.
// Drawn additively on a canvas covering the page; paused when the tab is
// hidden (requestAnimationFrame stops), and a single still frame under
// prefers-reduced-motion.
export function FlameMotes({ colors }: { colors: string[] }) {
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
        const a = m.angle + (m.speed * t * Math.PI * 2) / ORBIT_SECONDS;
        const d = reach * (m.dist + 0.03 * Math.sin(t * 0.21 + m.wobble));
        const x = cx + Math.cos(a) * d;
        // Squashed a little, like a swirl seen at an angle.
        const y = cy + Math.sin(a) * d * 0.7;
        if (x < -10 || x > W + 10 || y < -10 || y > H + 10) continue;
        const glow = 0.25 + 0.75 * Math.pow(0.5 + 0.5 * Math.sin(t * m.twinkle + m.phase), 3);
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
  }, [colors]);

  return <canvas ref={canvasRef} className={styles.flameMotes} aria-hidden="true" />;
}
