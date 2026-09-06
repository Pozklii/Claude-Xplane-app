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

const GLOBE_HEIGHT = 480;
const COUNTRIES_URL = "/data/countries-110m.json";

const OCEAN = "#cfe8f5";
const GRATICULE = "#8fbfd9";
const LAND = "#d9e8d3";
const BORDER = "#93b884";
const ARC_COLOR = "#2563eb";
const POINT_COLOR = "#e11d48";

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
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [width, setWidth] = useState(0);
  const [countries, setCountries] = useState<Feature<Geometry>[] | null>(
    null,
  );
  const [rotate, setRotate] = useState<[number, number]>(() => {
    if (points.length === 0) return [0, -20];
    const avgLng = points.reduce((sum, p) => sum + p.lng, 0) / points.length;
    const avgLat = points.reduce((sum, p) => sum + p.lat, 0) / points.length;
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

  const graticule = useMemo(() => geoGraticule10(), []);

  // Draw imperatively on a canvas rather than as SVG elements: with ~100+
  // country shapes, re-rendering them as DOM nodes on every drag tick (each
  // one re-diffed and re-painted by the browser) is what made dragging feel
  // laggy. A canvas redraw is a single imperative pass with no DOM diffing.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || width === 0) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.scale(dpr, dpr);

    const path = geoPath(projection, ctx);

    ctx.clearRect(0, 0, width, height);

    ctx.beginPath();
    path({ type: "Sphere" });
    ctx.fillStyle = OCEAN;
    ctx.fill();
    ctx.strokeStyle = GRATICULE;
    ctx.lineWidth = 1;
    ctx.stroke();

    ctx.beginPath();
    path(graticule);
    ctx.strokeStyle = GRATICULE;
    ctx.globalAlpha = 0.5;
    ctx.lineWidth = 0.5;
    ctx.stroke();
    ctx.globalAlpha = 1;

    if (countries) {
      ctx.beginPath();
      for (const countryFeature of countries) path(countryFeature);
      ctx.fillStyle = LAND;
      ctx.fill();
      ctx.strokeStyle = BORDER;
      ctx.lineWidth = 0.5;
      ctx.stroke();
    }

    for (const arc of arcs) {
      if (
        !isFrontFacing(rotate, arc.startLng, arc.startLat) &&
        !isFrontFacing(rotate, arc.endLng, arc.endLat)
      ) {
        continue;
      }
      ctx.beginPath();
      path({
        type: "LineString",
        coordinates: [
          [arc.startLng, arc.startLat],
          [arc.endLng, arc.endLat],
        ],
      });
      ctx.setLineDash([5, 4]);
      ctx.strokeStyle = ARC_COLOR;
      ctx.lineWidth = 1.6;
      ctx.stroke();
      ctx.setLineDash([]);
    }

    for (const point of points) {
      if (!isFrontFacing(rotate, point.lng, point.lat)) continue;
      const coords = projection([point.lng, point.lat]);
      if (!coords) continue;
      const [x, y] = coords;

      ctx.beginPath();
      ctx.arc(x, y, 3.5, 0, 2 * Math.PI);
      ctx.fillStyle = POINT_COLOR;
      ctx.fill();
      ctx.strokeStyle = "white";
      ctx.lineWidth = 1;
      ctx.stroke();

      const label = `${point.city} (${point.code})`;
      ctx.font =
        "600 11px ui-sans-serif, system-ui, -apple-system, sans-serif";
      ctx.lineWidth = 3;
      ctx.strokeStyle = "rgba(255, 255, 255, 0.85)";
      ctx.fillStyle = "#1f2937";
      ctx.textBaseline = "middle";
      ctx.strokeText(label, x + 7, y);
      ctx.fillText(label, x + 7, y);
    }
  }, [projection, countries, points, arcs, rotate, width, height, graticule]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || width === 0) return;

    let pendingDelta: { dx: number; dy: number } | null = null;
    let frame: number | null = null;

    const flush = () => {
      frame = null;
      if (!pendingDelta) return;
      const { dx, dy } = pendingDelta;
      pendingDelta = null;
      const sensitivity = 240 / scale;
      setRotate(([lambda, phi]) => [
        lambda + dx * sensitivity,
        Math.max(-90, Math.min(90, phi - dy * sensitivity)),
      ]);
    };

    const dragBehavior = d3drag<HTMLCanvasElement, unknown>().on(
      "drag",
      (event: D3DragEvent<HTMLCanvasElement, unknown, unknown>) => {
        pendingDelta = pendingDelta
          ? { dx: pendingDelta.dx + event.dx, dy: pendingDelta.dy + event.dy }
          : { dx: event.dx, dy: event.dy };
        if (frame === null) frame = requestAnimationFrame(flush);
      },
    );

    select(canvas).call(dragBehavior);
    return () => {
      if (frame !== null) cancelAnimationFrame(frame);
    };
  }, [width, scale]);

  return (
    <div
      ref={containerRef}
      className="overflow-hidden rounded-2xl border border-black/[.08] bg-[#cfe8f5] dark:border-white/[.145]"
    >
      {width > 0 && (
        <canvas
          ref={canvasRef}
          className="cursor-grab touch-none active:cursor-grabbing"
        />
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
