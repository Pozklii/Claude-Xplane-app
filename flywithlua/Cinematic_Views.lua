-- =============================================================================
--  Cinematic Views for X-Plane 12                                        v1.0.0
--  A FlyWithLua NG+ script: a virtual film crew for your flights.
--
--  * Director: automatic, flight-phase-aware camera work. It picks shots that
--    suit taxi, the takeoff roll, departure, cruise and approach, cuts or
--    glides between them, and never repeats itself back to back.
--  * 11 exterior shots through X-Plane's camera API: chase, orbit, flyby,
--    runway spotter (telephoto with zoom tracking), air-to-air photo ship,
--    crane sweep, and tail, wing, nose, top and gear cams rigidly mounted
--    on the airframe.
--  * 6 cockpit shots by moving the pilot's head: pilot's eye (with glances),
--    over the shoulder, panel sweep, side window, first officer, cabin window.
--  * Living cockpit: your head reacts to G-forces, turbulence, touchdowns and
--    runway rumble, looks into turns and leans against the bank. Works in
--    cinematic shots and, if you like, all the time while you fly.
--  * Handheld/telephoto lens behaviour, smooth blends, letterbox bars, shot
--    titles, a settings window, and commands for every function.
--
--  Install: copy this file to  X-Plane 12/Resources/plugins/FlyWithLua/Scripts/
--  Use:     Plugins > FlyWithLua > FlyWithLua Macros > Cinematic Views ...
--           or bind the "FlyWithLua/cinematic_views/..." commands to keys or
--           joystick buttons (Settings > Keyboard / Joystick).
--
--  Requires FlyWithLua NG+ (LuaJIT with FFI). Settings are saved next to this
--  file in Cinematic_Views.ini.
-- =============================================================================

local VERSION = "1.0.0"
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
  'int cv_CanWriteDataRef(void *ref) __asm__("XPLMCanWriteDataRef");',
  'int cv_GetDatai(void *ref) __asm__("XPLMGetDatai");',
  'float cv_GetDataf(void *ref) __asm__("XPLMGetDataf");',
  'double cv_GetDatad(void *ref) __asm__("XPLMGetDatad");',
  'void cv_SetDataf(void *ref, float value) __asm__("XPLMSetDataf");',
  'void *cv_FindCommand(const char *name) __asm__("XPLMFindCommand");',
  'void cv_CommandOnce(void *cmd) __asm__("XPLMCommandOnce");',
  'void cv_ControlCamera(int howLong, cv_CameraControl_f func, void *refcon) __asm__("XPLMControlCamera");',
  'void cv_DontControlCamera(void) __asm__("XPLMDontControlCamera");',
  'void *cv_CreateProbe(int type) __asm__("XPLMCreateProbe");',
  'void cv_DestroyProbe(void *probe) __asm__("XPLMDestroyProbe");',
  'int cv_ProbeTerrainXYZ(void *probe, float x, float y, float z, cv_ProbeInfo_t *info) __asm__("XPLMProbeTerrainXYZ");',
  'void cv_WorldToLocal(double lat, double lon, double alt, double *x, double *y, double *z) __asm__("XPLMWorldToLocal");',
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
  m_total = "sim/flightmodel/weight/m_total",
  throttle = "sim/cockpit2/engine/actuators/throttle_ratio_all",
  view_type = "sim/graphics/view/view_type",
  external = "sim/graphics/view/view_is_external",
  fov = "sim/graphics/view/field_of_view_deg",
  head_x = "sim/graphics/view/pilots_head_x",
  head_y = "sim/graphics/view/pilots_head_y",
  head_z = "sim/graphics/view/pilots_head_z",
  head_psi = "sim/graphics/view/pilots_head_psi",
  head_the = "sim/graphics/view/pilots_head_the",
  head_phi = "sim/graphics/view/pilots_head_phi",
  run_time = "sim/time/total_running_time_sec",
  frame_period = "sim/operation/misc/frame_rate_period",
  paused = "sim/time/paused",
  replay = "sim/time/is_in_replay",
  vr = "sim/graphics/VR/enabled",
}
for key, name in pairs(REF_NAMES) do REF[key] = find_ref(name) end

for _, key in ipairs({ "x", "y", "z", "psi", "the", "phi", "view_type", "external",
                       "head_x", "head_y", "head_z", "head_psi", "head_the", "run_time" }) do
  if not REF[key] then
    log("dataref " .. REF_NAMES[key] .. " not found - not started.")
    return
  end
end

local function getf(r) if r then return XPLM.cv_GetDataf(r) end return 0 end
local function getd(r) if r then return XPLM.cv_GetDatad(r) end return 0 end
local function geti(r) if r then return XPLM.cv_GetDatai(r) end return 0 end
local function setf(r, v) if r then XPLM.cv_SetDataf(r, v) end end

local FOV_WRITABLE = REF.fov ~= nil and XPLM.cv_CanWriteDataRef(REF.fov) ~= 0

local function find_cmd(...)
  for i = 1, select("#", ...) do
    local c = XPLM.cv_FindCommand((select(i, ...)))
    if c ~= nil then return c end
  end
  return nil
end

local CMD = {
  cockpit = find_cmd("sim/view/3d_cockpit_cmnd_look", "sim/view/default_view"),
  external = find_cmd("sim/view/chase", "sim/view/circle", "sim/view/free_camera"),
}

-- A view change while X-Plane hands the camera to us can call straight back
-- into Lua (our camera callback). LuaJIT only allows that from interpreted
-- code, so everything that can trigger it runs with the JIT off.
local function run_cmd(c)
  if c then XPLM.cv_CommandOnce(c) end
end

local VIEW_3D_COCKPIT = 1026

-- -----------------------------------------------------------------------------
-- Settings
-- -----------------------------------------------------------------------------

local DEFAULTS = {
  shot_length = 12,       -- Director: average seconds per shot
  cockpit_share = 0.3,    -- Director: share of cockpit shots
  use_exterior = true,
  use_cockpit = true,
  use_cabin = false,      -- cabin window in the Director (best with a modelled cabin)
  blend_time = 2.5,       -- glide between related exterior/cockpit shots (0 = always cut)
  distance = 1.0,         -- exterior camera distance multiplier
  orbit_speed = 5,        -- degrees per second
  shake = 0.5,            -- handheld camera shake, 0..1
  max_zoom = 8,           -- telephoto limit for flyby and spotter shots
  size_scale = 1.0,       -- multiplier on the estimated aircraft size
  normalize_lens = true,  -- frame exterior shots as if the sim FOV were 60 degrees
  living = true,          -- living cockpit (also while you fly yourself)
  living_amount = 1.0,
  look_into_turns = true,
  horizon_lean = true,
  cockpit_fov = 0,        -- FOV for cockpit shots, 0 = leave alone
  letterbox = true,
  aspect = 2.39,
  titles = true,
}

local RANGES = {
  shot_length = { 5, 40 }, cockpit_share = { 0, 1 }, blend_time = { 0, 5 }, distance = { 0.5, 3 },
  orbit_speed = { 1, 20 }, shake = { 0, 1 }, max_zoom = { 2, 15 }, size_scale = { 0.4, 2.5 },
  living_amount = { 0, 2 }, cockpit_fov = { 0, 100 }, aspect = { 1.6, 2.8 },
}

local S = {}
for k, v in pairs(DEFAULTS) do S[k] = v end

local SETTINGS_FILE = (type(SCRIPT_DIRECTORY) == "string" and SCRIPT_DIRECTORY or "") .. "Cinematic_Views.ini"
local settings_dirty = false

local function load_settings()
  local f = io.open(SETTINGS_FILE, "r")
  if not f then return end
  for line in f:lines() do
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

local function world_to_body(wx, wy, wz, psi, the, phi)
  local p, t, r = rad(psi), rad(the), rad(phi)
  local cp, sp = cos(p), sin(p)
  local x1, z1 = wx * cp + wz * sp, -wx * sp + wz * cp
  local ct, st = cos(t), sin(t)
  local y2, z2 = wy * ct + z1 * st, -wy * st + z1 * ct
  local cr, sr = cos(r), sin(r)
  return x1 * cr - y2 * sr, x1 * sr + y2 * cr, z2
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
  rvx = 0, rvy = 0, rvz = 0,         -- last raw velocity
  ax = 0, ay = 0, az = 0,            -- smoothed acceleration (m/s2, local axes)
  gs = 0, vs = 0, trk = 0, agl = 100, ias = 0, yaw_rate = 0, throttle = 0,
  on_ground = false, paused = false, replay = false,
  R = 10,                            -- characteristic aircraft size (m, about half the span or length)
  have_pos = false, have_v = false,
}

local function read_pose()
  A.x, A.y, A.z = getd(REF.x), getd(REF.y), getd(REF.z)
  A.psi, A.the, A.phi = getf(REF.psi), getf(REF.the), getf(REF.phi)
end

-- Size from the maximum weight: aircraft are close enough to geometrically
-- similar that the cube root tracks half the span/length well, from a Cessna
-- 172 (about 5 m) to an A380 (about 40 m). The settings window can scale it.
local function estimate_size()
  local m = getf(REF.m_max)
  if not (m > 50) then m = getf(REF.m_total) end
  if not (m > 50) then m = 1200 end
  return clamp(0.48 * m ^ (1 / 3), 3.5, 45) * S.size_scale
end

local function update_dynamics(dt)
  local px, py, pz, ppsi = A.x, A.y, A.z, A.psi
  read_pose()
  A.paused = geti(REF.paused) ~= 0
  A.replay = geti(REF.replay) ~= 0
  A.on_ground = geti(REF.on_ground) ~= 0
  A.agl = REF.agl and getf(REF.agl) or 100
  A.ias = getf(REF.ias)
  A.throttle = getf(REF.throttle)

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
    if A.have_v then
      local ax, ay, az = (vx - A.rvx) / dt, (vy - A.rvy) / dt, (vz - A.rvz) / dt
      local m = sqrt(ax * ax + ay * ay + az * az)
      if m > 50 then ax, ay, az = ax * 50 / m, ay * 50 / m, az * 50 / m end
      local k = 1 - exp(-dt / 0.06)
      A.ax, A.ay, A.az = A.ax + (ax - A.ax) * k, A.ay + (ay - A.ay) * k, A.az + (az - A.az) * k
    end
    A.rvx, A.rvy, A.rvz, A.have_v = vx, vy, vz, true
    local k = 1 - exp(-dt / 0.2)
    A.vx, A.vy, A.vz = A.vx + (vx - A.vx) * k, A.vy + (vy - A.vy) * k, A.vz + (vz - A.vz) * k
    local kr = 1 - exp(-dt / 0.3)
    A.yaw_rate = A.yaw_rate + (clamp(wrap180(A.psi - ppsi) / dt, -60, 60) - A.yaw_rate) * kr
  elseif dt > 0 then
    local k = exp(-dt / 0.2)
    A.ax, A.ay, A.az, A.yaw_rate = A.ax * k, A.ay * k, A.az * k, A.yaw_rate * k
  end

  A.gs = sqrt(A.vx * A.vx + A.vz * A.vz)
  A.vs = A.vy
  A.trk = (A.gs > 2) and deg(atan2(A.vx, -A.vz)) or A.psi
end

-- Flight phase, debounced so a bump or a gust does not flip it.
local PHASE_NAMES = { taxi = "Taxi", runway = "Runway", departure = "Departure",
                      cruise = "En route", approach = "Approach", low = "Low level" }
local PH = { cur = "taxi", cand = nil, since = 0, changed = false }

local function raw_phase()
  if A.on_ground then return (A.gs > 15) and "runway" or "taxi" end
  if A.agl < 450 then
    if A.vs < -1.2 then return "approach" end
    if A.vs > 1.2 then return "departure" end
    return "low"
  end
  return "cruise"
end

local function update_phase(dt)
  local p = raw_phase()
  if p == PH.cur then PH.cand = nil return end
  if p ~= PH.cand then PH.cand, PH.since = p, 0 end
  PH.since = PH.since + dt
  if PH.since >= ((p == "runway") and 1.0 or 2.5) then
    PH.cur, PH.cand, PH.changed = p, nil, true
  end
end

-- -----------------------------------------------------------------------------
-- Living cockpit: head motion from the forces you would feel
-- -----------------------------------------------------------------------------

local HP = {
  x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0,        -- head offset spring (m)
  pit = 0, pv = 0, rol = 0, rv = 0, yaw = 0, yv = 0,  -- head angle springs (deg)
  was_ground = true, last_vs = 0, rumble = 0,
  nx = 0, ny = 0, np = 0, nr = 0, n_t = 0,            -- runway rumble noise
  out = { 0, 0, 0, 0, 0, 0 },                         -- dx, dy, dz, dpsi, dthe, dphi
}

local function update_head_physics(dt)
  local o = HP.out
  if dt <= 0 then return end
  local amt = S.living_amount
  local g = 9.81

  -- Felt (specific) force in the aircraft's axes, minus the 1 g of sitting still.
  local fx, fy, fz = world_to_body(A.ax, A.ay + g, A.az, A.psi, A.the, A.phi)
  fy = fy - g
  local K = 0.0035 * amt
  local tx, ty, tz = clamp(-K * fx, -0.08, 0.08), clamp(-K * fy, -0.10, 0.06), clamp(-K * fz, -0.08, 0.10)
  HP.x, HP.vx = spring(HP.x, HP.vx, tx, 8, 0.55, dt)
  HP.y, HP.vy = spring(HP.y, HP.vy, ty, 8, 0.5, dt)
  HP.z, HP.vz = spring(HP.z, HP.vz, tz, 7, 0.6, dt)

  -- Touchdown: a firm landing bumps your head down and nods it.
  if A.on_ground and not HP.was_ground and HP.last_vs < -0.3 then
    local sink = clamp(-HP.last_vs, 0, 6)
    HP.vy = HP.vy - sink * 0.10 * amt
    HP.pv = HP.pv - sink * 9 * amt
  end
  HP.was_ground = A.on_ground
  HP.last_vs = A.vs

  -- Head angles: nod under load and acceleration, roll with side force,
  -- look into turns, and lean against the bank toward the horizon.
  local tp = clamp((-0.9 * fy / g - 1.4 * fz / g) * amt, -6, 6)
  local tr = clamp(-2.0 * fx / g * amt, -6, 6)
  local ty_ = 0
  if S.look_into_turns then
    ty_ = clamp(A.yaw_rate * (A.on_ground and 1.2 or 2.4), -20, 20) * min(amt, 1.2)
    if A.on_ground and A.gs < 1 then ty_ = 0 end
  end
  if S.horizon_lean and not A.on_ground then
    tr = tr + clamp(-0.22 * A.phi, -9, 9) * min(amt, 1.2)
  end
  HP.pit, HP.pv = spring(HP.pit, HP.pv, tp, 6, 0.6, dt)
  HP.rol, HP.rv = spring(HP.rol, HP.rv, tr, 3, 0.9, dt)
  HP.yaw, HP.yv = spring(HP.yaw, HP.yv, ty_, 2.2, 1, dt)

  -- Runway and taxiway rumble, stronger with speed; a little engine buzz.
  local rumble = 0
  if not A.paused then
    if A.on_ground and A.gs > 0.5 then rumble = min(A.gs / 35, 1) * 0.0045 * amt end
    rumble = rumble + clamp(A.throttle, 0, 1) * 0.0005 * amt
  end
  HP.n_t = HP.n_t + dt
  if HP.n_t > 1 / 24 then
    HP.n_t = 0
    HP.nx, HP.ny, HP.np, HP.nr = rnd(-1, 1), rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)
  end
  local k = 1 - exp(-dt / 0.03)
  HP.rumble = HP.rumble + (rumble - HP.rumble) * k

  o[1] = HP.x + HP.nx * HP.rumble * 0.4
  o[2] = HP.y + HP.ny * HP.rumble
  o[3] = HP.z
  o[4] = HP.yaw
  o[5] = HP.pit + HP.np * HP.rumble * 45
  o[6] = HP.rol + HP.nr * HP.rumble * 30
  for i = 1, 6 do
    if not finite(o[i]) then
      o[i] = 0
      HP.x, HP.y, HP.z, HP.vx, HP.vy, HP.vz = 0, 0, 0, 0, 0, 0
      HP.pit, HP.pv, HP.rol, HP.rv, HP.yaw, HP.yv = 0, 0, 0, 0, 0, 0
    end
  end
end

-- -----------------------------------------------------------------------------
-- Pilot's head
-- -----------------------------------------------------------------------------

local function read_head()
  return getf(REF.head_x), getf(REF.head_y), getf(REF.head_z),
         getf(REF.head_psi), getf(REF.head_the), getf(REF.head_phi)
end

local function write_head(x, y, z, psi, the, phi)
  if not (finite(x) and finite(y) and finite(z) and finite(psi) and finite(the) and finite(phi)) then return end
  setf(REF.head_x, x) setf(REF.head_y, y) setf(REF.head_z, z)
  setf(REF.head_psi, psi) setf(REF.head_the, the)
  if REF.head_phi then setf(REF.head_phi, phi) end
end

-- The living cockpit adds an offset on top of wherever the head is. Each frame
-- it takes back exactly the offset it added the frame before, so anything you
-- (or the mouse, or a plugin) changed in between is kept, and its own motion
-- can never pile up. A sudden big jump (a snap view or a preset) is taken as
-- a new head position as it stands.
local LV = { on = false, off = { 0, 0, 0, 0, 0, 0 }, last = { 0, 0, 0, 0, 0, 0 } }

-- The head pose without any living-cockpit offset in it.
local function head_without_offset()
  local cur = { read_head() }
  if LV.on then
    local jumped = false
    for i = 1, 6 do
      if abs(cur[i] - LV.last[i]) > ((i <= 3) and 0.25 or 15) then jumped = true end
    end
    if not jumped then
      for i = 1, 6 do cur[i] = cur[i] - LV.off[i] end
    end
  end
  return cur
end

local function living_tick(active)
  if not active then
    if LV.on then
      local base = head_without_offset()
      write_head(base[1], base[2], base[3], base[4], base[5], base[6])
      LV.on = false
    end
    return
  end
  local base, o = head_without_offset(), HP.out
  for i = 1, 6 do
    LV.off[i] = o[i]
    LV.last[i] = base[i] + o[i]
  end
  local l = LV.last
  write_head(l[1], l[2], l[3], l[4], l[5], l[6])
  LV.on = true
end

-- -----------------------------------------------------------------------------
-- Shots
--
-- Exterior shots set o.x/y/z (camera position, local axes) and either a target
-- to look at (o.tx/ty/tz) or angles (o.hdg/pit/rol), plus o.zoom. Cockpit
-- shots set the head pose relative to the aircraft (o.x/y/z, o.psi/the/phi)
-- from the captured pilot's eye point B.
-- -----------------------------------------------------------------------------

local SHOTS, SHOT_ORDER = {}, {}
local function shot(def)
  def.len = def.len or 1
  SHOTS[def.id] = def
  SHOT_ORDER[#SHOT_ORDER + 1] = def.id
end

local B = nil             -- pilot's eye point (head pose captured in the 3D cockpit)
local BASE_FOV = 60       -- the lens the exterior framings are designed for

local function seat_side()
  if not B then return 0 end
  if B[1] < -0.12 then return -1 elseif B[1] > 0.12 then return 1 end
  return 0
end

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

local function pass_done(st)
  if st.t < st.t_pass + 2 then return false end
  local x, _, z = to_local(st.lat, st.lon, st.alt)
  local dx, dz = A.x - x, A.z - z
  return dx * A.vx + dz * A.vz > 0 and dx * dx + dz * dz > (12 * A.R) ^ 2
end

-- Rigidly mounted on the airframe: position and view direction in body axes,
-- in units of the aircraft size.
local function mount(o, bx, by, bz, fx, fy, fz)
  local R = A.R
  local wx, wy, wz = body_to_world(bx * R, by * R, bz * R, A.psi, A.the, A.phi)
  o.x, o.y, o.z = A.x + wx, A.y + wy, A.z + wz
  local dx, dy, dz = body_to_world(fx, fy, fz, A.psi, A.the, A.phi)
  local ux, uy, uz = body_to_world(0, 1, 0, A.psi, A.the, A.phi)
  o.hdg, o.pit, o.rol = orient(dx, dy, dz, ux, uy, uz)
  o.zoom = 1
end

local function airborne() return not A.on_ground and A.agl > 15 end

-- Exterior -------------------------------------------------------------------

shot {
  id = "chase", name = "Chase", kind = "ext", rel = true, shake = 0.35, aim = 6,
  weights = { taxi = 3, runway = 3, departure = 3, cruise = 2, approach = 3, low = 2 },
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
  id = "orbit", name = "Orbit", kind = "ext", rel = true, shake = 0.2, len = 1.3,
  weights = { taxi = 2, cruise = 3, low = 1 },
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
  id = "flyby", name = "Flyby", kind = "ext", shake = 0.6, aim = 7,
  weights = { runway = 2, departure = 3, cruise = 2, approach = 3, low = 3 },
  init = function(st)
    plan_pass(st, rnd(4, 6), 1.4, 2.4, false, rnd(-0.3, 0.5))
    st.max_zoom = min(S.max_zoom, 4)
  end,
  duration = function(st) return clamp(st.t_pass + 4, 6, 25) end,
  place = function(st, o, dt) fixed_place(st, o, dt, 0.45, 2 / 7) end,
  done = pass_done,
}

shot {
  id = "spotter", name = "Spotter", kind = "ext", shake = 1.0, aim = 5,
  weights = { taxi = 1, runway = 5, departure = 2, approach = 4, low = 1 },
  available = function()
    if PH.cur == "departure" then return A.agl < 200 end
    if PH.cur == "approach" or PH.cur == "low" then return A.agl < 350 end
    return true
  end,
  init = function(st)
    plan_pass(st, rnd(6, 8), 3.5, 6.5, true, 0)
    st.max_zoom = S.max_zoom
  end,
  duration = function(st) return clamp(st.t_pass + 5, 7, 30) end,
  place = function(st, o, dt) fixed_place(st, o, dt, 0.35, 2 / 5) end,
  done = pass_done,
}

shot {
  id = "a2a", name = "Air-to-air", kind = "ext", rel = true, shake = 0.5, aim = 4, len = 1.2,
  weights = { departure = 2, cruise = 4, approach = 1, low = 2 },
  available = airborne,
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
  id = "sweep", name = "Crane sweep", kind = "ext", rel = true, shake = 0.25, aim = 5, len = 1.3,
  weights = { taxi = 1, departure = 1, cruise = 3, low = 1 },
  init = function(st)
    st.path = SWEEPS[random(#SWEEPS)]
    st.side = sign_rnd()
    st.h, st.hv = track_or_heading(), 0
  end,
  place = function(st, o, dt)
    st.h, st.hv = spring_angle(st.h, st.hv, track_or_heading(), 1.4, 1, dt)
    local T = max(st.T or 14, 4)
    local u = (st.t / T) % 2
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
  id = "tail", name = "Tail cam", kind = "ext", rel = true, vib = 1,
  weights = { taxi = 1, runway = 2, departure = 2, cruise = 2, approach = 2, low = 1 },
  init = function() end,
  place = function(st, o) mount(o, 0, 0.45, 1.10, 0, -0.07, -1) end,
}

shot {
  id = "wing", name = "Wing cam", kind = "ext", rel = true, vib = 1,
  weights = { taxi = 1, runway = 2, departure = 2, cruise = 2, approach = 1, low = 1 },
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 1.05, 0.30, 0.15, -st.side * 1.05, -0.30, -1.05) end,
}

shot {
  id = "nose", name = "Nose cam", kind = "ext", rel = true, vib = 1,
  weights = { departure = 1, cruise = 2, low = 1 },
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 0.18, 0.12, -1.45, -st.side * 0.18, -0.04, 0.65) end,
}

shot {
  id = "top", name = "Top cam", kind = "ext", rel = true, vib = 1,
  weights = { departure = 1, cruise = 1 },
  init = function() end,
  place = function(st, o) mount(o, 0, 0.34, -0.55, 0, -0.19, 1.65) end,
}

shot {
  id = "gear", name = "Gear cam", kind = "ext", rel = true, vib = 1.5, ground_margin = 0.35,
  weights = { taxi = 2, runway = 2, approach = 2 },
  available = function() return A.on_ground or A.agl < 300 end,
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 0.12, -0.20, 0.55, -st.side * 0.12, -0.08, -1.95) end,
}

-- Cockpit --------------------------------------------------------------------

local GLANCES = { { 0, 0, 4 }, { -35, -3, 1 }, { 35, -3, 1 }, { "side", -6, 1 }, { 0, -22, 1 }, { "other", -2, 1 } }

shot {
  id = "pilot", name = "Pilot's eye", kind = "int",
  weights = { taxi = 3, runway = 3, departure = 2, cruise = 2, approach = 3, low = 2 },
  init = function(st)
    st.gh, st.ghv, st.gp, st.gpv = 0, 0, 0, 0
    st.th, st.tp, st.next, st.last = 0, 0, rnd(2.5, 4.5), 1
  end,
  head = function(st, o, dt)
    if st.t >= st.next then
      local side = (seat_side() ~= 0) and seat_side() or -1
      local total = 0
      for i, gl in ipairs(GLANCES) do if i ~= st.last then total = total + gl[3] end end
      local pick, acc = random() * total, 0
      for i, gl in ipairs(GLANCES) do
        if i ~= st.last then
          acc = acc + gl[3]
          if pick <= acc then
            local h = gl[1]
            if h == "side" then h = side * 72 elseif h == "other" then h = -side * 48 end
            st.th, st.tp, st.last = h, gl[2], i
            break
          end
        end
      end
      st.next = st.t + rnd(3.5, 7.5)
    end
    st.gh, st.ghv = spring(st.gh, st.ghv, st.th, 2.4, 1, dt)
    st.gp, st.gpv = spring(st.gp, st.gpv, st.tp, 2.4, 1, dt)
    o.x = B[1] + sin(rad(st.gh)) * 0.05
    o.y = B[2] + 0.005 * wob(st.t * 0.25, 2)
    o.z = B[3] - abs(sin(rad(st.gh))) * 0.03
    o.psi, o.the, o.phi = B[4] + st.gh, B[5] + st.gp, B[6]
  end,
}

shot {
  id = "shoulder", name = "Over the shoulder", kind = "int",
  weights = { taxi = 2, runway = 2, departure = 1, cruise = 2, approach = 2, low = 1 },
  init = function() end,
  head = function(st, o)
    local seat = seat_side()
    local s = smoother(st.t / max(st.T or 12, 4))
    local single = (seat == 0)
    o.x = B[1] - seat * 0.30 + 0.015 * wob(st.t * 0.3, 1)
    o.y = B[2] + (single and 0.14 or 0.10) + 0.01 * wob(st.t * 0.21, 2)
    o.z = B[3] + lerp(0.68, 0.52, s) * (single and 0.55 or 1)
    o.psi = B[4] + seat * 7 + 2 * wob(st.t * 0.12, 3)
    o.the = B[5] - 8 + 1.5 * wob(st.t * 0.1, 4)
    o.phi = B[6]
  end,
}

shot {
  id = "panel", name = "Panel sweep", kind = "int",
  weights = { taxi = 1, cruise = 1 },
  init = function(st) st.dir = sign_rnd() end,
  head = function(st, o)
    local s = smoother(st.t / max(st.T or 12, 4))
    o.x, o.y, o.z = B[1], B[2] - 0.03, B[3] - 0.10 * s
    o.psi = B[4] + st.dir * lerp(-32, 32, s)
    o.the = B[5] + lerp(-24, -17, s)
    o.phi = B[6]
  end,
}

shot {
  id = "side", name = "Side window", kind = "int",
  weights = { taxi = 1, departure = 1, cruise = 2, low = 1 },
  init = function() end,
  head = function(st, o)
    local side = (seat_side() ~= 0) and seat_side() or -1
    o.x, o.y, o.z = B[1] + side * 0.08, B[2], B[3] + 0.03
    o.psi = B[4] + side * (76 + 8 * sin(st.t * 0.12))
    o.the = B[5] - 7 + 3 * sin(st.t * 0.09 + 1)
    o.phi = B[6]
  end,
}

shot {
  id = "fo", name = "First officer", kind = "int",
  weights = { taxi = 1, cruise = 1, approach = 1 },
  available = function() return seat_side() ~= 0 end,
  init = function() end,
  head = function(st, o)
    local seat = seat_side()
    o.x, o.y, o.z = -B[1], B[2], B[3]
    o.psi = B[4] + seat * 38 + 4 * wob(st.t * 0.1, 5)
    o.the = B[5] - 9 + wob(st.t * 0.13, 6)
    o.phi = B[6]
  end,
}

shot {
  id = "cabin", name = "Cabin window", kind = "int",
  weights = { departure = 1, cruise = 1, approach = 1 },
  available = function() return S.use_cabin and A.R >= 11 end,
  init = function() end,
  head = function(st, o)
    local side = (seat_side() ~= 0) and seat_side() or -1
    local half_width = 0.09 * A.R + 0.25
    o.x, o.y, o.z = side * half_width * 0.78, B[2] - 0.25, 0.12 * A.R
    o.psi = side * (100 + 6 * sin(st.t * 0.1))
    o.the = -9 + 2 * sin(st.t * 0.07)
    o.phi = 0
  end,
}

-- -----------------------------------------------------------------------------
-- Session state
-- -----------------------------------------------------------------------------

local cine = {
  active = false, director = false, hold = false,
  def = nil, st = nil,                  -- current shot
  prev_def = nil, prev_st = nil,        -- exterior shot being blended from
  blend = 1, blend_len = 0, blend_check = false,
  int_from = nil,                       -- cockpit pose being blended from
  shot_time = 0, shot_len = 12,
  ext_on = false, expect_release = false, override = false,
  waiting = nil, wait = 0,              -- "ext" / "int" while a view change is under way
  origin_internal = true,
  history = {},
  title = "", title_t = 0,
  fov_saved = nil,
  restore_frames = 0,
  head_moved = false,                   -- a cockpit shot has moved the pilot's head
  last_head = nil,                      -- last cockpit pose written by a shot
  message = nil,
}

local nudge = { yaw = 0, up = 0, zoom = 1 }
local function reset_nudge() nudge.yaw, nudge.up, nudge.zoom = 0, 0, 1 end

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

local function show_title(text)
  cine.title, cine.title_t = text, 4
end

-- -----------------------------------------------------------------------------
-- Exterior camera: X-Plane calls this every frame while we have the camera.
-- It reads the aircraft pose itself so the camera never lags the drawn aircraft.
-- -----------------------------------------------------------------------------

local work_a, work_b = {}, {}

local function run_exterior(def, st, o, dt)
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

local function camera_update(pos, losing)
  if losing ~= 0 then
    cine.ext_on = false
    if not cine.expect_release then cine.override = true end
    cine.expect_release = false
    return 0
  end
  if not (cine.active and cine.def and cine.def.kind == "ext") then return 0 end

  local t, dt = sim_dt(cam_clock.last)
  cam_clock.last = t
  -- If FlyWithLua has stopped running this script (another script's error,
  -- say), hand the camera back rather than keep a callback X-Plane might call
  -- after the Lua state is gone.
  if clock.last and t - clock.last > 2 then
    cine.ext_on, cine.override = false, true
    return 0
  end
  read_pose()

  local st = cine.st
  st.t = st.t + dt
  local o = work_a
  run_exterior(cine.def, st, o, dt)

  if cine.prev_def then
    local pst = cine.prev_st
    pst.t = pst.t + dt
    local b = work_b
    run_exterior(cine.prev_def, pst, b, dt)
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
-- Cockpit shots, run from the per-frame tick
-- -----------------------------------------------------------------------------

local head_out = {}

local function run_cockpit(dt)
  local def, st, o = cine.def, cine.st, head_out
  st.t = st.t + dt
  def.head(st, o, dt)
  local x, y, z, psi, the, phi = o.x, o.y, o.z, o.psi, o.the, o.phi

  if cine.int_from then
    cine.blend = cine.blend + dt / max(cine.blend_len, 0.05)
    if cine.blend >= 1 then
      cine.int_from = nil
    else
      local f, s = cine.int_from, smoother(cine.blend)
      x, y, z = lerp(f[1], x, s), lerp(f[2], y, s), lerp(f[3], z, s)
      psi = f[4] + wrap180(psi - f[4]) * s
      the, phi = lerp(f[5], the, s), lerp(f[6], phi, s)
    end
  end

  psi, the = psi + nudge.yaw, the + nudge.up * 10
  z = z - (nudge.zoom - 1) * 0.25
  cine.last_head = { x, y, z, psi, the, phi }
  cine.head_moved = true

  if S.living then
    local h = HP.out
    x, y, z, psi, the, phi = x + h[1], y + h[2], z + h[3], psi + h[4], the + h[5], phi + h[6]
  end
  -- A little breathing so a held cockpit shot never looks frozen.
  local b = S.shake * 0.25
  psi = psi + b * wob(st.t * 0.5, 21)
  the = the + b * 0.7 * wob(st.t * 0.6, 22)
  write_head(x, y, z, psi, the, phi)
end

local function capture_eye_point()
  B = head_without_offset()
  LV.on = false
end

local function set_cockpit_fov(on)
  if not FOV_WRITABLE then return end
  if on and S.cockpit_fov >= 20 then
    if not cine.fov_saved then cine.fov_saved = getf(REF.fov) end
    setf(REF.fov, S.cockpit_fov)
  elseif cine.fov_saved then
    setf(REF.fov, cine.fov_saved)
    cine.fov_saved = nil
  end
end

-- -----------------------------------------------------------------------------
-- Switching shots
-- -----------------------------------------------------------------------------

local function shot_available(def)
  if def.kind == "int" and (vr_on() or not CMD.cockpit) then return false end
  if def.kind == "ext" and not CMD.external then return false end
  return not def.available or def.available()
end

local function begin_shot(id, how)
  local def = SHOTS[id]
  if not def then return end
  local prev_def, prev_st = cine.def, cine.st
  local st = { t = 0 }

  if def.kind == "ext" then
    def.init(st)
    cine.int_from = nil
    if prev_def and prev_def.kind == "ext" and cine.ext_on then
      if S.blend_time > 0.05 and how ~= "cut" and prev_def.rel and def.rel then
        cine.prev_def, cine.prev_st = prev_def, prev_st
        cine.blend, cine.blend_len, cine.blend_check = 0, S.blend_time, true
      else
        cine.prev_def, cine.prev_st, cine.blend = nil, nil, 1
      end
      cine.waiting = nil
    else
      cine.prev_def, cine.prev_st, cine.blend = nil, nil, 1
      cine.waiting, cine.wait = "ext", 0
      if geti(REF.external) == 0 then run_cmd(CMD.external) end
      if geti(REF.external) ~= 0 then
        cine.waiting = nil
        take_camera()
      end
    end
    set_cockpit_fov(false)
  else
    def.init(st)
    cine.prev_def, cine.prev_st = nil, nil
    if prev_def and prev_def.kind == "int" and cine.last_head and S.blend_time > 0.05 and how ~= "cut" then
      cine.int_from, cine.blend, cine.blend_len = cine.last_head, 0, S.blend_time
    else
      cine.int_from, cine.blend = nil, 1
    end
    if cine.ext_on then
      cine.expect_release = true
      run_cmd(CMD.cockpit)
      release_camera()
    end
    if geti(REF.view_type) ~= VIEW_3D_COCKPIT then
      cine.waiting, cine.wait = "int", 0
      run_cmd(CMD.cockpit)
    else
      cine.waiting = nil
    end
  end

  cine.def, cine.st = def, st
  cine.shot_time = 0
  cine.shot_len = def.duration and def.duration(st) or S.shot_length * def.len * rnd(0.8, 1.25)
  st.T = cine.shot_len
  reset_nudge()
  local h = cine.history
  h[#h + 1] = id
  if #h > 4 then table.remove(h, 1) end
  if def.kind == "int" then
    set_cockpit_fov(true)
    -- Already in the cockpit: place the head now, so the cut has no stray frame.
    if geti(REF.view_type) == VIEW_3D_COCKPIT then
      cine.waiting = nil
      if not B then capture_eye_point() end
      run_cockpit(0)
    end
  end
  show_title(def.name)
end

local function recently_used(id, n)
  local h = cine.history
  for i = max(1, #h - n + 1), #h do if h[i] == id then return true end end
  return false
end

local function choose_shot()
  local phase = PH.cur
  local want_int
  if S.use_cockpit and S.use_exterior then
    want_int = random() < S.cockpit_share
  else
    want_int = S.use_cockpit
  end
  -- Pick by weight, relaxing the rules step by step if nothing qualifies.
  for pass = 1, 4 do
    local pool, total = {}, 0
    for _, id in ipairs(SHOT_ORDER) do
      local def = SHOTS[id]
      local w = def.weights[phase] or 0
      if pass >= 3 and w == 0 then w = 0.5 end
      local kind_ok = (pass >= 4) or ((def.kind == "int") == want_int)
      if w > 0 and kind_ok and shot_available(def)
         and not (pass <= 2 and recently_used(id, pass == 1 and 2 or 1)) and id ~= (cine.def and cine.def.id) then
        pool[#pool + 1], total = { id, w }, total + w
      end
    end
    if total > 0 then
      local pick, acc = random() * total, 0
      for _, e in ipairs(pool) do
        acc = acc + e[2]
        if pick <= acc then return e[1] end
      end
      return pool[#pool][1]
    end
  end
  return "chase"
end

-- -----------------------------------------------------------------------------
-- Starting and stopping
-- -----------------------------------------------------------------------------

local function start_session()
  if cine.active then return true end
  if vr_on() then
    log("cinematic shots are off in VR.")
    cine.message = "Not available in VR"
    return false
  end
  if not CMD.external and not CMD.cockpit then
    log("could not find X-Plane's view commands.")
    return false
  end
  cine.active, cine.override, cine.history, cine.head_moved = true, false, {}, false
  cine.origin_internal = geti(REF.external) == 0
  cine.message = nil
  A.R = estimate_size()
  PH.cur, PH.cand, PH.changed = raw_phase(), nil, false
  if geti(REF.view_type) == VIEW_3D_COCKPIT then capture_eye_point() end
  return true
end

local function stop_session(restore_view)
  if not cine.active then return end
  local was_int = cine.def and cine.def.kind == "int"
  cine.active, cine.director, cine.hold = false, false, false
  if restore_view then
    if cine.origin_internal then
      if cine.ext_on or geti(REF.view_type) ~= VIEW_3D_COCKPIT then
        cine.expect_release = true
        run_cmd(CMD.cockpit)
      end
    elseif was_int then
      run_cmd(CMD.external)
    end
  end
  release_camera()
  cine.def, cine.st, cine.prev_def, cine.prev_st, cine.int_from = nil, nil, nil, nil, nil
  cine.waiting, cine.last_head = nil, nil
  set_cockpit_fov(false)
  if B and cine.head_moved then
    -- Put the head back now (X-Plane keeps it for when you return to the
    -- cockpit) and for a few frames in case the view change resets it.
    write_head(B[1], B[2], B[3], B[4], B[5], B[6])
    cine.restore_frames = 3
  end
  cine.head_moved = false
  LV.on = false
  reset_nudge()
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

local function director_tick()
  if not cine.director or cine.hold or cine.waiting then return end
  local def, change = cine.def, false
  if not def or cine.shot_time >= cine.shot_len then change = true end
  if def and def.done and def.done(cine.st) then change = true end
  if def and PH.changed and cine.shot_time > 3 and (def.weights[PH.cur] or 0) == 0 then change = true end
  if def and def.available and cine.shot_time > 2 and not def.available() then change = true end
  if change then begin_shot(choose_shot(), "director") end
end

local function tick()
  local t, dt = sim_dt(clock.last)
  clock.last, clock.dt = t, dt

  update_dynamics(dt)
  update_phase(dt)
  update_head_physics(dt)

  -- Commands, macros and window buttons, run here with this frame's state.
  local q = queue
  queue = {}
  for _, fn in ipairs(q) do
    local ok, err = pcall(fn)
    if not ok then log("error: " .. tostring(err)) end
  end

  if cine.override then
    cine.override = false
    if cine.active then stop_session(false) end
  end

  local in_cockpit = geti(REF.view_type) == VIEW_3D_COCKPIT
  if cine.active and vr_on() then stop_session(false) end

  if cine.active and cine.def then
    local def = cine.def
    cine.shot_time = cine.shot_time + dt
    if def.kind == "ext" then
      if cine.waiting == "ext" then
        if geti(REF.external) ~= 0 then
          cine.waiting = nil
          take_camera()
        else
          cine.wait = cine.wait + 1
          if cine.wait % 30 == 0 then run_cmd(CMD.external) end
          if cine.wait > 150 then
            log("could not switch to an exterior view.")
            stop_session(true)
          end
        end
      elseif not cine.ext_on and not cine.override then
        take_camera()
      end
    else
      if in_cockpit then
        if cine.waiting == "int" or not B then
          cine.waiting = nil
          if not B then capture_eye_point() end
        end
        run_cockpit(dt)
      elseif cine.waiting == "int" then
        cine.wait = cine.wait + 1
        if cine.wait % 30 == 0 then run_cmd(CMD.cockpit) end
        if cine.wait > 150 then
          log("could not switch to the 3D cockpit.")
          stop_session(true)
        end
      else
        -- You changed the view yourself: hand the camera back.
        stop_session(false)
      end
    end
    if cine.active then director_tick() end
    if PH.changed then PH.changed = false end
    if cine.active and not cine.director and def.done and def.done(cine.st) then
      begin_shot(def.id, "cut")          -- manual flyby/spotter: set up the next pass
    end
  else
    PH.changed = false
    if cine.restore_frames > 0 then
      cine.restore_frames = cine.restore_frames - 1
      if B and in_cockpit then write_head(B[1], B[2], B[3], B[4], B[5], B[6]) end
    else
      living_tick(S.living and in_cockpit and not vr_on())
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
    local mode = cine.director and (cine.hold and "DIRECTOR - HOLD" or "DIRECTOR") or "MANUAL"
    draw_string(W - 30 - #mode * 8, y, mode, "white")
  end
end

-- -----------------------------------------------------------------------------
-- Public actions (commands, macros and the window all go through these)
-- -----------------------------------------------------------------------------

local function act_director()
  if cine.active and cine.director then
    stop_session(true)
  elseif start_session() then
    cine.director, cine.hold = true, false
    begin_shot(choose_shot(), "cut")
  end
end

local function act_shot(id)
  if not SHOTS[id] then return end
  if not cine.active and not start_session() then return end
  cine.director = false
  begin_shot(id, "manual")
end

local function act_step(step)
  if cine.active and cine.director then
    begin_shot(choose_shot(), "director")
    return
  end
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
  if cine.active then stop_session(true) else act_director() end
end

local M = {}
M.version = VERSION
M.toggle = function() request(act_toggle) end
M.toggle_director = function() request(act_director) end
M.stop = function() request(function() stop_session(true) end) end
M.next_shot = function() request(function() act_step(1) end) end
M.previous_shot = function() request(function() act_step(-1) end) end
M.shot = function(id) request(function() act_shot(id) end) end
M.toggle_hold = function() if cine.director then cine.hold = not cine.hold end end
M.toggle_living = function() S.living = not S.living settings_dirty = true end
M.toggle_letterbox = function() S.letterbox = not S.letterbox settings_dirty = true end

M.nudge = function(kind, dir)
  local dt = clock.dt
  if kind == "yaw" then
    nudge.yaw = wrap180(nudge.yaw + dir * 40 * dt)
  elseif kind == "up" then
    nudge.up = clamp(nudge.up + dir * 0.6 * dt, -2, 3)
  elseif kind == "zoom" then
    nudge.zoom = clamp(nudge.zoom * exp(dir * 0.8 * dt), 0.4, 10)
  end
end
M.reset_nudge = reset_nudge

-- Settings window -------------------------------------------------------------

local wnd = nil

local COL_ACTIVE = 0xFFD08A2A    -- imgui colours are 0xAABBGGRR
local COL_MUTED = 0xFF9A9A9A

local function shot_buttons(kind)
  local col = 0
  for _, id in ipairs(SHOT_ORDER) do
    local def = SHOTS[id]
    if def.kind == kind then
      if col > 0 then imgui.SameLine() end
      local current = cine.active and cine.def == def
      if current then imgui.PushStyleColor(imgui.constant.Col.Button, COL_ACTIVE) end
      if not shot_available(def) then imgui.PushStyleColor(imgui.constant.Col.Text, COL_MUTED) end
      if imgui.Button(def.name .. "##" .. id, 112, 26) then M.shot(id) end
      if not shot_available(def) then imgui.PopStyleColor() end
      if current then imgui.PopStyleColor() end
      col = (col + 1) % 4
    end
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
    local left = max(0, cine.shot_len - cine.shot_time)
    local mode = cine.director and (cine.hold and "Director (holding)" or ("Director - next cut in " .. math.floor(left + 0.5) .. " s")) or "Manual"
    imgui.TextUnformatted(cine.def.name .. "   |   " .. mode .. "   |   " .. PHASE_NAMES[PH.cur])
  else
    imgui.TextUnformatted((cine.message or "Camera is yours") .. "   |   " .. PHASE_NAMES[PH.cur])
  end

  local on = cine.active and cine.director
  if on then imgui.PushStyleColor(imgui.constant.Col.Button, COL_ACTIVE) end
  if imgui.Button(on and "Director ON" or "Start Director", 130, 30) then M.toggle_director() end
  if on then imgui.PopStyleColor() end
  imgui.SameLine()
  if imgui.Button(cine.hold and "Resume" or "Hold shot", 90, 30) then M.toggle_hold() end
  imgui.SameLine()
  if imgui.Button("<##prev", 34, 30) then M.previous_shot() end
  imgui.SameLine()
  if imgui.Button(">##next", 34, 30) then M.next_shot() end
  imgui.SameLine()
  if imgui.Button("Stop", 70, 30) then M.stop() end

  imgui.Separator()
  imgui.TextUnformatted("Exterior")
  shot_buttons("ext")
  imgui.TextUnformatted("Cockpit")
  shot_buttons("int")
  imgui.Separator()

  if imgui.TreeNode("Director") then
    slider("Shot length (s)", "shot_length", 5, 40, "%.0f")
    checkbox("Exterior shots", "use_exterior")
    imgui.SameLine()
    checkbox("Cockpit shots", "use_cockpit")
    slider("Cockpit share", "cockpit_share", 0, 1, "%.2f")
    checkbox("Cabin window shots (aircraft with a modelled cabin)", "use_cabin")
    slider("Glide between shots (s, 0 = cut)", "blend_time", 0, 5, "%.1f")
    imgui.TreePop()
  end

  if imgui.TreeNode("Exterior camera") then
    slider("Distance", "distance", 0.5, 3, "%.2fx")
    slider("Orbit speed (deg/s)", "orbit_speed", 1, 20, "%.0f")
    slider("Handheld shake", "shake", 0, 1, "%.2f")
    slider("Telephoto limit", "max_zoom", 2, 15, "%.0fx")
    if slider("Aircraft size", "size_scale", 0.4, 2.5, "%.2fx") then A.R = estimate_size() end
    muted(("   estimated size %.0f m (about half the span or length)"):format(A.R))
    checkbox("Frame shots for a 60 deg lens whatever the sim FOV", "normalize_lens")
    imgui.TextUnformatted("Adjust the live shot:")
    if imgui.Button("Orbit <", 70, 24) then nudge.yaw = wrap180(nudge.yaw - 15) end
    imgui.SameLine()
    if imgui.Button("Orbit >", 70, 24) then nudge.yaw = wrap180(nudge.yaw + 15) end
    imgui.SameLine()
    if imgui.Button("Up", 44, 24) then nudge.up = clamp(nudge.up + 0.25, -2, 3) end
    imgui.SameLine()
    if imgui.Button("Down", 50, 24) then nudge.up = clamp(nudge.up - 0.25, -2, 3) end
    imgui.SameLine()
    if imgui.Button("Zoom +", 62, 24) then nudge.zoom = clamp(nudge.zoom * 1.25, 0.4, 10) end
    imgui.SameLine()
    if imgui.Button("Zoom -", 62, 24) then nudge.zoom = clamp(nudge.zoom / 1.25, 0.4, 10) end
    if imgui.Button("Reset adjustments", 150, 24) then reset_nudge() end
    imgui.TreePop()
  end

  if imgui.TreeNode("Cockpit") then
    checkbox("Living cockpit (G-forces, turbulence, touchdown, rumble)", "living")
    slider("Strength", "living_amount", 0, 2, "%.2f")
    checkbox("Look into turns", "look_into_turns")
    imgui.SameLine()
    checkbox("Lean toward the horizon", "horizon_lean")
    if FOV_WRITABLE then slider("Cockpit shot FOV (0 = leave)", "cockpit_fov", 0, 100, "%.0f") end
    if imgui.Button("Use my current head position as the pilot's eye", 340, 24) then
      request(function() if geti(REF.view_type) == VIEW_3D_COCKPIT and not cine.active then capture_eye_point() end end)
    end
    muted(B and ("   pilot's eye at x %.2f  y %.2f  z %.2f m"):format(B[1], B[2], B[3]) or "   captured the first time the cockpit is used")
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

  if vr_on() then muted("VR is on: cinematic shots and the living cockpit are paused.") end
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
  wnd = float_wnd_create(520, 640, 1, true)
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
  if not cine.active then A.R = estimate_size() end
  if settings_dirty then save_settings() end
end

local shut = false
M.shutdown = function()
  if shut then return end
  shut = true
  pcall(stop_session, false)
  pcall(release_camera)
  pcall(XPLM.cv_DontControlCamera)
  if cine.fov_saved then pcall(set_cockpit_fov, false) end
  if LV.on then pcall(living_tick, false) end
  if probe then pcall(XPLM.cv_DestroyProbe, probe) probe = nil end
  if wnd and float_wnd_destroy then pcall(float_wnd_destroy, wnd) wnd = nil end
  if settings_dirty then pcall(save_settings) end
  pcall(function() camera_cb:free() end)
end

A.R = estimate_size()

-- For testing and for other scripts.
M._state = function() return cine, A, S, PH, B, HP end
M._shots = function() return SHOTS, SHOT_ORDER end

CinematicViews = M

-- -----------------------------------------------------------------------------
-- Registration with FlyWithLua
-- -----------------------------------------------------------------------------

do_every_frame("CinematicViews._frame()")
do_every_draw("CinematicViews._draw()")
do_often("CinematicViews._often()")
do_on_exit("CinematicViews.shutdown()")

local P = "FlyWithLua/cinematic_views/"
local function command(name, desc, code)
  create_command(P .. name, "Cinematic Views: " .. desc, code, "", "")
end
local function hold_command(name, desc, code)
  create_command(P .. name, "Cinematic Views: " .. desc, "", code, "")
end

command("toggle", "start the Director, or stop and hand the camera back", "CinematicViews.toggle()")
command("director", "start/stop the Director (automatic shots)", "CinematicViews.toggle_director()")
command("stop", "stop and return to your view", "CinematicViews.stop()")
command("next_shot", "next shot", "CinematicViews.next_shot()")
command("previous_shot", "previous shot", "CinematicViews.previous_shot()")
command("hold_shot", "Director: hold the current shot / resume", "CinematicViews.toggle_hold()")
command("toggle_living_cockpit", "living cockpit on/off", "CinematicViews.toggle_living()")
command("toggle_letterbox", "letterbox bars on/off", "CinematicViews.toggle_letterbox()")
command("toggle_window", "settings window", "CinematicViews.toggle_window()")
command("reset_adjustments", "reset orbit, height and zoom adjustments", "CinematicViews.reset_nudge()")
hold_command("orbit_left", "move the camera around the aircraft to the left (hold)", "CinematicViews.nudge('yaw', -1)")
hold_command("orbit_right", "move the camera around the aircraft to the right (hold)", "CinematicViews.nudge('yaw', 1)")
hold_command("camera_up", "raise the camera (hold)", "CinematicViews.nudge('up', 1)")
hold_command("camera_down", "lower the camera (hold)", "CinematicViews.nudge('up', -1)")
hold_command("zoom_in", "zoom in (hold)", "CinematicViews.nudge('zoom', 1)")
hold_command("zoom_out", "zoom out (hold)", "CinematicViews.nudge('zoom', -1)")
for _, id in ipairs(SHOT_ORDER) do
  command("shot_" .. id, SHOTS[id].name .. " shot", "CinematicViews.shot('" .. id .. "')")
end

if add_macro then
  add_macro("Cinematic Views: Director on/off", "CinematicViews.toggle_director()")
  add_macro("Cinematic Views: settings window", "CinematicViews.toggle_window()")
  add_macro("Cinematic Views: living cockpit on/off", "CinematicViews.toggle_living()")
end

if not CMD.external then log("no exterior view command found - exterior shots are off.") end
if not CMD.cockpit then log("no 3D cockpit view command found - cockpit shots are off.") end
log("v" .. VERSION .. " ready - Plugins > FlyWithLua > Macros, or the FlyWithLua/cinematic_views/ commands.")
