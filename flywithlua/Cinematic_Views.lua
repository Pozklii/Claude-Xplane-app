-- =============================================================================
--  Cinematic Views for X-Plane 12                                        v4.0.0
--  A FlyWithLua NG+ script: an automatic cinematic camera for screenshots
--  and videos, outside and inside the aircraft.
--
--  * Exterior shots through X-Plane's camera API, always moving slowly:
--    wide shots of the whole aircraft (rear quarter, front quarter, side
--    profile, high, low front) and close-ups of its parts (cockpit, nose,
--    engine, wing, wingtip, tail, main and nose gear), framed by the zoom.
--  * Cockpit shots with realistic head movement, focused on parts of the
--    cockpit: the pilot's scan, instrument panel, overhead panel, throttle
--    and pedestal, side window, autopilot and FMC. The head stays within a
--    few centimetres of the seat, so the view never leaves the cockpit.
--  * Endless random shots built from the same pieces. Save the ones you like
--    and they join Next / Previous.
--  * Cameras fit the aircraft: they read its span and length (or estimate
--    them from its weight), and remember a size correction per aircraft.
--  * Zoom: + and - (and the mouse wheel) zoom the exterior camera smoothly,
--    like X-Plane's own zoom; in the cockpit, and when you are not filming,
--    they are X-Plane's own as usual.
--  * A small window: camera on/off, previous/next, random, save, your own key
--    or joystick button for each, and a few sliders. Nothing is ever drawn
--    over the picture.
--
--  Install: copy this file to  X-Plane 12/Resources/plugins/FlyWithLua/Scripts/
--  Use:     Plugins > FlyWithLua > FlyWithLua Macros > Cinematic Views
--
--  Requires FlyWithLua NG+ (LuaJIT with FFI). Settings are saved next to this
--  file in Cinematic_Views.ini.
-- =============================================================================

local VERSION = "4.0.0"
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
  'int cv_GetDatavf(void *ref, float *values, int offset, int max) __asm__("XPLMGetDatavf");',
  'void *cv_FindCommand(const char *name) __asm__("XPLMFindCommand");',
  'void cv_CommandOnce(void *cmd) __asm__("XPLMCommandOnce");',
  'void cv_RegisterCommandHandler(void *cmd, cv_CommandCallback_f handler, int before, void *refcon) __asm__("XPLMRegisterCommandHandler");',
  'void cv_UnregisterCommandHandler(void *cmd, cv_CommandCallback_f handler, int before, void *refcon) __asm__("XPLMUnregisterCommandHandler");',
  'void cv_ControlCamera(int howLong, cv_CameraControl_f func, void *refcon) __asm__("XPLMControlCamera");',
  'void cv_DontControlCamera(void) __asm__("XPLMDontControlCamera");',
  'void *cv_CreateProbe(int type) __asm__("XPLMCreateProbe");',
  'void cv_DestroyProbe(void *probe) __asm__("XPLMDestroyProbe");',
  'int cv_ProbeTerrainXYZ(void *probe, float x, float y, float z, cv_ProbeInfo_t *info) __asm__("XPLMProbeTerrainXYZ");',
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
  engines = "sim/aircraft/engine/acf_num_engines",
  gear = "sim/flightmodel2/gear/deploy_ratio",
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
}

local RANGES = {
  blend_time = { 0, 5 }, distance = { 0.5, 3 }, orbit_speed = { 1, 20 }, shake = { 0, 1 },
  max_zoom = { 2, 15 }, head_motion = { 0, 1 },
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
local ACTION_IDS = { "toggle", "next", "prev", "random" }

-- Your saved shots ({ id, recipe }), and the saved recipes read from the file.
local MY, MY_RAW = {}, {}
local serialize_recipe          -- defined with the random shots

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
    local my = line:match("^%s*myshot%s*=%s*(.-)%s*$")
    if my then MY_RAW[#MY_RAW + 1] = my end
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
  for _, a in ipairs(ACTION_IDS) do
    if BIND[a] then f:write("bind.", a, " = ", format_binding(BIND[a]), "\n") end
  end
  for _, m in ipairs(MY) do f:write("myshot = ", serialize_recipe(m.recipe), "\n") end
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

-- -----------------------------------------------------------------------------
-- Terrain probe (cameras stay above the ground)
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
  size_source = "weight", mass = 1200,
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
  A.mass = m
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
-- Exterior shots are either a wide shot of the whole aircraft or a close-up
-- of one part of it, and the camera is always moving, slowly. They set
-- o.x/y/z (camera position, local axes), the point it looks at (o.tx/ty/tz),
-- o.rol and o.zoom. Cockpit shots move the pilot's head like a real pilot
-- looking at parts of the cockpit; they set the head pose in aircraft axes
-- (o.x/y/z, o.psi/the/phi) and the centre of the safe space it must stay in
-- (o.cx/cy/cz).
--
-- Every shot runs from a recipe (st.r): the listed shots make a fresh one,
-- with its own small variations, each time they start; random and saved
-- shots carry theirs.
-- -----------------------------------------------------------------------------

local SHOTS, SHOT_ORDER = {}, {}
local BASE_FOV = 60       -- the lens the exterior framings are designed for
local B = nil             -- pilot's eye point: head pose captured in the 3D cockpit

local function seat_side()
  if not B then return 0 end
  if B[1] < -0.12 then return -1 elseif B[1] > 0.12 then return 1 end
  return 0
end

local function track_or_heading() return (A.gs > 12) and A.trk or A.psi end

local RS = {}
do
  local TAU = 2 * math.pi

  local function pick(list)   -- { { value, weight }, ... }
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local x, acc = random() * total, 0
    for _, e in ipairs(list) do
      acc = acc + e[2]
      if x <= acc then return e[1] end
    end
    return list[#list][1]
  end

  -- What the aircraft has ---------------------------------------------------

  local gear_buf = ffi.new("float[1]")

  local function engine_count()
    if REF.engines then return geti(REF.engines) end
    return (A.R > 9) and 2 or 1
  end

  local function gear_down()
    if REF.gear and XPLM.cv_GetDatavf(REF.gear, gear_buf, 0, 1) == 1 then return gear_buf[0] > 0.9 end
    return A.on_ground or A.agl < 300
  end

  -- Parts to film close up. p: the point in body axes (x in half spans, y
  -- and z in half lengths); size: the half-size to frame (in R); views:
  -- where the camera may look from on the right-hand side, as azimuth from
  -- the nose and elevation ranges (mirrored for the left).
  local PARTS = {
    cockpit  = { p = { 0, 0.08, -0.8 }, size = 0.16, views = { { 15, 60, 2, 18 } } },
    nose     = { p = { 0, -0.02, -0.92 }, size = 0.18, views = { { 10, 70, -4, 12 } } },
    engine   = { size = 0.12, views = { { 20, 70, -6, 8 }, { 110, 150, -4, 8 } } },
    wing     = { p = { 0.6, 0, 0.05 }, size = 0.28, views = { { 100, 160, 15, 40 }, { 25, 60, 8, 22 } } },
    wingtip  = { p = { 0.95, 0.02, 0.15 }, size = 0.14, views = { { 50, 130, 2, 25 } } },
    tail     = { p = { 0, 0.3, 0.88 }, size = 0.2, views = { { 120, 170, 4, 25 }, { 80, 105, 0, 12 } } },
    gear     = { p = { 0.15, -0.2, 0.05 }, size = 0.12, views = { { 60, 120, 6, 12 } } },
    nosegear = { p = { 0, -0.22, -0.7 }, size = 0.1, views = { { 0, 40, 6, 12 } } },
  }
  local PART_ORDER = { "cockpit", "nose", "engine", "wing", "wingtip", "tail", "gear", "nosegear" }
  local PART_NAMES = { cockpit = "cockpit", nose = "nose", engine = "engine", wing = "wing", wingtip = "wingtip",
                       tail = "tail", gear = "main gear", nosegear = "nose gear" }

  local function part_ok(name)
    if name == "engine" then
      local n = engine_count()
      return (n == 1 and A.R < 9) or n == 2 or n == 4      -- a nose engine, or engines under the wings
    end
    if name == "gear" or name == "nosegear" then return gear_down() end
    return PARTS[name] ~= nil
  end

  -- A part's point in body axes (metres); side picks left or right, which
  -- the inner or outer engine of four.
  local function part_body(name, side, which)
    if name == "engine" then
      local n = engine_count()
      if n == 1 then return 0, -0.02 * A.Rl, -0.9 * A.Rl end
      local x = (n == 4 and which == 2) and 0.58 or 0.33
      return side * x * A.Rs, -0.1 * A.Rl, -0.12 * A.Rl
    end
    local p = PARTS[name].p
    return side * p[1] * A.Rs, p[2] * A.Rl, p[3] * A.Rl
  end

  -- The box around the airframe that cameras stay outside of.
  local function box() return A.Rs * 1.1 + 1, A.Rl * 0.45 + 1, A.Rl * 1.1 + 1 end
  RS.box = box

  -- How far from a point inside the box, along a direction (body axes,
  -- unit length), until outside it.
  local function exit_distance(px, py, pz, dx, dy, dz)
    local ex, ey, ez = box()
    local t = 1e9
    if abs(dx) > 1e-6 then t = min(t, ((dx > 0 and ex or -ex) - px) / dx) end
    if abs(dy) > 1e-6 then t = min(t, ((dy > 0 and ey or -ey) - py) / dy) end
    if abs(dz) > 1e-6 then t = min(t, ((dz > 0 and ez or -ez) - pz) / dz) end
    return max(t, 0)
  end

  -- What a shot looks at: the aircraft's centre (wide) or a part (close-up).
  local function subject(r)
    local bx, by, bz, size = 0, 0, 0, A.R * 1.05
    if r.family == "close" then
      bx, by, bz = part_body(r.part, r.side, r.which)
      size = PARTS[r.part].size * A.R
    end
    local wx, wy, wz = body_to_world(bx, by, bz, A.psi, A.the, A.phi)
    return A.x + wx, A.y + wy, A.z + wz, bx, by, bz, size
  end
  RS.subject = subject

  -- Exterior: the camera drifts slowly round a small ellipse - around and up
  -- and down at once, so it never stops - while easing in and out a little,
  -- and the zoom keeps the whole aircraft, or the part, filling the frame.
  local function film(r, st, o, dt)
    st.h, st.hv = spring_angle(st.h, st.hv, track_or_heading(), 1.2, 1, dt)
    local t = st.t
    local a = r.dir * TAU * t / r.per + r.ph1
    local az = (r.az + r.az_amp * sin(a)) * r.side
    local el = r.el + r.el_amp * cos(a)
    local breathe = 1 + r.d_amp * cos(a)                -- easing in and out, in step with the rest
    if r.family == "close" then breathe = 1 + r.d_amp * (1 + cos(a)) end   -- close-ups only ease outward
    local ce = cos(rad(el))
    local wx, wy, wz = heading_to_world(ce * sin(rad(az)), sin(rad(el)), -ce * cos(rad(az)), st.h)
    local tx, ty, tz, bx, by, bz, size = subject(r)
    local dist = r.d * A.R * S.distance
    if r.family == "close" then
      local dx, dy, dz = world_to_body(wx, wy, wz, A.psi, A.the, A.phi)
      dist = exit_distance(bx, by, bz, dx, dy, dz) + dist   -- as close as it can be from outside
    end
    dist = dist * breathe
    o.x, o.y, o.z = tx + wx * dist, ty + wy * dist, tz + wz * dist
    o.tx, o.ty, o.tz = tx, ty, tz
    local apparent = 2 * deg(atan2(size, max(dist, 1)))
    local want = clamp(r.frac * BASE_FOV / max(apparent, 0.01), 0.8, 6)
    if not st.zoom then st.zoom, st.zv = want, 0 end
    st.zoom, st.zv = spring(st.zoom, st.zv, want, 1.5, 1, dt)
    o.rol, o.zoom = r.bank * A.phi, st.zoom
  end

  local function motion(r, close)
    r.side, r.dir = sign_rnd(), sign_rnd()
    r.ph1 = rnd(0, TAU)
    r.az_amp, r.el_amp = close and rnd(6, 15) or rnd(12, 30), close and rnd(2.5, 5) or rnd(3, 8)
    r.per = close and rnd(25, 45) or rnd(30, 60)
    r.d_amp = rnd(0.04, 0.1)
    r.shake, r.aim = close and rnd(0.1, 0.35) or rnd(0.15, 0.45), rnd(3, 5.5)
    r.bank = close and rnd(0, 0.3) or rnd(0, 0.5)
    return r
  end

  -- A wide shot (from a set angle, or anywhere).
  local function new_wide(az, el, d)
    local r = motion({ kind = "ext", family = "wide" }, false)
    r.az = az or rnd(0, 180)
    r.el = el or ((random() < 0.7) and rnd(-2, 15) or rnd(15, 45))
    r.d = d or rnd(2.6, 4.2)
    r.el_amp = min(r.el_amp, r.el + 8)
    r.frac = rnd(0.55, 0.72)
    return r
  end

  -- A close-up of a part (a given one, or any the aircraft has right now).
  local function new_close(part)
    if not part then
      local list = {}
      for _, name in ipairs(PART_ORDER) do if part_ok(name) then list[#list + 1] = { name, 1 } end end
      part = pick(list)
    end
    local r = motion({ kind = "ext", family = "close", part = part, which = random(2) }, true)
    local v = PARTS[part].views[random(#PARTS[part].views)]
    r.az, r.el, r.d = rnd(v[1], v[2]), rnd(v[3], v[4]), rnd(0.15, 0.5)
    r.frac = rnd(0.5, 0.7)
    return r
  end

  -- Cockpit: where things are, from the pilot's seat. h and p: degrees from
  -- straight ahead (c = 1: toward the cockpit's centre; c = -1: toward your
  -- own window); spread: how far the eyes roam over it; dwell: seconds;
  -- lean: how the head leans toward it (m: toward the centre, up, back).
  local AREAS = {
    outside     = { h = 0, c = 0, p = 2, spread = 8, dwell = { 3, 7 }, lean = { 0, 0, 0 } },
    pfd         = { h = 2, c = 1, p = -20, spread = 4, dwell = { 1.5, 3.5 }, lean = { 0, -0.01, -0.02 } },
    nd          = { h = 10, c = 1, p = -20, spread = 3, dwell = { 1.5, 3 }, lean = { 0.01, -0.01, -0.02 } },
    eicas       = { h = 22, c = 1, p = -18, spread = 4, dwell = { 1.5, 3 }, lean = { 0.02, -0.01, -0.025 } },
    glareshield = { h = 12, c = 1, p = -6, spread = 6, dwell = { 1.5, 3 }, lean = { 0.01, 0, -0.02 } },
    overhead    = { h = 12, c = 1, p = 50, spread = 10, dwell = { 2, 4 }, lean = { 0.01, 0.02, 0.03 } },
    pedestal    = { h = 38, c = 1, p = -48, spread = 6, dwell = { 2, 4 }, lean = { 0.03, -0.03, -0.04 } },
    fmc         = { h = 30, c = 1, p = -36, spread = 4, dwell = { 2.5, 5 }, lean = { 0.03, -0.025, -0.05 } },
    side        = { h = 78, c = -1, p = -4, spread = 10, dwell = { 3, 6 }, lean = { -0.04, 0, -0.01 } },
    other       = { h = 55, c = 1, p = -4, spread = 5, dwell = { 2, 3 }, lean = { 0.02, 0, 0 } },
  }
  local AREA_ORDER = { "outside", "pfd", "nd", "eicas", "glareshield", "overhead", "pedestal", "fmc", "side", "other" }

  local function area_ok(name)
    if name == "overhead" then return A.mass >= 5700 end   -- light aircraft have no overhead panel
    return AREAS[name] ~= nil
  end

  -- The head: fix on a place, read it with small movements, then turn
  -- smoothly (a little overshoot that settles) to the next, leaning a few
  -- centimetres toward what it reads, breathing slowly.
  local function look_around(r, st, o, dt)
    local seat = seat_side()
    local c = (seat ~= 0) and -seat or 1
    if not st.area or st.t >= st.dwell_end then
      -- the next place to look; the same area again (a different spot on it)
      -- is fine, but not more than three looks running
      local choices = {}
      for _, name in ipairs(AREA_ORDER) do
        local w = r.w[name] or 0
        if w > 0 and area_ok(name) and not (name == st.area and (st.runs or 0) >= 3) then
          choices[#choices + 1] = { name, w }
        end
      end
      if #choices == 0 then choices[1] = { st.area or "outside", 1 } end
      local name = pick(choices)
      local a = AREAS[name]
      st.runs = (name == st.area) and (st.runs or 1) + 1 or 1
      st.area = name
      st.dwell_end = st.t + rnd(a.dwell[1], a.dwell[2]) * r.dwell
      st.bh = a.h * ((a.c == 0) and 1 or a.c * c) + rnd(-0.5, 0.5) * a.spread
      st.bp = a.p + rnd(-0.5, 0.5) * a.spread * 0.6
      st.th, st.tp = st.bh, st.bp
      st.micro = st.t + rnd(0.4, 1.0)
      st.lxt, st.lyt, st.lzt = a.lean[1] * c, a.lean[2], a.lean[3]
    elseif st.t >= st.micro then
      -- reading: a small move to another spot on the same thing
      local a = AREAS[st.area]
      local ang, reach = rnd(0, TAU), a.spread * rnd(0.25, 0.5)
      for _ = 1, 2 do                      -- at the edge of the area, go back the other way
        local th = clamp(st.th + cos(ang) * reach, st.bh - a.spread * 0.6, st.bh + a.spread * 0.6)
        local tp = clamp(st.tp + sin(ang) * reach * 0.6, st.bp - a.spread * 0.4, st.bp + a.spread * 0.4)
        if abs(th - st.th) + abs(tp - st.tp) > reach * 0.3 then
          st.th, st.tp = th, tp
          break
        end
        ang = ang + math.pi
      end
      st.micro = st.t + rnd(0.5, 1.4)
    end
    local gap = max(abs(st.th - st.h), abs(st.tp - st.p))
    local w = (gap > 15) and clamp(4.5 * sqrt(30 / gap), 2.2, 4.5) or 7   -- big turns take a little longer
    st.h, st.hv = spring(st.h, st.hv, st.th, w, 0.78, dt)
    st.p, st.pv = spring(st.p, st.pv, st.tp, w, 0.78, dt)
    st.hv, st.pv = clamp(st.hv, -160, 160), clamp(st.pv, -160, 160)       -- no faster than a real head
    local m = S.head_motion
    st.lx, st.lxv = spring(st.lx, st.lxv, st.lxt * m, 3, 1, dt)
    st.ly, st.lyv = spring(st.ly, st.lyv, st.lyt * m, 3, 1, dt)
    st.lz, st.lzv = spring(st.lz, st.lzv, st.lzt * m, 3, 1, dt)
    local breath, bm = sin(TAU * 0.22 * st.t), 0.3 + 0.7 * m
    o.cx, o.cy, o.cz = B[1], B[2], B[3]
    o.x, o.y, o.z = B[1] + st.lx, B[2] + st.ly + 0.003 * bm * breath, B[3] + st.lz
    o.psi = B[4] + st.h
    o.the = B[5] + st.p + 0.3 * bm * sin(TAU * 0.22 * st.t + 1)
    o.phi = B[6] + clamp(st.h * 0.04, -4, 4)
  end

  local function new_cockpit(weights)
    local r = { kind = "int", dwell = rnd(0.85, 1.2) }
    if not weights then
      weights = {}
      local main = pick({ { "pfd", 2 }, { "eicas", 1 }, { "overhead", area_ok("overhead") and 1 or 0 },
                          { "pedestal", 1 }, { "fmc", 1 }, { "glareshield", 1 }, { "side", 2 }, { "outside", 2 } })
      weights[main] = rnd(4, 6)
      for _ = 1, random(1, 3) do
        local other = AREA_ORDER[random(#AREA_ORDER)]
        if other ~= main then weights[other] = rnd(1, 2) end
      end
    end
    for name, w in pairs(weights) do r["w_" .. name] = w end
    return r
  end

  -- Recipes: kept in range (they also come from the settings file), and
  -- written as one line.
  local function sanitize(r)
    local function num(k, lo, hi, default) r[k] = clamp(tonumber(r[k]) or default, lo, hi) end
    if r.kind == "int" then
      num("dwell", 0.5, 2, 1)
      r.w = {}
      local any = false
      for _, name in ipairs(AREA_ORDER) do
        local w = tonumber(r["w_" .. name])
        if w and w > 0 then r.w[name], any = clamp(w, 0, 10), true end
      end
      if not any then r.w.outside, r.w_outside = 1, 1 end
      return r
    end
    if r.kind ~= "ext" or (r.family ~= "wide" and r.family ~= "close") then return nil end
    if r.family == "close" and not PARTS[r.part] then return nil end
    r.side = (tonumber(r.side) or 1) < 0 and -1 or 1
    num("which", 1, 2, 1)
    num("az", -360, 360, 150) num("el", -10, 60, 8) num("d", 0.05, 8, 3)
    r.dir = (tonumber(r.dir) or 1) < 0 and -1 or 1
    num("az_amp", 1, 45, 15) num("el_amp", 1, 15, 4) num("per", 10, 120, 40)
    num("d_amp", 0, 0.3, 0.06) num("ph1", 0, TAU, 0)
    num("frac", 0.3, 0.9, 0.6) num("shake", 0, 1, 0.3) num("aim", 2, 10, 4) num("bank", 0, 1, 0)
    return r
  end

  serialize_recipe = function(r)
    local keys = {}
    for k, v in pairs(r) do if type(v) ~= "table" then keys[#keys + 1] = k end end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      local v = r[k]
      parts[#parts + 1] = k .. "=" .. (type(v) == "number" and ("%.4g"):format(v) or tostring(v))
    end
    return table.concat(parts, ",")
  end

  local function parse_recipe(text)
    local r = {}
    for k, v in text:gmatch("([%w_]+)=([^,]*)") do r[k] = tonumber(v) or v end
    if r.kind ~= "ext" and r.kind ~= "int" then return nil end
    return sanitize(r)
  end

  -- Shots ---------------------------------------------------------------------

  local function define(def)
    def.rel = (def.kind == "ext")
    def.init = function(st)
      st.r = def.make()
      st.h, st.hv, st.p, st.pv = 0, 0, 0, 0
      st.lx, st.ly, st.lz, st.lxv, st.lyv, st.lzv = 0, 0, 0, 0, 0, 0
      if def.kind == "ext" then
        -- start already following the turn (if any), as the heading spring
        -- would after settling, so a shot in a turn starts smoothly
        local rate = A.yaw_rate or 0
        st.h, st.hv = wrap180(track_or_heading() - 2 * rate / 1.2), rate
      end
    end
    if def.kind == "ext" then
      def.place = function(st, o, dt) film(st.r, st, o, dt) end
    else
      def.head = function(st, o, dt) look_around(st.r, st, o, dt) end
    end
    return def
  end

  local function listed(def)
    define(def)
    SHOTS[def.id] = def
    SHOT_ORDER[#SHOT_ORDER + 1] = def.id
  end

  for _, w in ipairs({
    { "wide_rear", "Wide: rear quarter", 150, 8, 3.2 },
    { "wide_front", "Wide: front quarter", 35, 6, 3.0 },
    { "wide_side", "Wide: side profile", 90, 3, 3.4 },
    { "wide_high", "Wide: high", 130, 34, 3.4 },
    { "wide_low", "Wide: low front", 18, -1, 2.7 },
  }) do
    listed { id = w[1], name = w[2], kind = "ext", make = function() return new_wide(w[3], w[4], w[5]) end }
  end
  for _, part in ipairs(PART_ORDER) do
    listed { id = "close_" .. part, name = "Close-up: " .. PART_NAMES[part], kind = "ext",
             make = function() return new_close(part) end, available = function() return part_ok(part) end }
  end
  for _, plan in ipairs({
    { "scan", "Pilot's scan", { outside = 5, pfd = 4, nd = 2, glareshield = 1, eicas = 1, side = 1 } },
    { "panel", "Instrument panel", { pfd = 5, nd = 4, eicas = 4, glareshield = 1, outside = 1 } },
    { "overhead", "Overhead panel", { overhead = 9, glareshield = 1, outside = 1 } },
    { "throttle", "Throttle and pedestal", { pedestal = 7, fmc = 4, eicas = 1, outside = 1 } },
    { "window", "Side window", { side = 9, outside = 2, pfd = 1 } },
    { "autopilot", "Autopilot and FMC", { glareshield = 6, fmc = 5, pfd = 1, outside = 1 } },
  }) do
    listed { id = plan[1], name = plan[2], kind = "int", make = function() return sanitize(new_cockpit(plan[3])) end,
             available = (plan[1] == "overhead") and function() return area_ok("overhead") end or nil }
  end

  -- A shot from a recipe (random and saved shots).
  local function make_def(r, id)
    return define { id = id, kind = r.kind, name = (id:sub(1, 2) == "my") and "Saved shot" or "Random shot",
                    recipe = r, make = function() return r end }
  end

  -- Your saved shots.
  local my_count = 0
  local function add_my(r)
    my_count = my_count + 1
    local id = "my" .. my_count
    SHOTS[id] = make_def(r, id)
    MY[#MY + 1] = { id = id, recipe = r }
    return id
  end
  for _, text in ipairs(MY_RAW) do
    local r = parse_recipe(text)
    if r then add_my(r) end
  end

  RS.parse, RS.make_def, RS.add_my = parse_recipe, make_def, add_my
  RS.exterior = function() return (random() < 0.5) and new_wide() or new_close() end
  RS.cockpit = function() return sanitize(new_cockpit()) end
end

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
  last_id = "chase", last_listed = "chase",
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

-- Zoom is smooth, like X-Plane's own: every input (keys, wheel, commands)
-- moves the zoom you ask for, and the camera glides to it. Holding a zoom key
-- or button zooms at a steady rate; ZOOM.hold is its direction times speed.
local ZOOM = { log = 0, vel = 0, hold = 0 }
local ZOOM_RATE = 0.6                  -- per second, in log zoom (about x1.8 a second)
local ZOOM_STEP = 0.04                 -- what a quick tap or a wheel click adds
local function zoom_snap() ZOOM.log, ZOOM.vel = math.log(nudge.zoom), 0 end
local function zoom_hold(dir, fast)
  if dir ~= 0 and ZOOM.hold == 0 then zoom_by(exp(dir * ZOOM_STEP)) end
  ZOOM.hold = dir * (fast and 3 or 1)
end

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

-- Keep a camera outside a box around the airframe (half span across, half
-- length fore and aft, with a margin). One that strays in is pushed out
-- sideways or fore and aft - never down, where the ground would push it
-- back up - so it can never pass through the aircraft.
local function keep_outside(o)
  local bx, by, bz = world_to_body(o.x - A.x, o.y - A.y, o.z - A.z, A.psi, A.the, A.phi)
  local ex, ey, ez = RS.box()
  if abs(bx) < ex and abs(by) < ey and abs(bz) < ez then
    if abs(bx) + abs(bz) < 1e-3 then bx = 1e-3 end
    local k = min(ex / max(abs(bx), 1e-6), ez / max(abs(bz), 1e-6))
    local wx, wy, wz = body_to_world(bx * k, by, bz * k, A.psi, A.the, A.phi)
    o.x, o.y, o.z = A.x + wx, A.y + wy, A.z + wz
  end
end

local function run_shot(def, st, o, dt)
  o.tx, o.hdg, o.pit, o.rol, o.zoom = nil, 0, 0, 0, 1
  def.place(st, o, dt)

  if o.tx and (nudge.yaw ~= 0 or nudge.up ~= 0) then
    local ox, oy, oz = heading_to_world(o.x - A.x, o.y - A.y, o.z - A.z, nudge.yaw)
    o.x, o.y, o.z = A.x + ox, A.y + oy + nudge.up * A.R, A.z + oz
  end

  keep_outside(o)
  local gy = terrain_y(o.x, o.y, o.z)
  if gy and o.y < gy + 1.2 then o.y = gy + 1.2 end

  if o.tx then
    local h, p = look_angles(o.tx - o.x, o.ty - o.y, o.tz - o.z)
    local aim = (st.r and st.r.aim) or def.aim
    if aim then
      if not st.ah then st.ah, st.ahv, st.ap, st.apv = h, 0, p, 0 end
      st.ah, st.ahv = spring_angle(st.ah, st.ahv, h, aim, 1, dt)
      st.ap, st.apv = spring(st.ap, st.apv, p, aim, 1, dt)
      h, p = st.ah, st.ap
    end
    o.hdg, o.pit = h, p
  else
    o.hdg, o.pit = o.hdg + nudge.yaw, o.pit + nudge.up * 10
  end

  -- Handheld camera: slow drift plus a little jitter, calmer on long lenses.
  local shake = S.shake * ((st.r and st.r.shake) or def.shake or 0)
  if shake > 0 then
    local k, t = shake / sqrt(max(o.zoom, 1)), st.t
    o.hdg = o.hdg + k * 0.9 * (wob(t * 1.6, 1) + 0.25 * sin(t * 11.3))
    o.pit = o.pit + k * 0.7 * (wob(t * 1.9, 7) + 0.25 * sin(t * 13.1 + 1))
    o.rol = o.rol + k * 0.6 * wob(t * 1.3, 13)
  end
  o.zoom = o.zoom * exp(ZOOM.log)
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
  ZOOM.log, ZOOM.vel = spring(ZOOM.log, ZOOM.vel, math.log(nudge.zoom), 9, 1, dt)

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
        keep_outside(o)                  -- the glide goes round the aircraft, never through it
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
    zoom_hold(z.dir, z.rate > 1)
  elseif phase == 2 then
    zoom_hold(0)
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
       then
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
  if id:sub(1, 3) ~= "rnd" then cine.last_listed = id end
  use_adjustments(id)
  zoom_snap()
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
  if not SHOTS[id] then id = "chase" end
  if not cine.active and not start_session() then return end
  begin_shot(id, "manual")
end

local function in_cycle(def)
  return shot_available(def) and (def.kind == "ext" or S.cockpit_in_cycle)
end

-- The random shot on screen (each new one replaces the last; Save keeps it).
local random_n, last_random = 0, nil

local function remember_random(r)
  random_n = random_n + 1
  local id = "rnd" .. random_n
  SHOTS[id] = RS.make_def(r, id)
  if last_random then
    SHOTS[last_random], adjustments[last_random] = nil, nil
  end
  last_random = id
  return id
end

local function cockpit_ok() return (HAS_HEAD and CMD.cockpit and not vr_on()) and true or false end

local function act_random(kind)
  if not kind then
    kind = (cockpit_ok() and S.cockpit_in_cycle and random() < 0.25) and "int" or "ext"
  end
  if kind == "int" and not cockpit_ok() then return end
  act_shot(remember_random(kind == "int" and RS.cockpit() or RS.exterior()))
end

local function cycle_ids()
  local ids = {}
  for _, id in ipairs(SHOT_ORDER) do ids[#ids + 1] = id end
  for _, m in ipairs(MY) do ids[#ids + 1] = m.id end
  return ids
end

local function act_step(step)
  if not cine.active then return act_shot(cine.last_id) end   -- off: start with your last shot
  local ids = cycle_ids()
  local cur, n = cine.def and cine.def.id, #ids
  if cur and cur:sub(1, 3) == "rnd" then cur = cine.last_listed end   -- from a random shot: carry on the list
  local idx = (step > 0) and 0 or 1
  for i, id in ipairs(ids) do if id == cur then idx = i end end
  for _ = 1, n do
    idx = (idx - 1 + step) % n + 1
    if in_cycle(SHOTS[ids[idx]]) then break end
  end
  act_shot(ids[idx])
end

local function act_save()
  local def = cine.active and cine.def
  if not (def and def.recipe) or def.id:sub(1, 2) == "my" or def.saved_as then return end
  local r = RS.parse(serialize_recipe(cine.st.r or def.recipe))
  if not r then return end
  local id = RS.add_my(r)
  def.saved_as = id
  adjustments[id] = { yaw = nudge.yaw, up = nudge.up, zoom = nudge.zoom }
  settings_dirty = true
end

local function act_delete(id)
  for i, m in ipairs(MY) do
    if m.id == id then
      table.remove(MY, i)
      if SHOTS[id] then SHOTS[id].deleted = true end
      if not (cine.def and cine.def.id == id) then SHOTS[id] = nil end
      settings_dirty = true
      return
    end
  end
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
M.random_shot = function(kind) request(function() act_random(kind) end) end
M.save_shot = function() request(act_save) end
M.delete_shot = function(id) request(function() act_delete(id) end) end

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
    if cine.active and cine.def and cine.def.kind == "int" then native_zoom(dir) else zoom_by(exp(dir * ZOOM_RATE * dt)) end
  end
end
M.reset_nudge = reset_nudge

local ACTIONS = {
  { id = "toggle", name = "Camera on/off", run = M.toggle },
  { id = "next", name = "Next view", run = M.next_shot },
  { id = "prev", name = "Previous view", run = M.previous_shot },
  { id = "random", name = "New random view", run = function() M.random_shot() end },
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
    if not pressed then zoom_hold(0) end
    if filming_outside() then
      if pressed then zoom_hold(dir, shift) end
      RESUME_KEY = true
    end
  end
end

-- The mouse wheel zooms the exterior camera; otherwise it is X-Plane's.
local function on_wheel()
  if filming_outside() and (tonumber(MOUSE_WHEEL_NUMBER) or 0) == 0 then
    zoom_by(exp(ZOOM_STEP * 2 * (tonumber(MOUSE_WHEEL_CLICKS) or 0)))
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
  if ZOOM.hold ~= 0 then
    if filming_outside() then zoom_by(exp(ZOOM.hold * ZOOM_RATE * dt)) else ZOOM.hold = 0 end
  end
end

-- -----------------------------------------------------------------------------
-- Per-frame work
-- -----------------------------------------------------------------------------

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
  elseif cine.restore_frames > 0 then
    cine.restore_frames = cine.restore_frames - 1
    if B and in_cockpit then write_head(B[1], B[2], B[3], B[4], B[5], B[6]) end
  end

end

local function on_frame()
  if frame.ticked ~= frame.id then
    frame.ticked = frame.id
    tick()
  end
end

-- Nothing is drawn over the picture: the draw callback only keeps the
-- script running while the sim is paused, when flight loops may not run.
local function on_draw()
  if frame.ticked ~= frame.id then
    frame.ticked = frame.id
    local ok, err = pcall(tick)
    if not ok then log("error: " .. tostring(err)) end
  end
  frame.id = frame.id + 1
end

-- -----------------------------------------------------------------------------
-- The window: kept small
-- -----------------------------------------------------------------------------

local wnd = nil

local COL_ON = 0xFF3C9A3C        -- imgui colours are 0xAABBGGRR
local COL_HINT = 0xFF9A9A9A
local COL_ASK = 0xFFE0C080

local function text(colour, s)
  imgui.PushStyleColor(imgui.constant.Col.Text, colour)
  imgui.TextUnformatted(s)
  imgui.PopStyleColor()
end

local function slider(label, key, lo, hi, fmt)
  local changed, v = imgui.SliderFloat(label, S[key], lo, hi, fmt)
  if changed then S[key], settings_dirty = v, true end
  return changed
end

local function build_window()
  local on, def = cine.active, cine.active and cine.def
  if on then imgui.PushStyleColor(imgui.constant.Col.Button, COL_ON) end
  if imgui.Button(on and "Camera ON" or "Camera OFF", 110, 30) then M.toggle() end
  if on then imgui.PopStyleColor() end
  imgui.SameLine()
  if imgui.Button("< Previous", 95, 30) then M.previous_shot() end
  imgui.SameLine()
  if imgui.Button("Next >", 95, 30) then M.next_shot() end
  imgui.SameLine()
  if imgui.Button("Random", 80, 30) then M.random_shot() end
  imgui.SameLine()
  local saved_shot = def and def.id:sub(1, 2) == "my" and not def.deleted
  local can_save = def and def.recipe and not def.saved_as and def.id:sub(1, 3) == "rnd"
  if imgui.Button(saved_shot and "Delete" or (def and def.saved_as) and "Saved" or "Save", 70, 30) then
    if saved_shot then M.delete_shot(def.id) elseif can_save then M.save_shot() end
  end
  if cine.message and not on then text(COL_HINT, cine.message) end

  imgui.Separator()
  for _, a in ipairs(ACTIONS) do
    imgui.TextUnformatted(a.name)
    imgui.SameLine(140)
    if capture.action == a.id then
      text(COL_ASK, "Press a key or joystick button...")
    else
      imgui.TextUnformatted(binding_label(BIND[a.id]))
    end
    imgui.SameLine(370)
    if imgui.Button((capture.action == a.id and "Cancel##" or "Assign##") .. a.id, 70, 22) then
      if capture.action == a.id then capture.action = nil else start_capture(a.id) end
    end
    imgui.SameLine()
    if imgui.Button("Clear##" .. a.id, 60, 22) then
      BIND[a.id], settings_dirty = nil, true
    end
  end
  if capture.msg then text(COL_HINT, capture.msg) end

  imgui.Separator()
  slider("Camera distance", "distance", 0.5, 3, "%.2fx")
  slider("Camera shake", "shake", 0, 1, "%.2f")
  slider("Shot transition (s)", "blend_time", 0, 5, "%.1f")
  slider("Cockpit head movement", "head_motion", 0, 1, "%.2f")
  local changed, v = imgui.SliderFloat("Aircraft size", SIZE.scales[SIZE.key] or 1, 0.4, 2.5, "%.2fx")
  if changed then
    SIZE.scales[SIZE.key], settings_dirty = v, true
    measure_aircraft()
  end
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
  wnd = float_wnd_create(560, 330, 1, true)
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
M._random = function()
  return { MY = MY, subject = RS.subject, box = RS.box, serialize = serialize_recipe, parse = RS.parse,
           exterior = RS.exterior, cockpit = RS.cockpit,
           start = function(r) request(function() act_shot(remember_random(r)) end) end }
end

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
command("toggle_window", "settings window", "CinematicViews.toggle_window()")
command("reset_adjustments", "reset orbit, height and zoom adjustments", "CinematicViews.reset_nudge()")
command("random_view", "new random view", "CinematicViews.random_shot()")
command("random_exterior", "new random exterior view", "CinematicViews.random_shot('ext')")
command("random_cockpit", "new random cockpit view", "CinematicViews.random_shot('int')")
command("save_shot", "save the current random shot to your shots", "CinematicViews.save_shot()")
hold_command("orbit_left", "move the camera around the aircraft to the left (hold)", "CinematicViews.nudge('yaw', -1)")
hold_command("orbit_right", "move the camera around the aircraft to the right (hold)", "CinematicViews.nudge('yaw', 1)")
hold_command("camera_up", "raise the camera (hold)", "CinematicViews.nudge('up', 1)")
hold_command("camera_down", "lower the camera (hold)", "CinematicViews.nudge('up', -1)")
hold_command("zoom_in", "zoom in (hold)", "CinematicViews.nudge('zoom', 1)")
hold_command("zoom_out", "zoom out (hold)", "CinematicViews.nudge('zoom', -1)")
for _, id in ipairs(SHOT_ORDER) do
  command("shot_" .. id, SHOTS[id].name .. " shot", "CinematicViews.shot('" .. id .. "')")
end

if add_macro then add_macro("Cinematic Views", "CinematicViews.toggle_window()") end

if not CMD.external then log("no exterior view command found - exterior shots are off.") end
if not (CMD.cockpit and HAS_HEAD) then log("no 3D cockpit view - cockpit shots are off.") end
log("v" .. VERSION .. " ready - Plugins > FlyWithLua > FlyWithLua Macros > Cinematic Views.")
