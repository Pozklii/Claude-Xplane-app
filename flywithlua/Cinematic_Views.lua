-- =============================================================================
--  Cinematic Views for X-Plane 12                                        v3.0.0
--  A FlyWithLua NG+ script: an automatic cinematic camera for screenshots
--  and videos, outside and inside the aircraft.
--
--  * 11 exterior shots through X-Plane's camera API: chase, orbit, flyby,
--    runway spotter (telephoto with zoom tracking), air-to-air photo ship,
--    crane sweep, and tail, wing, nose, top and gear cams rigidly mounted
--    on the airframe.
--  * 5 cockpit shots: pilot's eye, panel sweep, side window, cockpit pan and
--    first officer. They look around rather than move around: the head stays
--    within a few centimetres of the seat, so the view never leaves the
--    cockpit or clips through the aircraft.
--  * Cameras fit the aircraft: they read its span and length (or estimate
--    them from its weight), and remember a size correction per aircraft.
--  * Zoom: + and - (and the mouse wheel) zoom the exterior camera; in the
--    cockpit, and when you are not filming, they are X-Plane's own as usual.
--  * One settings window with everything in it, including a key or joystick
--    button of your choice for camera on/off, next view and previous view.
--
--  Install: copy this file to  X-Plane 12/Resources/plugins/FlyWithLua/Scripts/
--  Use:     Plugins > FlyWithLua > FlyWithLua Macros > Cinematic Views ...
--
--  Requires FlyWithLua NG+ (LuaJIT with FFI). Settings are saved next to this
--  file in Cinematic_Views.ini.
-- =============================================================================

local VERSION = "3.0.0"
local TAG = "Cinematic Views: "

local function log(msg)
  if logMsg then logMsg(TAG .. msg) else print(TAG .. msg) end
end

-- A second copy of the script, or a reload into the same Lua state, must not
-- leave the earlier copy's callbacks registered with X-Plane.
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
  "typedef int (*cv_CommandCallback_f)(void *cmd, int phase, void *refcon);",
  "typedef struct { int structSize; float locationX, locationY, locationZ, normalX, normalY, normalZ, velocityX, velocityY, velocityZ; int is_wet; } cv_ProbeInfo_t;",
  'void *cv_FindDataRef(const char *name) __asm__("XPLMFindDataRef");',
  'int cv_GetDatai(void *ref) __asm__("XPLMGetDatai");',
  'float cv_GetDataf(void *ref) __asm__("XPLMGetDataf");',
  'double cv_GetDatad(void *ref) __asm__("XPLMGetDatad");',
  'void cv_SetDataf(void *ref, float value) __asm__("XPLMSetDataf");',
  'int cv_GetDatavi(void *ref, int *values, int offset, int max) __asm__("XPLMGetDatavi");',
  'void *cv_FindCommand(const char *name) __asm__("XPLMFindCommand");',
  'void cv_CommandOnce(void *cmd) __asm__("XPLMCommandOnce");',
  'void cv_RegisterCommandHandler(void *cmd, cv_CommandCallback_f handler, int before, void *refcon) __asm__("XPLMRegisterCommandHandler");',
  'void cv_UnregisterCommandHandler(void *cmd, cv_CommandCallback_f handler, int before, void *refcon) __asm__("XPLMUnregisterCommandHandler");',
  'void cv_ControlCamera(int howLong, cv_CameraControl_f func, void *refcon) __asm__("XPLMControlCamera");',
  'void cv_DontControlCamera(void) __asm__("XPLMDontControlCamera");',
  'void *cv_CreateProbe(int type) __asm__("XPLMCreateProbe");',
  'void cv_DestroyProbe(void *probe) __asm__("XPLMDestroyProbe");',
  'int cv_ProbeTerrainXYZ(void *probe, float x, float y, float z, cv_ProbeInfo_t *info) __asm__("XPLMProbeTerrainXYZ");',
  'void cv_WorldToLocal(double lat, double lon, double alt, double *x, double *y, double *z) __asm__("XPLMWorldToLocal");',
  'void cv_LocalToWorld(double x, double y, double z, double *lat, double *lon, double *alt) __asm__("XPLMLocalToWorld");',
  'void cv_GetNthAircraftModel(int index, char *fileName, char *path) __asm__("XPLMGetNthAircraftModel");',
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
  size_x = "sim/aircraft/view/acf_size_x",
  size_z = "sim/aircraft/view/acf_size_z",
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
  joy = "sim/joystick/joystick_button_values",
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

local HAS_HEAD = REF.view_type and REF.head_x and REF.head_y and REF.head_z and REF.head_psi and REF.head_the

local function getf(r) if r then return XPLM.cv_GetDataf(r) end return 0 end
local function getd(r) if r then return XPLM.cv_GetDatad(r) end return 0 end
local function geti(r) if r then return XPLM.cv_GetDatai(r) end return 0 end
local function setf(r, v) if r then XPLM.cv_SetDataf(r, v) end end

local function find_cmd(...)
  for i = 1, select("#", ...) do
    local c = XPLM.cv_FindCommand((select(i, ...)))
    if c ~= nil then return c end
  end
  return nil
end

local CMD = {
  external = find_cmd("sim/view/chase", "sim/view/circle", "sim/view/free_camera"),
  cockpit = find_cmd("sim/view/3d_cockpit_cmnd_look", "sim/view/default_view"),
  zoom_in = find_cmd("sim/general/zoom_in"),
  zoom_out = find_cmd("sim/general/zoom_out"),
}

-- X-Plane's own zoom commands (= and - by default, Shift for fast). During an
-- exterior shot they zoom its camera; otherwise they are left to X-Plane.
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

local VIEW_3D_COCKPIT = 1026

-- -----------------------------------------------------------------------------
-- Settings
-- -----------------------------------------------------------------------------

local DEFAULTS = {
  blend_time = 2.5,       -- glide between related shots (0 = always cut)
  distance = 1.0,         -- exterior camera distance multiplier
  orbit_speed = 5,        -- degrees per second
  shake = 0.5,            -- handheld camera shake, 0..1
  max_zoom = 8,           -- telephoto limit for flyby and spotter shots
  normalize_lens = true,  -- frame exterior shots as if the sim FOV were 60 degrees
  head_motion = 0.5,      -- how much the head moves in cockpit shots, 0..1
  cockpit_in_cycle = true,-- Next/Previous include the cockpit shots
  letterbox = true,
  aspect = 2.39,
  titles = true,
}

local RANGES = {
  blend_time = { 0, 5 }, distance = { 0.5, 3 }, orbit_speed = { 1, 20 }, shake = { 0, 1 },
  max_zoom = { 2, 15 }, head_motion = { 0, 1 }, aspect = { 1.6, 2.8 },
}

local S = {}
for k, v in pairs(DEFAULTS) do S[k] = v end

local SETTINGS_FILE = (type(SCRIPT_DIRECTORY) == "string" and SCRIPT_DIRECTORY or "") .. "Cinematic_Views.ini"
local settings_dirty = false

-- Size corrections you set, per aircraft (keyed by its .acf file name).
local SIZE = { key = "default", scales = {} }

-- Your key or joystick button for each action: { kind = "key", vk, shift,
-- ctrl, alt } or { kind = "joy", n }.
local BIND = {}

local function parse_binding(v)
  local vk, sh, ct, al = v:match("^key:(%d+):(%d):(%d):(%d)$")
  if vk then return { kind = "key", vk = tonumber(vk), shift = sh == "1", ctrl = ct == "1", alt = al == "1" } end
  local n = v:match("^joy:(%d+)$")
  if n then return { kind = "joy", n = tonumber(n) } end
  return nil
end

local function format_binding(b)
  if b.kind == "key" then
    return ("key:%d:%d:%d:%d"):format(b.vk, b.shift and 1 or 0, b.ctrl and 1 or 0, b.alt and 1 or 0)
  end
  return ("joy:%d"):format(b.n)
end

local function load_settings()
  local f = io.open(SETTINGS_FILE, "r")
  if not f then return end
  for line in f:lines() do
    local acf, sv = line:match("^%s*size%.([%w_%-]+)%s*=%s*(.-)%s*$")
    local n = tonumber(sv)
    if acf and n then SIZE.scales[acf] = math.max(0.4, math.min(2.5, n)) end
    local action, bv = line:match("^%s*bind%.(%a+)%s*=%s*(.-)%s*$")
    if action then BIND[action] = parse_binding(bv) end
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    local d = k and DEFAULTS[k]
    if type(d) == "boolean" then
      S[k] = (v == "true")
    elseif type(d) == "number" then
      local num = tonumber(v)
      if num then
        local r = RANGES[k]
        if r then num = math.max(r[1], math.min(r[2], num)) end
        S[k] = num
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
  for _, a in ipairs({ "toggle", "next", "prev" }) do
    if BIND[a] then f:write("bind.", a, " = ", format_binding(BIND[a]), "\n") end
  end
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
  Rs = 10, Rl = 10,                  -- half the span and half the length (m)
  R = 10,                            -- the larger of the two: how far cameras need to stand off
  size_source = "weight",
  have_pos = false, have_v = false,
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

-- -----------------------------------------------------------------------------
-- Head motion for cockpit shots: a little give from G-forces, turbulence,
-- touchdowns and runway rumble, looking into turns. Kept small; the safe
-- space around the seat (below) has the final say.
-- -----------------------------------------------------------------------------

local HP = {
  x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0,
  pit = 0, pv = 0, rol = 0, rv = 0, yaw = 0, yv = 0,
  was_ground = true, last_vs = 0, rumble = 0,
  nx = 0, ny = 0, np = 0, nr = 0, n_t = 0,
  out = { 0, 0, 0, 0, 0, 0 },                          -- dx, dy, dz, dpsi, dthe, dphi
}

local function update_head_motion(dt)
  local o = HP.out
  if dt <= 0 then return end
  local amt, g = S.head_motion, 9.81

  local fx, fy, fz = world_to_body(A.ax, A.ay + g, A.az, A.psi, A.the, A.phi)
  fy = fy - g
  local K = 0.003 * amt
  HP.x, HP.vx = spring(HP.x, HP.vx, clamp(-K * fx, -0.04, 0.04), 8, 0.6, dt)
  HP.y, HP.vy = spring(HP.y, HP.vy, clamp(-K * fy, -0.04, 0.03), 8, 0.55, dt)
  HP.z, HP.vz = spring(HP.z, HP.vz, clamp(-K * fz, -0.04, 0.05), 7, 0.6, dt)

  if A.on_ground and not HP.was_ground and HP.last_vs < -0.3 then
    local sink = clamp(-HP.last_vs, 0, 6)
    HP.vy = HP.vy - sink * 0.06 * amt
    HP.pv = HP.pv - sink * 6 * amt
  end
  HP.was_ground, HP.last_vs = A.on_ground, A.vs

  local tp = clamp((-0.8 * fy / g - 1.2 * fz / g) * amt, -4, 4)
  local tr = clamp(-1.6 * fx / g * amt, -4, 4)
  local ty = 0
  if not (A.on_ground and A.gs < 1) then ty = clamp(A.yaw_rate * 1.8, -12, 12) * amt end
  if not A.on_ground then tr = tr + clamp(-0.18 * A.phi, -6, 6) * amt end
  HP.pit, HP.pv = spring(HP.pit, HP.pv, tp, 6, 0.6, dt)
  HP.rol, HP.rv = spring(HP.rol, HP.rv, tr, 3, 0.9, dt)
  HP.yaw, HP.yv = spring(HP.yaw, HP.yv, ty, 2.2, 1, dt)

  local rumble = 0
  if not A.paused then
    if A.on_ground and A.gs > 0.5 then rumble = min(A.gs / 35, 1) * 0.003 * amt end
    rumble = rumble + clamp(A.throttle, 0, 1) * 0.0003 * amt
  end
  HP.n_t = HP.n_t + dt
  if HP.n_t > 1 / 24 then
    HP.n_t = 0
    HP.nx, HP.ny, HP.np, HP.nr = rnd(-1, 1), rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)
  end
  HP.rumble = HP.rumble + (rumble - HP.rumble) * (1 - exp(-dt / 0.03))

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

-- The safe space around the seat. Cockpit shots never move the head further
-- than this from the eye point, so the view cannot leave the cockpit or pass
-- through the panel, the seat or the walls; they look around instead.
local SAFE = { side = 0.08, up = 0.05, down = 0.04, fwd = 0.08, back = 0.06 }

-- -----------------------------------------------------------------------------
-- Shots
--
-- Exterior shots set o.x/y/z (camera position, local axes) and either a target
-- to look at (o.tx/ty/tz) or angles (o.hdg/pit/rol), plus o.zoom. Cockpit
-- shots set the head pose in aircraft axes (o.x/y/z, o.psi/the/phi) and the
-- centre of the safe space it must stay in (o.cx/cy/cz).
-- -----------------------------------------------------------------------------

local SHOTS, SHOT_ORDER = {}, {}
local function shot(def)
  SHOTS[def.id] = def
  SHOT_ORDER[#SHOT_ORDER + 1] = def.id
end

local BASE_FOV = 60       -- the lens the exterior framings are designed for
local SWEEP_TIME = 16     -- seconds for one crane move (it then goes back)
local PAN_TIME = 18       -- seconds for one cockpit pan (it then goes back)

local B = nil             -- pilot's eye point: head pose captured in the 3D cockpit

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

-- Exterior -------------------------------------------------------------------

shot {
  id = "chase", name = "Chase", kind = "ext", rel = true, shake = 0.35, aim = 6,
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
  id = "orbit", name = "Orbit", kind = "ext", rel = true, shake = 0.2,
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
  init = function(st)
    plan_pass(st, rnd(4, 6), 1.4, 2.4, false, rnd(-0.3, 0.5))
    st.max_zoom = min(S.max_zoom, 4)
  end,
  place = function(st, o, dt) fixed_place(st, o, dt, 0.45, 2 / 7) end,
  done = pass_done,
}

shot {
  id = "spotter", name = "Spotter", kind = "ext", shake = 1.0, aim = 5,
  init = function(st)
    plan_pass(st, rnd(6, 8), 3.5, 6.5, true, 0)
    st.max_zoom = S.max_zoom
  end,
  place = function(st, o, dt) fixed_place(st, o, dt, 0.35, 2 / 5) end,
  done = pass_done,
}

shot {
  id = "a2a", name = "Air-to-air", kind = "ext", rel = true, shake = 0.5, aim = 4,
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
  id = "sweep", name = "Crane sweep", kind = "ext", rel = true, shake = 0.25, aim = 5,
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
  id = "tail", name = "Tail cam", kind = "ext", rel = true, vib = 1,
  init = function() end,
  place = function(st, o) mount(o, 0, 0.45, 1.10, 0, 0.38, 0.10) end,
}

shot {
  id = "wing", name = "Wing cam", kind = "ext", rel = true, vib = 1,
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 1.05, 0.30, 0.15, 0, 0, -0.90, true) end,
}

shot {
  id = "nose", name = "Nose cam", kind = "ext", rel = true, vib = 1,
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 0.18, 0.12, -1.45, 0, 0.08, -0.80) end,
}

shot {
  id = "top", name = "Top cam", kind = "ext", rel = true, vib = 1,
  init = function() end,
  place = function(st, o) mount(o, 0, 0.34, -0.55, 0, 0.15, 1.10) end,
}

shot {
  id = "gear", name = "Gear cam", kind = "ext", rel = true, vib = 1.5, ground_margin = 0.35,
  available = function() return A.on_ground or A.agl < 300 end,
  init = function(st) st.side = sign_rnd() end,
  place = function(st, o) mount(o, st.side * 0.12, -0.20, 0.55, 0, -0.28, -1.40) end,
}

-- Cockpit --------------------------------------------------------------------
-- These turn the head to look around; the only movement is a few centimetres
-- of lean (scaled by "head movement"), and the safe space caps it.

local function at_seat(o)
  o.cx, o.cy, o.cz = B[1], B[2], B[3]
  o.x, o.y, o.z = B[1], B[2], B[3]
  o.phi = B[6]
end

-- Where the pilot glances: heading and pitch offsets, and how often.
local GLANCES = { { 0, 0, 4 }, { -35, -3, 1 }, { 35, -3, 1 }, { "side", -6, 1 }, { 0, -20, 1 }, { "other", -2, 1 } }

shot {
  id = "pilot", name = "Pilot's eye", kind = "int",
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
            if h == "side" then h = side * 70 elseif h == "other" then h = -side * 45 end
            st.th, st.tp, st.last = h, gl[2], i
            break
          end
        end
      end
      st.next = st.t + rnd(3.5, 7.5)
    end
    st.gh, st.ghv = spring(st.gh, st.ghv, st.th, 2.4, 1, dt)
    st.gp, st.gpv = spring(st.gp, st.gpv, st.tp, 2.4, 1, dt)
    at_seat(o)
    local m = S.head_motion
    o.x = B[1] + sin(rad(st.gh)) * 0.04 * m                  -- lean a little into a glance
    o.z = B[3] - max(0, -st.gp / 20) * 0.03 * m              -- and toward the panel
    o.psi, o.the = B[4] + st.gh, B[5] + st.gp
  end,
}

shot {
  id = "panel", name = "Panel sweep", kind = "int",
  init = function(st) st.dir = sign_rnd() end,
  head = function(st, o)
    local u = (st.t / PAN_TIME) % 2
    if u > 1 then u = 2 - u end
    local s = smoother(u)
    at_seat(o)
    o.z = B[3] - 0.03 * S.head_motion
    o.psi = B[4] + st.dir * lerp(-30, 30, s)
    o.the = B[5] + lerp(-22, -16, s)
  end,
}

shot {
  id = "side", name = "Side window", kind = "int",
  init = function() end,
  head = function(st, o)
    local side = (seat_side() ~= 0) and seat_side() or -1
    at_seat(o)
    o.x = B[1] + side * 0.04 * S.head_motion                 -- lean toward the window
    o.psi = B[4] + side * (74 + 8 * sin(st.t * 0.12))
    o.the = B[5] - 6 + 3 * sin(st.t * 0.09 + 1)
  end,
}

shot {
  id = "cpan", name = "Cockpit pan", kind = "int",
  init = function(st) st.dir = sign_rnd() end,
  head = function(st, o)
    local u = (st.t / PAN_TIME) % 2
    if u > 1 then u = 2 - u end
    local s = smoother(u)
    local h = st.dir * lerp(-85, 85, s)
    at_seat(o)
    o.psi = B[4] + h
    o.the = B[5] - 6 - 6 * cos(rad(h))                       -- dip toward the panel in the middle
  end,
}

shot {
  id = "fo", name = "First officer", kind = "int", other_seat = true,
  -- Only where the seats are side by side; the eye point is mirrored across.
  available = function() return B ~= nil and abs(B[1]) >= 0.25 and abs(B[1]) <= 1.2 end,
  init = function() end,
  head = function(st, o)
    local seat = seat_side()
    o.cx, o.cy, o.cz = -B[1], B[2], B[3]
    o.x, o.y, o.z = -B[1], B[2], B[3]
    o.psi = B[4] + seat * 38 + 4 * wob(st.t * 0.1, 5)
    o.the = B[5] - 9 + wob(st.t * 0.13, 6)
    o.phi = B[6]
  end,
}

-- -----------------------------------------------------------------------------
-- Session state
-- -----------------------------------------------------------------------------

local cine = {
  active = false,
  def = nil, st = nil,                  -- current shot
  prev_def = nil, prev_st = nil,        -- exterior shot being glided from
  blend = 1, blend_len = 0, blend_check = false,
  int_from = nil,                       -- cockpit pose being glided from
  ext_on = false, expect_release = false, override = false,
  waiting = nil, wait = 0,              -- "ext" / "int" while a view change is under way
  origin_internal = true,               -- you started in the cockpit
  head_moved = false, last_head = nil, restore_frames = 0,
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
local function filming_outside() return cine.active and cine.ext_on end

-- -----------------------------------------------------------------------------
-- The exterior camera: X-Plane calls this every frame while we have the
-- camera. It reads the aircraft pose itself so the camera never lags the
-- drawn aircraft.
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
  if not (cine.active and cine.def and cine.def.kind == "ext") then return 0 end

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

  psi, the = psi + nudge.yaw, clamp(the + nudge.up * 10, -80, 80)
  cine.last_head = { x, y, z, psi, the, phi }

  local h = HP.out
  x, y, z = x + h[1], y + h[2], z + h[3]
  psi, the, phi = psi + h[4], the + h[5], phi + h[6]
  -- A held shot breathes a little, so it never looks frozen.
  local b = S.shake * 0.2
  psi = psi + b * wob(st.t * 0.5, 21)
  the = the + b * 0.7 * wob(st.t * 0.6, 22)

  -- Never leave the safe space around the seat.
  x = clamp(x, o.cx - SAFE.side, o.cx + SAFE.side)
  y = clamp(y, o.cy - SAFE.down, o.cy + SAFE.up)
  z = clamp(z, o.cz - SAFE.fwd, o.cz + SAFE.back)
  write_head(x, y, z, psi, the, phi)
  cine.head_moved = true
end

local function capture_eye_point()
  B = { read_head() }
end

-- -----------------------------------------------------------------------------
-- X-Plane's zoom while filming outside: its zoom commands (keys, joystick
-- buttons) are taken over only during an exterior shot and handed back after.
-- -----------------------------------------------------------------------------

local zoom_hooked = false

local function zoom_command(phase, refcon)
  local z = ZOOM_CMDS[tonumber(ffi.cast("intptr_t", refcon))]
  if not (z and filming_outside()) then return 1 end
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
  if def.kind == "int" and (vr_on() or not CMD.cockpit or not HAS_HEAD) then return false end
  if def.kind == "ext" and not CMD.external then return false end
  return not def.available or def.available()
end

local function begin_shot(id, how)
  local def = SHOTS[id]
  if not def then return end
  local prev_def, prev_st = cine.def, cine.st
  local st = { t = 0 }
  def.init(st)

  if def.kind == "ext" then
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
      -- Switch to an exterior view, then take the camera (now, if the switch
      -- already happened, or as soon as it does).
      cine.prev_def, cine.prev_st, cine.blend = nil, nil, 1
      cine.waiting, cine.wait = "ext", 0
      if geti(REF.external) == 0 then run_cmd(CMD.external) end
      if geti(REF.external) ~= 0 then
        cine.waiting = nil
        take_camera()
      end
    end
  else
    cine.prev_def, cine.prev_st = nil, nil
    if prev_def and prev_def.kind == "int" and cine.last_head and S.blend_time > 0.05 and how ~= "cut"
       and not def.other_seat and not prev_def.other_seat then
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

  cine.def, cine.st, cine.last_id = def, st, id
  use_adjustments(id)
  cine.title, cine.title_t = def.name, 4
  if def.kind == "int" and geti(REF.view_type) == VIEW_3D_COCKPIT then
    -- Already in the cockpit: place the head now, so the cut has no stray frame.
    cine.waiting = nil
    if not B then capture_eye_point() end
    run_cockpit(0)
  end
end

local function start_session()
  if cine.active then return true end
  if vr_on() then
    log("cinematic views are off in VR.")
    cine.message = "Not available in VR"
    return false
  end
  if not CMD.external and not CMD.cockpit then
    log("could not find X-Plane's view commands.")
    return false
  end
  cine.active, cine.override, cine.message, cine.head_moved = true, false, nil, false
  cine.origin_internal = geti(REF.external) == 0
  measure_aircraft()
  if HAS_HEAD and geti(REF.view_type) == VIEW_3D_COCKPIT then capture_eye_point() end
  hook_zoom(true)
  return true
end

local function stop_session(restore_view)
  if not cine.active then return end
  local was_int = cine.def and cine.def.kind == "int"
  cine.active = false
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
  hook_zoom(false)
  cine.def, cine.st, cine.prev_def, cine.prev_st, cine.int_from = nil, nil, nil, nil, nil
  cine.waiting, cine.last_head = nil, nil
  if B and cine.head_moved then
    -- Put the head back now (X-Plane keeps it for when you return to the
    -- cockpit) and for a few frames in case the view change resets it.
    write_head(B[1], B[2], B[3], B[4], B[5], B[6])
    cine.restore_frames = 3
  end
  cine.head_moved = false
end

for _, f in ipairs({ run_cmd, take_camera, release_camera, begin_shot, stop_session }) do
  if jit and jit.off then jit.off(f, true) end
end

-- -----------------------------------------------------------------------------
-- Actions (commands, macros, the window and your assigned keys and buttons)
-- -----------------------------------------------------------------------------

local queue = {}
local function request(fn) queue[#queue + 1] = fn end

local function act_shot(id)
  if not SHOTS[id] then return end
  if not cine.active and not start_session() then return end
  begin_shot(id, "manual")
end

local function in_cycle(def)
  return shot_available(def) and (def.kind == "ext" or S.cockpit_in_cycle)
end

local function act_step(step)
  if not cine.active then return act_shot(cine.last_id) end   -- off: start with your last shot
  local cur, n = cine.def and cine.def.id, #SHOT_ORDER
  local idx = (step > 0) and 0 or 1
  for i, id in ipairs(SHOT_ORDER) do if id == cur then idx = i end end
  for _ = 1, n do
    idx = (idx - 1 + step) % n + 1
    if in_cycle(SHOTS[SHOT_ORDER[idx]]) then break end
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

-- Zoom: the exterior camera's own; in the cockpit, X-Plane's.
local function native_zoom(dir)
  run_cmd(dir > 0 and CMD.zoom_in or CMD.zoom_out)
end

M.nudge = function(kind, dir)
  local dt = clock.dt
  if kind == "yaw" then
    nudge.yaw = wrap180(nudge.yaw + dir * 40 * dt)
  elseif kind == "up" then
    nudge.up = clamp(nudge.up + dir * 0.6 * dt, -2, 3)
  elseif kind == "zoom" then
    if cine.active and cine.def and cine.def.kind == "int" then native_zoom(dir) else zoom_by(exp(dir * 0.8 * dt)) end
  end
end
M.reset_nudge = reset_nudge

local ACTIONS = {
  { id = "toggle", name = "Camera on/off", run = M.toggle },
  { id = "next", name = "Next view", run = M.next_shot },
  { id = "prev", name = "Previous view", run = M.previous_shot },
}

-- -----------------------------------------------------------------------------
-- Keys: your assigned keys, and + / - zooming the exterior camera. FlyWithLua
-- passes a key on to X-Plane unless a script sets RESUME_KEY = true, so this
-- only ever sets it for keys it uses.
-- -----------------------------------------------------------------------------

local KEY_NAMES = {
  [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Return", [0x20] = "Space",
  [0x21] = "Page Up", [0x22] = "Page Down", [0x23] = "End", [0x24] = "Home",
  [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
  [0x2D] = "Insert", [0x2E] = "Delete",
  [0x6A] = "Num *", [0x6B] = "Num +", [0x6D] = "Num -", [0x6E] = "Num .", [0x6F] = "Num /",
  [0xB0] = "=", [0xB1] = "-", [0xB2] = "]", [0xB3] = "[", [0xB4] = "'", [0xB5] = ";", [0xB6] = "\\",
  [0xB7] = ",", [0xB8] = "/", [0xB9] = ".", [0xBA] = "`", [0xBB] = "Enter", [0xBC] = "Num Enter", [0xBD] = "Num =",
}
for i = 0, 9 do KEY_NAMES[0x30 + i], KEY_NAMES[0x60 + i] = tostring(i), "Num " .. i end
for i = 0, 25 do KEY_NAMES[0x41 + i] = string.char(65 + i) end
for i = 1, 24 do KEY_NAMES[0x6F + i] = "F" .. i end

local VK_ESCAPE = 0x1B

local function binding_label(b)
  if not b then return "not set" end
  if b.kind == "joy" then return "Joystick button " .. b.n end
  return (b.ctrl and "Ctrl+" or "") .. (b.alt and "Alt+" or "") .. (b.shift and "Shift+" or "")
         .. (KEY_NAMES[b.vk] or ("key " .. b.vk))
end

-- + / = and - (top row or keypad) zoom; returns +1, -1 or nil.
local function zoom_key(vk, ch)
  if vk == 0xB0 or vk == 0x6B or ch == "+" or ch == "=" then return 1 end
  if vk == 0xB1 or vk == 0x6D or ch == "-" then return -1 end
  return nil
end

local keys_down = {}
local zoom_held = nil                  -- { dir, fast, t } while + or - is held outside
local capture = { action = nil, msg = nil, t = 0, base = nil }

local JOY = { n = 0, all = nil, one = ffi.new("int[1]"), last = {} }
if REF.joy then
  JOY.n = clamp(XPLM.cv_GetDatavi(REF.joy, nil, 0, 0), 0, 8192)
  if JOY.n > 0 then JOY.all = ffi.new("int[?]", JOY.n) end
end

local function read_buttons()
  if JOY.n == 0 then return nil end
  XPLM.cv_GetDatavi(REF.joy, JOY.all, 0, JOY.n)
  return JOY.all
end

local function joy_down(n)
  if not REF.joy or n >= JOY.n then return false end
  XPLM.cv_GetDatavi(REF.joy, JOY.one, n, 1)
  return JOY.one[0] ~= 0
end

local function start_capture(action)
  capture.action, capture.msg, capture.t = action, nil, 0
  capture.base = {}
  local all = read_buttons()
  if all then for i = 0, JOY.n - 1 do capture.base[i] = all[i] ~= 0 end end
end

local function assign(action, b)
  -- One input per action, and an input for one action only.
  for id, other in pairs(BIND) do
    if other.kind == b.kind and ((b.kind == "joy" and other.n == b.n) or
       (b.kind == "key" and other.vk == b.vk and other.shift == b.shift and other.ctrl == b.ctrl and other.alt == b.alt)) then
      BIND[id] = nil
    end
  end
  BIND[action] = b
  if b.kind == "joy" then JOY.last[b.n] = true end   -- it is held right now
  capture.action, capture.msg = nil, nil
  settings_dirty = true
end

local function on_key()
  local vk = (tonumber(VKEY) or 0) % 256     -- FlyWithLua passes the key code as a signed char
  local ch = type(CKEY) == "string" and CKEY or ""
  local pressed = KEY_ACTION == "pressed"
  local shift, ctrl, alt = SHIFT_KEY == true, CONTROL_KEY == true, OPTION_KEY == true

  if capture.action then
    if pressed then
      if vk == VK_ESCAPE then
        capture.action, capture.msg = nil, "Cancelled."
      elseif zoom_key(vk, ch) and not ctrl and not alt then
        capture.msg = "+ and - are kept for zoom - pick another key."
      else
        assign(capture.action, { kind = "key", vk = vk, shift = shift, ctrl = ctrl, alt = alt })
      end
    end
    keys_down[vk] = pressed or nil
    RESUME_KEY = true
    return
  end

  for _, a in ipairs(ACTIONS) do
    local b = BIND[a.id]
    if b and b.kind == "key" and b.vk == vk then
      if pressed and b.shift == shift and b.ctrl == ctrl and b.alt == alt then
        if not keys_down[vk] then a.run() end         -- ignore key repeat
        keys_down[vk] = true
        RESUME_KEY = true
        return
      elseif not pressed and keys_down[vk] then
        keys_down[vk] = nil
        RESUME_KEY = true
        return
      end
    end
  end

  local dir = (not ctrl and not alt) and zoom_key(vk, ch) or nil
  if dir then
    if not pressed then zoom_held = nil end
    if filming_outside() then
      if pressed and not zoom_held then
        zoom_by(exp(dir * (shift and 0.15 or 0.05)))
        zoom_held = { dir = dir, fast = shift, t = 0 }
      end
      RESUME_KEY = true
    end
  end
end

-- The mouse wheel zooms the exterior camera; otherwise it is X-Plane's.
local function on_wheel()
  if filming_outside() and (tonumber(MOUSE_WHEEL_NUMBER) or 0) == 0 then
    zoom_by(1.1 ^ (tonumber(MOUSE_WHEEL_CLICKS) or 0))
    RESUME_MOUSE_WHEEL = true
  end
end

local function buttons_tick(dt)
  if capture.action then
    capture.t = capture.t + dt
    local all = read_buttons()
    if all then
      for i = 0, JOY.n - 1 do
        local down = all[i] ~= 0
        if down and not capture.base[i] then
          assign(capture.action, { kind = "joy", n = i })
          return
        end
        if not down then capture.base[i] = false end
      end
    end
    if capture.t > 15 then capture.action, capture.msg = nil, "Nothing pressed - try again." end
    return
  end
  for _, a in ipairs(ACTIONS) do
    local b = BIND[a.id]
    if b and b.kind == "joy" then
      local down = joy_down(b.n)
      if down and not JOY.last[b.n] then a.run() end
      JOY.last[b.n] = down
    end
  end
  if zoom_held then
    zoom_held.t = zoom_held.t + dt
    if not filming_outside() then
      zoom_held = nil
    elseif zoom_held.t > 0.25 then
      zoom_by(exp(zoom_held.dir * (zoom_held.fast and 2.4 or 0.8) * dt))
    end
  end
end

-- -----------------------------------------------------------------------------
-- Per-frame work
-- -----------------------------------------------------------------------------

local LB = { amount = 0 }

local function tick()
  local t, dt = sim_dt(clock.last)
  clock.last, clock.dt = t, dt

  update_dynamics(dt)
  update_head_motion(dt)
  buttons_tick(dt)

  -- Commands, macros, keys and window buttons, run here with this frame's state.
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

  local in_cockpit = HAS_HEAD and geti(REF.view_type) == VIEW_3D_COCKPIT
  if cine.active and cine.def then
    local def = cine.def
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
      elseif not cine.ext_on then
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
        stop_session(false)              -- you left the cockpit view yourself
      end
    end
    if cine.active and def.done and def.done(cine.st) then
      begin_shot(def.id, "cut")          -- flyby/spotter: set up the next pass
    end
  elseif cine.restore_frames > 0 then
    cine.restore_frames = cine.restore_frames - 1
    if B and in_cockpit then write_head(B[1], B[2], B[3], B[4], B[5], B[6]) end
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
-- Drawing: letterbox and shot title (FlyWithLua's own drawing functions)
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
  if not (W and H) then return end
  local bar = 0
  if LB.amount > 0.001 and glRectf and glColor4f then
    bar = max(0, (H - W / S.aspect) / 2) * smoother(LB.amount)
    if bar >= 1 then
      XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)
      glColor4f(0, 0, 0, 1)
      glRectf(0, 0, W, bar)
      glRectf(0, H - bar, W, H)
    end
  end
  if S.titles and cine.active and cine.title_t > 0 and draw_string then
    local y = (bar > 24) and (bar / 2 - 4) or 30
    draw_string(30, y, cine.title, "white")
  end
end

-- -----------------------------------------------------------------------------
-- The window: everything in one place
-- -----------------------------------------------------------------------------

local wnd = nil

local COL_ACTIVE = 0xFFD08A2A    -- imgui colours are 0xAABBGGRR
local COL_ON = 0xFF3C9A3C
local COL_MUTED = 0xFF9A9A9A
local COL_HEAD = 0xFFE0C080

local function heading(text)
  imgui.Separator()
  imgui.PushStyleColor(imgui.constant.Col.Text, COL_HEAD)
  imgui.TextUnformatted(text)
  imgui.PopStyleColor()
end

local function muted(text)
  imgui.PushStyleColor(imgui.constant.Col.Text, COL_MUTED)
  imgui.TextUnformatted(text)
  imgui.PopStyleColor()
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

local function shot_buttons(kind)
  local col = 0
  for _, id in ipairs(SHOT_ORDER) do
    local def = SHOTS[id]
    if def.kind == kind then
      if col % 4 > 0 then imgui.SameLine() end
      local current = cine.active and cine.def == def
      local usable = shot_available(def)
      if current then imgui.PushStyleColor(imgui.constant.Col.Button, COL_ACTIVE) end
      if not usable then imgui.PushStyleColor(imgui.constant.Col.Text, COL_MUTED) end
      if imgui.Button(def.name .. "##" .. id, 118, 26) then M.shot(id) end
      if not usable then imgui.PopStyleColor() end
      if current then imgui.PopStyleColor() end
      col = col + 1
    end
  end
end

local function build_window()
  -- Camera on/off and the current shot
  local on = cine.active
  if on then imgui.PushStyleColor(imgui.constant.Col.Button, COL_ON) end
  if imgui.Button(on and "Camera ON  (click to stop)" or "Start camera", 230, 32) then M.toggle() end
  if on then imgui.PopStyleColor() end
  imgui.SameLine()
  if imgui.Button("< Previous", 110, 32) then M.previous_shot() end
  imgui.SameLine()
  if imgui.Button("Next >", 110, 32) then M.next_shot() end
  if on and cine.def then
    local z = cine.def.kind == "ext" and ("zoom %.1fx"):format(nudge.zoom) or "zoom: X-Plane's own"
    imgui.TextUnformatted(("Now: %s   |   %s"):format(cine.def.name, z))
  else
    muted(cine.message or ("Starts with: " .. SHOTS[cine.last_id].name))
  end

  heading("EXTERIOR SHOTS")
  shot_buttons("ext")
  heading("COCKPIT SHOTS")
  shot_buttons("int")
  checkbox("Include cockpit shots in Next / Previous", "cockpit_in_cycle")

  heading("CONTROLS")
  for _, a in ipairs(ACTIONS) do
    imgui.TextUnformatted(a.name)
    imgui.SameLine(130)
    if capture.action == a.id then
      imgui.PushStyleColor(imgui.constant.Col.Text, COL_HEAD)
      imgui.TextUnformatted("Press a key or joystick button...")
      imgui.PopStyleColor()
    else
      imgui.TextUnformatted(binding_label(BIND[a.id]))
    end
    imgui.SameLine(380)
    if imgui.Button((capture.action == a.id and "Cancel##" or "Assign##") .. a.id, 70, 22) then
      if capture.action == a.id then capture.action = nil else start_capture(a.id) end
    end
    imgui.SameLine()
    if imgui.Button("Clear##" .. a.id, 60, 22) then
      BIND[a.id], settings_dirty = nil, true
    end
  end
  if capture.msg then muted(capture.msg) end
  muted("Assigned keys only control the camera. Pick joystick buttons that X-Plane doesn't use.")
  muted("Zoom: + and - or the mouse wheel. In the cockpit they're X-Plane's own zoom.")

  heading("EXTERIOR CAMERA")
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
  muted(("   %.0f m span x %.0f m long, %s - remembered for this aircraft"):format(2 * A.Rs, 2 * A.Rl,
    A.size_source == "dimensions" and "from its dimensions" or "estimated from its weight"))
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
  if imgui.Button("Zoom +", 62, 24) then
    if cine.def and cine.def.kind == "int" then native_zoom(1) else zoom_by(1.25) end
  end
  imgui.SameLine()
  if imgui.Button("Zoom -", 62, 24) then
    if cine.def and cine.def.kind == "int" then native_zoom(-1) else zoom_by(1 / 1.25) end
  end
  imgui.SameLine()
  if imgui.Button("Reset", 56, 24) then reset_nudge() end

  heading("COCKPIT CAMERA")
  slider("Head movement", "head_motion", 0, 1, "%.2f")
  muted("   The head stays within a few cm of your seat, so the view never leaves the cockpit.")
  if imgui.Button("Use my current head position as the pilot's eye", 340, 24) then
    request(function()
      if geti(REF.view_type) == VIEW_3D_COCKPIT and not cine.active then capture_eye_point() end
    end)
  end
  muted(B and ("   eye point x %.2f  y %.2f  z %.2f m"):format(B[1], B[2], B[3])
          or "   taken from your seat when filming starts in the cockpit")

  heading("LOOK")
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

  imgui.Separator()
  if vr_on() then muted("VR is on: cinematic views are paused.") end
  muted("Cinematic Views " .. VERSION .. "  -  settings save automatically")
end

function cinematic_views_build_window(_, _, _)
  local ok, err = pcall(build_window)
  if not ok then
    log("window error: " .. tostring(err))
  end
end

function cinematic_views_window_closed(_)
  wnd = nil
  capture.action = nil
  if settings_dirty then save_settings() end
end

M.toggle_window = function()
  if wnd then
    float_wnd_destroy(wnd)
    wnd = nil
    capture.action = nil
    if settings_dirty then save_settings() end
    return
  end
  if not (SUPPORTS_FLOATING_WINDOWS and float_wnd_create) then
    log("the settings window needs FlyWithLua NG 2.7 or later; the commands still work.")
    return
  end
  wnd = float_wnd_create(560, 780, 1, true)
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
M._key = function()
  local ok, err = pcall(on_key)
  if not ok then log("key error: " .. tostring(err)) end
end
M._wheel = function()
  local ok, err = pcall(on_wheel)
  if not ok then log("wheel error: " .. tostring(err)) end
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
M._state = function() return cine, A, S, BIND, function() return B end end
M._shots = function() return SHOTS, SHOT_ORDER end

CinematicViews = M

-- -----------------------------------------------------------------------------
-- Registration with FlyWithLua
-- -----------------------------------------------------------------------------

do_every_frame("CinematicViews._frame()")
do_every_draw("CinematicViews._draw()")
do_often("CinematicViews._often()")
do_on_exit("CinematicViews.shutdown()")
if do_on_keystroke then do_on_keystroke("CinematicViews._key()") end
if do_on_mouse_wheel then do_on_mouse_wheel("CinematicViews._wheel()") end

local P = "FlyWithLua/cinematic_views/"
local function command(name, desc, code)
  create_command(P .. name, "Cinematic Views: " .. desc, code, "", "")
end
local function hold_command(name, desc, code)
  create_command(P .. name, "Cinematic Views: " .. desc, "", code, "")
end

command("toggle", "camera on/off (starts with the last shot)", "CinematicViews.toggle()")
command("stop", "stop and return to your view", "CinematicViews.stop()")
command("next_shot", "next view", "CinematicViews.next_shot()")
command("previous_shot", "previous view", "CinematicViews.previous_shot()")
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
  add_macro("Cinematic Views: camera on/off", "CinematicViews.toggle()")
  add_macro("Cinematic Views: next view", "CinematicViews.next_shot()")
  add_macro("Cinematic Views: settings window", "CinematicViews.toggle_window()")
end

if not CMD.external then log("no exterior view command found - exterior shots are off.") end
if not (CMD.cockpit and HAS_HEAD) then log("no 3D cockpit view - cockpit shots are off.") end
log("v" .. VERSION .. " ready - Plugins > FlyWithLua > Macros, or the FlyWithLua/cinematic_views/ commands.")
