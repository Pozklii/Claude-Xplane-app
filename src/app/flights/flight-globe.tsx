"use client";

import dynamic from "next/dynamic";
import { useEffect, useRef, useState } from "react";
import type { GlobeMethods } from "react-globe.gl";

const Globe = dynamic(() => import("react-globe.gl"), {
  ssr: false,
  loading: () => (
    <div className="flex h-[480px] items-center justify-center text-sm text-zinc-500">
      Loading globe…
    </div>
  ),
});

export type GlobePoint = {
  code: string;
  name: string;
  lat: number;
  lng: number;
};

export type GlobeArc = {
  id: string;
  startLat: number;
  startLng: number;
  endLat: number;
  endLng: number;
  label: string;
};

const GLOBE_HEIGHT = 480;

export function FlightGlobe({
  points,
  arcs,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
}) {
  const globeRef = useRef<GlobeMethods | undefined>(undefined);
  const containerRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const observer = new ResizeObserver(([entry]) => {
      setWidth(entry.contentRect.width);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!globeRef.current || points.length === 0) return;
    const avgLat =
      points.reduce((sum, p) => sum + p.lat, 0) / points.length;
    const avgLng =
      points.reduce((sum, p) => sum + p.lng, 0) / points.length;
    globeRef.current.pointOfView({ lat: avgLat, lng: avgLng, altitude: 2 }, 0);
  }, [points]);

  return (
    <div
      ref={containerRef}
      className="overflow-hidden rounded-2xl border border-black/[.08] bg-[#04060f] dark:border-white/[.145]"
    >
      {width > 0 && (
        <Globe
          ref={globeRef}
          width={width}
          height={GLOBE_HEIGHT}
          globeTileEngineUrl={(x, y, l) =>
            `https://basemaps.cartocdn.com/rastertiles/voyager/${l}/${x}/${y}.png`
          }
          backgroundColor="rgba(0,0,0,0)"
          showAtmosphere
          atmosphereColor="#60a5fa"
          pointsData={points}
          pointLat="lat"
          pointLng="lng"
          pointColor={() => "#e11d48"}
          pointAltitude={0.01}
          pointRadius={0.3}
          pointLabel={(d) => {
            const point = d as GlobePoint;
            return `${point.name} (${point.code})`;
          }}
          arcsData={arcs}
          arcStartLat="startLat"
          arcStartLng="startLng"
          arcEndLat="endLat"
          arcEndLng="endLng"
          arcColor={() => ["#2563eb", "#7c3aed"]}
          arcDashLength={0.4}
          arcDashGap={0.2}
          arcDashAnimateTime={4000}
          arcStroke={0.5}
          arcLabel={(d) => (d as GlobeArc).label}
        />
      )}
      <p className="px-3 py-1.5 text-[11px] text-zinc-500 dark:text-zinc-500">
        Map tiles &copy;{" "}
        <a
          href="https://carto.com/attributions"
          className="underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          CARTO
        </a>
        , data &copy;{" "}
        <a
          href="https://www.openstreetmap.org/copyright"
          className="underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          OpenStreetMap
        </a>{" "}
        contributors
      </p>
    </div>
  );
}
