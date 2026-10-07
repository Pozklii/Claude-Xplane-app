--[[
  CineCam - automatic cinematic camera for X-Plane 12 (FlyWithLua NG / NG+)

  Cycles through orbit, chase, flyby and ground-spot shots around your aircraft.
  Unlike most camera scripts it keeps running when X-Plane takes the camera
  away (e.g. when you take a screenshot): it simply grabs the camera back a
  moment later and continues the current shot.

  Install:
    Copy this file to  X-Plane 12/Resources/plugins/FlyWithLua/Scripts/

  Use:
    Settings > Keyboard, search "CineCam" and bind keys to:
      FlyWithLua/CineCam/toggle      start / stop the cinematic camera
      FlyWithLua/CineCam/next_shot   skip to the next shot
      FlyWithLua/CineCam/screenshot  take a screenshot and resume instantly
    Or use the menu: Plugins > FlyWithLua > FlyWithLua Macros > CineCam.

  To leave the camera, use the toggle command. Changing views with the normal
  view keys while CineCam is on only interrupts it briefly, the same as a
  screenshot does.
--]]

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------

local CFG = {
  RESUME_DELAY = 0.25,   -- seconds to wait before grabbing the camera back
  SCALE = 1.0,           -- multiplies all camera distances; try 2-3 for airliners
  MIN_AGL = 1.8,         -- never put the camera lower than this above the ground (m)
  MAX_ZOOM = 4.0,        -- maximum telephoto zoom for flyby and spot shots

  -- Relative chance of each shot being picked (0 disables it)
  SHOTS = { orbit = 3, chase = 3, flyby = 3, spot = 2 },

  ORBIT = { radius = { 35, 70 }, height = { -5, 20 }, speed = { 4, 9 }, duration = { 14, 22 } },
  CHASE = { duration = { 10, 16 }, lag = 1.2 },    -- lag: seconds the camera takes to follow turns
  FLYBY = { lead = { 4, 7 }, side = { 25, 70 }, height = { -8, 15 }, zoom_ref = 60 },
  SPOT  = { lead = { 6, 12 }, side = { 120, 350 }, duration = { 14, 20 }, zoom_ref = 120 },

  -- Chase camera positions relative to the aircraft: { right, up, forward } in metres
  CHASE_PRESETS = {
    { 0, 6, -30 },      -- behind, above
    { -12, 2, -22 },    -- behind, left, low
    { 18, 1, 4 },       -- right side
    { 0, -2, -40 },     -- low behind
  },

  -- View to switch to when CineCam is turned off ("" to stay in free camera)
  EXIT_VIEW_COMMAND = "sim/view/3d_cockpit_cmnd_look",
}

-------------------------------------------------------------------------------
-- X-Plane SDK access through LuaJIT FFI
-------------------------------------------------------------------------------

local ffi = require("ffi")

-- Each declaration is separate so a clash with another script's cdef is harmless.
local function cdef(s) pcall(ffi.cdef, s) end
cdef [[ typedef struct { float x, y, z, pitch, heading, roll, zoom; } cinecam_campos_t; ]]
cdef [[ typedef int (*cinecam_ctrl_f)(cinecam_campos_t *pos, int losing, void *ref); ]]
cdef [[ void XPLMControlCamera(int inHowLong, cinecam_ctrl_f inControlFunc, void *inRefcon); ]]
cdef [[ void XPLMDontControlCamera(void); ]]
cdef [[ int XPLMIsCameraBeingControlled(int *outCameraControlDuration); ]]
cdef [[ void *XPLMFindDataRef(const char *inDataRefName); ]]
cdef [[ float XPLMGetDataf(void *inDataRef); ]]
cdef [[ double XPLMGetDatad(void *inDataRef); ]]
cdef [[ void *XPLMFindCommand(const char *inName); ]]
cdef [[ void XPLMCommandOnce(void *inCommand); ]]

local XPLM_LIB = {
  IBM = "XPLM_64",
  LIN = "Resources/plugins/XPLM_64.so",
  APL = "Resources/plugins/XPLM.framework/XPLM",
}
local XPLM = ffi.load(XPLM_LIB[SYSTEM])

local xplm_ControlCameraForever = 2

local function find_dataref(name)
  local ref = XPLM.XPLMFindDataRef(name)
  if ref == nil then error("CineCam: dataref not found: " .. name) end
  return ref
end

local function find_command(name)
  if name == nil or name == "" then return nil end
  local cmd = XPLM.XPLMFindCommand(name)
  if cmd == nil then logMsg("CineCam: command not found: " .. name) end
  return cmd
end

local DR = {
  x   = find_dataref("sim/flightmodel/position/local_x"),
  y   = find_dataref("sim/flightmodel/position/local_y"),
  z   = find_dataref("sim/flightmodel/position/local_z"),
  vx  = find_dataref("sim/flightmodel/position/local_vx"),
  vy  = find_dataref("sim/flightmodel/position/local_vy"),
  vz  = find_dataref("sim/flightmodel/position/local_vz"),
  hdg = find_dataref("sim/flightmodel/position/psi"),
  agl = find_dataref("sim/flightmodel/position/y_agl"),
  gs  = find_dataref("sim/flightmodel/position/groundspeed"),
  dt  = find_dataref("sim/operation/misc/frame_rate_period"),
}

local CMD = {
  free_camera = find_command("sim/view/free_camera"),
  screenshot  = find_command("sim/operation/screenshot"),
  exit_view   = find_command(CFG.EXIT_VIEW_COMMAND),
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local sin, cos, rad, deg = math.sin, math.cos, math.rad, math.deg

local function rnd(range) return range[1] + math.random() * (range[2] - range[1]) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function wrap180(a) return (a + 180) % 360 - 180 end
local function either_side() return math.random() < 0.5 and -1 or 1 end

-- Aircraft state, refreshed every frame and every camera callback
local AC = { x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, hdg = 0, agl = 0, gs = 0, ground = 0 }

local function read_aircraft()
  AC.x = XPLM.XPLMGetDatad(DR.x)
  AC.y = XPLM.XPLMGetDatad(DR.y)
  AC.z = XPLM.XPLMGetDatad(DR.z)
  AC.vx = XPLM.XPLMGetDataf(DR.vx)
  AC.vy = XPLM.XPLMGetDataf(DR.vy)
  AC.vz = XPLM.XPLMGetDataf(DR.vz)
  AC.hdg = XPLM.XPLMGetDataf(DR.hdg)
  AC.agl = XPLM.XPLMGetDataf(DR.agl)
  AC.gs = XPLM.XPLMGetDataf(DR.gs)
  AC.ground = AC.y - AC.agl
end

-- Point the camera at (cx, cy, cz) towards the aircraft.
-- X-Plane local coordinates: +x east, +y up, +z south. Heading 0 = north.
local function aim(pos, cx, cy, cz, zoom)
  local dx, dy, dz = AC.x - cx, AC.y - cy, AC.z - cz
  pos.x, pos.y, pos.z = cx, cy, cz
  pos.heading = deg(math.atan2(dx, -dz))
  pos.pitch = deg(math.atan2(dy, math.sqrt(dx * dx + dz * dz)))
  pos.roll = 0
  pos.zoom = zoom or 1
end

local function distance_to_aircraft(cx, cy, cz)
  local dx, dy, dz = AC.x - cx, AC.y - cy, AC.z - cz
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Fixed camera point placed ahead of the aircraft's track, off to one side.
local function place_ahead(s, lead, side)
  local hs = math.sqrt(AC.vx * AC.vx + AC.vz * AC.vz)
  local dirx, dirz
  if hs > 1 then
    dirx, dirz = AC.vx / hs, AC.vz / hs
  else
    dirx, dirz = sin(rad(AC.hdg)), -cos(rad(AC.hdg))
  end
  -- right of travel direction is (-dirz, dirx)
  s.cx = AC.x + AC.vx * lead - dirz * side
  s.cz = AC.z + AC.vz * lead + dirx * side
  s.ground = AC.ground
end

-------------------------------------------------------------------------------
-- Shots: start(s) sets up a new shot, pose(s, pos) fills in the camera
-------------------------------------------------------------------------------

local SHOTS = {}

SHOTS.orbit = {
  start = function(s)
    local o = CFG.ORBIT
    s.dur = rnd(o.duration)
    s.angle = math.random() * 360
    s.radius = rnd(o.radius) * CFG.SCALE
    s.height = rnd(o.height) * CFG.SCALE
    s.rate = rnd(o.speed) * either_side()
  end,
  pose = function(s, pos)
    local a = rad(s.angle + s.rate * s.t)
    local cy = math.max(AC.y + s.height, AC.ground + CFG.MIN_AGL)
    aim(pos, AC.x + sin(a) * s.radius, cy, AC.z - cos(a) * s.radius)
  end,
}

SHOTS.chase = {
  start = function(s)
    s.dur = rnd(CFG.CHASE.duration)
    s.offset = CFG.CHASE_PRESETS[math.random(#CFG.CHASE_PRESETS)]
    s.hdg = AC.hdg
  end,
  -- heading follows the aircraft with a lag, so turns swing the camera round
  frame = function(s, dt)
    local alpha = 1 - math.exp(-dt / CFG.CHASE.lag)
    s.hdg = (s.hdg + wrap180(AC.hdg - s.hdg) * alpha) % 360
  end,
  pose = function(s, pos)
    local h = rad(s.hdg)
    local fx, fz = sin(h), -cos(h)      -- forward
    local rx, rz = cos(h), sin(h)       -- right
    local right, up, fwd = s.offset[1] * CFG.SCALE, s.offset[2] * CFG.SCALE, s.offset[3] * CFG.SCALE
    local cx = AC.x + rx * right + fx * fwd
    local cz = AC.z + rz * right + fz * fwd
    local cy = math.max(AC.y + up, AC.ground + CFG.MIN_AGL)
    aim(pos, cx, cy, cz)
  end,
}

SHOTS.flyby = {
  start = function(s)
    local f = CFG.FLYBY
    local lead = rnd(f.lead)
    s.dur = lead * 2
    place_ahead(s, lead, rnd(f.side) * CFG.SCALE * either_side())
    if AC.agl < 5 then
      s.cy = AC.ground + CFG.MIN_AGL
    else
      s.cy = math.max(AC.y + AC.vy * lead + rnd(f.height) * CFG.SCALE, s.ground + CFG.MIN_AGL)
    end
  end,
  pose = function(s, pos)
    local zoom = clamp(distance_to_aircraft(s.cx, s.cy, s.cz) / (CFG.FLYBY.zoom_ref * CFG.SCALE), 1, CFG.MAX_ZOOM)
    aim(pos, s.cx, s.cy, s.cz, zoom)
  end,
}

SHOTS.spot = {
  start = function(s)
    local p = CFG.SPOT
    s.dur = rnd(p.duration)
    place_ahead(s, rnd(p.lead), rnd(p.side) * CFG.SCALE * either_side())
    s.cy = s.ground + CFG.MIN_AGL
  end,
  pose = function(s, pos)
    local zoom = clamp(distance_to_aircraft(s.cx, s.cy, s.cz) / (CFG.SPOT.zoom_ref * CFG.SCALE), 1, CFG.MAX_ZOOM)
    aim(pos, s.cx, s.cy, s.cz, zoom)
  end,
}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local C = {
  enabled = false,       -- the user wants the camera on
  have_control = false,  -- X-Plane currently gives us the camera
  lost_time = 0,         -- seconds since we lost the camera
  resume_now = false,    -- skip RESUME_DELAY once (after our own screenshot)
}

local S = { name = nil, t = 0, dur = 0 }  -- current shot

local function pick_shot()
  local choices, total = {}, 0
  for name, weight in pairs(CFG.SHOTS) do
    local usable = SHOTS[name] and weight > 0 and name ~= S.name
    if name == "flyby" and AC.gs < 15 then usable = false end
    if usable then
      choices[#choices + 1] = { name, weight }
      total = total + weight
    end
  end
  if total == 0 then return S.name or "orbit" end
  local r = math.random() * total
  for _, c in ipairs(choices) do
    r = r - c[2]
    if r <= 0 then return c[1] end
  end
  return choices[#choices][1]
end

local function start_shot(name)
  S = { name = name, t = 0, dur = 10 }
  SHOTS[name].start(S)
end

-------------------------------------------------------------------------------
-- Camera control
-------------------------------------------------------------------------------

local function camera_body(pos, losing)
  if losing ~= 0 then
    C.have_control = false
    C.lost_time = 0
    return 0
  end
  if not C.enabled then return 0 end
  if pos == nil then return 1 end
  read_aircraft()
  SHOTS[S.name].pose(S, pos)
  return 1
end

-- X-Plane calls this every time it draws. Errors must not escape into C.
local camera_callback = ffi.cast("cinecam_ctrl_f", function(pos, losing, ref)
  local ok, result = pcall(camera_body, pos, losing)
  if ok then return result end
  logMsg("CineCam error: " .. tostring(result))
  C.enabled = false
  C.have_control = false
  return 0
end)

local function grab_camera()
  if CMD.free_camera ~= nil then XPLM.XPLMCommandOnce(CMD.free_camera) end
  XPLM.XPLMControlCamera(xplm_ControlCameraForever, camera_callback, nil)
  C.have_control = true
  C.lost_time = 0
  C.resume_now = false
end

-------------------------------------------------------------------------------
-- Public functions (global, used by commands, macro and frame loop)
-------------------------------------------------------------------------------

function cinecam_enable()
  if C.enabled then return end
  math.randomseed(os.time())
  read_aircraft()
  C.enabled = true
  start_shot(pick_shot())
  grab_camera()
end

local function release_camera()
  local was_enabled = C.enabled
  C.enabled = false
  if C.have_control then XPLM.XPLMDontControlCamera() end
  C.have_control = false
  return was_enabled
end

function cinecam_disable()
  if release_camera() and CMD.exit_view ~= nil then XPLM.XPLMCommandOnce(CMD.exit_view) end
end

function cinecam_shutdown()
  release_camera()
end

function cinecam_toggle()
  if C.enabled then cinecam_disable() else cinecam_enable() end
end

function cinecam_next_shot()
  if not C.enabled then return end
  start_shot(pick_shot())
end

function cinecam_screenshot()
  if C.enabled then C.resume_now = true end
  if CMD.screenshot ~= nil then XPLM.XPLMCommandOnce(CMD.screenshot) end
end

function cinecam_on_frame()
  if not C.enabled then return end
  local dt = clamp(XPLM.XPLMGetDataf(DR.dt), 0, 0.1)
  read_aircraft()

  S.t = S.t + dt
  if S.t >= S.dur then start_shot(pick_shot()) end
  if SHOTS[S.name].frame then SHOTS[S.name].frame(S, dt) end

  -- Something (a screenshot, a view key) took the camera: take it back.
  if C.have_control and XPLM.XPLMIsCameraBeingControlled(nil) == 0 then
    C.have_control = false
    C.lost_time = 0
  end
  if not C.have_control then
    C.lost_time = C.lost_time + dt
    if C.resume_now or C.lost_time >= CFG.RESUME_DELAY then grab_camera() end
  end
end

create_command("FlyWithLua/CineCam/toggle", "CineCam: start / stop cinematic camera", "cinecam_toggle()", "", "")
create_command("FlyWithLua/CineCam/next_shot", "CineCam: next shot", "cinecam_next_shot()", "", "")
create_command("FlyWithLua/CineCam/screenshot", "CineCam: screenshot and keep filming", "cinecam_screenshot()", "", "")

add_macro("CineCam: cinematic camera", "cinecam_enable()", "cinecam_disable()", "deactivate")

do_every_frame("cinecam_on_frame()")

-- Release the camera before FlyWithLua reloads scripts, or X-Plane would call a dead callback.
do_on_exit("cinecam_shutdown()")
