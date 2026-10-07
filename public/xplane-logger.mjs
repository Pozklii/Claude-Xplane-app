#!/usr/bin/env node
// Flight World's X-Plane companion: logs your X-Plane flights to your
// Flight World Flight Log automatically.
//
//   node xplane-logger.mjs --site https://your-flight-world --token fw_...
//
// Make the token (and copy the full command) on the Flight Log page, under
// "Log flights automatically from X-Plane". Needs Node.js 18 or later, and
// nothing else: no packages to install, no X-Plane plugin.
//
// It asks X-Plane (11 or 12, on this computer unless you pass
// --xplane-host) for its position, speed and so on over X-Plane's own UDP
// interface (port 49000, on by default), and follows each flight: blocks
// off when you start to taxi, takeoff, touchdown (with your landing rate),
// and blocks on once you've been stopped for 30 seconds after landing.
// Then it sends the flight: where it started and ended (Flight World works
// out the airports), the aircraft, takeoff and landing times (sim UTC),
// block time, landing rate, fuel burned and the route flown. Flights that
// can't be sent (offline) are saved next to where you run it and sent the
// next time it starts.
//
// Options:
//   --site URL          your Flight World address (required)
//   --token TOKEN       your connection token (or FLIGHTWORLD_TOKEN)
//   --xplane-host HOST  the computer running X-Plane (default 127.0.0.1)
//   --xplane-port PORT  X-Plane's UDP port (default 49000)
//   --dry-run           print flights instead of sending them

import dgram from "node:dgram";
import fs from "node:fs";
import path from "node:path";

// ---------------------------------------------------------------- options

function readArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("--")) continue;
    const [key, inline] = arg.slice(2).split("=", 2);
    if (inline !== undefined) args[key] = inline;
    else if (argv[i + 1] && !argv[i + 1].startsWith("--")) args[key] = argv[++i];
    else args[key] = true;
  }
  return args;
}

const args = readArgs(process.argv.slice(2));
const SITE = String(args.site ?? process.env.FLIGHTWORLD_SITE ?? "").replace(/\/+$/, "");
const TOKEN = String(args.token ?? process.env.FLIGHTWORLD_TOKEN ?? "");
const XP_HOST = String(args["xplane-host"] ?? "127.0.0.1");
const XP_PORT = Number(args["xplane-port"] ?? 49000);
const DRY_RUN = Boolean(args["dry-run"]);
const UNSENT_DIR = path.resolve("xplane-logger-unsent");

if (!DRY_RUN && (!/^https?:\/\//.test(SITE) || !TOKEN)) {
  console.error(
    "Usage: node xplane-logger.mjs --site https://your-flight-world --token fw_...\n" +
      "Copy the full command from the Flight Log page (Log flights automatically from X-Plane).",
  );
  process.exit(1);
}

const ENDPOINT = `${SITE}/api/xplane/flights`;

const log = (...parts) =>
  console.log(
    `[${new Date().toLocaleTimeString(undefined, { hour12: false })}]`,
    ...parts,
  );

// ---------------------------------------------------------- X-Plane UDP

// Datarefs asked for (RREF), by index. Arrays are asked for an element at
// a time; the aircraft's ICAO type is a byte array, one character each.
const DATAREFS = [
  ["lat", "sim/flightmodel/position/latitude"],
  ["lon", "sim/flightmodel/position/longitude"],
  ["elevation", "sim/flightmodel/position/elevation"], // m MSL
  ["agl", "sim/flightmodel/position/y_agl"], // m
  ["groundspeed", "sim/flightmodel/position/groundspeed"], // m/s
  ["vs", "sim/flightmodel/position/vh_ind_fpm"], // fpm
  ["onGround", "sim/flightmodel/failures/onground_any"],
  ["zulu", "sim/time/zulu_time_sec"],
  ["paused", "sim/time/paused"],
  ["fuel", "sim/flightmodel/weight/m_fuel_total"], // kg
  ...Array.from({ length: 8 }, (_, i) => [
    `icao${i}`,
    `sim/aircraft/view/acf_ICAO[${i}]`,
  ]),
];
const RATE_HZ = 10;

const socket = dgram.createSocket("udp4");
const values = {};
let lastPacketAt = 0;
let lastSubscribeAt = 0;

function subscribe(frequency) {
  lastSubscribeAt = Date.now();
  DATAREFS.forEach(([, name], index) => {
    // "RREF\0", frequency and index (int32 LE), then the dataref's name
    // padded to 400 bytes.
    const packet = Buffer.alloc(413);
    packet.write("RREF", 0, "ascii");
    packet.writeInt32LE(frequency, 5);
    packet.writeInt32LE(index, 9);
    packet.write(name, 13, "ascii");
    socket.send(packet, XP_PORT, XP_HOST);
  });
}

socket.on("message", (message) => {
  if (message.length < 5 || message.toString("ascii", 0, 4) !== "RREF") return;
  // "RREF" plus one byte, then (index int32, value float32) pairs.
  for (let offset = 5; offset + 8 <= message.length; offset += 8) {
    const index = message.readInt32LE(offset);
    const entry = DATAREFS[index];
    if (entry) values[entry[0]] = message.readFloatLE(offset + 4);
  }
  lastPacketAt = Date.now();
});

socket.on("error", (error) => {
  log("UDP error:", error.message);
});

// ------------------------------------------------------- following a flight

const KT_PER_MS = 1.943844;
const FT_PER_M = 3.28084;

const aircraftIcao = () =>
  Array.from({ length: 8 }, (_, i) => values[`icao${i}`])
    .map((code) => (code > 32 && code < 127 ? String.fromCharCode(code) : ""))
    .join("")
    .trim();

const zuluClock = (seconds) => {
  if (typeof seconds !== "number" || !Number.isFinite(seconds)) return null;
  const minutes = Math.floor(seconds / 60) % 1440;
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
};

const localDate = () => {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
};

// Nautical miles between two positions (haversine).
function distanceNm(a, b) {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLon = (b.lon - a.lon) * rad;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * 3440.065 * Math.asin(Math.min(1, Math.sqrt(h)));
}

// parked → taxiing → airborne → landed → (blocks on) sent, back to parked.
let phase = "parked";
let flight = null;
// Sim seconds while unpaused, so pauses don't count towards block time.
let simClock = 0;
let lastTick = Date.now();
let lastPosition = null;
// Timers (simClock) for conditions that must hold a while.
let airborneSince = null;
let stoppedSince = null;
// Vertical speeds over the last second in the air, for the landing rate.
const recentVs = [];
// Flights being sent, so stopping can wait for them.
const sending = new Set();

function startFlight(position) {
  flight = {
    flownOn: localDate(),
    aircraftIcao: aircraftIcao(),
    start: position,
    startFuel: values.fuel,
    blockOffAt: simClock,
    takeoffZulu: null,
    landingZulu: null,
    landingRateFpm: null,
    track: [],
    lastTrackAt: -Infinity,
  };
  phase = "taxiing";
  log(
    `Blocks off${flight.aircraftIcao ? ` in a ${flight.aircraftIcao}` : ""}. Following your flight.`,
  );
}

function addTrackPoint(position, force = false) {
  const interval = phase === "airborne" ? 5 : 15;
  if (!force && simClock - flight.lastTrackAt < interval) return;
  flight.lastTrackAt = simClock;
  // Standing still (holding short, at the gate): no new point.
  const last = flight.track.at(-1);
  if (
    last &&
    distanceNm({ lon: last[0], lat: last[1] }, position) < 0.01 &&
    phase !== "airborne"
  ) {
    return;
  }
  flight.track.push([
    Number(position.lon.toFixed(5)),
    Number(position.lat.toFixed(5)),
    Math.round(values.elevation * FT_PER_M),
  ]);
}

function tick() {
  const now = Date.now();
  const dt = (now - lastTick) / 1000;
  lastTick = now;

  // Nothing from X-Plane lately: ask again every few seconds (it forgets
  // on restart).
  if (now - lastPacketAt > 5000) {
    if (now - lastSubscribeAt > 5000) subscribe(RATE_HZ);
    // Landed and X-Plane gone quiet (closed): the flight's done.
    if (phase === "landed" && now - lastPacketAt > 30000 && flight) {
      log("X-Plane stopped sending; finishing the flight where it ended.");
      finishFlight();
    }
    return;
  }
  if (values.paused >= 0.5 || typeof values.lat !== "number") return;
  simClock += Math.min(dt, 1);

  const position = { lat: values.lat, lon: values.lon };
  // A new flight or a move on the map: a jump no aircraft could fly.
  if (lastPosition && distanceNm(lastPosition, position) > 20) {
    if (phase === "landed") finishFlight(lastPosition);
    else if (phase !== "parked") {
      log("Aircraft moved (new flight or repositioned); that flight wasn't logged.");
    }
    reset();
  }
  lastPosition = position;
  if (position.lat === 0 && position.lon === 0) return;

  const onGround = values.onGround >= 0.5;
  const knots = (values.groundspeed ?? 0) * KT_PER_MS;

  if (!onGround) {
    recentVs.push([simClock, values.vs ?? 0]);
    while (recentVs.length && simClock - recentVs[0][0] > 1) recentVs.shift();
  }

  switch (phase) {
    case "parked":
      if (knots > 3) startFlight(position);
      break;

    case "taxiing":
      addTrackPoint(position);
      if (!onGround && (values.agl ?? 0) > 15) {
        airborneSince ??= simClock;
        if (simClock - airborneSince > 3) {
          phase = "airborne";
          flight.takeoffZulu ??= zuluClock(values.zulu);
          addTrackPoint(position, true);
          log(`Takeoff at ${flight.takeoffZulu}Z.`);
        }
      } else {
        airborneSince = null;
      }
      break;

    case "airborne":
      addTrackPoint(position);
      if (onGround) {
        // Touchdown: the firmest descent in the last half second.
        const rate = Math.min(
          0,
          ...recentVs
            .filter(([t]) => simClock - t <= 0.5)
            .map(([, vs]) => vs),
        );
        flight.landingRateFpm = Math.round(Math.abs(rate));
        flight.landingZulu = zuluClock(values.zulu);
        phase = "landed";
        addTrackPoint(position, true);
        log(
          `Touchdown at ${flight.landingZulu}Z, ${flight.landingRateFpm} fpm.`,
        );
      }
      break;

    case "landed":
      addTrackPoint(position);
      if (!onGround) {
        // Off the ground again: a bounce while it stays low; climbing away
        // (over 50 m) is a touch-and-go or go-around, and the next
        // touchdown counts.
        if ((values.agl ?? 0) > 50) {
          phase = "airborne";
          stoppedSince = null;
          log("Airborne again (go-around or touch-and-go).");
        }
        break;
      }
      if (knots < 1) {
        stoppedSince ??= simClock;
        if (simClock - stoppedSince > 30) finishFlight(position);
      } else {
        stoppedSince = null;
      }
      break;
  }
}

function reset() {
  phase = "parked";
  flight = null;
  airborneSince = null;
  stoppedSince = null;
  recentVs.length = 0;
}

function finishFlight(position = lastPosition) {
  if (!flight || !position) {
    reset();
    return;
  }
  addTrackPoint(position, true);
  const payload = {
    version: 1,
    flownOn: flight.flownOn,
    aircraftIcao: flight.aircraftIcao || aircraftIcao(),
    start: flight.start,
    end: position,
    blockHours: (simClock - flight.blockOffAt) / 3600,
    takeoffZulu: flight.takeoffZulu,
    landingZulu: flight.landingZulu,
    landingRateFpm: flight.landingRateFpm,
    fuelUsedKg:
      typeof flight.startFuel === "number" && typeof values.fuel === "number"
        ? Math.max(0, flight.startFuel - values.fuel)
        : null,
    track: flight.track,
  };
  log(
    `Blocks on after ${payload.blockHours.toFixed(1)}h. Sending the flight to Flight World…`,
  );
  reset();
  const sent = send(payload).catch(() => {});
  sending.add(sent);
  sent.finally(() => sending.delete(sent));
}

// ------------------------------------------------------------ sending

async function post(payload) {
  const response = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${TOKEN}`,
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(30000),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(body.error ?? `HTTP ${response.status}`);
    // Not worth retrying: a bad token or flight.
    error.permanent = response.status === 400 || response.status === 401;
    throw error;
  }
  return body;
}

async function send(payload) {
  if (DRY_RUN) {
    console.log(JSON.stringify(payload, null, 2));
    return;
  }
  try {
    const result = await post(payload);
    log(
      `Logged ${result.departure} → ${result.arrival} (${result.aircraft}). It's in your Flight Log.`,
    );
  } catch (error) {
    log(`Couldn't send the flight: ${error.message}`);
    if (!error.permanent) saveUnsent(payload);
  }
}

function saveUnsent(payload) {
  try {
    fs.mkdirSync(UNSENT_DIR, { recursive: true });
    const file = path.join(UNSENT_DIR, `flight-${Date.now()}.json`);
    fs.writeFileSync(file, JSON.stringify(payload));
    log(`Saved it to ${file}; it'll be sent next time.`);
  } catch (error) {
    log(`Couldn't save it either (${error.message}). Here it is:`);
    console.log(JSON.stringify(payload));
  }
}

async function sendUnsent() {
  let files = [];
  try {
    files = fs.readdirSync(UNSENT_DIR).filter((f) => f.endsWith(".json"));
  } catch {
    return;
  }
  for (const name of files) {
    const file = path.join(UNSENT_DIR, name);
    try {
      const result = await post(JSON.parse(fs.readFileSync(file, "utf8")));
      fs.unlinkSync(file);
      log(`Sent a saved flight: ${result.departure} → ${result.arrival}.`);
    } catch (error) {
      if (error.permanent) {
        fs.renameSync(file, `${file}.failed`);
        log(`A saved flight was refused (${error.message}); kept as ${name}.failed.`);
      } else {
        return; // Still offline; try again later.
      }
    }
  }
}

// ------------------------------------------------------------- start

async function checkToken() {
  try {
    const response = await fetch(ENDPOINT, {
      headers: { authorization: `Bearer ${TOKEN}` },
      signal: AbortSignal.timeout(15000),
    });
    const body = await response.json().catch(() => ({}));
    if (response.ok) {
      log(`Connected to Flight World (${SITE}).`);
      return true;
    }
    log(`Flight World refused the connection: ${body.error ?? response.status}`);
    return response.status !== 401;
  } catch (error) {
    log(`Can't reach Flight World right now (${error.message}). Flights will be saved and sent later.`);
    return true;
  }
}

socket.bind(0, async () => {
  if (!DRY_RUN) {
    if (!(await checkToken())) process.exit(1);
    await sendUnsent();
    setInterval(() => sendUnsent().catch(() => {}), 5 * 60 * 1000);
  }
  log(`Listening to X-Plane at ${XP_HOST}:${XP_PORT}. Leave this running while you fly.`);
  subscribe(RATE_HZ);
  setInterval(tick, 1000 / RATE_HZ);
  let warned = false;
  setInterval(() => {
    if (!lastPacketAt && !warned) {
      warned = true;
      log("No data from X-Plane yet. Is it running (with a flight loaded)?");
    }
    if (lastPacketAt && warned) warned = false;
  }, 15000);
});

let stopping = false;
async function shutdown() {
  if (stopping) process.exit(0);
  stopping = true;
  if (phase === "landed") {
    log("Stopping: logging the landed flight first.");
    finishFlight();
  } else if (phase === "taxiing" || phase === "airborne") {
    log("Stopping mid-flight; this flight won't be logged.");
  }
  subscribe(0);
  // Let any flight being sent finish (or be saved for next time).
  await Promise.all(sending);
  setTimeout(() => process.exit(0), 200);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
