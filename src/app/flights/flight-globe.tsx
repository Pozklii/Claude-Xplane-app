"use client";

import { useEffect, useRef } from "react";
import { ArcLayer, ScatterplotLayer } from "@deck.gl/layers";
import { MapboxOverlay } from "@deck.gl/mapbox";
import {
  LngLatBounds,
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
// A "space" palette for the flight paths and airport markers — electric
// cyan-to-violet plasma arcs with a soft glow, and glowing satellite-like
// markers — layered over the map's regular (unrecolored) basemap.
const ARC_SOURCE: [number, number, number, number] = [56, 217, 255, 210];
const ARC_TARGET: [number, number, number, number] = [168, 85, 247, 210];
const ARC_SOURCE_SELECTED: [number, number, number, number] = [
  150, 240, 255, 255,
];
const ARC_TARGET_SELECTED: [number, number, number, number] = [
  200, 140, 255, 255,
];
const ARC_GLOW: [number, number, number, number] = [130, 170, 255, 55];
const ARC_GLOW_SELECTED: [number, number, number, number] = [
  170, 150, 255, 110,
];
const MARKER: [number, number, number, number] = [214, 250, 255, 255];
const MARKER_SELECTED: [number, number, number, number] = [255, 255, 255, 255];
const MARKER_GLOW: [number, number, number, number] = [56, 217, 255, 90];
const MARKER_GLOW_SELECTED: [number, number, number, number] = [
  120, 170, 255, 150,
];
const MARKER_RING: [number, number, number, number] = [16, 40, 70, 200];

// Selecting a flight zooms and tilts the camera in on its two airports,
// giving a pitched view of the route. Deselecting eases back out to the
// full overview.
const SELECTION_PITCH = 55;
const SELECTION_PADDING = 90;
const SELECTION_MAX_ZOOM = 9;
const SELECTION_FLY_DURATION = 1500;
const OVERVIEW_FLY_DURATION = 1200;

// Clicking an individual airport flies in close enough, at a steep enough
// pitch, for MapLibre's native 3D buildings (real OpenStreetMap building
// footprints, extruded by height) to render — an actual, if only as
// detailed as OSM's own coverage of that airport, 3D view of its
// buildings, rather than a generic marker standing in for one.
const AIRPORT_ZOOM = 16;
const AIRPORT_PITCH = 60;
const AIRPORT_FLY_DURATION = 1800;

// Idle auto-rotation, paused during any drag/rotate/pitch gesture and once
// zoomed in past the overview (selecting a flight or an airport both push
// zoom well above this, so it also naturally stays off while either is
// active, and resumes once the camera eases back out to the overview).
const SPIN_DEGREES_PER_SECOND = 4;
// Comfortably above the fitBounds zoom for most flight-log spans (even a
// fairly tight regional cluster lands around 3-4), so idle spin actually
// engages for realistic data rather than only for globe-spanning ones.
const SPIN_MAX_ZOOM = 5;

export function FlightGlobe({
  points,
  arcs,
  bare = false,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
  /** Skip the bordered/rounded card wrapper and caption styling meant for
   * a standalone card, for use where the globe should sit directly on its
   * own background instead of looking like a boxed widget. */
  bare?: boolean;
}) {
  const { selectedFlightId: selectedId, setSelectedFlightId: onSelectId } =
    useSelection();
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const overlayRef = useRef<MapboxOverlay | null>(null);
  const onSelectIdRef = useRef(onSelectId);
  const selectedIdRef = useRef(selectedId);
  // Set around every programmatic flyTo so the idle-spin loop below doesn't
  // fight it by nudging the center mid-animation.
  const cameraAnimatingRef = useRef(false);
  const flyToTracked = (
    map: MapLibreMap,
    options: Parameters<MapLibreMap["flyTo"]>[0],
  ) => {
    cameraAnimatingRef.current = true;
    map.once("moveend", () => {
      cameraAnimatingRef.current = false;
    });
    map.flyTo(options);
  };

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

    // Slowly spin the globe on its axis (moving the center longitude, not
    // the bearing, so it reads as the Earth turning rather than the camera
    // orbiting) whenever it's idle at the overview zoom — paused for the
    // duration of any user gesture, and skipped entirely for
    // prefers-reduced-motion.
    const prefersReducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    let userInteracting = false;
    let spinFrame = 0;
    let lastFrameTime = 0;
    const spinGlobe = (time: number) => {
      const deltaSeconds = lastFrameTime ? (time - lastFrameTime) / 1000 : 0;
      lastFrameTime = time;
      if (
        !userInteracting &&
        !cameraAnimatingRef.current &&
        !selectedIdRef.current &&
        !document.hidden &&
        map.getZoom() < SPIN_MAX_ZOOM
      ) {
        const center = map.getCenter();
        center.lng -= SPIN_DEGREES_PER_SECOND * deltaSeconds;
        map.setCenter(center);
      }
      spinFrame = requestAnimationFrame(spinGlobe);
    };
    if (!prefersReducedMotion) {
      spinFrame = requestAnimationFrame(spinGlobe);
      const startInteracting = () => (userInteracting = true);
      const stopInteracting = () => (userInteracting = false);
      // MapLibre only fires dragstart/rotatestart/pitchstart once it has
      // recognized real gesture movement past its own threshold — in the
      // gap between the initial mousedown/touchstart and that recognition,
      // spin's per-frame setCenter() was still running, and could shift
      // the center out from under the drag handler's own reference point
      // for "how far has the pointer moved," making the drag it was about
      // to start feel like it didn't register. Pausing on the raw
      // press/release closes that gap; the gesture-specific events stay as
      // a fallback (e.g. a drag released outside the canvas).
      map.on("mousedown", startInteracting);
      map.on("touchstart", startInteracting);
      map.on("mouseup", stopInteracting);
      map.on("touchend", stopInteracting);
      map.on("dragstart", startInteracting);
      map.on("rotatestart", startInteracting);
      map.on("pitchstart", startInteracting);
      map.on("dragend", stopInteracting);
      map.on("rotateend", stopInteracting);
      map.on("pitchend", stopInteracting);
      // Scroll-wheel and pinch zooming go through MapLibre's own eased
      // zoomTo, not a drag — without pausing spin for it too, the spin
      // loop's per-frame setCenter() fights that animation every frame,
      // which is what made zooming feel broken/stuck. And like
      // dragstart, zoomstart only fires once MapLibre has recognized the
      // gesture (accumulated a few wheel ticks) — pause on the raw wheel
      // event too so a spin frame can't land in that gap and throw off
      // the "zoom around the point under the cursor" reference, the same
      // class of race fixed above for drag.
      map.on("wheel", startInteracting);
      map.on("zoomstart", startInteracting);
      map.on("zoomend", stopInteracting);
    }

    map.on("load", () => {
      map.setProjection({ type: "globe" });

      // The style's own 3D building layer(s) are typically gated behind a
      // minzoom tuned for street-level browsing; clear that so they're
      // free to render as soon as we fly in close on an airport, whatever
      // the upstream style's default turns out to be.
      for (const layer of map.getStyle()?.layers ?? []) {
        if (layer.type === "fill-extrusion") {
          try {
            map.setLayerZoomRange(layer.id, 0, 24);
          } catch {
            // Not fatal — worst case the layer keeps its own zoom range.
          }
        }
      }

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

      // deck.gl's own onClick prop on a layer doesn't reliably fire from
      // real MapLibre-driven clicks in interleaved mode (interaction
      // handling is delegated to MapLibre, which only forwards a subset of
      // events) — pick manually from MapLibre's click event instead, which
      // is proven reliable.
      map.on("click", (event) => {
        const hit = overlay.pickObject({
          x: event.point.x,
          y: event.point.y,
          radius: 6,
          layerIds: ["flight-arcs", "flight-points"],
        });

        if (hit?.layer?.id === "flight-points") {
          const point = hit.object as GlobePoint | undefined;
          if (point) {
            flyToTracked(map, {
              center: [point.lng, point.lat],
              zoom: AIRPORT_ZOOM,
              pitch: AIRPORT_PITCH,
              duration: AIRPORT_FLY_DURATION,
            });
          }
          return;
        }

        const hitId = (hit?.object as GlobeArc | undefined)?.id ?? null;
        onSelectIdRef.current(
          hitId && selectedIdRef.current !== hitId ? hitId : null,
        );
      });
    });

    const resizeObserver = new ResizeObserver(() => map.resize());
    resizeObserver.observe(container);

    return () => {
      cancelAnimationFrame(spinFrame);
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

      // deck.gl has no native bloom/glow — approximated here with a wide,
      // low-opacity layer under a thin, bright one for both arcs and
      // markers, purely via alpha blending. Both layers sit at the exact
      // same ground position as their core counterpart, so under the
      // globe's real depth testing they'd tie on depth and flicker
      // (whichever fragment happened to win varying frame to frame,
      // worse once the camera is continuously moving during idle spin) —
      // depthWriteEnabled: false keeps the glow from contesting that tie
      // while still letting it be occluded by real geometry like the
      // globe itself.
      const arcGlowLayer = new ArcLayer<GlobeArc>({
        id: "flight-arcs-glow",
        data: arcs,
        pickable: false,
        greatCircle: true,
        // GlobeView back-face-culls by default, which hides an arc's tube
        // geometry from most angles unless culling is disabled for it.
        parameters: { cullMode: "none", depthWriteEnabled: false },
        getSourcePosition: (d) => [d.startLng, d.startLat],
        getTargetPosition: (d) => [d.endLng, d.endLat],
        getSourceColor: (d) =>
          d.id === selectedId ? ARC_GLOW_SELECTED : ARC_GLOW,
        getTargetColor: (d) =>
          d.id === selectedId ? ARC_GLOW_SELECTED : ARC_GLOW,
        getWidth: (d) => (d.id === selectedId ? 9 : 5),
        getHeight: 0.35,
        widthUnits: "pixels",
      });

      const arcLayer = new ArcLayer<GlobeArc>({
        id: "flight-arcs",
        data: arcs,
        pickable: true,
        greatCircle: true,
        parameters: { cullMode: "none" },
        getSourcePosition: (d) => [d.startLng, d.startLat],
        getTargetPosition: (d) => [d.endLng, d.endLat],
        getSourceColor: (d) =>
          d.id === selectedId ? ARC_SOURCE_SELECTED : ARC_SOURCE,
        getTargetColor: (d) =>
          d.id === selectedId ? ARC_TARGET_SELECTED : ARC_TARGET,
        getWidth: (d) => (d.id === selectedId ? 2.5 : 1.3),
        getHeight: 0.35,
        widthUnits: "pixels",
      });

      const pointGlowLayer = new ScatterplotLayer<GlobePoint>({
        id: "flight-points-glow",
        data: points,
        pickable: false,
        // Same GlobeView back-face-culling caveat as the arcs above.
        parameters: { cullMode: "none", depthWriteEnabled: false },
        getPosition: (d) => [d.lng, d.lat],
        getFillColor: (d) =>
          highlightedCodes.has(d.code) ? MARKER_GLOW_SELECTED : MARKER_GLOW,
        getRadius: (d) => (highlightedCodes.has(d.code) ? 15 : 9),
        radiusUnits: "pixels",
      });

      const pointLayer = new ScatterplotLayer<GlobePoint>({
        id: "flight-points",
        data: points,
        pickable: true,
        parameters: { cullMode: "none" },
        getPosition: (d) => [d.lng, d.lat],
        getFillColor: (d) =>
          highlightedCodes.has(d.code) ? MARKER_SELECTED : MARKER,
        getRadius: (d) => (highlightedCodes.has(d.code) ? 6 : 3.5),
        radiusUnits: "pixels",
        stroked: true,
        getLineColor: MARKER_RING,
        lineWidthMinPixels: 1,
      });

      overlayRef.current.setProps({
        layers: [arcGlowLayer, arcLayer, pointGlowLayer, pointLayer],
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
        return;
      }

      if (selectedArc) {
        const lngs = [selectedArc.startLng, selectedArc.endLng];
        const lats = [selectedArc.startLat, selectedArc.endLat];
        const bounds = new LngLatBounds([
          Math.min(...lngs),
          Math.min(...lats),
          Math.max(...lngs),
          Math.max(...lats),
        ]);
        const camera = map.cameraForBounds(bounds, {
          padding: SELECTION_PADDING,
          pitch: SELECTION_PITCH,
          maxZoom: SELECTION_MAX_ZOOM,
        });
        flyToTracked(map, {
          center: camera?.center ?? [
            (selectedArc.startLng + selectedArc.endLng) / 2,
            (selectedArc.startLat + selectedArc.endLat) / 2,
          ],
          zoom: camera?.zoom ?? SELECTION_MAX_ZOOM,
          bearing: camera?.bearing ?? 0,
          pitch: SELECTION_PITCH,
          duration: SELECTION_FLY_DURATION,
        });
      } else if (points.length > 0) {
        const lngs = points.map((p) => p.lng);
        const lats = points.map((p) => p.lat);
        const overviewBounds: LngLatBoundsLike = [
          [Math.min(...lngs), Math.min(...lats)],
          [Math.max(...lngs), Math.max(...lats)],
        ];
        const camera = map.cameraForBounds(overviewBounds, {
          padding: 60,
          maxZoom: 4,
        });
        if (camera) {
          flyToTracked(map, {
            ...camera,
            pitch: 0,
            duration: OVERVIEW_FLY_DURATION,
          });
        }
      }
    };

    if (overlay && map.isStyleLoaded()) apply();
    else map.once("load", apply);
  }, [arcs, points, selectedId]);

  return (
    <div
      className={
        bare
          ? ""
          : "overflow-hidden rounded-2xl border border-black/[.08] dark:border-white/[.145]"
      }
    >
      <div ref={containerRef} style={{ height: MAP_HEIGHT }} />
      <p
        className={
          bare
            ? "px-1 py-1.5 text-[11px] text-white/40"
            : "px-3 py-1.5 text-[11px] text-zinc-600"
        }
      >

        Drag to rotate, scroll to zoom, click a flight for its route, click
        an airport to fly into its real 3D buildings. Map data &copy;{" "}
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
