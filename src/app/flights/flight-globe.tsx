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
export const DEFAULT_ARC_COLOR = "#38d9ff";
const MARKER: [number, number, number, number] = [214, 250, 255, 255];
const MARKER_SELECTED: [number, number, number, number] = [255, 255, 255, 255];
const MARKER_RING: [number, number, number, number] = [16, 40, 70, 200];

type Rgb = [number, number, number];

function hexToRgb(hex: string): Rgb {
  const n = parseInt(hex.replace("#", ""), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function mixToward(rgb: Rgb, target: Rgb, amount: number): Rgb {
  return [
    Math.round(rgb[0] + (target[0] - rgb[0]) * amount),
    Math.round(rgb[1] + (target[1] - rgb[1]) * amount),
    Math.round(rgb[2] + (target[2] - rgb[2]) * amount),
  ];
}

// One flat color along the whole arc (same at both ends, no gradient),
// with the selected and glow states derived from it.
function resolveArcColors(arcColor: string) {
  const rgb = hexToRgb(arcColor);
  const base: [number, number, number, number] = [...rgb, 210];
  const selected: [number, number, number, number] = [
    ...mixToward(rgb, [255, 255, 255], 0.55),
    255,
  ];
  const glow: [number, number, number, number] = [...rgb, 55];
  const glowSelected: [number, number, number, number] = [
    ...mixToward(rgb, [255, 255, 255], 0.3),
    110,
  ];
  return { base, selected, glow, glowSelected };
}

// Selecting a flight zooms and tilts the camera in on its two airports,
// giving a pitched view of the route. Deselecting eases back out to the
// full overview.
const SELECTION_PITCH = 55;
const SELECTION_PADDING = 90;
const SELECTION_MAX_ZOOM = 9;
const SELECTION_FLY_DURATION = 1500;
const OVERVIEW_FLY_DURATION = 1200;
// Default cap for the initial fit and the post-deselect overview — can be
// overridden per instance (see the overviewMaxZoom prop) for containers
// too small for this to keep the whole globe in view.
const OVERVIEW_MAX_ZOOM = 4;

// Clicking an individual airport flies in close enough, at a steep enough
// pitch, for MapLibre's native 3D buildings (real OpenStreetMap building
// footprints, extruded by height) to render — an actual, if only as
// detailed as OSM's own coverage of that airport, 3D view of its
// buildings, rather than a generic marker standing in for one. Lowered
// from 16: the building layer's own zoom range is widened to 0-24 below,
// so it's the underlying vector tile data's own resolution — not this
// value — that ultimately decides how much detail is visible at a given
// distance; this just means less of a fly-in is needed to reach it.
const AIRPORT_ZOOM = 15;
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
  overviewMaxZoom = OVERVIEW_MAX_ZOOM,
  height = MAP_HEIGHT,
  arcColor = DEFAULT_ARC_COLOR,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
  /** Skip the bordered/rounded card wrapper and caption styling meant for
   * a standalone card, for use where the globe should sit directly on its
   * own background instead of looking like a boxed widget. In bare mode
   * the map container is also a square (aspect-ratio: 1, tracking
   * whatever width its parent gives it) clipped to a circle, so it always
   * reads as a floating globe rather than a rectangular map, whatever the
   * zoom level — the navigation control is skipped too, since it would
   * otherwise sit in a corner the circular clip cuts off. */
  bare?: boolean;
  /** Caps how far the initial fit (and the post-deselect overview) zooms
   * in. The default suits the roomier /flights layout; a small container
   * (like the landing page's compact globe) needs a lower cap so the
   * whole sphere stays visible instead of the fit tightening around a
   * tight cluster of points until it overflows the container's edges. */
  overviewMaxZoom?: number;
  /** Pixel height of the map container outside bare mode (which sizes
   * itself via aspect-ratio instead). Defaults to the /flights layout. */
  height?: number;
  /** CSS hex color (e.g. "#38d9ff") for every flight route, applied flat
   * along the whole arc; selected and glow variants are derived from it. */
  arcColor?: string;
}) {
  const { selectedFlightId: selectedId, setSelectedFlightId: onSelectId } =
    useSelection();
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const overlayRef = useRef<MapboxOverlay | null>(null);
  const onSelectIdRef = useRef(onSelectId);
  const selectedIdRef = useRef(selectedId);
  // bare doesn't change over an instance's lifetime; captured in a ref
  // purely so the mount-once effect below can read it without needing to
  // be in that effect's dependency array.
  const bareRef = useRef(bare);
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
    // Skipped in bare mode: its container is clipped to a circle (see the
    // render below), and this control sits in a screen corner that a
    // circular clip would cut off.
    if (!bareRef.current) {
      map.addControl(new NavigationControl(), "top-right");
    }

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

    // Runs on "styledata" (fired as soon as the style JSON itself is
    // parsed — its layer list is available even though sources/tiles
    // haven't necessarily loaded yet) rather than "load" (fired only once
    // the map has actually painted its first frame): reacting on "load"
    // meant the browser had already drawn one or more frames of the
    // upstream style at full detail — every layer, all its labels and
    // terrain-style texture — before this code ran and hid most of it,
    // which showed up as a visible flash of the "wrong" map right before
    // it switched to the simplified one. Applying the same changes here
    // instead means nothing gets painted until after they're already in
    // effect.
    map.once("styledata", () => {
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

      // Strip the basemap down to just airports — their name label and
      // physical layout (runways, taxiways, aprons/stands, terminals) —
      // plus enough base geography (water, and the 3D buildings widened
      // above, which is what actually draws an airport's terminals) to
      // still read as a globe. Everything else (landcover/landuse
      // texture, place/road/POI labels, roads, boundaries, hillshading)
      // is real "terrain detail" that's just clutter at this scale.
      // OpenMapTiles-schema styles (which OpenFreeMap's "liberty" style
      // is one of) name the relevant vector source-layers consistently:
      // "aeroway" for the physical layout, "aerodrome_label" for the
      // airport's name.
      for (const layer of map.getStyle()?.layers ?? []) {
        const sourceLayer = (layer as { "source-layer"?: string })[
          "source-layer"
        ];
        const isAirportDetail =
          sourceLayer === "aeroway" ||
          sourceLayer === "aerodrome_label" ||
          layer.id.includes("aeroway") ||
          layer.id.includes("aerodrome") ||
          layer.id.includes("airport");
        const isBaseGeography =
          layer.type === "background" ||
          layer.type === "fill-extrusion" ||
          sourceLayer === "water";
        if (isAirportDetail || isBaseGeography) continue;
        try {
          map.setLayoutProperty(layer.id, "visibility", "none");
        } catch {
          // Not fatal — worst case that layer stays visible.
        }
      }

      // The style's own airport name label (aerodrome_label) is normally
      // tuned to only appear once reasonably zoomed in — sensible for a
      // full-detail basemap where it'd otherwise compete with everything
      // else, but since this map shows nothing else, the airport's name
      // is the one thing worth being able to read from much further out.
      // Widen it the same way as the fill-extrusion buildings above.
      for (const layer of map.getStyle()?.layers ?? []) {
        const sourceLayer = (layer as { "source-layer"?: string })[
          "source-layer"
        ];
        const isAirportLabel =
          sourceLayer === "aerodrome_label" ||
          layer.id.includes("aerodrome") ||
          layer.id.includes("airport");
        if (!isAirportLabel) continue;
        try {
          map.setLayerZoomRange(layer.id, 0, 24);
        } catch {
          // Not fatal — worst case the label keeps its own zoom range.
        }
      }

      // The "aeroway" layer(s) kept above draw the physical layout
      // (runways, taxiways, aprons, terminal footprints) but — being
      // fill/line geometry, not symbol layers — carry no text of their
      // own. Label whichever of those features actually have a name (most
      // named ones are terminals) or a ref (most stands/gates use this
      // instead of a name), sourced from that exact same vector source/
      // source-layer rather than guessing the source id, so it stays
      // correct even if OpenFreeMap changes which style/source backs it.
      const aerowayLayer = map
        .getStyle()
        ?.layers?.find(
          (layer) =>
            (layer as { "source-layer"?: string })["source-layer"] ===
            "aeroway",
        ) as { source?: string } | undefined;
      if (aerowayLayer?.source) {
        try {
          map.addLayer({
            id: "aeroway-detail-label",
            type: "symbol",
            source: aerowayLayer.source,
            "source-layer": "aeroway",
            minzoom: 12,
            filter: ["any", ["has", "name"], ["has", "ref"]],
            layout: {
              "text-field": ["coalesce", ["get", "name"], ["get", "ref"]],
              "text-size": 11,
              "text-font": ["Noto Sans Regular"],
              "symbol-placement": "point",
            },
            paint: {
              "text-color": "#dcedf7",
              "text-halo-color": "#0a1622",
              "text-halo-width": 1.2,
            },
          });
        } catch {
          // Not fatal — worst case the physical layout stays unlabeled.
        }
      }

      // In bare mode the globe sits directly on the page's own background
      // rather than a card, so the style's "space" fill (the background
      // layer, painted across the whole canvas rectangle behind the
      // sphere) would otherwise show up as a visible box around the
      // circular globe. Make it transparent so only the sphere itself —
      // real map content — is visible, at any zoom.
      if (bareRef.current) {
        for (const layer of map.getStyle()?.layers ?? []) {
          if (layer.type === "background") {
            try {
              map.setPaintProperty(layer.id, "background-opacity", 0);
            } catch {
              // Not fatal — worst case that layer keeps its own fill.
            }
          }
        }
      }
    });

    map.on("load", () => {
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

      // MapboxOverlay's own camera sync (for its interleaved picking
      // viewport, as opposed to the separately-and-correctly-synced
      // rendering path) only takes effect once its underlying Deck
      // instance finishes its own async init, which can land after our
      // initial fitBounds below — leaving pickObject() permanently
      // testing against the *construction-time* camera (here, the
      // placeholder center/zoom passed to `new MapLibreMap` above) rather
      // than wherever the map actually ends up, so a click would never
      // find anything under the cursor. Keeping it in sync ourselves on
      // every "move" closes that gap.
      // viewState is deliberately excluded from MapboxOverlayProps (the
      // library expects to own it via that same internal sync), so this
      // needs a narrow cast to set it directly.
      const setOverlayViewState = overlay.setProps.bind(overlay) as (props: {
        viewState: {
          longitude: number;
          latitude: number;
          zoom: number;
          bearing: number;
          pitch: number;
        };
      }) => void;
      const syncOverlayViewState = () => {
        const center = map.getCenter();
        setOverlayViewState({
          viewState: {
            longitude: ((center.lng + 540) % 360) - 180,
            latitude: center.lat,
            zoom: map.getZoom(),
            bearing: map.getBearing(),
            pitch: map.getPitch(),
          },
        });
      };
      map.on("move", syncOverlayViewState);
      syncOverlayViewState();

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
      const arcColors = resolveArcColors(arcColor);

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
          d.id === selectedId ? arcColors.glowSelected : arcColors.glow,
        getTargetColor: (d) =>
          d.id === selectedId ? arcColors.glowSelected : arcColors.glow,
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
          d.id === selectedId ? arcColors.selected : arcColors.base,
        getTargetColor: (d) =>
          d.id === selectedId ? arcColors.selected : arcColors.base,
        getWidth: (d) => (d.id === selectedId ? 2.5 : 1.3),
        getHeight: 0.35,
        widthUnits: "pixels",
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
        layers: [arcGlowLayer, arcLayer, pointLayer],
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
        map.fitBounds(bounds, { padding: 60, duration: 0, maxZoom: overviewMaxZoom });
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
          maxZoom: overviewMaxZoom,
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
  }, [arcs, points, selectedId, overviewMaxZoom, arcColor]);

  return (
    <div
      className={
        bare
          ? ""
          : "overflow-hidden rounded-2xl border border-black/[.08] dark:border-white/[.145]"
      }
    >
      <div
        ref={containerRef}
        style={
          bare
            ? { aspectRatio: "1", borderRadius: "50%", overflow: "hidden" }
            : { height }
        }
      />
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
