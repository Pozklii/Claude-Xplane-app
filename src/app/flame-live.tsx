"use client";

import { useEffect, useRef, useState } from "react";
import { startFlame } from "./flame-gl";
import { FLAME_PARAMS, type FlameParams } from "./flame-params";
import { generateFlame, renderFlameStill } from "./flame-random";
import styles from "./home.module.css";

// The still a generated flame falls back to: small, drawn on the CPU and
// scaled up (soft anyway, and quick).
const STILL_WIDTH = 360;
const STILL_HEIGHT = 225;

// The live, morphing version of a fractal-flame background (flame-gl.ts),
// faded in once it has built up: either one of the hand-picked flames
// (`flame`), over its pre-rendered still, or one generated from `seed`
// (flame-random.ts) over the page's dark ground. Under
// prefers-reduced-motion, without WebGL2, or on a device too slow to keep
// it running, the hand-picked flames keep their still, and a generated one
// gets a still drawn here instead.
export function FlameLive({
  flame,
  seed,
  sharp = false,
}: {
  flame?: keyof typeof FLAME_PARAMS;
  seed?: number;
  sharp?: boolean;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stillRef = useRef<HTMLCanvasElement>(null);
  const [live, setLive] = useState(false);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    // Generated in the browser: a few dozen milliseconds of work that
    // needn't run on every request.
    const params: FlameParams | null =
      seed !== undefined
        ? generateFlame(seed)
        : flame
          ? FLAME_PARAMS[flame]
          : null;
    if (!params) return;

    const drawStill = () => {
      const target = stillRef.current;
      const ctx = target?.getContext("2d");
      if (seed === undefined || !target || !ctx) return;
      const pixels = renderFlameStill(params, STILL_WIDTH, STILL_HEIGHT, 8000);
      // (Until drawn, the canvas is simply transparent.)
      ctx.putImageData(new ImageData(pixels, STILL_WIDTH, STILL_HEIGHT), 0, 0);
    };

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      drawStill();
      return;
    }
    return startFlame(canvas, params, {
      onReady: () => setLive(true),
      onFail: () => {
        setLive(false);
        drawStill();
      },
      sharp,
    });
  }, [flame, seed, sharp]);

  return (
    <>
      {seed !== undefined && (
        <canvas
          ref={stillRef}
          width={STILL_WIDTH}
          height={STILL_HEIGHT}
          className={styles.flameStill}
          aria-hidden="true"
        />
      )}
      <canvas
        ref={canvasRef}
        className={`${styles.flameLive} ${live ? styles.flameLiveOn : ""}`}
        aria-hidden="true"
      />
    </>
  );
}
