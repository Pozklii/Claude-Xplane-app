"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { geoDistance, geoGraticule10, geoOrthographic, geoPath } from "d3-geo";
import { drag as d3drag, type D3DragEvent } from "d3-drag";
import { select } from "d3-selection";
import { feature } from "topojson-client";
import type { Topology } from "topojson-specification";
import type { Feature, Geometry } from "geojson";

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
const COUNTRIES_URL = "/data/countries-50m.json";

function isFrontFacing(rotate: [number, number], lng: number, lat: number) {
  const [lambda, phi] = rotate;
  return geoDistance([-lambda, -phi], [lng, lat]) < Math.PI / 2;
}

export function FlightGlobe({
  points,
  arcs,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const [width, setWidth] = useState(0);
  const [countries, setCountries] = useState<Feature<Geometry>[] | null>(
    null,
  );
  const [rotate, setRotate] = useState<[number, number]>(() => {
    if (points.length === 0) return [0, -20];
    const avgLng =
      points.reduce((sum, p) => sum + p.lng, 0) / points.length;
    const avgLat =
      points.reduce((sum, p) => sum + p.lat, 0) / points.length;
    return [-avgLng, -avgLat];
  });

  useEffect(() => {
    let cancelled = false;
    fetch(COUNTRIES_URL)
      .then((res) => res.json())
      .then((topology: Topology) => {
        if (cancelled) return;
        const collection = feature(topology, topology.objects.countries);
        const features =
          "features" in collection ? collection.features : [collection];
        setCountries(features as Feature<Geometry>[]);
      })
      .catch(() => {
        if (!cancelled) setCountries([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const observer = new ResizeObserver(([entry]) => {
      setWidth(entry.contentRect.width);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const height = GLOBE_HEIGHT;
  const scale = Math.max(width, 1) * 0.42;

  const projection = useMemo(
    () =>
      geoOrthographic()
        .rotate([rotate[0], rotate[1], 0])
        .translate([width / 2, height / 2])
        .scale(scale)
        .clipAngle(90),
    [rotate, width, height, scale],
  );

  const path = useMemo(() => geoPath(projection), [projection]);
  const graticule = useMemo(() => geoGraticule10(), []);

  useEffect(() => {
    if (!svgRef.current || width === 0) return;

    const dragBehavior = d3drag<SVGSVGElement, unknown>().on(
      "drag",
      (event: D3DragEvent<SVGSVGElement, unknown, unknown>) => {
        const sensitivity = 240 / scale;
        setRotate(([lambda, phi]) => [
          lambda + event.dx * sensitivity,
          Math.max(-90, Math.min(90, phi - event.dy * sensitivity)),
        ]);
      },
    );

    select(svgRef.current).call(dragBehavior);
  }, [width, scale]);

  const visiblePoints = points.filter((p) => isFrontFacing(rotate, p.lng, p.lat));
  const visibleArcs = arcs.filter(
    (a) =>
      isFrontFacing(rotate, a.startLng, a.startLat) ||
      isFrontFacing(rotate, a.endLng, a.endLat),
  );

  return (
    <div
      ref={containerRef}
      className="overflow-hidden rounded-2xl border border-black/[.08] bg-[#cfe8f5] dark:border-white/[.145]"
    >
      {width > 0 && (
        <svg
          ref={svgRef}
          width={width}
          height={height}
          className="cursor-grab touch-none active:cursor-grabbing"
        >
          <path
            d={path({ type: "Sphere" }) ?? undefined}
            fill="#cfe8f5"
            stroke="#8fbfd9"
            strokeWidth={1}
          />
          <path
            d={path(graticule) ?? undefined}
            fill="none"
            stroke="#8fbfd9"
            strokeWidth={0.5}
            opacity={0.5}
          />
          {countries?.map((countryFeature, i) => (
            <path
              key={i}
              d={path(countryFeature) ?? undefined}
              fill="#d9e8d3"
              stroke="#93b884"
              strokeWidth={0.5}
            />
          ))}
          {visibleArcs.map((arc) => (
            <path
              key={arc.id}
              d={
                path({
                  type: "LineString",
                  coordinates: [
                    [arc.startLng, arc.startLat],
                    [arc.endLng, arc.endLat],
                  ],
                }) ?? undefined
              }
              fill="none"
              stroke="#2563eb"
              strokeWidth={1.6}
              strokeDasharray="5 4"
              className="flight-arc"
            >
              <title>{arc.label}</title>
            </path>
          ))}
          {visiblePoints.map((point) => {
            const coords = projection([point.lng, point.lat]);
            if (!coords) return null;
            return (
              <circle
                key={point.code}
                cx={coords[0]}
                cy={coords[1]}
                r={3.5}
                fill="#e11d48"
                stroke="white"
                strokeWidth={1}
              >
                <title>
                  {point.name} ({point.code})
                </title>
              </circle>
            );
          })}
        </svg>
      )}
      <p className="px-3 py-1.5 text-[11px] text-zinc-600">
        Drag the globe to rotate. Map data &copy;{" "}
        <a
          href="https://www.naturalearthdata.com/"
          className="underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          Natural Earth
        </a>
        .
      </p>
    </div>
  );
}
