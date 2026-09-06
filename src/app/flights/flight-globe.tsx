"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  geoBounds,
  geoCentroid,
  geoDistance,
  geoGraticule10,
  geoOrthographic,
  geoPath,
} from "d3-geo";
import { drag as d3drag, type D3DragEvent } from "d3-drag";
import { select } from "d3-selection";
import { feature } from "topojson-client";
import type { Topology } from "topojson-specification";
import type { Feature, Geometry } from "geojson";
import { useSelection } from "./selection-context";

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

type CityDatum = {
  name: string;
  lat: number;
  lon: number;
  pop: number;
};

// A country's shape plus a bounding cap (centroid + angular radius covering
// its full extent) used to skip it entirely when it's certainly not in the
// visible hemisphere, without changing what ends up on screen.
type CountryCap = {
  geometry: Geometry;
  centroid: [number, number];
  radius: number;
};

function boundingCap(feature: Feature<Geometry>): CountryCap {
  const centroid = geoCentroid(feature) as [number, number];
  const [[lon0, lat0], [lon1, lat1]] = geoBounds(feature);
  const corners: [number, number][] = [
    [lon0, lat0],
    [lon0, lat1],
    [lon1, lat0],
    [lon1, lat1],
  ];
  let radius = 0;
  for (const corner of corners) {
    const d = geoDistance(centroid, corner);
    if (d > radius) radius = d;
  }
  return { geometry: feature.geometry, centroid, radius };
}

const GLOBE_HEIGHT = 480;
const COUNTRIES_URL = "/data/countries-50m.json";
const CITIES_URL = "/data/cities.json";

const OCEAN = "#cfe8f5";
const GRATICULE = "#8fbfd9";
const LAND = "#d9e8d3";
const BORDER = "#93b884";
const CITY_DOT = "#7a8a70";
const CITY_LABEL = "#4b5563";
const ARC_COLOR = "rgba(37, 99, 235, 0.45)";
const ARC_COLOR_SELECTED = "#2563eb";
const POINT_COLOR = "#facc15";
const POINT_COLOR_SELECTED = "#ffffff";
const CLICK_TOLERANCE_PX = 6;
const DRAG_THRESHOLD_PX = 2;
const MIN_ZOOM = 0.6;
const MAX_ZOOM = 6;
// At zoom 1, only cities above this population are shown; zooming in
// reveals progressively smaller cities.
const CITY_POPULATION_AT_DEFAULT_ZOOM = 3_000_000;

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
  const { selectedFlightId: selectedId, setSelectedFlightId: onSelectId } =
    useSelection();
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [width, setWidth] = useState(0);
  const [countries, setCountries] = useState<CountryCap[] | null>(null);
  const [cities, setCities] = useState<CityDatum[]>([]);
  const [zoom, setZoom] = useState(1);
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
        setCountries((features as Feature<Geometry>[]).map(boundingCap));
      })
      .catch(() => {
        if (!cancelled) setCountries([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    fetch(CITIES_URL)
      .then((res) => res.json())
      .then((data: CityDatum[]) => {
        if (!cancelled) setCities(data);
      })
      .catch(() => {
        if (!cancelled) setCities([]);
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
  const scale = Math.max(width, 1) * 0.42 * zoom;

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

  const selectedArc = arcs.find((arc) => arc.id === selectedId) ?? null;
  const highlightedCodes = useMemo(() => {
    if (!selectedArc) return new Set<string>();
    return new Set([selectedArc.fromCode, selectedArc.toCode]);
  }, [selectedArc]);

  // Draw. Runs on every rotation/selection change; a single imperative
  // canvas pass rather than per-country/per-point DOM nodes keeps dragging
  // smooth even with ~180 country shapes.
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
      // Build one combined geometry of the (likely) visible countries and
      // render it with a single geoPath call + Path2D fill/stroke, rather
      // than invoking geoPath separately per country: constructing d3's
      // projection/clip pipeline has a real fixed cost per call, and with
      // ~240 countries that per-call overhead — not the point count — was
      // the actual drag-time bottleneck.
      const viewCenter: [number, number] = [-rotate[0], -rotate[1]];
      const geometries: Geometry[] = [];
      for (const { geometry, centroid, radius } of countries) {
        // Skip countries whose full extent is certainly beyond the visible
        // hemisphere — d3's clip pipeline would draw nothing for them
        // anyway, but only after walking every point of their boundary.
        if (geoDistance(viewCenter, centroid) > Math.PI / 2 + radius) {
          continue;
        }
        geometries.push(geometry);
      }
      const countriesPath = geoPath(projection)({
        type: "GeometryCollection",
        geometries,
      });
      if (countriesPath) {
        const countryShape = new Path2D(countriesPath);
        ctx.fillStyle = LAND;
        ctx.fill(countryShape);
        ctx.strokeStyle = BORDER;
        ctx.lineWidth = 0.5;
        ctx.stroke(countryShape);
      }
    }

    const cityPopulationCutoff = CITY_POPULATION_AT_DEFAULT_ZOOM / zoom;
    ctx.font = "10px ui-sans-serif, system-ui, -apple-system, sans-serif";
    ctx.textBaseline = "middle";
    for (const city of cities) {
      if (city.pop < cityPopulationCutoff) continue;
      if (!isFrontFacing(rotate, city.lon, city.lat)) continue;
      const coords = projection([city.lon, city.lat]);
      if (!coords) continue;
      const [x, y] = coords;

      ctx.beginPath();
      ctx.arc(x, y, 1.5, 0, 2 * Math.PI);
      ctx.fillStyle = CITY_DOT;
      ctx.fill();

      ctx.fillStyle = CITY_LABEL;
      ctx.fillText(city.name, x + 4, y);
    }

    for (const arc of arcs) {
      if (
        !isFrontFacing(rotate, arc.startLng, arc.startLat) &&
        !isFrontFacing(rotate, arc.endLng, arc.endLat)
      ) {
        continue;
      }
      const selected = arc.id === selectedId;
      ctx.beginPath();
      path({
        type: "LineString",
        coordinates: [
          [arc.startLng, arc.startLat],
          [arc.endLng, arc.endLat],
        ],
      });
      ctx.strokeStyle = selected ? ARC_COLOR_SELECTED : ARC_COLOR;
      ctx.lineWidth = selected ? 2 : 1.2;
      ctx.stroke();
    }

    for (const point of points) {
      if (!isFrontFacing(rotate, point.lng, point.lat)) continue;
      const coords = projection([point.lng, point.lat]);
      if (!coords) continue;
      const [x, y] = coords;
      const highlighted = highlightedCodes.has(point.code);

      ctx.beginPath();
      ctx.arc(x, y, highlighted ? 5 : 3, 0, 2 * Math.PI);
      ctx.fillStyle = highlighted ? POINT_COLOR_SELECTED : POINT_COLOR;
      ctx.fill();
      ctx.strokeStyle = "rgba(0, 0, 0, 0.5)";
      ctx.lineWidth = 1;
      ctx.stroke();

      if (highlighted) {
        const label = `${point.city} (${point.code})`;
        ctx.font =
          "600 11px ui-sans-serif, system-ui, -apple-system, sans-serif";
        ctx.lineWidth = 3;
        ctx.strokeStyle = "rgba(255, 255, 255, 0.9)";
        ctx.fillStyle = "#1f2937";
        ctx.textBaseline = "middle";
        ctx.strokeText(label, x + 7, y);
        ctx.fillText(label, x + 7, y);
      }
    }
  }, [
    projection,
    countries,
    cities,
    zoom,
    points,
    arcs,
    rotate,
    width,
    height,
    graticule,
    selectedId,
    highlightedCodes,
  ]);

  // Kept in refs (rather than effect deps) so the drag/click listener below
  // is bound once per size change and never mid-gesture, while still always
  // seeing the latest arcs/selection/projection when a click is finally
  // resolved. Arc hit-test paths are built from projectionRef on demand
  // (inside handleClick) rather than eagerly on every render, since that's
  // the only place they're used but rotate (and so projection) changes on
  // every drag frame.
  const arcsRef = useRef(arcs);
  const selectedIdRef = useRef(selectedId);
  const onSelectIdRef = useRef(onSelectId);
  const projectionRef = useRef(projection);
  useEffect(() => {
    arcsRef.current = arcs;
    selectedIdRef.current = selectedId;
    onSelectIdRef.current = onSelectId;
    projectionRef.current = projection;
  });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || width === 0) return;

    let pendingDelta: { dx: number; dy: number } | null = null;
    let frame: number | null = null;
    let moved = 0;

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

    const handleClick = (x: number, y: number) => {
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.lineWidth = CLICK_TOLERANCE_PX;
      const svgPath = geoPath(projectionRef.current);
      for (const arc of arcsRef.current) {
        const d = svgPath({
          type: "LineString",
          coordinates: [
            [arc.startLng, arc.startLat],
            [arc.endLng, arc.endLat],
          ],
        });
        if (!d) continue;
        if (ctx.isPointInStroke(new Path2D(d), x, y)) {
          onSelectIdRef.current(
            selectedIdRef.current === arc.id ? null : arc.id,
          );
          return;
        }
      }
      onSelectIdRef.current(null);
    };

    const dragBehavior = d3drag<HTMLCanvasElement, unknown>()
      .on("start", () => {
        moved = 0;
      })
      .on("drag", (event: D3DragEvent<HTMLCanvasElement, unknown, unknown>) => {
        moved += Math.abs(event.dx) + Math.abs(event.dy);
        pendingDelta = pendingDelta
          ? {
              dx: pendingDelta.dx + event.dx,
              dy: pendingDelta.dy + event.dy,
            }
          : { dx: event.dx, dy: event.dy };
        if (frame === null) frame = requestAnimationFrame(flush);
      })
      .on("end", (event: D3DragEvent<HTMLCanvasElement, unknown, unknown>) => {
        if (moved <= DRAG_THRESHOLD_PX) {
          handleClick(event.x, event.y);
        }
      });

    select(canvas).call(dragBehavior);
    return () => {
      if (frame !== null) cancelAnimationFrame(frame);
    };
  }, [width, scale]);

  // Scroll/pinch to zoom. Kept in its own effect (rather than folded into
  // the drag effect above) so rapid wheel events don't repeatedly tear down
  // and rebind the drag/click listeners.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || width === 0) return;

    const handleWheel = (event: WheelEvent) => {
      event.preventDefault();
      const delta = -event.deltaY * 0.0015;
      setZoom((z) => Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, z * (1 + delta))));
    };

    canvas.addEventListener("wheel", handleWheel, { passive: false });
    return () => canvas.removeEventListener("wheel", handleWheel);
  }, [width]);

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
        Drag to rotate, scroll to zoom, click a flight to see its airports. Map
        data &copy;{" "}
        <a
          href="https://www.naturalearthdata.com/"
          className="underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          Natural Earth
        </a>
        , city data &copy;{" "}
        <a
          href="https://www.geonames.org/"
          className="underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          GeoNames
        </a>
        .
      </p>
    </div>
  );
}
