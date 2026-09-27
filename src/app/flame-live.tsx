"use client";

import { useEffect, useRef, useState } from "react";
import { startFlame } from "./flame-gl";
import { FLAME_PARAMS } from "./flame-params";
import styles from "./home.module.css";

// The live, morphing version of a fractal-flame background (flame-gl.ts),
// faded in over the still once it has built up. The still stays under it,
// and is all there is under prefers-reduced-motion, without WebGL2, or on
// a device too slow to keep it running.
export function FlameLive({ flame }: { flame: keyof typeof FLAME_PARAMS }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [live, setLive] = useState(false);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    return startFlame(canvas, FLAME_PARAMS[flame], {
      onReady: () => setLive(true),
      onFail: () => setLive(false),
    });
  }, [flame]);

  return (
    <canvas
      ref={canvasRef}
      className={`${styles.flameLive} ${live ? styles.flameLiveOn : ""}`}
      aria-hidden="true"
    />
  );
}
