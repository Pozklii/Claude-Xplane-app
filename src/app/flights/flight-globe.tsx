"use client";

import { useEffect, useRef } from "react";
import { geoInterpolate } from "d3-geo";
import {
  Map as MapLibreMap,
  NavigationControl,
  type GeoJSONSource,
  type LngLatBoundsLike,
} from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
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

// A free, no-API-key vector style — good detail (roads, place labels,
// land/water) without needing a MapTiler (or similar) key. Swap for a
// MapTiler satellite style once a key is available.
const STYLE_URL = "https://tiles.openfreemap.org/styles/liberty";
const MAP_HEIGHT = 480;
const ARC_SEGMENTS = 64;
const ARC_COLOR = "#2563eb";
const ARC_COLOR_SELECTED = "#1d4ed8";
const POINT_COLOR = "#facc15";
const POINT_COLOR_SELECTED = "#ffffff";

function greatCircleLine(arc: GlobeArc): GeoJSON.Feature<GeoJSON.LineString> {
  const interpolate = geoInterpolate(
    [arc.startLng, arc.startLat],
    [arc.endLng, arc.endLat],
  );
  const coordinates: [number, number][] = [];
  for (let i = 0; i <= ARC_SEGMENTS; i++) {
    coordinates.push(interpolate(i / ARC_SEGMENTS));
  }
  return {
    type: "Feature",
    id: arc.id,
    properties: { id: arc.id, selected: false },
    geometry: { type: "LineString", coordinates },
  };
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
  const mapRef = useRef<MapLibreMap | null>(null);
  const onSelectIdRef = useRef(onSelectId);
  const selectedIdRef = useRef(selectedId);
  useEffect(() => {
    onSelectIdRef.current = onSelectId;
    selectedIdRef.current = selectedId;
  });

  // Create the map once. Data (arcs/points) and selection are pushed into
  // it imperatively via the effects below rather than by recreating the
  // map, so panning/zoom state isn't lost on every flight-log change.
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const map = new MapLibreMap({
      container,
      style: STYLE_URL,
      center: [0, 20],
      zoom: 0.5,
      attributionControl: { compact: true },
    });
    mapRef.current = map;
    map.addControl(new NavigationControl(), "top-right");

    map.on("load", () => {
      map.setProjection({ type: "globe" });

      map.addSource("flight-arcs", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });
      map.addSource("flight-points", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });

      // A wide, invisible line under the visible one, purely to give
      // clicking a generous hit area — the thin visible line alone would
      // be hard to click precisely.
      map.addLayer({
        id: "flight-arcs-hit",
        type: "line",
        source: "flight-arcs",
        paint: { "line-width": 16, "line-color": "#000000", "line-opacity": 0 },
      });
      map.addLayer({
        id: "flight-arcs-line",
        type: "line",
        source: "flight-arcs",
        paint: {
          "line-color": [
            "case",
            ["get", "selected"],
            ARC_COLOR_SELECTED,
            ARC_COLOR,
          ],
          "line-width": ["case", ["get", "selected"], 2.5, 1.2],
          "line-opacity": ["case", ["get", "selected"], 0.95, 0.55],
        },
      });
      map.addLayer({
        id: "flight-points-circle",
        type: "circle",
        source: "flight-points",
        paint: {
          "circle-radius": ["case", ["get", "highlighted"], 6, 3.5],
          "circle-color": [
            "case",
            ["get", "highlighted"],
            POINT_COLOR_SELECTED,
            POINT_COLOR,
          ],
          "circle-stroke-color": "rgba(0, 0, 0, 0.6)",
          "circle-stroke-width": 1,
        },
      });
      map.addLayer({
        id: "flight-points-label",
        type: "symbol",
        source: "flight-points",
        filter: ["==", ["get", "highlighted"], true],
        layout: {
          "text-field": ["get", "label"],
          "text-size": 12,
          "text-font": ["Noto Sans Bold"],
          "text-offset": [0.8, 0],
          "text-anchor": "left",
        },
        paint: {
          "text-color": "#1f2937",
          "text-halo-color": "rgba(255, 255, 255, 0.9)",
          "text-halo-width": 2,
        },
      });

      map.on("click", (event) => {
        const hits = map.queryRenderedFeatures(event.point, {
          layers: ["flight-arcs-hit"],
        });
        const hitId = hits[0]?.properties?.id as string | undefined;
        onSelectIdRef.current(
          hitId && selectedIdRef.current !== hitId ? hitId : null,
        );
      });
      map.on(
        "mouseenter",
        "flight-arcs-hit",
        () => (map.getCanvas().style.cursor = "pointer"),
      );
      map.on(
        "mouseleave",
        "flight-arcs-hit",
        () => (map.getCanvas().style.cursor = ""),
      );
    });

    const resizeObserver = new ResizeObserver(() => map.resize());
    resizeObserver.observe(container);

    return () => {
      resizeObserver.disconnect();
      map.remove();
      mapRef.current = null;
    };
    // Intentionally created once; see the effects below for how
    // points/arcs/selection stay in sync afterward.
  }, []);

  // Push arcs/points into the map's sources whenever the flight data
  // changes, and fit the view to them the first time they arrive.
  const hasFitRef = useRef(false);
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    const apply = () => {
      const arcSource = map.getSource("flight-arcs") as
        | GeoJSONSource
        | undefined;
      const pointSource = map.getSource("flight-points") as
        | GeoJSONSource
        | undefined;
      if (!arcSource || !pointSource) return;

      arcSource.setData({
        type: "FeatureCollection",
        features: arcs.map((arc) => {
          const feature = greatCircleLine(arc);
          feature.properties = {
            id: arc.id,
            selected: arc.id === selectedId,
          };
          return feature;
        }),
      });

      const selectedArc = arcs.find((arc) => arc.id === selectedId) ?? null;
      const highlightedCodes = selectedArc
        ? new Set([selectedArc.fromCode, selectedArc.toCode])
        : new Set<string>();

      pointSource.setData({
        type: "FeatureCollection",
        features: points.map((point) => ({
          type: "Feature",
          properties: {
            code: point.code,
            label: `${point.city} (${point.code})`,
            highlighted: highlightedCodes.has(point.code),
          },
          geometry: { type: "Point", coordinates: [point.lng, point.lat] },
        })),
      });

      if (!hasFitRef.current && points.length > 0) {
        hasFitRef.current = true;
        const lngs = points.map((p) => p.lng);
        const lats = points.map((p) => p.lat);
        const bounds: LngLatBoundsLike = [
          [Math.min(...lngs), Math.min(...lats)],
          [Math.max(...lngs), Math.max(...lats)],
        ];
        map.fitBounds(bounds, { padding: 60, duration: 0, maxZoom: 4 });
      }
    };

    if (map.isStyleLoaded()) apply();
    else map.once("load", apply);
  }, [arcs, points, selectedId]);

  return (
    <div className="overflow-hidden rounded-2xl border border-black/[.08] dark:border-white/[.145]">
      <div ref={containerRef} style={{ height: MAP_HEIGHT }} />
      <p className="px-3 py-1.5 text-[11px] text-zinc-600">
        Drag to rotate, scroll to zoom, click a flight to see its airports.
        Map data &copy;{" "}
        <a
          href="https://www.openstreetmap.org/copyright"
          className="underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          OpenStreetMap
        </a>{" "}
        contributors, tiles via{" "}
        <a
          href="https://openfreemap.org/"
          className="underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          OpenFreeMap
        </a>
        .
      </p>
    </div>
  );
}
