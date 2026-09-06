"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { geoEquirectangular, geoGraticule10, geoPath } from "d3-geo";
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
const MIN_ZOOM = 1;
const MAX_ZOOM = 24;
// At zoom 1, only cities above this population are shown; zooming in
// reveals progressively smaller cities (down to the ~20,000 floor of the
// bundled dataset by MAX_ZOOM).
const CITY_POPULATION_AT_DEFAULT_ZOOM = 3_000_000;
const CITY_ZOOM_EXPONENT = 1.6;
// The rendered base-map bitmap covers up to this many viewports in each
// dimension, centered on the current pan position, rather than the whole
// world — so its size (and memory) stays bounded even at high zoom, instead
// of growing with mapWidth/mapHeight. Panning re-renders it only when the
// viewport would drift outside this cached area.
const TILE_ZOOM_FACTOR = 2.5;

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
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
  const tileCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const [width, setWidth] = useState(0);
  const [countries, setCountries] = useState<Geometry[] | null>(null);
  const [cities, setCities] = useState<CityDatum[]>([]);
  const [zoom, setZoom] = useState(1);
  // The lon/lat currently centered in the viewport. Panning only ever
  // updates this — it never touches the projection itself, so dragging
  // never re-projects the map's geometry (see the draw effect below).
  const [center, setCenter] = useState<[number, number]>(() => {
    if (points.length === 0) return [0, 20];
    const avgLng = points.reduce((sum, p) => sum + p.lng, 0) / points.length;
    const avgLat = points.reduce((sum, p) => sum + p.lat, 0) / points.length;
    return [avgLng, avgLat];
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
        setCountries((features as Feature<Geometry>[]).map((f) => f.geometry));
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

  // A flat world map is naturally 2:1 (width:height); match the viewport to
  // that so the whole world fits with no blank margins at the default zoom.
  const height = Math.max(Math.round(width / 2), 1);
  // The whole world, at the current zoom, rendered at mapWidth x mapHeight
  // pixels (2:1 aspect, standard for an equirectangular map). This is
  // independent of pan — only zoom (and container width) change it — so
  // panning never needs to touch the projection or re-render the map.
  const mapWidth = Math.max(width, 1) * zoom;
  const mapHeight = mapWidth / 2;
  const scale = mapWidth / (2 * Math.PI);

  // Fixed projection: prime meridian at the center of the rendered map,
  // never rotated or re-translated by panning.
  const projection = useMemo(
    () =>
      geoEquirectangular()
        .translate([mapWidth / 2, mapHeight / 2])
        .scale(scale),
    [mapWidth, mapHeight, scale],
  );

  const graticule = useMemo(() => geoGraticule10(), []);

  const selectedArc = arcs.find((arc) => arc.id === selectedId) ?? null;
  const highlightedCodes = useMemo(() => {
    if (!selectedArc) return new Set<string>();
    return new Set([selectedArc.fromCode, selectedArc.toCode]);
  }, [selectedArc]);

  // Pixel pan offset for the current center — recomputed cheaply from the
  // (stable) projection each render, rather than stored directly, so
  // zooming keeps the same lon/lat centered for free.
  const panX = width / 2 - (projection([center[0], 0])?.[0] ?? 0);
  const rawPanY = height / 2 - (projection([0, center[1]])?.[1] ?? 0);
  const panY =
    mapHeight <= height
      ? (height - mapHeight) / 2
      : clamp(rawPanY, height - mapHeight, 0);

  // The base map (ocean, graticule, countries, city labels) is rendered to
  // an off-DOM "tile" canvas covering an area a few viewports wide/tall
  // around the current pan position — not the whole world — so its size
  // (and memory) stays bounded even at very high zoom. It's only
  // re-rendered when zoom/data changes or panning drifts near its edge, so
  // ordinary dragging costs just a couple of drawImage blits plus
  // redrawing the handful of arcs/points on top.
  const tileOriginRef = useRef<{ x: number; y: number } | null>(null);
  const tileSizeRef = useRef({ w: 0, h: 0 });
  const tileSourceRef = useRef<{
    projection: typeof projection;
    countries: typeof countries;
    cities: typeof cities;
  } | null>(null);

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
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, width, height);

    const tileWidth = Math.min(mapWidth, width * TILE_ZOOM_FACTOR);
    const tileHeight = Math.min(mapHeight, height * TILE_ZOOM_FACTOR);
    // When the tile already spans the full world in a dimension, panning
    // along it never needs a re-render — it's just modular wraparound
    // within content that's already fully cached. Checking containment
    // there instead would be a no-margin, exactly-equal comparison, which
    // floating-point rounding (mapHeight vs height, computed slightly
    // differently) can fail spuriously on every single frame.
    const tileCoversFullWidth = tileWidth >= mapWidth;
    const tileCoversFullHeight = tileHeight >= mapHeight;
    const viewLeft = -panX;
    const viewTop = -panY;

    const sourceChanged =
      !tileSourceRef.current ||
      tileSourceRef.current.projection !== projection ||
      tileSourceRef.current.countries !== countries ||
      tileSourceRef.current.cities !== cities;
    const origin = tileOriginRef.current;
    const horizontalOk =
      tileCoversFullWidth ||
      (!!origin &&
        viewLeft >= origin.x &&
        viewLeft + width <= origin.x + tileWidth);
    const verticalOk =
      tileCoversFullHeight ||
      (!!origin &&
        viewTop >= origin.y &&
        viewTop + height <= origin.y + tileHeight);
    const needsRender =
      sourceChanged ||
      !origin ||
      tileSizeRef.current.w !== tileWidth ||
      tileSizeRef.current.h !== tileHeight ||
      !horizontalOk ||
      !verticalOk;

    if (needsRender) {
      const originX = viewLeft - (tileWidth - width) / 2;
      const originY = clamp(
        viewTop - (tileHeight - height) / 2,
        0,
        Math.max(0, mapHeight - tileHeight),
      );

      let tileCanvas = tileCanvasRef.current;
      if (!tileCanvas) {
        tileCanvas = document.createElement("canvas");
        tileCanvasRef.current = tileCanvas;
      }
      tileCanvas.width = Math.max(1, Math.ceil(tileWidth * dpr));
      tileCanvas.height = Math.max(1, Math.ceil(tileHeight * dpr));
      const tctx = tileCanvas.getContext("2d");
      if (tctx) {
        tctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        tctx.clearRect(0, 0, tileWidth, tileHeight);

        const tilePath = geoPath(projection, tctx);
        // The world content lives in x ∈ [0, mapWidth); draw it at three
        // horizontal offsets so it correctly fills the tile regardless of
        // where the tile's origin falls relative to that range (origin is
        // a continuous coordinate, not wrapped, so it can land slightly
        // outside it).
        const worldOffsets = [0, -mapWidth, mapWidth];

        let countryShape: Path2D | null = null;
        if (countries) {
          // One combined geometry + a single geoPath/Path2D call, rather
          // than looping and calling geoPath per country: constructing
          // d3's projection/clip pipeline has a real fixed cost per call,
          // and with ~240 countries that per-call overhead dominates.
          const d = geoPath(projection)({
            type: "GeometryCollection",
            geometries: countries,
          });
          if (d) countryShape = new Path2D(d);
        }

        const cityPopulationCutoff =
          CITY_POPULATION_AT_DEFAULT_ZOOM / Math.pow(zoom, CITY_ZOOM_EXPONENT);
        tctx.font = "10px ui-sans-serif, system-ui, -apple-system, sans-serif";
        tctx.textBaseline = "middle";

        for (const wx of worldOffsets) {
          tctx.save();
          tctx.translate(wx - originX, -originY);

          tctx.beginPath();
          tilePath({ type: "Sphere" });
          tctx.fillStyle = OCEAN;
          tctx.fill();

          tctx.beginPath();
          tilePath(graticule);
          tctx.strokeStyle = GRATICULE;
          tctx.globalAlpha = 0.5;
          tctx.lineWidth = 0.5;
          tctx.stroke();
          tctx.globalAlpha = 1;

          if (countryShape) {
            tctx.fillStyle = LAND;
            tctx.fill(countryShape);
            tctx.strokeStyle = BORDER;
            tctx.lineWidth = 0.5;
            tctx.stroke(countryShape);
          }

          for (const city of cities) {
            if (city.pop < cityPopulationCutoff) continue;
            const coords = projection([city.lon, city.lat]);
            if (!coords) continue;
            const [x, y] = coords;

            tctx.beginPath();
            tctx.arc(x, y, 1.5, 0, 2 * Math.PI);
            tctx.fillStyle = CITY_DOT;
            tctx.fill();

            tctx.fillStyle = CITY_LABEL;
            tctx.fillText(city.name, x + 4, y);
          }

          tctx.restore();
        }
      }

      tileOriginRef.current = { x: originX, y: originY };
      tileSizeRef.current = { w: tileWidth, h: tileHeight };
      tileSourceRef.current = { projection, countries, cities };
    }

    const tile = tileOriginRef.current;
    const tileSize = tileSizeRef.current;
    const tileCanvas = tileCanvasRef.current;
    if (!tile || !tileCanvas) return;

    // At low zoom the tile covers the entire world width, so blitting it
    // once isn't enough — the viewport can fall anywhere along that
    // wrapped content, same as the arcs/points below. At higher zoom the
    // tile is a genuine crop that needsRender already guarantees covers
    // the viewport, so a single blit suffices.
    const blitOffsets = tileCoversFullWidth ? [-mapWidth, 0, mapWidth] : [0];
    for (const blitOffset of blitOffsets) {
      ctx.drawImage(
        tileCanvas,
        tile.x + panX + blitOffset,
        tile.y + panY,
        tileSize.w,
        tileSize.h,
      );
    }

    // The tile itself already covers the full viewport (that's what
    // needsRender guarantees), so unlike the tile's own content the arcs
    // and points below only need the same three world-wrap copies used
    // everywhere else for horizontal wraparound — not the tile's offset.
    const wrappedX = ((panX % mapWidth) + mapWidth) % mapWidth;
    const wrapOffsets = [-mapWidth, 0, mapWidth];

    const path = geoPath(projection, ctx);

    for (const offset of wrapOffsets) {
      ctx.save();
      ctx.translate(wrappedX + offset, panY);

      for (const arc of arcs) {
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

      ctx.restore();
    }
  }, [
    panX,
    panY,
    mapWidth,
    mapHeight,
    projection,
    width,
    height,
    zoom,
    countries,
    cities,
    graticule,
    arcs,
    points,
    selectedId,
    highlightedCodes,
  ]);

  // Kept in refs (rather than effect deps) so the drag/click listener below
  // is bound once per size change and never mid-gesture, while still always
  // seeing the latest arcs/selection/pan when a click is finally resolved.
  const arcsRef = useRef(arcs);
  const selectedIdRef = useRef(selectedId);
  const onSelectIdRef = useRef(onSelectId);
  const projectionRef = useRef(projection);
  const panRef = useRef({ x: panX, y: panY, mapWidth });
  useEffect(() => {
    arcsRef.current = arcs;
    selectedIdRef.current = selectedId;
    onSelectIdRef.current = onSelectId;
    projectionRef.current = projection;
    panRef.current = { x: panX, y: panY, mapWidth };
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
      const degreesPerPixel = 360 / mapWidth;
      setCenter(([lng, lat]) => {
        const nextLng = ((lng - dx * degreesPerPixel + 540) % 360) - 180;
        const nextLat = clamp(lat + dy * degreesPerPixel, -85, 85);
        return [nextLng, nextLat];
      });
    };

    const handleClick = (x: number, y: number) => {
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.lineWidth = CLICK_TOLERANCE_PX;
      const { x: px, y: py, mapWidth: mw } = panRef.current;
      const wrappedX = ((px % mw) + mw) % mw;
      const localY = y - py;
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
        const arcPath = new Path2D(d);
        const hit = [wrappedX - mw, wrappedX, wrappedX + mw].some((offsetX) =>
          ctx.isPointInStroke(arcPath, x - offsetX, localY),
        );
        if (hit) {
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
  }, [width, mapWidth]);

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
        Drag to pan, scroll to zoom, click a flight to see its airports. Map
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
