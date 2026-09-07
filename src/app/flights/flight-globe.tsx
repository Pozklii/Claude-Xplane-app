"use client";

import { useEffect, useRef } from "react";
import { ArcLayer, ScatterplotLayer } from "@deck.gl/layers";
import { MapboxOverlay } from "@deck.gl/mapbox";
import {
  Map as MapLibreMap,
  NavigationControl,
  type GeoJSONSource,
  type LngLatBoundsLike,
  type LayerSpecification,
  type StyleSpecification,
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
// land/water) without needing a MapTiler (or similar) key. Its colors are
// overridden below (applyNeonStyle) rather than forking a whole new style.
const STYLE_URL: string | StyleSpecification =
  "https://tiles.openfreemap.org/styles/liberty";
const MAP_HEIGHT = 480;

// "Neon Approach" palette — ultraviolet ocean, acid-teal coastlines,
// magenta-to-cyan flight routes with a soft glow.
const NEON = {
  background: "#170a2e",
  water: "#170a2e",
  waterway: "#3a1461",
  landcover: "#0f2e2f",
  building: "#1c1033",
  boundary: "#22e6b0",
  road: "#4a1a6b",
  labelText: "#eafcff",
  labelHalo: "#170a2e",
  skyColor: "#170a2e",
  horizonColor: "#5a1f8f",
} as const;

// deck.gl color accessors take [r, g, b, a] (0-255), not CSS strings.
const ARC_SOURCE: [number, number, number, number] = [255, 63, 214, 210];
const ARC_TARGET: [number, number, number, number] = [34, 230, 255, 210];
const ARC_SOURCE_SELECTED: [number, number, number, number] = [
  255, 63, 214, 255,
];
const ARC_TARGET_SELECTED: [number, number, number, number] = [
  34, 230, 255, 255,
];
const ARC_GLOW: [number, number, number, number] = [217, 70, 239, 70];
const ARC_GLOW_SELECTED: [number, number, number, number] = [
  217, 70, 239, 130,
];
const MARKER: [number, number, number, number] = [232, 255, 91, 255];
const MARKER_HIGHLIGHTED: [number, number, number, number] = [
  255, 255, 255, 255,
];
const MARKER_GLOW: [number, number, number, number] = [232, 255, 91, 90];
const MARKER_GLOW_HIGHLIGHTED: [number, number, number, number] = [
  255, 255, 255, 130,
];

// Recolors an OpenMapTiles-schema style (which OpenFreeMap's styles follow)
// by source-layer/type rather than hardcoding this particular style's own
// layer names, so it keeps working if the upstream style is regenerated.
function applyNeonStyle(map: MapLibreMap) {
  const layers = map.getStyle()?.layers as LayerSpecification[] | undefined;
  if (!layers) return;

  for (const layer of layers) {
    const sourceLayer =
      "source-layer" in layer ? layer["source-layer"] : undefined;
    try {
      if (layer.type === "background") {
        map.setPaintProperty(layer.id, "background-color", NEON.background);
      } else if (layer.type === "fill") {
        if (sourceLayer === "water") {
          map.setPaintProperty(layer.id, "fill-color", NEON.water);
        } else if (
          sourceLayer === "landcover" ||
          sourceLayer === "landuse" ||
          sourceLayer === "park"
        ) {
          map.setPaintProperty(layer.id, "fill-color", NEON.landcover);
        } else if (sourceLayer === "building") {
          map.setPaintProperty(layer.id, "fill-color", NEON.building);
          map.setPaintProperty(layer.id, "fill-opacity", 0.5);
        }
      } else if (layer.type === "fill-extrusion" && sourceLayer === "building") {
        map.setPaintProperty(layer.id, "fill-extrusion-color", NEON.building);
      } else if (layer.type === "line") {
        if (sourceLayer === "waterway") {
          map.setPaintProperty(layer.id, "line-color", NEON.waterway);
        } else if (sourceLayer === "boundary") {
          map.setPaintProperty(layer.id, "line-color", NEON.boundary);
          map.setPaintProperty(layer.id, "line-opacity", 0.55);
        } else if (
          sourceLayer === "road" ||
          sourceLayer === "transportation"
        ) {
          map.setPaintProperty(layer.id, "line-color", NEON.road);
          map.setPaintProperty(layer.id, "line-opacity", 0.45);
        } else if (sourceLayer === "building") {
          map.setPaintProperty(layer.id, "line-color", NEON.building);
        }
      } else if (layer.type === "symbol") {
        map.setPaintProperty(layer.id, "text-color", NEON.labelText);
        map.setPaintProperty(layer.id, "text-halo-color", NEON.labelHalo);
      }
    } catch {
      // Not every layer supports every paint property for its type (e.g. a
      // layer with no opacity ever set) — skip it rather than aborting the
      // whole recolor pass over one layer.
    }
  }

  map.setSky({
    "sky-color": NEON.skyColor,
    "horizon-color": NEON.horizonColor,
    "atmosphere-blend": 0.9,
  });
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
      applyNeonStyle(map);

      // Text labels for the two airports of the selected flight only —
      // the dots themselves are drawn by the deck.gl ScatterplotLayer
      // below, which can glow in a way MapLibre's circle layer can't.
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
          "text-offset": [0.9, 0],
          "text-anchor": "left",
        },
        paint: {
          "text-color": "#eafcff",
          "text-halo-color": NEON.background,
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
          layerIds: ["flight-arcs-glow"],
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

      const arcGlowLayer = new ArcLayer<GlobeArc>({
        id: "flight-arcs-glow",
        data: arcs,
        pickable: true,
        greatCircle: true,
        // GlobeView back-face-culls by default, which hides an arc's tube
        // geometry from most angles unless culling is disabled for it.
        parameters: { cullMode: "none" },
        getSourcePosition: (d) => [d.startLng, d.startLat],
        getTargetPosition: (d) => [d.endLng, d.endLat],
        getSourceColor: (d) =>
          d.id === selectedId ? ARC_GLOW_SELECTED : ARC_GLOW,
        getTargetColor: (d) =>
          d.id === selectedId ? ARC_GLOW_SELECTED : ARC_GLOW,
        getWidth: (d) => (d.id === selectedId ? 10 : 6),
        getHeight: 0.35,
        widthUnits: "pixels",
      });

      const arcCoreLayer = new ArcLayer<GlobeArc>({
        id: "flight-arcs-core",
        data: arcs,
        pickable: false,
        greatCircle: true,
        parameters: { cullMode: "none" },
        getSourcePosition: (d) => [d.startLng, d.startLat],
        getTargetPosition: (d) => [d.endLng, d.endLat],
        getSourceColor: (d) =>
          d.id === selectedId ? ARC_SOURCE_SELECTED : ARC_SOURCE,
        getTargetColor: (d) =>
          d.id === selectedId ? ARC_TARGET_SELECTED : ARC_TARGET,
        getWidth: (d) => (d.id === selectedId ? 2.6 : 1.3),
        getHeight: 0.35,
        widthUnits: "pixels",
      });

      const pointGlowLayer = new ScatterplotLayer<GlobePoint>({
        id: "flight-points-glow",
        data: points,
        pickable: false,
        getPosition: (d) => [d.lng, d.lat],
        getFillColor: (d) =>
          highlightedCodes.has(d.code) ? MARKER_GLOW_HIGHLIGHTED : MARKER_GLOW,
        getRadius: (d) => (highlightedCodes.has(d.code) ? 16 : 9),
        radiusUnits: "pixels",
      });

      const pointCoreLayer = new ScatterplotLayer<GlobePoint>({
        id: "flight-points-core",
        data: points,
        pickable: false,
        getPosition: (d) => [d.lng, d.lat],
        getFillColor: (d) =>
          highlightedCodes.has(d.code) ? MARKER_HIGHLIGHTED : MARKER,
        getRadius: (d) => (highlightedCodes.has(d.code) ? 6 : 3.5),
        radiusUnits: "pixels",
        stroked: true,
        getLineColor: [10, 6, 20, 200],
        lineWidthMinPixels: 1,
      });

      overlayRef.current.setProps({
        layers: [arcGlowLayer, arcCoreLayer, pointGlowLayer, pointCoreLayer],
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
