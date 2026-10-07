--[[
  CineCam - automatic cinematic camera for X-Plane 12 (FlyWithLua NG / NG+)

  Slowly sweeps the camera around your aircraft, close in, in one continuous
  move after another (no cuts). The camera follows the aircraft's heading with
  a lag, like X-Plane's external chase views.
  Unlike most camera scripts it keeps running when X-Plane takes the camera
  away (e.g. when you take a screenshot): it simply grabs the camera back a
  moment later and carries on with the same move.

  Install:
    Copy this file to  X-Plane 12/Resources/plugins/FlyWithLua/Scripts/

  Use:
    Settings > Keyboard, search "CineCam" and bind keys to:
      FlyWithLua/CineCam/toggle      start / stop the cinematic camera
      FlyWithLua/CineCam/next_shot   start a new camera move now
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

  -- Each move glides the camera from where it is to a new spot around the
  -- aircraft. Angles are measured from the nose: 0 = in front, 180 = behind.
  MOVE_TIME   = { 14, 24 },    -- seconds per move
  ANGLE_STEP  = { 40, 140 },   -- degrees swept per move
  DISTANCE    = { 18, 38 },    -- metres from the aircraft
  HEIGHT      = { -3, 10 },    -- metres above (or below) the aircraft
  HEADING_LAG = 2.0,           -- seconds the camera takes to follow turns

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

-------------------------------------------------------------------------------
-- The sweep: one continuous, eased move after another, relative to the
-- aircraft's (lagged) heading so it stays framed like an external view.
-------------------------------------------------------------------------------

local function smoothstep(x) return x * x * (3 - 2 * x) end
local function lerp(a, b, x) return a + (b - a) * x end

local C = {
  enabled = false,       -- the user wants the camera on
  have_control = false,  -- X-Plane currently gives us the camera
  lost_time = 0,         -- seconds since we lost the camera
  resume_now = false,    -- skip RESUME_DELAY once (after our own screenshot)
}

-- Current camera placement around the aircraft, plus the move in progress
local M = { angle = 160, dist = 25, height = 4, hdg = 0, t = 0, dur = 1 }

local function new_move()
  M.from = { angle = M.angle, dist = M.dist, height = M.height }
  M.to = {
    angle = M.angle + rnd(CFG.ANGLE_STEP) * either_side(),
    dist = rnd(CFG.DISTANCE) * CFG.SCALE,
    height = rnd(CFG.HEIGHT) * CFG.SCALE,
  }
  M.t = 0
  M.dur = rnd(CFG.MOVE_TIME)
end

local function start_sweep()
  M.hdg = AC.hdg
  M.angle = math.random() * 360
  M.dist = rnd(CFG.DISTANCE) * CFG.SCALE
  M.height = rnd(CFG.HEIGHT) * CFG.SCALE
  new_move()
end

local function update_sweep(dt)
  M.t = M.t + dt
  if M.t >= M.dur then
    M.angle, M.dist, M.height = M.to.angle, M.to.dist, M.to.height
    new_move()
  end
  local x = smoothstep(clamp(M.t / M.dur, 0, 1))
  M.angle = lerp(M.from.angle, M.to.angle, x)
  M.dist = lerp(M.from.dist, M.to.dist, x)
  M.height = lerp(M.from.height, M.to.height, x)

  local alpha = 1 - math.exp(-dt / CFG.HEADING_LAG)
  M.hdg = (M.hdg + wrap180(AC.hdg - M.hdg) * alpha) % 360
end

local function sweep_pose(pos)
  local a = rad(M.hdg + M.angle)
  local cx = AC.x + sin(a) * M.dist
  local cz = AC.z - cos(a) * M.dist
  local cy = math.max(AC.y + M.height, AC.ground + CFG.MIN_AGL)
  aim(pos, cx, cy, cz)
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
  sweep_pose(pos)
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
  start_sweep()
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
  new_move()
end

function cinecam_screenshot()
  if C.enabled then C.resume_now = true end
  if CMD.screenshot ~= nil then XPLM.XPLMCommandOnce(CMD.screenshot) end
end

function cinecam_on_frame()
  if not C.enabled then return end
  local dt = clamp(XPLM.XPLMGetDataf(DR.dt), 0, 0.1)
  read_aircraft()

  update_sweep(dt)

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
create_command("FlyWithLua/CineCam/next_shot", "CineCam: start a new camera move", "cinecam_next_shot()", "", "")
create_command("FlyWithLua/CineCam/screenshot", "CineCam: screenshot and keep filming", "cinecam_screenshot()", "", "")

add_macro("CineCam: cinematic camera", "cinecam_enable()", "cinecam_disable()", "deactivate")

do_every_frame("cinecam_on_frame()")

-- Release the camera before FlyWithLua reloads scripts, or X-Plane would call a dead callback.
do_on_exit("cinecam_shutdown()")
