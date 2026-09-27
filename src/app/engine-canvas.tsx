"use client";

import { useEffect, useRef } from "react";
import { startEngineFx } from "./engine-fx";
import styles from "./home.module.css";

// The hero's animated gold turbofan (see engine-fx.ts), drawn on a canvas
// covering the hero. The engine itself sits on the hero's anchor element
// (marked data-engine-anchor), which the page lays out like any other box,
// so the engine's place and size stay in the layout and stylesheet.
export function EngineCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const anchor = canvas?.parentElement?.querySelector<HTMLElement>("[data-engine-anchor]");
    if (!canvas || !anchor) return;
    return startEngineFx(canvas, anchor);
  }, []);

  return <canvas ref={canvasRef} className={styles.engineCanvas} aria-hidden="true" />;
}
