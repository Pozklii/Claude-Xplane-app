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

type ViewMode = "3d" | "2d";
type MarkerDatum = GlobePoint & { highlighted: boolean };

const GLOBE_HEIGHT = 480;
const EARTH_TEXTURE = "/globe/earth-blue-marble.jpg";
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

function Globe3D({
  points,
  arcs,
  selectedId,
  onSelect,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
  selectedId: string | null;
  onSelect: (id: string | null) => void;
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
    <div ref={containerRef}>
      {width > 0 && (
        <Globe
          ref={globeRef}
          width={width}
          height={GLOBE_HEIGHT}
          globeImageUrl={EARTH_TEXTURE}
          backgroundColor="rgba(0,0,0,0)"
          showAtmosphere
          atmosphereColor="#60a5fa"
          onGlobeReady={() => {
            const renderer = globeRef.current?.renderer();
            renderer?.setPixelRatio(
              Math.min(window.devicePixelRatio || 1, 2),
            );
          }}
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
            onSelect(selectedId === arc.id ? null : arc.id);
          }}
          onGlobeClick={() => onSelect(null)}
        />
      )}
    </div>
  );
}

function toRad(deg: number) {
  return (deg * Math.PI) / 180;
}
function toDeg(rad: number) {
  return (rad * 180) / Math.PI;
}

/** Great-circle interpolation between two lat/lng points (slerp on the sphere). */
function greatCirclePoint(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
  t: number,
): [number, number] {
  const [la1, lo1, la2, lo2] = [lat1, lng1, lat2, lng2].map(toRad);
  const d =
    2 *
    Math.asin(
      Math.sqrt(
        Math.sin((la2 - la1) / 2) ** 2 +
          Math.cos(la1) * Math.cos(la2) * Math.sin((lo2 - lo1) / 2) ** 2,
      ),
    );
  if (d === 0) return [lat1, lng1];
  const a = Math.sin((1 - t) * d) / Math.sin(d);
  const b = Math.sin(t * d) / Math.sin(d);
  const x = a * Math.cos(la1) * Math.cos(lo1) + b * Math.cos(la2) * Math.cos(lo2);
  const y = a * Math.cos(la1) * Math.sin(lo1) + b * Math.cos(la2) * Math.sin(lo2);
  const z = a * Math.sin(la1) + b * Math.sin(la2);
  const lat = toDeg(Math.atan2(z, Math.sqrt(x * x + y * y)));
  const lng = toDeg(Math.atan2(y, x));
  return [lat, lng];
}

const SAMPLES = 32;

function FlatMap({
  points,
  arcs,
  selectedId,
  onSelect,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
  selectedId: string | null;
  onSelect: (id: string | null) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const height = width / 2;

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const observer = new ResizeObserver(([entry]) => {
      setWidth(entry.contentRect.width);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const selectedArc = arcs.find((arc) => arc.id === selectedId) ?? null;
  const highlightedCodes = useMemo(() => {
    if (!selectedArc) return new Set<string>();
    return new Set([selectedArc.fromCode, selectedArc.toCode]);
  }, [selectedArc]);

  const project = useMemo(
    () =>
      (lat: number, lng: number): [number, number] => [
        ((lng + 180) / 360) * width,
        ((90 - lat) / 180) * height,
      ],
    [width, height],
  );

  const arcPaths = useMemo(() => {
    if (width === 0) return [];
    return arcs.map((arc) => {
      const samples: [number, number][] = [];
      for (let i = 0; i <= SAMPLES; i++) {
        const t = i / SAMPLES;
        samples.push(
          greatCirclePoint(
            arc.startLat,
            arc.startLng,
            arc.endLat,
            arc.endLng,
            t,
          ),
        );
      }
      const projected = samples.map(([lat, lng]) => project(lat, lng));
      // Split into segments wherever the path crosses the antimeridian
      // (a jump of more than half the map width between consecutive samples).
      const segments: [number, number][][] = [[]];
      for (let i = 0; i < projected.length; i++) {
        const [x, y] = projected[i];
        const current = segments[segments.length - 1];
        if (current.length > 0) {
          const [px] = current[current.length - 1];
          if (Math.abs(x - px) > width / 2) {
            segments.push([]);
          }
        }
        segments[segments.length - 1].push([x, y]);
      }
      return { arc, segments };
    });
  }, [arcs, width, project]);

  return (
    <div
      ref={containerRef}
      className="relative w-full"
      style={{ aspectRatio: "2 / 1" }}
      onClick={() => onSelect(null)}
    >
      {width > 0 && (
        <>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={EARTH_TEXTURE}
            alt="World map"
            className="absolute inset-0 h-full w-full select-none object-cover"
            draggable={false}
          />
          <svg
            width={width}
            height={height}
            viewBox={`0 0 ${width} ${height}`}
            className="absolute inset-0"
          >
            {arcPaths.map(({ arc, segments }) => {
              const selected = arc.id === selectedId;
              return (
                <g key={arc.id}>
                  {segments.map((segment, i) => (
                    <g key={i}>
                      <polyline
                        points={segment.map(([x, y]) => `${x},${y}`).join(" ")}
                        fill="none"
                        stroke="transparent"
                        strokeWidth={5}
                        className="cursor-pointer"
                        onClick={(e) => {
                          e.stopPropagation();
                          onSelect(selected ? null : arc.id);
                        }}
                      />
                      <polyline
                        points={segment.map(([x, y]) => `${x},${y}`).join(" ")}
                        fill="none"
                        stroke={selected ? ARC_COLOR_SELECTED : ARC_COLOR}
                        strokeWidth={selected ? 2 : 1.2}
                        pointerEvents="none"
                      >
                        <title>{arc.label}</title>
                      </polyline>
                    </g>
                  ))}
                </g>
              );
            })}
            {points.map((point) => {
              const highlighted = highlightedCodes.has(point.code);
              const [x, y] = project(point.lat, point.lng);
              return (
                <g key={point.code}>
                  <circle
                    cx={x}
                    cy={y}
                    r={highlighted ? 5 : 3}
                    fill={highlighted ? "#ffffff" : "#facc15"}
                    stroke="rgba(0,0,0,0.5)"
                    strokeWidth={1}
                  />
                  {highlighted && (
                    <text
                      x={x + 8}
                      y={y + 4}
                      fontSize={11}
                      fontWeight={600}
                      fill="#ffffff"
                      stroke="rgba(0,0,0,0.9)"
                      strokeWidth={3}
                      paintOrder="stroke"
                    >
                      {point.city} ({point.code})
                    </text>
                  )}
                </g>
              );
            })}
          </svg>
        </>
      )}
    </div>
  );
}

export function FlightGlobe({
  points,
  arcs,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
}) {
  const [viewMode, setViewMode] = useState<ViewMode>("3d");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  return (
    <div className="relative overflow-hidden rounded-2xl border border-black/[.08] bg-[#04060f] dark:border-white/[.145]">
      <div className="absolute right-3 top-3 z-10 flex rounded-full border border-white/20 bg-black/40 p-0.5 backdrop-blur-sm">
        {(
          [
            ["3d", "3D"],
            ["2d", "2D"],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            onClick={() => setViewMode(value)}
            className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
              viewMode === value
                ? "bg-white text-black"
                : "text-white/80 hover:text-white"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {viewMode === "3d" ? (
        <Globe3D
          points={points}
          arcs={arcs}
          selectedId={selectedId}
          onSelect={setSelectedId}
        />
      ) : (
        <FlatMap
          points={points}
          arcs={arcs}
          selectedId={selectedId}
          onSelect={setSelectedId}
        />
      )}

      <p className="px-3 py-1.5 text-[11px] text-zinc-400">
        Click a flight to see its airports. Imagery &copy; NASA Visible Earth
        (Blue Marble).
      </p>
    </div>
  );
}
