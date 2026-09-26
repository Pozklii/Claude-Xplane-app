"use client";

import { useEffect, useRef } from "react";
import { startEngineFx } from "./engine-fx";
import styles from "./home.module.css";

// The hero's animated gold turbofan (see engine-fx.ts), drawn on a canvas
// covering the hero. The engine itself sits on the anchor box, which CSS
// positions and sizes (.engineBox), so the layout stays in the stylesheet.
export function EngineCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const anchorRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!canvasRef.current || !anchorRef.current) return;
    return startEngineFx(canvasRef.current, anchorRef.current);
  }, []);

  return (
    <>
      <canvas ref={canvasRef} className={styles.engineCanvas} aria-hidden="true" />
      <div ref={anchorRef} className={styles.engineBox} aria-hidden="true" />
    </>
  );
}
