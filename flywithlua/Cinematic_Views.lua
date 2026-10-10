-- =============================================================================
--  Cinematic Views for X-Plane 12                                        v2.0.0
--  A FlyWithLua NG+ script: cinematic exterior cameras for your flights.
--
--  * 11 exterior shots through X-Plane's camera API: chase, orbit, flyby,
--    runway spotter (telephoto with zoom tracking), air-to-air photo ship,
--    crane sweep, and tail, wing, nose, top and gear cams rigidly mounted
--    on the airframe.
--  * You pick the shot; related shots glide into each other.
--  * Cameras fit the aircraft: they read its span and length (or estimate
--    them from its weight), and remember a size correction per aircraft.
--  * X-Plane's own zoom works while filming: its zoom keys/commands and the
--    mouse wheel zoom the cinematic camera, remembered for each shot.
--  * Handheld/telephoto lens behaviour, letterbox bars, shot titles, a
--    settings window, and commands for every function.
--
--  Install: copy this file to  X-Plane 12/Resources/plugins/FlyWithLua/Scripts/
--  Use:     Plugins > FlyWithLua > FlyWithLua Macros > Cinematic Views ...
--           or bind the "FlyWithLua/cinematic_views/..." commands to keys or
--           joystick buttons (Settings > Keyboard / Joystick).
--
--  Requires FlyWithLua NG+ (LuaJIT with FFI). Settings are saved next to this
--  file in Cinematic_Views.ini.
-- =============================================================================

local VERSION = "2.0.0"
local TAG = "Cinematic Views: "

local function log(msg)
  if logMsg then logMsg(TAG .. msg) else print(TAG .. msg) end
end

-- A second copy of the script, or a reload into the same Lua state, must not
-- leave the earlier copy's camera callback registered with X-Plane.
if type(CinematicViews) == "table" and type(CinematicViews.shutdown) == "function" then
  pcall(CinematicViews.shutdown)
end

local has_ffi, ffi = pcall(require, "ffi")
if not has_ffi then
  log("needs FlyWithLua NG+ (LuaJIT with FFI) - not started.")
  return
end

-- -----------------------------------------------------------------------------
-- X-Plane SDK through the FFI. Every name is prefixed (and redirected to the
-- real symbol with __asm__) so declarations made by other scripts sharing this
-- Lua state can never clash with ours.
-- -----------------------------------------------------------------------------

local DECLARATIONS = {
  "typedef struct { float x, y, z, pitch, heading, roll, zoom; } cv_CameraPosition_t;",
  "typedef int (*cv_CameraControl_f)(cv_CameraPosition_t *pos, int losing, void *refcon);",
  "typedef struct { int structSize; float locationX, locationY, locationZ, normalX, normalY, normalZ, velocityX, velocityY, velocityZ; int is_wet; } cv_ProbeInfo_t;",
  'void *cv_FindDataRef(const char *name) __asm__("XPLMFindDataRef");',
  'int cv_GetDatai(void *ref) __asm__("XPLMGetDatai");',
  'float cv_GetDataf(void *ref) __asm__("XPLMGetDataf");',
  'double cv_GetDatad(void *ref) __asm__("XPLMGetDatad");',
  'void *cv_FindCommand(const char *name) __asm__("XPLMFindCommand");',
  'void cv_CommandOnce(void *cmd) __asm__("XPLMCommandOnce");',
  'void cv_ControlCamera(int howLong, cv_CameraControl_f func, void *refcon) __asm__("XPLMControlCamera");',
  'void cv_DontControlCamera(void) __asm__("XPLMDontControlCamera");',
  'void *cv_CreateProbe(int type) __asm__("XPLMCreateProbe");',
  'void cv_DestroyProbe(void *probe) __asm__("XPLMDestroyProbe");',
  'int cv_ProbeTerrainXYZ(void *probe, float x, float y, float z, cv_ProbeInfo_t *info) __asm__("XPLMProbeTerrainXYZ");',
  'void cv_WorldToLocal(double lat, double lon, double alt, double *x, double *y, double *z) __asm__("XPLMWorldToLocal");',
  "typedef int (*cv_CommandCallback_f)(void *cmd, int phase, void *refcon);",
  'void cv_RegisterCommandHandler(void *cmd, cv_CommandCallback_f handler, int before, void *refcon) __asm__("XPLMRegisterCommandHandler");',
  'void cv_UnregisterCommandHandler(void *cmd, cv_CommandCallback_f handler, int before, void *refcon) __asm__("XPLMUnregisterCommandHandler");',
  'void cv_GetNthAircraftModel(int index, char *fileName, char *path) __asm__("XPLMGetNthAircraftModel");',
  'void cv_LocalToWorld(double x, double y, double z, double *lat, double *lon, double *alt) __asm__("XPLMLocalToWorld");',
}
for _, decl in ipairs(DECLARATIONS) do
  local ok, err = pcall(ffi.cdef, decl)
  if not ok and not tostring(err):find("redefin") then log("FFI declaration failed: " .. tostring(err)) end
end

local function load_xplm()
  local root = type(SCRIPT_DIRECTORY) == "string" and SCRIPT_DIRECTORY:match("^(.-)[Rr]esources[/\\][Pp]lugins[/\\]") or nil
  local names
  if SYSTEM == "IBM" then
    names = { "XPLM_64", "XPLM_64.dll", "Resources/plugins/XPLM_64.dll" }
  elseif SYSTEM == "APL" then
    names = { "Resources/plugins/XPLM.framework/XPLM" }
  else
    names = { "Resources/plugins/XPLM_64.so", "XPLM_64.so" }
  end
  local candidates = {}
  for _, n in ipairs(names) do
    candidates[#candidates + 1] = n
    if root and n:find("^Resources/") then candidates[#candidates + 1] = root .. n end
  end
  for _, path in ipairs(candidates) do
    local ok, lib = pcall(ffi.load, path)
    if ok and pcall(function() return lib.cv_FindDataRef end) then return lib end
  end
  if pcall(function() return ffi.C.cv_FindDataRef end) then return ffi.C end
  return nil
end

local XPLM = load_xplm()
if not XPLM then
  log("could not load the X-Plane SDK library (XPLM) through the FFI - not started.")
  return
end

-- -----------------------------------------------------------------------------
-- Datarefs and commands
-- -----------------------------------------------------------------------------

local function find_ref(name)
  local r = XPLM.cv_FindDataRef(name)
  if r == nil then return nil end
  return r
end

local REF = {}
local REF_NAMES = {
  x = "sim/flightmodel/position/local_x",
  y = "sim/flightmodel/position/local_y",
  z = "sim/flightmodel/position/local_z",
  psi = "sim/flightmodel/position/psi",
  the = "sim/flightmodel/position/theta",
  phi = "sim/flightmodel/position/phi",
  vx = "sim/flightmodel/position/local_vx",
  vy = "sim/flightmodel/position/local_vy",
  vz = "sim/flightmodel/position/local_vz",
  agl = "sim/flightmodel/position/y_agl",
  ias = "sim/flightmodel/position/indicated_airspeed",
  on_ground = "sim/flightmodel/failures/onground_any",
  m_max = "sim/aircraft/weight/acf_m_max",
  size_x = "sim/aircraft/view/acf_size_x",
  size_z = "sim/aircraft/view/acf_size_z",
  m_total = "sim/flightmodel/weight/m_total",
  external = "sim/graphics/view/view_is_external",
  fov = "sim/graphics/view/field_of_view_deg",
  run_time = "sim/time/total_running_time_sec",
  frame_period = "sim/operation/misc/frame_rate_period",
  paused = "sim/time/paused",
  replay = "sim/time/is_in_replay",
  vr = "sim/graphics/VR/enabled",
}
for key, name in pairs(REF_NAMES) do REF[key] = find_ref(name) end

for _, key in ipairs({ "x", "y", "z", "psi", "the", "phi", "external", "run_time" }) do
  if not REF[key] then
    log("dataref " .. REF_NAMES[key] .. " not found - not started.")
    return
  end
end

local function getf(r) if r then return XPLM.cv_GetDataf(r) end return 0 end
local function getd(r) if r then return XPLM.cv_GetDatad(r) end return 0 end
local function geti(r) if r then return XPLM.cv_GetDatai(r) end return 0 end

local function find_cmd(...)
  for i = 1, select("#", ...) do
    local c = XPLM.cv_FindCommand((select(i, ...)))
    if c ~= nil then return c end
  end
  return nil
end

local CMD = {
  external = find_cmd("sim/view/chase", "sim/view/circle", "sim/view/free_camera"),
  cockpit = find_cmd("sim/view/3d_cockpit_cmnd_look", "sim/view/default_view"),   -- to return you to it
}

-- X-Plane's own zoom commands. While a shot runs they zoom its camera.
local ZOOM_CMDS = {
  { name = "sim/general/zoom_in", dir = 1, rate = 1 },
  { name = "sim/general/zoom_out", dir = -1, rate = 1 },
  { name = "sim/general/zoom_in_fast", dir = 1, rate = 3 },
  { name = "sim/general/zoom_out_fast", dir = -1, rate = 3 },
}
for _, z in ipairs(ZOOM_CMDS) do z.ref = find_cmd(z.name) end

-- A view change while X-Plane hands the camera to us can call straight back
-- into Lua (our camera callback). LuaJIT only allows that from interpreted
-- code, so everything that can trigger it runs with the JIT off.
local function run_cmd(c)
  if c then XPLM.cv_CommandOnce(c) end
end

-- -----------------------------------------------------------------------------
-- Settings
-- -----------------------------------------------------------------------------

local DEFAULTS = {
  blend_time = 2.5,       -- glide between related shots (0 = always cut)
  distance = 1.0,         -- camera distance multiplier
  orbit_speed = 5,        -- degrees per second
  shake = 0.5,            -- handheld camera shake, 0..1
  max_zoom = 8,           -- telephoto limit for flyby and spotter shots
  normalize_lens = true,  -- frame shots as if the sim FOV were 60 degrees
  letterbox = true,
  aspect = 2.39,
  titles = true,
}

local RANGES = {
  blend_time = { 0, 5 }, distance = { 0.5, 3 }, orbit_speed = { 1, 20 }, shake = { 0, 1 },
  max_zoom = { 2, 15 }, aspect = { 1.6, 2.8 },
}

local S = {}
for k, v in pairs(DEFAULTS) do S[k] = v end

local SETTINGS_FILE = (type(SCRIPT_DIRECTORY) == "string" and SCRIPT_DIRECTORY or "") .. "Cinematic_Views.ini"
local settings_dirty = false

-- Size corrections you set, per aircraft (keyed by its .acf file name).
local SIZE = { key = "default", scales = {} }

local function load_settings()
  local f = io.open(SETTINGS_FILE, "r")
  if not f then return end
  for line in f:lines() do
    local acf, sv = line:match("^%s*size%.([%w_%-]+)%s*=%s*(.-)%s*$")
    local n = tonumber(sv)
    if acf and n then SIZE.scales[acf] = math.max(0.4, math.min(2.5, n)) end
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    local d = k and DEFAULTS[k]
    if type(d) == "boolean" then
      S[k] = (v == "true")
    elseif type(d) == "number" then
      local n = tonumber(v)
      if n then
        local r = RANGES[k]
        if r then n = math.max(r[1], math.min(r[2], n)) end
        S[k] = n
      end
    end
  end
  f:close()
end

local function save_settings()
  local f = io.open(SETTINGS_FILE, "w")
  if not f then return end
  f:write("# Cinematic Views ", VERSION, " settings, written by the script\n")
  local keys = {}
  for k in pairs(DEFAULTS) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do f:write(k, " = ", tostring(S[k]), "\n") end
  local acfs = {}
  for k, v in pairs(SIZE.scales) do if math.abs(v - 1) > 1e-3 then acfs[#acfs + 1] = k end end
  table.sort(acfs)
  for _, k in ipairs(acfs) do f:write("size.", k, " = ", ("%.2f"):format(SIZE.scales[k]), "\n") end
  f:close()
  settings_dirty = false
end

load_settings()

-- -----------------------------------------------------------------------------
-- Maths
-- -----------------------------------------------------------------------------

local sin, cos, tan, atan2, sqrt, abs, exp = math.sin, math.cos, math.tan, math.atan2, math.sqrt, math.abs, math.exp
local min, max, rad, deg, random = math.min, math.max, math.rad, math.deg, math.random

math.randomseed(os.time())

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function wrap180(a) return (a + 180) % 360 - 180 end
local function smoother(t) t = clamp(t, 0, 1) return t * t * t * (t * (t * 6 - 15) + 10) end
local function rnd(a, b) return a + (b - a) * random() end
local function sign_rnd() return random() < 0.5 and -1 or 1 end
local function finite(v) return v == v and v > -1e12 and v < 1e12 end

-- Smooth pseudo-noise in about -1..1, different for every seed.
local function wob(t, s)
  return 0.5 * sin(t + s * 1.7) + 0.3 * sin(t * 2.37 + s * 3.1) + 0.2 * sin(t * 5.13 + s * 0.7)
end

-- Damped spring toward a target: implicit integration, so it is stable and
-- behaves the same at any frame rate. zeta 1 = critically damped.
local function spring(x, v, target, omega, zeta, dt)
  local f = 1 + 2 * dt * zeta * omega
  local hoo = dt * omega * omega
  local hhoo = dt * hoo
  local inv = 1 / (f + hhoo)
  return (f * x + dt * v + hhoo * target) * inv, (v + hoo * (target - x)) * inv
end

local function spring_angle(a, v, target, omega, zeta, dt)
  local na, nv = spring(a, v, a + wrap180(target - a), omega, zeta, dt)
  return wrap180(na), nv
end

-- Aircraft body axes (x right, y up, z aft) to X-Plane local OpenGL axes
-- (x east, y up, z south), for heading psi, pitch theta and roll phi.
local function body_to_world(bx, by, bz, psi, the, phi)
  local p, t, r = rad(psi), rad(the), rad(phi)
  local cr, sr = cos(r), sin(r)
  local x1, y1 = bx * cr + by * sr, -bx * sr + by * cr
  local ct, st = cos(t), sin(t)
  local y2, z2 = y1 * ct - bz * st, y1 * st + bz * ct
  local cp, sp = cos(p), sin(p)
  return x1 * cp - z2 * sp, y2, x1 * sp + z2 * cp
end

-- A level frame turned to heading h: x right, y up, z behind.
local function heading_to_world(x, y, z, h)
  local c, s = cos(rad(h)), sin(rad(h))
  return x * c - z * s, y, x * s + z * c
end

local function look_angles(dx, dy, dz)
  return deg(atan2(dx, -dz)), deg(atan2(dy, sqrt(dx * dx + dz * dz)))
end

-- Heading, pitch and roll of a camera looking along f with "up" u.
local function orient(fx, fy, fz, ux, uy, uz)
  local n = sqrt(fx * fx + fy * fy + fz * fz)
  if n < 1e-9 then return 0, 0, 0 end
  fx, fy, fz = fx / n, fy / n, fz / n
  local h = atan2(fx, -fz)
  local p = math.asin(clamp(fy, -1, 1))
  local ch, sh, cp, sp = cos(h), sin(h), cos(p), sin(p)
  local r0x, r0z = ch, sh                      -- level "right"
  local u0x, u0y, u0z = -sp * sh, cp, sp * ch  -- "up" with no roll
  local roll = atan2(ux * r0x + uz * r0z, ux * u0x + uy * u0y + uz * u0z)
  return deg(h), deg(p), deg(roll)
end

-- -----------------------------------------------------------------------------
-- Terrain probe and world <-> local conversion (fixed cameras are stored as
-- latitude/longitude so they survive X-Plane moving its local origin)
-- -----------------------------------------------------------------------------

local probe = XPLM.cv_CreateProbe(0)
if probe == nil then probe = nil end
local probe_info = ffi.new("cv_ProbeInfo_t")
local PROBE_SIZE = ffi.sizeof("cv_ProbeInfo_t")

local function terrain_y(x, y, z)
  if not probe then return nil end
  probe_info.structSize = PROBE_SIZE
  if XPLM.cv_ProbeTerrainXYZ(probe, x, y, z, probe_info) == 0 then return probe_info.locationY end
  return nil
end

local dbuf = ffi.new("double[3]")
local function to_world(x, y, z)
  XPLM.cv_LocalToWorld(x, y, z, dbuf, dbuf + 1, dbuf + 2)
  return dbuf[0], dbuf[1], dbuf[2]
end
local function to_local(lat, lon, alt)
  XPLM.cv_WorldToLocal(lat, lon, alt, dbuf, dbuf + 1, dbuf + 2)
  return dbuf[0], dbuf[1], dbuf[2]
end

-- -----------------------------------------------------------------------------
-- Aircraft state
-- -----------------------------------------------------------------------------

local A = {
  x = 0, y = 0, z = 0, psi = 0, the = 0, phi = 0,
  vx = 0, vy = 0, vz = 0,            -- smoothed velocity (m/s, local axes)
  gs = 0, vs = 0, trk = 0, agl = 100, ias = 0,
  on_ground = false, paused = false, replay = false,
  Rs = 10, Rl = 10,                  -- half the span and half the length (m)
  R = 10,                            -- the larger of the two: how far cameras need to stand off
  size_source = "weight",
  have_pos = false,
}

local function read_pose()
  A.x, A.y, A.z = getd(REF.x), getd(REF.y), getd(REF.z)
  A.psi, A.the, A.phi = getf(REF.psi), getf(REF.the), getf(REF.phi)
end

local name_buf, path_buf = ffi.new("char[1024]"), ffi.new("char[2048]")
local HAS_ACF_NAME = pcall(function() return XPLM.cv_GetNthAircraftModel end)

local function aircraft_key()
  if not HAS_ACF_NAME then return "default" end
  name_buf[0] = 0
  XPLM.cv_GetNthAircraftModel(0, name_buf, path_buf)
  local name = ffi.string(name_buf):gsub("%.acf$", ""):gsub("[^%w_%-]", "_")
  return name ~= "" and name or "default"
end

-- How big is the aircraft? From its dimensions (half span and half length)
-- when X-Plane gives them, else from its maximum weight: aircraft are close
-- enough to geometrically similar that the cube root tracks half the span or
-- length well, from a Cessna 172 (about 5 m) to an A380 (about 40 m). The
-- weight estimate also sanity-checks the dimensions and tells metres from
-- feet. Your size correction for this aircraft is applied on top.
local function measure_aircraft()
  local m = getf(REF.m_max)
  if not (m > 50) then m = getf(REF.m_total) end
  if not (m > 50) then m = 1200 end
  local est = clamp(0.48 * m ^ (1 / 3), 3.5, 45)
  local span, len, source = est, est, "weight"
  local sx, sz = getf(REF.size_x), getf(REF.size_z)
  if finite(sx) and finite(sz) and sx > 0.5 and sz > 0.5 then
    local g = max(sx, sz)
    for _, unit in ipairs({ 1, 0.3048 }) do
      if g * unit >= 0.45 * est and g * unit <= 2.6 * est then
        span, len, source = sx * unit, sz * unit, "dimensions"
        break
      end
    end
  end
  local big = max(span, len)
  span, len = max(span, 0.3 * big), max(len, 0.3 * big)
  SIZE.key = aircraft_key()
  local scale = SIZE.scales[SIZE.key] or 1
  A.Rs, A.Rl = span * scale, len * scale
  A.R = max(A.Rs, A.Rl)
  A.size_source = source
end

local function update_dynamics(dt)
  local px, py, pz = A.x, A.y, A.z
  read_pose()
  A.paused = geti(REF.paused) ~= 0
  A.replay = geti(REF.replay) ~= 0
  A.on_ground = geti(REF.on_ground) ~= 0
  A.agl = REF.agl and getf(REF.agl) or 100
  A.ias = getf(REF.ias)

  local vx, vy, vz
  if A.replay or not REF.vx then
    -- In replays the velocity datarefs are not dependable: use the motion itself.
    if A.have_pos and dt > 0 then
      local dx, dy, dz = A.x - px, A.y - py, A.z - pz
      if dx * dx + dy * dy + dz * dz < (1000 * dt) ^ 2 then vx, vy, vz = dx / dt, dy / dt, dz / dt end
    end
  else
    vx, vy, vz = getf(REF.vx), getf(REF.vy), getf(REF.vz)
  end
  A.have_pos = true

  if vx and dt > 0 and not A.paused then
    local k = 1 - exp(-dt / 0.2)
    A.vx, A.vy, A.vz = A.vx + (vx - A.vx) * k, A.vy + (vy - A.vy) * k, A.vz + (vz - A.vz) * k
  end

  A.gs = sqrt(A.vx * A.vx + A.vz * A.vz)
  A.vs = A.vy
  A.trk = (A.gs > 2) and deg(atan2(A.vx, -A.vz)) or A.psi
end

-- -----------------------------------------------------------------------------
-- Shots
--
-- Each shot sets o.x/y/z (camera position, local axes) and either a target to
-- look at (o.tx/ty/tz) or angles (o.hdg/pit/rol), plus o.zoom.
-- -----------------------------------------------------------------------------

local SHOTS, SHOT_ORDER = {}, {}
local function shot(def)
  SHOTS[def.id] = def
  SHOT_ORDER[#SHOT_ORDER + 1] = def.id
end

local BASE_FOV = 60       -- the lens the framings are designed for
local SWEEP_TIME = 16     -- seconds for one crane move (it then goes back)

local function track_or_heading() return (A.gs > 12) and A.trk or A.psi end

-- Plan a pass: a camera ahead of the aircraft, off to one side, which the
-- aircraft will fly or roll past in about lead_t seconds.
local function plan_pass(st, lead_t, lat_min, lat_max, on_ground, vert)
  local h = (A.gs > 3) and A.trk or A.psi
  local fx, fz = sin(rad(h)), -cos(rad(h))
  local rx, rz = cos(rad(h)), sin(rad(h))
  local lead = clamp(A.gs * lead_t, 5 * A.R, 3000)
  local lat = max(rnd(lat_min, lat_max) * A.R * S.distance, on_ground and 30 or 12) * sign_rnd()
  local px, pz = A.x + fx * lead + rx * lat, A.z + fz * lead + rz * lat
  local t_pass = (A.gs > 1) and lead / A.gs or lead_t
  local ground = terrain_y(px, A.y, pz) or (A.y - A.agl)
  local py
  if on_ground then
    py = ground + 1.7
  else
    py = max(A.y + A.vs * t_pass + vert * A.R, ground + 3)
  end
  st.lat, st.lon, st.alt = to_world(px, py, pz)
  st.t_pass = t_pass
  st.zoom, st.zv = 1, 0
end

-- A fixed camera tracking the aircraft like a camera operator. The aim spring
-- lags a moving target by about 2/omega seconds, so aim that far ahead.
local function fixed_place(st, o, dt, frame_frac, lead)
  local x, y, z = to_local(st.lat, st.lon, st.alt)
  o.x, o.y, o.z = x, y, z
  o.tx, o.ty, o.tz = A.x + A.vx * lead, A.y + A.vy * lead, A.z + A.vz * lead
  local dx, dy, dz = A.x - x, A.y - y, A.z - z
  local dist = sqrt(dx * dx + dy * dy + dz * dz)
  local apparent = 2 * deg(atan2(A.R, max(dist, 1)))
  local want = clamp(frame_frac * BASE_FOV / max(apparent, 0.01), 1, st.max_zoom)
  st.zoom, st.zv = spring(st.zoom, st.zv, want, 2.2, 1, dt)
  o.rol, o.zoom = 0, st.zoom
end

-- Once the aircraft has gone past and away, the pass is over (and a new one
-- is set up).
local function pass_done(st)
  if st.t < st.t_pass + 2 then return false end
  local x, _, z = to_local(st.lat, st.lon, st.alt)
  local dx, dz = A.x - x, A.z - z
  return dx * A.vx + dz * A.vz > 0 and dx * dx + dz * dz > (12 * A.R) ^ 2
end

-- Rigidly mounted on the airframe: a position and a point it looks at, in
-- body axes, in units of half the aircraft's length (across: half its span
-- for wing mounts), so mounts sit right on short and long, narrow and wide
-- aircraft alike.
local function mount(o, px, py, pz, tx, ty, tz, span_x)
  local W, L = span_x and A.Rs or A.Rl, A.Rl
  local bx, by, bz = px * W, py * L, pz * L
  local wx, wy, wz = body_to_world(bx, by, bz, A.psi, A.the, A.phi)
  o.x, o.y, o.z = A.x + wx, A.y + wy, A.z + wz
  local dx, dy, dz = body_to_world(tx * W - bx, ty * L - by, tz * L - bz, A.psi, A.the, A.phi)
  local ux, uy, uz = body_to_world(0, 1, 0, A.psi, A.the, A.phi)
  o.hdg, o.pit, o.rol = orient(dx, dy, dz, ux, uy, uz)
  o.zoom = 1
end

shot {
  id = "chase", name = "Chase", rel = true, shake = 0.35, aim = 6,
  init = function(st)
    st.h, st.hv = track_or_heading(), 0
    st.side = rnd(0.15, 0.45) * sign_rnd()
    st.up, st.back = rnd(0.35, 0.7), rnd(2.8, 3.6)
  end,
  place = function(st, o, dt)
    st.h, st.hv = spring_angle(st.h, st.hv, track_or_heading(), 1.5, 1, dt)
    local D = A.R * S.distance
    local f = rad(clamp(deg(atan2(A.vs, max(A.gs, 5))), -15, 15) * 0.5)
    local y0, z0 = st.up * D, st.back * D
    local ox, oy, oz = heading_to_world(st.side * D, y0 * cos(f) - z0 * sin(f), y0 * sin(f) + z0 * cos(f), st.h)
    o.x, o.y, o.z = A.x + ox, A.y + oy, A.z + oz
    local fx, fz = sin(rad(st.h)), -cos(rad(st.h))
    o.tx, o.ty, o.tz = A.x + fx * 0.6 * A.R, A.y + 0.1 * A.R, A.z + fz * 0.6 * A.R
    o.rol, o.zoom = 0.3 * A.phi, 1
  end,
}

shot {
  id = "orbit", name = "Orbit", rel = true, shake = 0.2,
  init = function(st)
    st.ang = A.psi + rnd(120, 160) * sign_rnd()
    st.dir = sign_rnd()
    st.ph = rnd(0, 6.28)
  end,
  place = function(st, o, dt)
    st.ang = st.ang + S.orbit_speed * st.dir * dt
    local elev = rad(8 + 8 * sin(st.t * 0.08 + st.ph))
    local D = 2.7 * A.R * S.distance
    local r, a = D * cos(elev), rad(st.ang)
    o.x, o.y, o.z = A.x + r * sin(a), A.y + D * sin(elev), A.z - r * cos(a)
    o.tx, o.ty, o.tz = A.x, A.y + 0.05 * A.R, A.z
    o.rol, o.zoom = 0, 1
  end,
}

shot {
  id = "flyby", name = "Flyby", shake = 0.6, aim = 7,
  init = function(st)
    plan_pass(st, rnd(4, 6), 1.4, 2.4, false, rnd(-0.3, 0.5))
    st.max_zoom = min(S.max_zoom, 4)
  end,
  place = function(st, o, dt) fixed_place(st, o, dt, 0.45, 2 / 7) end,
  done = pass_done,
}

shot {
  id = "spotter", name = "Spotter", shake = 1.0, aim = 5,
  init = function(st)
    plan_pass(st, rnd(6, 8), 3.5, 6.5, true, 0)
    st.max_zoom = S.max_zoom
  end,
  place = function(st, o, dt) fixed_place(st, o, dt, 0.35, 2 / 5) end,
  done = pass_done,
}

shot {
  id = "a2a", name = "Air-to-air", rel = true, shake = 0.5, aim = 4,
  available = function() return not A.on_ground and A.agl > 15 end,
  init = function(st)
    local side = sign_rnd()
    st.bx, st.by, st.bz = side * rnd(1.9, 2.6), rnd(-0.15, 0.45), rnd(-0.9, 0.6)
    st.h, st.hv = track_or_heading(), 0
    st.roll, st.rv = 0.6 * A.phi, 0
    st.seed = rnd(0, 100)
  end,
  place = function(st, o, dt)
    st.h, st.hv = spring_angle(st.h, st.hv, track_or_heading(), 1.4, 1, dt)
    local D, s, t = A.R * S.distance, st.seed, st.t
    local ox, oy, oz = heading_to_world((st.bx + 0.30 * wob(t * 0.10, s)) * D,
                                        (st.by + 0.18 * wob(t * 0.13, s + 1)) * D,
                                        (st.bz + 0.45 * wob(t * 0.07, s + 2)) * D, st.h)
    o.x, o.y, o.z = A.x + ox, A.y + oy, A.z + oz
    o.tx = A.x + 0.08 * A.R * wob(t * 0.2, s + 3)
    o.ty = A.y + 0.05 * A.R * wob(t * 0.17, s + 4)
    o.tz = A.z + 0.08 * A.R * wob(t * 0.15, s + 5)
    st.roll, st.rv = spring(st.roll, st.rv, 0.6 * A.phi, 2, 1, dt)
    o.rol, o.zoom = st.roll, 1.15
  end,
}

local SWEEPS = {
  { { 0.5, -0.15, -3.0 }, { 3.4, 0.5, -0.6 }, { 1.4, 1.2, 2.8 } },   -- low front, past the wing, up behind
  { { 2.8, 1.4, 1.5 }, { 2.2, 0.2, -1.5 }, { -0.8, 0.35, -3.2 } },   -- high behind, down the side, across the nose
  { { -2.6, 0.1, 2.2 }, { 0.0, 1.9, 0.2 }, { 2.6, 0.1, -1.4 } },     -- over the top, side to side
}

shot {
  id = "sweep", name = "Crane sweep", rel = true, shake = 0.25, aim = 5,
  init = function(st)
    st.path = SWEEPS[random(#SWEEPS)]
    st.side = sign_rnd()
    st.h, st.hv = track_or_heading(), 0
  end,
  place = function(st, o, dt)
    st.h, st.hv = spring_angle(st.h, st.hv, track_or_heading(), 1.4, 1, dt)
    local u = (st.t / SWEEP_TIME) % 2
    if u > 1 then u = 2 - u end
    local s = smoother(u)
    local a, b, c = (1 - s) * (1 - s), 2 * (1 - s) * s, s * s
    local P0, P1, P2 = st.path[1], st.path[2], st.path[3]
    local D = A.R * S.distance
    local hx = (a * P0[1] + b * P1[1] + c * P2[1]) * st.side * D
    local hy = (a * P0[2] + b * P1[2] + c * P2[2]) * D
    local hz = (a * P0[3] + b * P1[3] + c * P2[3]) * D
    local ox, oy, oz = heading_to_world(hx, hy, hz, st.h)
    o.x, o.y, o.z = A.x + ox, A.y + oy, A.z + oz
    o.tx, o.ty, o.tz = A.x, A.y, A.z
    o.rol, o.zoom = 0.15 * A.phi, 1
  end,
}

shot {
  id = "tail", name = "Tail cam", rel = true, vib = 1,
  init = function() end,
  place = function(st, o) mount(o, 0, 0.45, 1.10, 0, 0.38, 0.10) end,
}

shot {
  id = "wing", name = "Wing cam", rel = true, vib = 1,
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 1.05, 0.30, 0.15, 0, 0, -0.90, true) end,
}

shot {
  id = "nose", name = "Nose cam", rel = true, vib = 1,
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 0.18, 0.12, -1.45, 0, 0.08, -0.80) end,
}

shot {
  id = "top", name = "Top cam", rel = true, vib = 1,
  init = function() end,
  place = function(st, o) mount(o, 0, 0.34, -0.55, 0, 0.15, 1.10) end,
}

shot {
  id = "gear", name = "Gear cam", rel = true, vib = 1.5, ground_margin = 0.35,
  available = function() return A.on_ground or A.agl < 300 end,
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 0.12, -0.20, 0.55, 0, -0.28, -1.40) end,
}

-- -----------------------------------------------------------------------------
-- Session state
-- -----------------------------------------------------------------------------

local cine = {
  active = false,
  def = nil, st = nil,                  -- current shot
  prev_def = nil, prev_st = nil,        -- shot being glided from
  blend = 1, blend_len = 0, blend_check = false,
  ext_on = false, expect_release = false, override = false,
  waiting = false, wait = 0,            -- switching to an exterior view
  origin_internal = true,               -- you started in the cockpit
  last_id = "chase",
  title = "", title_t = 0,
  message = nil,
}

-- Your adjustments (zoom, orbit around, height), kept for each shot so going
-- back to a shot, or a flyby setting up its next pass, keeps them.
local adjustments = {}
local nudge = { yaw = 0, up = 0, zoom = 1 }
local function use_adjustments(id)
  local a = adjustments[id]
  if not a then
    a = { yaw = 0, up = 0, zoom = 1 }
    adjustments[id] = a
  end
  nudge = a
end
local function reset_nudge() nudge.yaw, nudge.up, nudge.zoom = 0, 0, 1 end
local function zoom_by(f) nudge.zoom = clamp(nudge.zoom * f, 0.4, 10) end

local clock = { last = nil, dt = 1 / 30 }
local cam_clock = { last = nil }
local frame = { id = 0, ticked = -1 }

local function sim_dt(last)
  local t = getf(REF.run_time)
  local dt = last and (t - last) or 0
  if not (dt > 0 and dt < 0.25) then dt = clamp(getf(REF.frame_period), 0.001, 0.1) end
  return t, dt
end

local function vr_on() return REF.vr ~= nil and geti(REF.vr) ~= 0 end

-- -----------------------------------------------------------------------------
-- The camera: X-Plane calls this every frame while we have the camera. It
-- reads the aircraft pose itself so the camera never lags the drawn aircraft.
-- -----------------------------------------------------------------------------

local work_a, work_b = {}, {}

local function run_shot(def, st, o, dt)
  o.tx, o.hdg, o.pit, o.rol, o.zoom = nil, 0, 0, 0, 1
  def.place(st, o, dt)

  if o.tx and (nudge.yaw ~= 0 or nudge.up ~= 0) then
    local ox, oy, oz = heading_to_world(o.x - A.x, o.y - A.y, o.z - A.z, nudge.yaw)
    o.x, o.y, o.z = A.x + ox, A.y + oy + nudge.up * A.R, A.z + oz
  end

  local margin = def.ground_margin or 1.2
  local gy = terrain_y(o.x, o.y, o.z)
  if gy and o.y < gy + margin then o.y = gy + margin end

  if o.tx then
    local h, p = look_angles(o.tx - o.x, o.ty - o.y, o.tz - o.z)
    if def.aim then
      if not st.ah then st.ah, st.ahv, st.ap, st.apv = h, 0, p, 0 end
      st.ah, st.ahv = spring_angle(st.ah, st.ahv, h, def.aim, 1, dt)
      st.ap, st.apv = spring(st.ap, st.apv, p, def.aim, 1, dt)
      h, p = st.ah, st.ap
    end
    o.hdg, o.pit = h, p
  else
    o.hdg, o.pit = o.hdg + nudge.yaw, o.pit + nudge.up * 10
  end

  -- Handheld camera: slow drift plus a little jitter, calmer on long lenses.
  local shake = S.shake * (def.shake or 0)
  if shake > 0 then
    local k, t = shake / sqrt(max(o.zoom, 1)), st.t
    o.hdg = o.hdg + k * 0.9 * (wob(t * 1.6, 1) + 0.25 * sin(t * 11.3))
    o.pit = o.pit + k * 0.7 * (wob(t * 1.9, 7) + 0.25 * sin(t * 13.1 + 1))
    o.rol = o.rol + k * 0.6 * wob(t * 1.3, 13)
  end
  -- Airframe vibration for mounted cameras.
  if def.vib then
    local v = def.vib * (0.3 + S.shake) * (min(A.ias / 150, 1.5) * 0.05 + (A.on_ground and min(A.gs / 30, 1) * 0.12 or 0))
    if v > 0 then
      o.hdg = o.hdg + rnd(-v, v) * 0.5
      o.pit = o.pit + rnd(-v, v)
      o.rol = o.rol + rnd(-v, v) * 0.5
    end
  end
  o.zoom = o.zoom * nudge.zoom
end

-- Would a straight glide between two camera positions pass through the aircraft?
local function path_clear(a, b)
  local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
  local len2 = dx * dx + dy * dy + dz * dz
  local t = 0
  if len2 > 1e-6 then t = clamp(((A.x - a.x) * dx + (A.y - a.y) * dy + (A.z - a.z) * dz) / len2, 0, 1) end
  local cx, cy, cz = a.x + dx * t - A.x, a.y + dy * t - A.y, a.z + dz * t - A.z
  return cx * cx + cy * cy + cz * cz > (0.9 * A.R) ^ 2
end

local function lens_factor()
  if not S.normalize_lens or not REF.fov then return 1 end
  local fov = getf(REF.fov)
  if not (fov > 20 and fov < 150) then return 1 end
  return tan(rad(fov / 2)) / tan(rad(BASE_FOV / 2))
end

local last_good = nil
local hook_zoom          -- defined with the zoom handling below

local function camera_update(pos, losing)
  if losing ~= 0 then
    cine.ext_on = false
    if not cine.expect_release then cine.override = true end
    cine.expect_release = false
    return 0
  end
  if not (cine.active and cine.def) then return 0 end

  local t, dt = sim_dt(cam_clock.last)
  cam_clock.last = t
  -- If FlyWithLua has stopped running this script (another script's error,
  -- say), hand the camera back rather than keep a callback X-Plane might call
  -- after the Lua state is gone.
  if clock.last and t - clock.last > 2 then
    cine.ext_on, cine.override = false, true
    hook_zoom(false)
    return 0
  end
  read_pose()

  local st = cine.st
  st.t = st.t + dt
  local o = work_a
  run_shot(cine.def, st, o, dt)

  if cine.prev_def then
    local pst = cine.prev_st
    pst.t = pst.t + dt
    local b = work_b
    run_shot(cine.prev_def, pst, b, dt)
    if cine.blend_check then
      cine.blend_check = false
      if not path_clear(b, o) then cine.prev_def, cine.prev_st, cine.blend = nil, nil, 1 end
    end
    if cine.prev_def then
      cine.blend = cine.blend + dt / max(cine.blend_len, 0.05)
      if cine.blend >= 1 then
        cine.prev_def, cine.prev_st, cine.blend = nil, nil, 1
      else
        local s = smoother(cine.blend)
        local ax, ay, az = o.x, o.y, o.z
        o.x, o.y, o.z = lerp(b.x, ax, s), lerp(b.y, ay, s), lerp(b.z, az, s)
        local gy = terrain_y(o.x, o.y, o.z)
        if gy and o.y < gy + 1.2 then o.y = gy + 1.2 end
        if o.tx and b.tx then
          -- Both look at the aircraft: keep it framed all the way, carrying
          -- over each shot's lag and shake.
          local ha, pa = look_angles(o.tx - ax, o.ty - ay, o.tz - az)
          local hb, pb = look_angles(b.tx - b.x, b.ty - b.y, b.tz - b.z)
          local h, p = look_angles(lerp(b.tx, o.tx, s) - o.x, lerp(b.ty, o.ty, s) - o.y, lerp(b.tz, o.tz, s) - o.z)
          o.hdg = h + lerp(wrap180(b.hdg - hb), wrap180(o.hdg - ha), s)
          o.pit = p + lerp(b.pit - pb, o.pit - pa, s)
        else
          o.hdg = b.hdg + wrap180(o.hdg - b.hdg) * s
          o.pit = lerp(b.pit, o.pit, s)
        end
        o.rol = lerp(b.rol, o.rol, s)
        o.zoom = lerp(b.zoom, o.zoom, s)
      end
    end
  end

  local zoom = o.zoom * lens_factor()
  if not (finite(o.x) and finite(o.y) and finite(o.z) and finite(o.hdg) and finite(o.pit) and finite(o.rol) and finite(zoom)) then
    if not last_good then return 0 end
    o = last_good
  else
    zoom = clamp(zoom, 0.3, 40)
    last_good = last_good or {}
    last_good.x, last_good.y, last_good.z = o.x, o.y, o.z
    last_good.hdg, last_good.pit, last_good.rol, last_good.zoom = o.hdg, o.pit, o.rol, zoom
    o = last_good
  end
  pos.x, pos.y, pos.z = o.x, o.y, o.z
  pos.pitch, pos.heading, pos.roll, pos.zoom = o.pit, o.hdg, o.rol, o.zoom
  return 1
end

local camera_error_logged = false
local camera_cb = ffi.cast("cv_CameraControl_f", function(pos, losing, refcon)
  local ok, res = pcall(camera_update, pos, losing)
  if ok then return res end
  if not camera_error_logged then
    camera_error_logged = true
    log("camera error, handing the camera back: " .. tostring(res))
  end
  cine.ext_on = false
  cine.override = true
  return 0
end)

local function take_camera()
  cine.expect_release = false
  cam_clock.last = nil
  last_good = nil
  XPLM.cv_ControlCamera(1, camera_cb, nil)   -- 1 = until the view changes
  cine.ext_on = true
end

local function release_camera()
  if cine.ext_on then
    cine.expect_release = true
    XPLM.cv_DontControlCamera()
    cine.ext_on = false
  end
end

-- -----------------------------------------------------------------------------
-- X-Plane's zoom while filming: its zoom commands (keys, joystick buttons)
-- are taken over only while a shot runs and handed straight back after.
-- -----------------------------------------------------------------------------

local zoom_hooked = false

local function zoom_command(phase, refcon)
  local z = ZOOM_CMDS[tonumber(ffi.cast("intptr_t", refcon))]
  if not (z and cine.active) then return 1 end
  if phase == 0 then
    zoom_by(exp(z.dir * z.rate * 0.05))                    -- a tap: one step
  elseif phase == 1 then
    zoom_by(exp(z.dir * z.rate * 0.8 * clock.dt))          -- held: smooth zoom
  end
  return 0
end

local zoom_cb = ffi.cast("cv_CommandCallback_f", function(cmd, phase, refcon)
  local ok, res = pcall(zoom_command, phase, refcon)
  if ok then return res end
  return 1
end)

hook_zoom = function(on)
  if on == zoom_hooked then return end
  for i, z in ipairs(ZOOM_CMDS) do
    if z.ref then
      if on then
        XPLM.cv_RegisterCommandHandler(z.ref, zoom_cb, 1, ffi.cast("void *", i))
      else
        XPLM.cv_UnregisterCommandHandler(z.ref, zoom_cb, 1, ffi.cast("void *", i))
      end
    end
  end
  zoom_hooked = on
end

-- -----------------------------------------------------------------------------
-- Switching shots, starting and stopping
-- -----------------------------------------------------------------------------

local function shot_available(def)
  return not def.available or def.available()
end

local function begin_shot(id, how)
  local def = SHOTS[id]
  if not def then return end
  local prev_def, prev_st = cine.def, cine.st
  local st = { t = 0 }
  def.init(st)

  if prev_def and cine.ext_on then
    if S.blend_time > 0.05 and how ~= "cut" and prev_def.rel and def.rel then
      cine.prev_def, cine.prev_st = prev_def, prev_st
      cine.blend, cine.blend_len, cine.blend_check = 0, S.blend_time, true
    else
      cine.prev_def, cine.prev_st, cine.blend = nil, nil, 1
    end
    cine.waiting = false
  else
    -- Switch to an exterior view, then take the camera (now, if the switch
    -- already happened, or as soon as it does).
    cine.prev_def, cine.prev_st, cine.blend = nil, nil, 1
    cine.waiting, cine.wait = true, 0
    if geti(REF.external) == 0 then run_cmd(CMD.external) end
    if geti(REF.external) ~= 0 then
      cine.waiting = false
      take_camera()
    end
  end

  cine.def, cine.st, cine.last_id = def, st, id
  use_adjustments(id)
  cine.title, cine.title_t = def.name, 4
end

local function start_session()
  if cine.active then return true end
  if vr_on() then
    log("cinematic views are off in VR.")
    cine.message = "Not available in VR"
    return false
  end
  if not CMD.external then
    log("could not find X-Plane's exterior view command.")
    return false
  end
  cine.active, cine.override, cine.message = true, false, nil
  cine.origin_internal = geti(REF.external) == 0
  measure_aircraft()
  hook_zoom(true)
  return true
end

local function stop_session(restore_view)
  if not cine.active then return end
  cine.active = false
  if restore_view and cine.origin_internal and CMD.cockpit then
    cine.expect_release = true
    run_cmd(CMD.cockpit)
  end
  release_camera()
  hook_zoom(false)
  cine.def, cine.st, cine.prev_def, cine.prev_st, cine.waiting = nil, nil, nil, nil, false
end

for _, f in ipairs({ run_cmd, take_camera, release_camera, begin_shot, stop_session }) do
  if jit and jit.off then jit.off(f, true) end
end

-- -----------------------------------------------------------------------------
-- Per-frame work
-- -----------------------------------------------------------------------------

local queue = {}
local function request(fn) queue[#queue + 1] = fn end

local LB = { amount = 0 }

local function tick()
  local t, dt = sim_dt(clock.last)
  clock.last, clock.dt = t, dt

  update_dynamics(dt)

  -- Commands, macros and window buttons, run here with this frame's state.
  local q = queue
  queue = {}
  for _, fn in ipairs(q) do
    local ok, err = pcall(fn)
    if not ok then log("error: " .. tostring(err)) end
  end

  if cine.override then
    -- You changed the view yourself: the camera is yours again.
    cine.override = false
    if cine.active then stop_session(false) end
  end
  if cine.active and vr_on() then stop_session(false) end

  if cine.active and cine.def then
    if cine.waiting then
      if geti(REF.external) ~= 0 then
        cine.waiting = false
        take_camera()
      else
        cine.wait = cine.wait + 1
        if cine.wait % 30 == 0 then run_cmd(CMD.external) end
        if cine.wait > 150 then
          log("could not switch to an exterior view.")
          stop_session(true)
        end
      end
    elseif not cine.ext_on then
      take_camera()
    end
    local def = cine.def
    if cine.active and def and def.done and def.done(cine.st) then
      begin_shot(def.id, "cut")          -- flyby/spotter: set up the next pass
    end
  end

  if cine.title_t > 0 then cine.title_t = cine.title_t - dt end
  local want = (cine.active and S.letterbox and not vr_on()) and 1 or 0
  if LB.amount < want then
    LB.amount = min(want, LB.amount + dt / 0.8)
  elseif LB.amount > want then
    LB.amount = max(want, LB.amount - dt / 0.8)
  end
end

local function on_frame()
  if frame.ticked ~= frame.id then
    frame.ticked = frame.id
    tick()
  end
end

-- -----------------------------------------------------------------------------
-- Drawing: letterbox and shot title
-- -----------------------------------------------------------------------------

local function on_draw()
  -- Also the heartbeat while paused, when flight loops may not run.
  if frame.ticked ~= frame.id then
    frame.ticked = frame.id
    local ok, err = pcall(tick)
    if not ok then log("error: " .. tostring(err)) end
  end
  frame.id = frame.id + 1

  local W, H = SCREEN_WIDTH, SCREEN_HIGHT
  if not (W and H) or not graphics then return end
  local bar = 0
  if LB.amount > 0.001 then
    bar = max(0, (H - W / S.aspect) / 2) * smoother(LB.amount)
    if bar >= 1 then
      XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)
      graphics.set_color(0, 0, 0, 1)
      graphics.draw_rectangle(0, 0, W, bar)
      graphics.draw_rectangle(0, H - bar, W, H)
    end
  end
  if S.titles and cine.active and cine.title_t > 0 and draw_string then
    local y = (bar > 24) and (bar / 2 - 4) or 30
    draw_string(30, y, cine.title, "white")
  end
end

-- -----------------------------------------------------------------------------
-- Public actions (commands, macros and the window all go through these)
-- -----------------------------------------------------------------------------

local function act_shot(id)
  if not SHOTS[id] then return end
  if not cine.active and not start_session() then return end
  begin_shot(id, "manual")
end

local function act_step(step)
  local cur, n = cine.def and cine.def.id, #SHOT_ORDER
  local idx = (step > 0) and 0 or 1
  for i, id in ipairs(SHOT_ORDER) do if id == cur then idx = i end end
  for _ = 1, n do
    idx = (idx - 1 + step) % n + 1
    if shot_available(SHOTS[SHOT_ORDER[idx]]) then break end
  end
  act_shot(SHOT_ORDER[idx])
end

local function act_toggle()
  if cine.active then stop_session(true) else act_shot(cine.last_id) end
end

local M = {}
M.version = VERSION
M.toggle = function() request(act_toggle) end
M.stop = function() request(function() stop_session(true) end) end
M.next_shot = function() request(function() act_step(1) end) end
M.previous_shot = function() request(function() act_step(-1) end) end
M.shot = function(id) request(function() act_shot(id) end) end
M.toggle_letterbox = function() S.letterbox = not S.letterbox settings_dirty = true end

-- The mouse wheel zooms the camera while a shot runs; otherwise it is left alone.
M._wheel = function()
  if cine.active and cine.ext_on and (tonumber(MOUSE_WHEEL_NUMBER) or 0) == 0 then
    zoom_by(1.1 ^ (tonumber(MOUSE_WHEEL_CLICKS) or 0))
    RESUME_MOUSE_WHEEL = false
  else
    RESUME_MOUSE_WHEEL = true
  end
end

M.nudge = function(kind, dir)
  local dt = clock.dt
  if kind == "yaw" then
    nudge.yaw = wrap180(nudge.yaw + dir * 40 * dt)
  elseif kind == "up" then
    nudge.up = clamp(nudge.up + dir * 0.6 * dt, -2, 3)
  elseif kind == "zoom" then
    zoom_by(exp(dir * 0.8 * dt))
  end
end
M.reset_nudge = reset_nudge

-- Settings window -------------------------------------------------------------

local wnd = nil

local COL_ACTIVE = 0xFFD08A2A    -- imgui colours are 0xAABBGGRR
local COL_MUTED = 0xFF9A9A9A

local function shot_buttons()
  for i, id in ipairs(SHOT_ORDER) do
    local def = SHOTS[id]
    if (i - 1) % 4 > 0 then imgui.SameLine() end
    local current = cine.active and cine.def == def
    local usable = shot_available(def)
    if current then imgui.PushStyleColor(imgui.constant.Col.Button, COL_ACTIVE) end
    if not usable then imgui.PushStyleColor(imgui.constant.Col.Text, COL_MUTED) end
    if imgui.Button(def.name .. "##" .. id, 112, 26) then M.shot(id) end
    if not usable then imgui.PopStyleColor() end
    if current then imgui.PopStyleColor() end
  end
end

local function slider(label, key, lo, hi, fmt)
  local changed, v = imgui.SliderFloat(label, S[key], lo, hi, fmt)
  if changed then S[key], settings_dirty = v, true end
  return changed
end

local function checkbox(label, key)
  local changed, v = imgui.Checkbox(label, S[key])
  if changed then S[key], settings_dirty = v, true end
  return changed
end

local function muted(text)
  imgui.PushStyleColor(imgui.constant.Col.Text, COL_MUTED)
  imgui.TextUnformatted(text)
  imgui.PopStyleColor()
end

local function build_window()
  if cine.active and cine.def then
    imgui.TextUnformatted(("Filming: %s   |   zoom %.1fx"):format(cine.def.name, nudge.zoom))
  else
    imgui.TextUnformatted(cine.message or "Camera is yours")
  end

  local on = cine.active
  if on then imgui.PushStyleColor(imgui.constant.Col.Button, COL_ACTIVE) end
  if imgui.Button(on and "Stop" or ("Start (" .. SHOTS[cine.last_id].name .. ")"), 160, 30) then M.toggle() end
  if on then imgui.PopStyleColor() end
  imgui.SameLine()
  if imgui.Button("< Previous", 100, 30) then M.previous_shot() end
  imgui.SameLine()
  if imgui.Button("Next >", 100, 30) then M.next_shot() end

  imgui.Separator()
  shot_buttons()
  imgui.Separator()

  if imgui.TreeNode("Camera") then
    slider("Distance", "distance", 0.5, 3, "%.2fx")
    slider("Orbit speed (deg/s)", "orbit_speed", 1, 20, "%.0f")
    slider("Handheld shake", "shake", 0, 1, "%.2f")
    slider("Telephoto limit", "max_zoom", 2, 15, "%.0fx")
    slider("Glide between shots (s, 0 = cut)", "blend_time", 0, 5, "%.1f")
    local changed, v = imgui.SliderFloat("Aircraft size", SIZE.scales[SIZE.key] or 1, 0.4, 2.5, "%.2fx")
    if changed then
      SIZE.scales[SIZE.key], settings_dirty = v, true
      measure_aircraft()
    end
    muted(("   %.0f m span x %.0f m long, %s"):format(2 * A.Rs, 2 * A.Rl,
      A.size_source == "dimensions" and "from the aircraft's dimensions" or "estimated from its weight"))
    muted("   a size correction is remembered for each aircraft")
    checkbox("Frame shots for a 60 deg lens whatever the sim FOV", "normalize_lens")
    imgui.TextUnformatted("Adjust the live shot (zoom: mouse wheel or X-Plane's zoom keys):")
    if imgui.Button("Orbit <", 70, 24) then nudge.yaw = wrap180(nudge.yaw - 15) end
    imgui.SameLine()
    if imgui.Button("Orbit >", 70, 24) then nudge.yaw = wrap180(nudge.yaw + 15) end
    imgui.SameLine()
    if imgui.Button("Up", 44, 24) then nudge.up = clamp(nudge.up + 0.25, -2, 3) end
    imgui.SameLine()
    if imgui.Button("Down", 50, 24) then nudge.up = clamp(nudge.up - 0.25, -2, 3) end
    imgui.SameLine()
    if imgui.Button("Zoom +", 62, 24) then zoom_by(1.25) end
    imgui.SameLine()
    if imgui.Button("Zoom -", 62, 24) then zoom_by(1 / 1.25) end
    if imgui.Button("Reset adjustments", 150, 24) then reset_nudge() end
    imgui.SameLine()
    muted(("zoom %.1fx"):format(nudge.zoom))
    imgui.TreePop()
  end

  if imgui.TreeNode("Look") then
    checkbox("Letterbox bars", "letterbox")
    imgui.SameLine()
    checkbox("Shot titles", "titles")
    for _, a in ipairs({ { 1.85, "1.85:1" }, { 2.0, "2:1" }, { 2.39, "2.39:1 scope" } }) do
      local cur = abs(S.aspect - a[1]) < 0.01
      if cur then imgui.PushStyleColor(imgui.constant.Col.Button, COL_ACTIVE) end
      if imgui.Button(a[2], 100, 24) then S.aspect, settings_dirty = a[1], true end
      if cur then imgui.PopStyleColor() end
      imgui.SameLine()
    end
    imgui.TextUnformatted("")
    imgui.TreePop()
  end

  if vr_on() then muted("VR is on: cinematic views are paused.") end
  muted("Cinematic Views " .. VERSION .. "  -  every button is also a command under FlyWithLua/cinematic_views/")
end

function cinematic_views_build_window(_, _, _)
  local ok, err = pcall(build_window)
  if not ok then
    log("window error: " .. tostring(err))
  end
end

function cinematic_views_window_closed(_)
  wnd = nil
  if settings_dirty then save_settings() end
end

M.toggle_window = function()
  if wnd then
    float_wnd_destroy(wnd)
    wnd = nil
    if settings_dirty then save_settings() end
    return
  end
  if not (SUPPORTS_FLOATING_WINDOWS and float_wnd_create) then
    log("the settings window needs FlyWithLua NG 2.7 or later; the commands still work.")
    return
  end
  wnd = float_wnd_create(500, 460, 1, true)
  float_wnd_set_title(wnd, "Cinematic Views")
  float_wnd_set_imgui_builder(wnd, "cinematic_views_build_window")
  float_wnd_set_onclose(wnd, "cinematic_views_window_closed")
end

-- Housekeeping ----------------------------------------------------------------

M._frame = function()
  local ok, err = pcall(on_frame)
  if not ok then log("error: " .. tostring(err)) end
end
M._draw = function()
  local ok, err = pcall(on_draw)
  if not ok then log("draw error: " .. tostring(err)) end
end
M._often = function()
  if not cine.active then measure_aircraft() end
  if settings_dirty then save_settings() end
end

local shut = false
M.shutdown = function()
  if shut then return end
  shut = true
  pcall(stop_session, false)
  pcall(release_camera)
  pcall(XPLM.cv_DontControlCamera)
  pcall(hook_zoom, false)
  if probe then pcall(XPLM.cv_DestroyProbe, probe) probe = nil end
  if wnd and float_wnd_destroy then pcall(float_wnd_destroy, wnd) wnd = nil end
  if settings_dirty then pcall(save_settings) end
  pcall(function() camera_cb:free() end)
  pcall(function() zoom_cb:free() end)
end

measure_aircraft()

-- For testing and for other scripts.
M._state = function() return cine, A, S end
M._shots = function() return SHOTS, SHOT_ORDER end

CinematicViews = M

-- -----------------------------------------------------------------------------
-- Registration with FlyWithLua
-- -----------------------------------------------------------------------------

do_every_frame("CinematicViews._frame()")
do_every_draw("CinematicViews._draw()")
do_often("CinematicViews._often()")
do_on_exit("CinematicViews.shutdown()")
if do_on_mouse_wheel then do_on_mouse_wheel("CinematicViews._wheel()") end

local P = "FlyWithLua/cinematic_views/"
local function command(name, desc, code)
  create_command(P .. name, "Cinematic Views: " .. desc, code, "", "")
end
local function hold_command(name, desc, code)
  create_command(P .. name, "Cinematic Views: " .. desc, "", code, "")
end

command("toggle", "start (with the last shot) or stop and hand the camera back", "CinematicViews.toggle()")
command("stop", "stop and return to your view", "CinematicViews.stop()")
command("next_shot", "next shot", "CinematicViews.next_shot()")
command("previous_shot", "previous shot", "CinematicViews.previous_shot()")
command("toggle_letterbox", "letterbox bars on/off", "CinematicViews.toggle_letterbox()")
command("toggle_window", "settings window", "CinematicViews.toggle_window()")
command("reset_adjustments", "reset orbit, height and zoom adjustments", "CinematicViews.reset_nudge()")
hold_command("orbit_left", "move the camera around the aircraft to the left (hold)", "CinematicViews.nudge('yaw', -1)")
hold_command("orbit_right", "move the camera around the aircraft to the right (hold)", "CinematicViews.nudge('yaw', 1)")
hold_command("camera_up", "raise the camera (hold)", "CinematicViews.nudge('up', 1)")
hold_command("camera_down", "lower the camera (hold)", "CinematicViews.nudge('up', -1)")
hold_command("zoom_in", "zoom in (hold; X-Plane's own zoom commands work too)", "CinematicViews.nudge('zoom', 1)")
hold_command("zoom_out", "zoom out (hold)", "CinematicViews.nudge('zoom', -1)")
for _, id in ipairs(SHOT_ORDER) do
  command("shot_" .. id, SHOTS[id].name .. " shot", "CinematicViews.shot('" .. id .. "')")
end

if add_macro then
  add_macro("Cinematic Views: start/stop", "CinematicViews.toggle()")
  add_macro("Cinematic Views: next shot", "CinematicViews.next_shot()")
  add_macro("Cinematic Views: settings window", "CinematicViews.toggle_window()")
end

if not CMD.external then log("no exterior view command found - cinematic views are off.") end
log("v" .. VERSION .. " ready - Plugins > FlyWithLua > Macros, or the FlyWithLua/cinematic_views/ commands.")
