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
  city: string;
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

type MapStyle = "day" | "night";

const GLOBE_HEIGHT = 480;
const TEXTURES: Record<MapStyle, string> = {
  day: "/globe/earth-blue-marble.jpg",
  night: "/globe/earth-night.jpg",
};

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
  const [mapStyle, setMapStyle] = useState<MapStyle>("day");

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
    const avgLat = points.reduce((sum, p) => sum + p.lat, 0) / points.length;
    const avgLng = points.reduce((sum, p) => sum + p.lng, 0) / points.length;
    globeRef.current.pointOfView({ lat: avgLat, lng: avgLng, altitude: 1 }, 0);
  }, [points]);

  return (
    <div
      ref={containerRef}
      className="relative overflow-hidden rounded-2xl border border-black/[.08] bg-[#04060f] dark:border-white/[.145]"
    >
      <div className="absolute right-3 top-3 z-10 flex rounded-full border border-white/20 bg-black/40 p-0.5 backdrop-blur-sm">
        {(
          [
            ["day", "Day"],
            ["night", "Night"],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            onClick={() => setMapStyle(value)}
            className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
              mapStyle === value
                ? "bg-white text-black"
                : "text-white/80 hover:text-white"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {width > 0 && (
        <Globe
          ref={globeRef}
          width={width}
          height={GLOBE_HEIGHT}
          globeImageUrl={TEXTURES[mapStyle]}
          backgroundColor="rgba(0,0,0,0)"
          showAtmosphere
          atmosphereColor="#60a5fa"
          pointsData={points}
          pointLat="lat"
          pointLng="lng"
          pointColor={() => "#facc15"}
          pointAltitude={0.005}
          pointRadius={0.15}
          labelsData={points}
          labelLat="lat"
          labelLng="lng"
          labelText={(d) => {
            const point = d as GlobePoint;
            return `${point.city} (${point.code})`;
          }}
          labelSize={1.0}
          labelDotRadius={0}
          labelColor={() => "#facc15"}
          labelAltitude={0.006}
          labelResolution={4}
          arcsData={arcs}
          arcStartLat="startLat"
          arcStartLng="startLng"
          arcEndLat="endLat"
          arcEndLng="endLng"
          arcColor={() => "#facc15"}
          arcLabel={(d) => (d as GlobeArc).label}
        />
      )}

      <p className="px-3 py-1.5 text-[11px] text-zinc-400">
        Imagery &copy; NASA Visible Earth (Blue Marble / Black Marble).
      </p>
    </div>
  );
}
