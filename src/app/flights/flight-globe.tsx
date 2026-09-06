"use client";

import dynamic from "next/dynamic";
import { useEffect, useMemo, useRef, useState } from "react";
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
  fromCode: string;
  toCode: string;
  label: string;
};

type MapStyle = "day" | "night";
type MarkerDatum = GlobePoint & { highlighted: boolean };

const GLOBE_HEIGHT = 480;
const TEXTURES: Record<MapStyle, string> = {
  day: "/globe/earth-blue-marble.jpg",
  night: "/globe/earth-night.jpg",
};
const ARC_COLOR = "rgba(250, 204, 21, 0.45)";
const ARC_COLOR_SELECTED = "#ffffff";

function markerElement(d: object) {
  const point = d as MarkerDatum;
  const wrapper = document.createElement("div");
  wrapper.style.display = "flex";
  wrapper.style.alignItems = "center";
  wrapper.style.gap = "4px";
  wrapper.style.transform = "translate(-50%, -50%)";
  wrapper.style.pointerEvents = "none";

  const dot = document.createElement("div");
  const size = point.highlighted ? 8 : 5;
  dot.style.width = `${size}px`;
  dot.style.height = `${size}px`;
  dot.style.borderRadius = "50%";
  dot.style.background = point.highlighted ? "#ffffff" : "#facc15";
  dot.style.border = "1px solid rgba(0,0,0,0.5)";
  dot.style.boxSizing = "border-box";
  wrapper.appendChild(dot);

  if (point.highlighted) {
    const label = document.createElement("span");
    label.textContent = `${point.city} (${point.code})`;
    label.style.fontSize = "11px";
    label.style.fontWeight = "600";
    label.style.fontFamily = "ui-sans-serif, system-ui, sans-serif";
    label.style.color = "#ffffff";
    label.style.textShadow = "0 1px 3px rgba(0,0,0,0.9)";
    label.style.whiteSpace = "nowrap";
    wrapper.appendChild(label);
  }

  return wrapper;
}

function setMarkerVisibility(el: HTMLElement, isVisible: boolean) {
  el.style.display = isVisible ? "flex" : "none";
}

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
  const [selectedId, setSelectedId] = useState<string | null>(null);

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

  const selectedArc = arcs.find((arc) => arc.id === selectedId) ?? null;

  const highlightedCodes = useMemo(() => {
    if (!selectedArc) return new Set<string>();
    return new Set([selectedArc.fromCode, selectedArc.toCode]);
  }, [selectedArc]);

  const markers = useMemo<MarkerDatum[]>(
    () =>
      points.map((p) => ({
        ...p,
        highlighted: highlightedCodes.has(p.code),
      })),
    [points, highlightedCodes],
  );

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
          lineHoverPrecision={20}
          htmlElementsData={markers}
          htmlLat="lat"
          htmlLng="lng"
          htmlElement={markerElement}
          htmlElementVisibilityModifier={setMarkerVisibility}
          arcsData={arcs}
          arcStartLat="startLat"
          arcStartLng="startLng"
          arcEndLat="endLat"
          arcEndLng="endLng"
          arcColor={(d: object) =>
            (d as GlobeArc).id === selectedId ? ARC_COLOR_SELECTED : ARC_COLOR
          }
          arcStroke={null}
          arcLabel={(d: object) => (d as GlobeArc).label}
          onArcClick={(d: object) => {
            const arc = d as GlobeArc;
            setSelectedId((prev) => (prev === arc.id ? null : arc.id));
          }}
          onGlobeClick={() => setSelectedId(null)}
        />
      )}

      <p className="px-3 py-1.5 text-[11px] text-zinc-400">
        Click a flight to see its airports. Imagery &copy; NASA Visible Earth
        (Blue Marble / Black Marble).
      </p>
    </div>
  );
}
