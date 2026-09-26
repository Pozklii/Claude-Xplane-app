// A small decoder for raw METAR reports (as served by aviationweather.gov),
// covering what the app shows: wind, visibility, weather, cloud, temperature
// and pressure, plus the derived flight category and runway crosswinds.
// Parsing stops at remarks and trend groups.

export type FlightCategory = "VFR" | "MVFR" | "IFR" | "LIFR";

export type Wind = {
  /** Degrees true, or null when variable ("VRB"). */
  directionDeg: number | null;
  speedKt: number;
  gustKt: number | null;
  /** "240V300": wind direction varying between these. */
  varyingFromDeg: number | null;
  varyingToDeg: number | null;
};

export type CloudLayer = {
  cover: "FEW" | "SCT" | "BKN" | "OVC" | "VV";
  baseFt: number | null;
  /** Cumulonimbus or towering cumulus. */
  convective: "CB" | "TCU" | null;
};

export type Metar = {
  raw: string;
  station: string;
  /** Observation day/time as reported, e.g. "261950Z". */
  observed: string | null;
  wind: Wind | null;
  /** Prevailing visibility in statute miles (10 = 10 or more). */
  visibilitySm: number | null;
  cavok: boolean;
  weather: string[];
  clouds: CloudLayer[];
  /** Explicitly clear (SKC/CLR/NSC/NCD/CAVOK). */
  clear: boolean;
  temperatureC: number | null;
  dewpointC: number | null;
  altimeterHpa: number | null;
  altimeterInHg: number | null;
  /** Lowest broken/overcast layer or vertical visibility, in feet. */
  ceilingFt: number | null;
  category: FlightCategory | null;
};

const KT_PER_MPS = 1.94384;
const SM_PER_M = 1 / 1609.344;
const HPA_PER_INHG = 33.8639;

const WEATHER =
  /^(\+|-|VC)?(MI|PR|BC|DR|BL|SH|TS|FZ)?((DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PY|PO|SQ|FC|SS|DS)+)?$/;

function parseFraction(text: string) {
  const [num, den] = text.split("/").map(Number);
  return den ? num / den : Number.NaN;
}

function parseTemp(text: string) {
  if (!text) return null;
  const value = Number(text.replace(/^M/, "-"));
  return Number.isFinite(value) ? value : null;
}

/** Decodes one raw METAR/SPECI line. Returns null if it has no station. */
export function parseMetar(raw: string): Metar | null {
  const tokens = raw.trim().split(/\s+/);
  while (tokens[0] && /^(METAR|SPECI|COR)$/.test(tokens[0])) tokens.shift();
  const station = tokens.shift();
  if (!station || !/^[A-Z0-9]{3,4}$/.test(station)) return null;

  const metar: Metar = {
    raw: raw.trim(),
    station,
    observed: null,
    wind: null,
    visibilitySm: null,
    cavok: false,
    weather: [],
    clouds: [],
    clear: false,
    temperatureC: null,
    dewpointC: null,
    altimeterHpa: null,
    altimeterInHg: null,
    ceilingFt: null,
    category: null,
  };

  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (/^(RMK|TEMPO|BECMG|NOSIG|FM\d+)$/.test(token)) break;

    let m: RegExpMatchArray | null;
    if ((m = token.match(/^(\d{6})Z$/))) {
      metar.observed = token;
    } else if (
      (m = token.match(/^(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)$/))
    ) {
      const factor = m[4] === "MPS" ? KT_PER_MPS : 1;
      metar.wind = {
        directionDeg: m[1] === "VRB" ? null : Number(m[1]),
        speedKt: Math.round(Number(m[2]) * factor),
        gustKt: m[3] ? Math.round(Number(m[3]) * factor) : null,
        varyingFromDeg: null,
        varyingToDeg: null,
      };
    } else if ((m = token.match(/^(\d{3})V(\d{3})$/)) && metar.wind) {
      metar.wind.varyingFromDeg = Number(m[1]);
      metar.wind.varyingToDeg = Number(m[2]);
    } else if (token === "CAVOK") {
      metar.cavok = true;
      metar.clear = true;
      metar.visibilitySm = 10;
    } else if (
      (m = token.match(/^(\d{4})(NDV)?$/)) &&
      metar.visibilitySm === null
    ) {
      // Metres; 9999 means 10 km or more.
      metar.visibilitySm =
        m[1] === "9999" ? 10 : Math.min(10, Number(m[1]) * SM_PER_M);
    } else if ((m = token.match(/^([PM])?(\d+(?:\/\d+)?)SM$/))) {
      // A whole number may precede a fraction as its own token: "1 1/2SM".
      let value = m[2].includes("/") ? parseFraction(m[2]) : Number(m[2]);
      const previous = tokens[i - 1];
      if (m[2].includes("/") && previous && /^\d$/.test(previous)) {
        value += Number(previous);
      }
      metar.visibilitySm = m[1] === "P" ? Math.max(value, 6) : value;
    } else if (/^\d$/.test(token) && /^\d+\/\d+SM$/.test(tokens[i + 1] ?? "")) {
      // Whole-number part of a split visibility; read with the next token.
    } else if (/^(SKC|CLR|NSC|NCD)$/.test(token)) {
      metar.clear = true;
    } else if (
      (m = token.match(/^(FEW|SCT|BKN|OVC|VV)(\d{3}|\/\/\/)(CB|TCU)?$/))
    ) {
      metar.clouds.push({
        cover: m[1] as CloudLayer["cover"],
        baseFt: m[2] === "///" ? null : Number(m[2]) * 100,
        convective: (m[3] as CloudLayer["convective"]) ?? null,
      });
    } else if ((m = token.match(/^(M?\d{2})\/(M?\d{2})?$/))) {
      metar.temperatureC = parseTemp(m[1]);
      metar.dewpointC = parseTemp(m[2] ?? "");
    } else if ((m = token.match(/^Q(\d{4})$/))) {
      metar.altimeterHpa = Number(m[1]);
      metar.altimeterInHg =
        Math.round((Number(m[1]) / HPA_PER_INHG) * 100) / 100;
    } else if ((m = token.match(/^A(\d{4})$/))) {
      metar.altimeterInHg = Number(m[1]) / 100;
      metar.altimeterHpa = Math.round((Number(m[1]) / 100) * HPA_PER_INHG);
    } else if ((m = token.match(WEATHER)) && (m[3] || m[2] === "TS")) {
      metar.weather.push(token);
    }
  }

  const ceiling = metar.clouds.find(
    (layer) =>
      (layer.cover === "BKN" ||
        layer.cover === "OVC" ||
        layer.cover === "VV") &&
      layer.baseFt !== null,
  );
  metar.ceilingFt = ceiling?.baseFt ?? null;
  metar.category = flightCategory(metar.visibilitySm, metar.ceilingFt);
  return metar;
}

export function flightCategory(
  visibilitySm: number | null,
  ceilingFt: number | null,
): FlightCategory | null {
  if (visibilitySm === null && ceilingFt === null) return null;
  const vis = visibilitySm ?? Infinity;
  const ceil = ceilingFt ?? Infinity;
  if (ceil < 500 || vis < 1) return "LIFR";
  if (ceil < 1000 || vis < 3) return "IFR";
  if (ceil <= 3000 || vis <= 5) return "MVFR";
  return "VFR";
}

const WEATHER_WORDS: Record<string, string> = {
  MI: "shallow",
  PR: "partial",
  BC: "patches of",
  DR: "drifting",
  BL: "blowing",
  SH: "showers of",
  TS: "thunderstorm",
  FZ: "freezing",
  DZ: "drizzle",
  RA: "rain",
  SN: "snow",
  SG: "snow grains",
  IC: "ice crystals",
  PL: "ice pellets",
  GR: "hail",
  GS: "small hail",
  UP: "unknown precipitation",
  BR: "mist",
  FG: "fog",
  FU: "smoke",
  VA: "volcanic ash",
  DU: "dust",
  SA: "sand",
  HZ: "haze",
  PY: "spray",
  PO: "dust whirls",
  SQ: "squalls",
  FC: "funnel cloud",
  SS: "sandstorm",
  DS: "duststorm",
};

/** "+TSRA" → "heavy thunderstorm rain". */
export function describeWeather(code: string) {
  const intensity = code.startsWith("+")
    ? "heavy "
    : code.startsWith("-")
      ? "light "
      : code.startsWith("VC")
        ? "nearby "
        : "";
  const body = code.replace(/^(\+|-|VC)/, "");
  const words = body.match(/.{2}/g)?.map((part) => WEATHER_WORDS[part] ?? part);
  return intensity + (words?.join(" ") ?? body);
}

/** Runway end headings (degrees) from names like "09L/27R" → [90, 270]. */
export function runwayHeadings(runwayName: string) {
  return runwayName
    .split("/")
    .map((end) => end.match(/^(\d{1,2})[LRC]?$/))
    .filter((m): m is RegExpMatchArray => m !== null)
    .map((m) => (Number(m[1]) % 36 || 36) * 10);
}

export type RunwayWind = {
  runwayEnd: string;
  headwindKt: number;
  crosswindKt: number;
};

/**
 * For each runway end, the headwind and crosswind components of the
 * wind's (gust, if any) speed, best-aligned runway end first. Empty when
 * the wind is calm or variable or no runway headings are known.
 */
export function runwayWinds(wind: Wind | null, runwayNames: string[]) {
  if (!wind || wind.directionDeg === null || wind.speedKt === 0) return [];
  const speed = wind.gustKt ?? wind.speedKt;
  const results: RunwayWind[] = [];
  for (const name of runwayNames) {
    const ends = name.split("/");
    const headings = runwayHeadings(name);
    if (headings.length !== ends.length) continue;
    headings.forEach((heading, i) => {
      const angle = ((wind.directionDeg! - heading) * Math.PI) / 180;
      results.push({
        runwayEnd: ends[i],
        headwindKt: Math.round(speed * Math.cos(angle)),
        crosswindKt: Math.round(Math.abs(speed * Math.sin(angle))),
      });
    });
  }
  return results.sort(
    (a, b) => a.crosswindKt - b.crosswindKt || b.headwindKt - a.headwindKt,
  );
}

export type WeatherChallenge = {
  score: number;
  reasons: string[];
};

/**
 * How demanding the current weather makes an arrival: strong/gusty wind,
 * crosswind on the best runway, low cloud or visibility, and hazardous
 * weather each add to the score, with a short reason for each.
 */
export function weatherChallenge(
  metar: Metar,
  runwayNames: string[],
): WeatherChallenge {
  let score = 0;
  const reasons: string[] = [];
  const wind = metar.wind;

  if (wind?.gustKt && wind.gustKt >= 25) {
    score += 2;
    reasons.push(`Gusting ${wind.gustKt} kt`);
  } else if (wind && wind.speedKt >= 20) {
    score += 1;
    reasons.push(`Wind ${wind.speedKt} kt`);
  }

  const best = runwayWinds(wind, runwayNames)[0];
  if (best && best.crosswindKt >= 15) {
    score += 2;
    reasons.push(
      `${best.crosswindKt} kt crosswind on runway ${best.runwayEnd}`,
    );
  } else if (best && best.crosswindKt >= 10) {
    score += 1;
    reasons.push(
      `${best.crosswindKt} kt crosswind on runway ${best.runwayEnd}`,
    );
  }

  if (metar.category === "LIFR") {
    score += 3;
    reasons.push("LIFR: very low cloud or visibility");
  } else if (metar.category === "IFR") {
    score += 2;
    reasons.push("IFR conditions");
  } else if (metar.category === "MVFR") {
    score += 1;
    reasons.push("Marginal VFR");
  }

  const weather = metar.weather.join(" ");
  if (/TS/.test(weather) || metar.clouds.some((c) => c.convective === "CB")) {
    score += 2;
    reasons.push("Thunderstorms around");
  }
  if (/FZ/.test(weather)) {
    score += 2;
    reasons.push("Freezing precipitation");
  } else if (/SN|PL|GR/.test(weather)) {
    score += 1;
    reasons.push("Snow or hail");
  }
  if (/\+RA|\+SH/.test(weather)) {
    score += 1;
    reasons.push("Heavy rain");
  }

  return { score, reasons };
}
