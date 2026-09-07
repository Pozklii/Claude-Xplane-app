"use client";

import { useEffect, useRef } from "react";
import { ArcLayer, ScatterplotLayer } from "@deck.gl/layers";
import { MapboxOverlay } from "@deck.gl/mapbox";
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

// deck.gl color accessors take [r, g, b, a] (0-255), not CSS strings.
const ARC_COLOR: [number, number, number, number] = [37, 99, 235, 140];
const ARC_COLOR_SELECTED: [number, number, number, number] = [
  29, 78, 216, 242,
];
const POINT_COLOR: [number, number, number, number] = [250, 204, 21, 255];
const POINT_COLOR_SELECTED: [number, number, number, number] = [
  255, 255, 255, 255,
];

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
  const overlayRef = useRef<MapboxOverlay | null>(null);
  const onSelectIdRef = useRef(onSelectId);
  const selectedIdRef = useRef(selectedId);
  useEffect(() => {
    onSelectIdRef.current = onSelectId;
    selectedIdRef.current = selectedId;
  });

  // Create the map (and its deck.gl overlay) once. Data (arcs/points) and
  // selection are pushed into it imperatively via the effect below rather
  // than by recreating the map, so panning/zoom state isn't lost on every
  // flight-log change.
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

      // Text labels for the two airports of the selected flight only —
      // the dots themselves are drawn by the deck.gl ScatterplotLayer
      // below.
      map.addSource("flight-point-labels", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });
      map.addLayer({
        id: "flight-point-labels",
        type: "symbol",
        source: "flight-point-labels",
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

      const overlay = new MapboxOverlay({ interleaved: true, layers: [] });
      map.addControl(overlay);
      overlayRef.current = overlay;

      // deck.gl's own onClick prop on the arc layer doesn't reliably fire
      // from real MapLibre-driven clicks in interleaved mode (interaction
      // handling is delegated to MapLibre, which only forwards a subset of
      // events) — pick manually from MapLibre's click event instead, which
      // is proven reliable.
      map.on("click", (event) => {
        const hit = overlay.pickObject({
          x: event.point.x,
          y: event.point.y,
          radius: 6,
          layerIds: ["flight-arcs"],
        });
        const hitId = (hit?.object as GlobeArc | undefined)?.id ?? null;
        onSelectIdRef.current(
          hitId && selectedIdRef.current !== hitId ? hitId : null,
        );
      });
    });

    const resizeObserver = new ResizeObserver(() => map.resize());
    resizeObserver.observe(container);

    return () => {
      resizeObserver.disconnect();
      map.remove();
      mapRef.current = null;
      overlayRef.current = null;
    };
    // Intentionally created once; see the effect below for how
    // points/arcs/selection stay in sync afterward.
  }, []);

  // Push arcs/points into the deck.gl overlay and the label source whenever
  // the flight data or selection changes, and fit the view to them the
  // first time they arrive.
  const hasFitRef = useRef(false);
  useEffect(() => {
    const map = mapRef.current;
    const overlay = overlayRef.current;
    if (!map) return;

    const apply = () => {
      if (!overlayRef.current) return;

      const selectedArc = arcs.find((arc) => arc.id === selectedId) ?? null;
      const highlightedCodes = selectedArc
        ? new Set([selectedArc.fromCode, selectedArc.toCode])
        : new Set<string>();

      const arcLayer = new ArcLayer<GlobeArc>({
        id: "flight-arcs",
        data: arcs,
        pickable: true,
        greatCircle: true,
        // GlobeView back-face-culls by default, which hides an arc's tube
        // geometry from most angles unless culling is disabled for it.
        parameters: { cullMode: "none" },
        getSourcePosition: (d) => [d.startLng, d.startLat],
        getTargetPosition: (d) => [d.endLng, d.endLat],
        getSourceColor: (d) =>
          d.id === selectedId ? ARC_COLOR_SELECTED : ARC_COLOR,
        getTargetColor: (d) =>
          d.id === selectedId ? ARC_COLOR_SELECTED : ARC_COLOR,
        getWidth: (d) => (d.id === selectedId ? 2.5 : 1.2),
        getHeight: 0.35,
        widthUnits: "pixels",
      });

      const pointLayer = new ScatterplotLayer<GlobePoint>({
        id: "flight-points",
        data: points,
        pickable: false,
        getPosition: (d) => [d.lng, d.lat],
        getFillColor: (d) =>
          highlightedCodes.has(d.code) ? POINT_COLOR_SELECTED : POINT_COLOR,
        getRadius: (d) => (highlightedCodes.has(d.code) ? 6 : 3.5),
        radiusUnits: "pixels",
        stroked: true,
        getLineColor: [0, 0, 0, 150],
        lineWidthMinPixels: 1,
      });

      overlayRef.current.setProps({
        layers: [arcLayer, pointLayer],
      });

      const labelSource = map.getSource("flight-point-labels") as
        | GeoJSONSource
        | undefined;
      if (labelSource) {
        labelSource.setData({
          type: "FeatureCollection",
          features: points
            .filter((point) => highlightedCodes.has(point.code))
            .map((point) => ({
              type: "Feature",
              properties: { label: `${point.city} (${point.code})` },
              geometry: { type: "Point", coordinates: [point.lng, point.lat] },
            })),
        });
      }

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

    if (overlay && map.isStyleLoaded()) apply();
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
