--[[
    Cinematic View for X-Plane 12
    A FlyWithLua NG+ script

    A self-directing camera in the style of the Need for Speed and Forza
    Horizon attract modes: it cuts between chase, trackside, spotter, orbit,
    crane, tracking, wheel, mounted and drone shots outside the aircraft, and
    pilot's-eye, over-the-shoulder, side window and panel shots inside the
    cockpit, with letterbox bars and fades. Shots suit what the aircraft is
    doing (runway-level shots on takeoff and landing, air-to-air in cruise),
    liftoff and touchdown get shots of their own, and cameras shake with
    turbulence, runway rumble and touchdowns.

    It can be switched on and off by hand, and it starts by itself after a
    while with no keyboard, mouse or joystick input (any input ends it again).
    X-Plane's zoom keys (+ and -) zoom the cinematic camera.

    Install: copy this file to X-Plane 12/Resources/plugins/FlyWithLua/Scripts/

    Everything is in one window: Plugins > FlyWithLua > FlyWithLua Macros >
    Cinematic View. It starts and stops the cinematic, holds all the settings
    and lets you set a key for each action. Settings and keys are saved next
    to this script in cinematic_view.ini.

    Each action is also an X-Plane command, for joystick buttons (Settings >
    Joystick, search for "cinematic"):
        FlyWithLua/cinematic_view/toggle       start/stop
        FlyWithLua/cinematic_view/next_shot    cut to the next shot
        FlyWithLua/cinematic_view/toggle_afk   auto-start when away on/off
        FlyWithLua/cinematic_view/cycle_mode   mixed / outside / cockpit shots
        FlyWithLua/cinematic_view/zoom_in      zoom in (hold)
        FlyWithLua/cinematic_view/zoom_out     zoom out (hold)
        FlyWithLua/cinematic_view/settings     show/hide the window

    How it moves the camera: outside shots take control of X-Plane's camera
    through the plugin SDK (XPLMControlCamera, called through LuaJIT's FFI),
    and cockpit shots move the pilot's head in the 3D cockpit. If the SDK
    library can't be loaded, outside shots fall back to X-Plane's own chase,
    circle and flyby views.
--]]

local VERSION = "1.2"

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

local DEFAULTS = {
    afk_enabled = true,           -- start by itself when you're away
    afk_timeout = 120,            -- seconds without input before it starts
    afk_when_paused = true,       -- also start while the sim is paused
    mode = "mixed",               -- "mixed", "outside" or "cockpit"
    cockpit_share = 30,           -- % of shots in the cockpit in mixed mode
    shot_min = 7,                 -- shortest shot, seconds
    shot_max = 14,                -- longest shot, seconds
    camera_speed = 1.0,           -- how fast cameras move, pan and orbit (0.25 to 2.5)
    letterbox = true,             -- cinema bars top and bottom
    fades = true,                 -- dip to black between some shots
    shake = true,                 -- cameras shake with turbulence, runway rumble and touchdowns
    manual_exit_on_input = false, -- any input also ends a cinematic you started yourself
    joystick_deadband = 0.03,     -- how far an axis must move to count as input
    -- keys, as "<virtual key> <modifiers> <name>" (modifiers: 1 shift, 2 ctrl, 4 alt); empty for none
    bind_toggle = "",
    bind_next_shot = "",
    bind_toggle_afk = "",
    bind_cycle_mode = "",
    bind_zoom_in = "",
    bind_zoom_out = "",
    bind_settings = "",
}

local MODES = { "mixed", "outside", "cockpit" }
local MODE_LABELS = { mixed = "Mixed", outside = "Outside only", cockpit = "Cockpit only" }

local settings = {}
for k, v in pairs(DEFAULTS) do settings[k] = v end

local function settings_path()
    local dir = SCRIPT_DIRECTORY or ""
    local last = dir:sub(-1)
    if dir ~= "" and last ~= "/" and last ~= "\\" then dir = dir .. "/" end
    return dir .. "cinematic_view.ini"
end

local function sanitize_settings()
    local s = settings
    if s.mode ~= "mixed" and s.mode ~= "outside" and s.mode ~= "cockpit" then s.mode = "mixed" end
    s.afk_timeout = math.max(10, math.min(3600, math.floor(s.afk_timeout + 0.5)))
    s.cockpit_share = math.max(0, math.min(100, math.floor(s.cockpit_share + 0.5)))
    s.shot_min = math.max(3, math.min(60, s.shot_min))
    s.shot_max = math.max(s.shot_min, math.min(90, s.shot_max))
    s.camera_speed = math.max(0.25, math.min(2.5, s.camera_speed))
    s.joystick_deadband = math.max(0.001, math.min(0.5, s.joystick_deadband))
    for k, v in pairs(s) do
        if k:match("^bind_") and v ~= "" and not v:match("^%d+ %d+ .+$") then s[k] = "" end
    end
end

local function load_settings()
    local f = io.open(settings_path(), "r")
    if not f then return end
    for line in f:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        local default = key and DEFAULTS[key]
        if default ~= nil then
            if type(default) == "boolean" then
                settings[key] = (value == "true")
            elseif type(default) == "number" then
                settings[key] = tonumber(value) or default
            else
                settings[key] = value
            end
        end
    end
    f:close()
    sanitize_settings()
end

local function save_settings()
    local f = io.open(settings_path(), "w")
    if not f then return end
    f:write("# Cinematic View settings (written by cinematic_view.lua)\n")
    local keys = {}
    for k in pairs(DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(k, " = ", tostring(settings[k]), "\n") end
    f:close()
end

------------------------------------------------------------------------------
-- Math helpers
------------------------------------------------------------------------------

local M = {}
local sin, cos, sqrt, atan2 = math.sin, math.cos, math.sqrt, math.atan2
local rad, deg, abs = math.rad, math.deg, math.abs

function M.clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
function M.lerp(a, b, k) return a + (b - a) * k end
function M.ease(k) k = M.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
function M.wrap180(a) return (a + 180) % 360 - 180 end
function M.rand(lo, hi) return lo + (hi - lo) * math.random() end
function M.sign() return math.random() < 0.5 and -1 or 1 end
-- Fraction to move toward a target this frame for a lag of tau seconds.
function M.smooth(dt, tau) return 1 - math.exp(-dt / tau) end
function M.approach_angle(cur, target, k) return cur + M.wrap180(target - cur) * k end

-- Rotates a vector from aircraft axes (x right, y up, z aft) into X-Plane's
-- local OpenGL axes (x east, y up, z south), for heading psi, pitch theta and
-- roll phi in degrees: the same rotations X-Plane draws the aircraft with.
function M.body_to_world(x, y, z, psi, the, phi)
    local a = rad(-phi)
    local ca, sa = cos(a), sin(a)
    x, y = x * ca - y * sa, x * sa + y * ca
    a = rad(the)
    ca, sa = cos(a), sin(a)
    y, z = y * ca - z * sa, y * sa + z * ca
    a = rad(-psi)
    ca, sa = cos(a), sin(a)
    x, z = x * ca + z * sa, -x * sa + z * ca
    return x, y, z
end

-- Heading and pitch (degrees) of a camera at c looking at t.
function M.look_at(cx, cy, cz, tx, ty, tz)
    local dx, dy, dz = tx - cx, ty - cy, tz - cz
    return deg(atan2(dx, -dz)), deg(atan2(dy, sqrt(dx * dx + dz * dz)))
end

-- Roll (degrees) that turns a camera with this heading and pitch so that its
-- up direction matches the world vector u.
function M.roll_for(h, p, ux, uy, uz)
    h, p = rad(h), rad(p)
    local r = ux * cos(h) + uz * sin(h)
    local u = -ux * sin(p) * sin(h) + uy * cos(p) + uz * sin(p) * cos(h)
    return deg(atan2(r, u))
end

------------------------------------------------------------------------------
-- X-Plane access: the plugin SDK through LuaJIT's FFI when it can be loaded,
-- FlyWithLua's own dataref functions otherwise
------------------------------------------------------------------------------

local XP = { lib = nil, ffi = nil, camera_ok = false }

do
    local ok, ffi = pcall(require, "ffi")
    if ok and ffi then
        XP.ffi = ffi
        -- Each declaration on its own, so one another script already made
        -- doesn't stop the rest. Pointers are void * so they match any
        -- earlier declaration too.
        local function cdef(s) pcall(ffi.cdef, s) end
        cdef("typedef struct { float x, y, z, pitch, heading, roll, zoom; } cinematic_view_cam_t;")
        cdef("typedef int (*cinematic_view_cam_f)(cinematic_view_cam_t *, int, void *);")
        cdef([[typedef struct { int structSize; float locationX, locationY, locationZ;
            float normalX, normalY, normalZ; float velocityX, velocityY, velocityZ;
            int is_wet; } cinematic_view_probe_t;]])
        cdef("void *XPLMFindDataRef(const char *);")
        cdef("int XPLMGetDatai(void *);")
        cdef("void XPLMSetDatai(void *, int);")
        cdef("float XPLMGetDataf(void *);")
        cdef("void XPLMSetDataf(void *, float);")
        cdef("double XPLMGetDatad(void *);")
        cdef("int XPLMGetDatavf(void *, float *, int, int);")
        cdef("int XPLMGetDatavi(void *, int *, int, int);")
        cdef("float XPLMGetElapsedTime(void);")
        cdef("void XPLMControlCamera(int, void *, void *);")
        cdef("void XPLMDontControlCamera(void);")
        cdef("void *XPLMCreateProbe(int);")
        cdef("void XPLMDestroyProbe(void *);")
        cdef("int XPLMProbeTerrainXYZ(void *, float, float, float, void *);")

        local names = {}
        local root = type(SYSTEM_DIRECTORY) == "string" and SYSTEM_DIRECTORY or ""
        if SYSTEM == "IBM" then
            names = { "XPLM_64", "XPLM" }
        elseif SYSTEM == "LIN" then
            names = { "Resources/plugins/XPLM_64.so", root .. "Resources/plugins/XPLM_64.so" }
        elseif SYSTEM == "APL" then
            names = { "Resources/plugins/XPLM.framework/XPLM", root .. "Resources/plugins/XPLM.framework/XPLM" }
        end
        for _, name in ipairs(names) do
            local loaded, lib = pcall(ffi.load, name)
            if loaded and lib then
                local works = pcall(function()
                    return lib.XPLMFindDataRef("sim/graphics/view/view_type") ~= nil
                        and lib.XPLMGetElapsedTime() >= 0
                end)
                if works then XP.lib = lib break end
            end
        end
    end
end

function XP.find(name)
    if XP.lib then
        local r = XP.lib.XPLMFindDataRef(name)
        if r == nil then return nil end -- a NULL pointer is truthy in Lua
        return r
    end
    if XPLMFindDataRef then return XPLMFindDataRef(name) end
    return nil
end

if XP.lib then
    local lib = XP.lib
    XP.geti = function(r) return lib.XPLMGetDatai(r) end
    XP.getf = function(r) return lib.XPLMGetDataf(r) end
    XP.getd = function(r) return lib.XPLMGetDatad(r) end
    XP.seti = function(r, v) lib.XPLMSetDatai(r, v) end
    XP.setf = function(r, v) lib.XPLMSetDataf(r, v) end
else
    XP.geti = function(r) return XPLMGetDatai(r) end
    XP.getf = function(r) return XPLMGetDataf(r) end
    XP.getd = function(r) return XPLMGetDatad(r) end
    XP.seti = function(r, v) XPLMSetDatai(r, v) end
    XP.setf = function(r, v) XPLMSetDataf(r, v) end
end

local R = {}
do
    local list = {
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
        paused = "sim/time/paused",
        frame_period = "sim/operation/misc/frame_rate_period",
        view_type = "sim/graphics/view/view_type",
        head_x = "sim/graphics/view/pilots_head_x",
        head_y = "sim/graphics/view/pilots_head_y",
        head_z = "sim/graphics/view/pilots_head_z",
        head_psi = "sim/graphics/view/pilots_head_psi",
        head_the = "sim/graphics/view/pilots_head_the",
        head_phi = "sim/graphics/view/pilots_head_phi",
        eye_x = "sim/aircraft/view/acf_peX",
        eye_y = "sim/aircraft/view/acf_peY",
        eye_z = "sim/aircraft/view/acf_peZ",
        size_x = "sim/aircraft/view/acf_size_x",
        size_z = "sim/aircraft/view/acf_size_z",
        m_max = "sim/aircraft/weight/acf_m_max",
        vr = "sim/graphics/VR/enabled",
        onground = "sim/flightmodel/failures/onground_any",
        g_nrml = "sim/flightmodel/forces/g_nrml",
        axes = "sim/joystick/joystick_axis_values",
        buttons = "sim/joystick/joystick_button_values",
    }
    for key, name in pairs(list) do R[key] = XP.find(name) end
end

local function gi(r, default) if r then return XP.geti(r) end return default or 0 end
local function gf(r, default) if r then return XP.getf(r) end return default or 0 end
local function gd(r, default) if r then return XP.getd(r) end return default or 0 end

local VIEW_3D_COCKPIT = 1026
local CMD_COCKPIT = "sim/view/3d_cockpit_cmnd_look_forward"
local CMD_CHASE = "sim/view/chase"

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

local CV = {
    active = false,
    reason = nil,           -- "manual" or "afk"
    started_at = 0,
    shot = nil,             -- the running shot: { def, t0, duration, ... }
    trans = nil,            -- a fade in progress: { phase, t0, def }
    fade = 0,               -- black overlay, 0..1
    bars = 0,               -- letterbox, 0..1
    settle = 0,             -- frames to wait for a view change to take effect
    expected_view = nil,    -- view_type while a shot runs; a change means the user picked a view
    base_view = nil,        -- "chase", "cockpit" or a built-in view command
    recent = {},            -- ids of the last few shots
    saved_view = nil,
    saved_head = nil,
    eye = nil,              -- cockpit eye point for this cinematic
    restore_frames = 0,
    restore_view_check = 0,
    cam_active = false,
    cam_lost = false,
    cam_releasing = false,
    cam_error = nil,
    cam_last = nil,
    heartbeat = 0,
    last_tick = 0,
    fclock = 0,             -- frame-time clock when the SDK timer isn't available
    last_input = 0,
    input_flag = false,
    input_stop_at = -100,
    afk_armed = true,
    mx = nil, my = nil,
    joy_t = 0,
    head_prev = nil,
    toast_text = nil, toast_until = 0,
    dirty = false, dirty_t = 0,
    errors = 0, disabled = false, logged = {},
    draw_last = nil,
    tick_last = nil,
    size = 15,
    user_zoom = 1,          -- zoom set with + and - during a cinematic
    zoom_dir = 0,           -- +1 zooming in, -1 zooming out
    zoom_vk = nil,          -- the + or - key being held
    native_zoom = nil,      -- X-Plane zoom command held for a bound key or joystick button
    keys_down = {},         -- bound keys held down (to ignore auto-repeat)
    held = {},              -- hold actions (zoom) by the key that started them
    capturing = nil,        -- action waiting for its new key in the settings window
    ignore_buttons_until = 0, -- joystick buttons that just ran one of our commands aren't "input"
}

local function now()
    if XP.lib then return XP.lib.XPLMGetElapsedTime() end
    return CV.fclock
end

local function log(msg)
    if logMsg then logMsg("Cinematic View: " .. msg) end
end

local function toast(text, seconds)
    CV.toast_text = text
    CV.toast_until = now() + (seconds or 2.5)
end

local function mark_dirty()
    CV.dirty = true
    CV.dirty_t = now()
end

local function view_type() return gi(R.view_type, 0) end

local function vr_on() return gi(R.vr, 0) ~= 0 end

local function read_head()
    return {
        x = gf(R.head_x), y = gf(R.head_y), z = gf(R.head_z),
        psi = gf(R.head_psi), the = gf(R.head_the), phi = gf(R.head_phi),
    }
end

local function write_head(x, y, z, psi, the, phi)
    if R.head_x then XP.setf(R.head_x, x) end
    if R.head_y then XP.setf(R.head_y, y) end
    if R.head_z then XP.setf(R.head_z, z) end
    if R.head_psi then XP.setf(R.head_psi, psi) end
    if R.head_the then XP.setf(R.head_the, the) end
    if R.head_phi then XP.setf(R.head_phi, phi) end
end

-- Rough wingspan in metres: the aircraft's size if X-Plane reports a
-- plausible one, otherwise a guess from its maximum weight.
local function aircraft_size()
    local m = gf(R.m_max)
    local guess = m > 100 and 0.9 * m ^ (1 / 3) or 15
    local s = math.max(gf(R.size_x), gf(R.size_z))
    if s > 4 and s < 120 and s > 0.5 * guess then guess = s end
    return M.clamp(guess, 8, 70)
end

-- The cockpit eye point. X-Plane's default eye point if it agrees with where
-- the head is (or the head reads zero), otherwise wherever the head is now.
local function find_eye()
    local head = CV.saved_head or read_head()
    local ex, ey, ez = gf(R.eye_x), gf(R.eye_y), gf(R.eye_z)
    local eye_ok = (ex ~= 0 or ey ~= 0 or ez ~= 0) and abs(ex) < 3 and abs(ey) < 15 and abs(ez) < 40
    local head_ok = (head.x ~= 0 or head.y ~= 0 or head.z ~= 0)
    local d = sqrt((head.x - ex) ^ 2 + (head.y - ey) ^ 2 + (head.z - ez) ^ 2)
    local x, y, z = head.x, head.y, head.z
    if eye_ok and (d < 1.0 or not head_ok) then x, y, z = ex, ey, ez end
    local seat = 0
    if x < -0.12 then seat = -1 elseif x > 0.12 then seat = 1 end
    return { x = x, y = y, z = z, seat = seat }
end

------------------------------------------------------------------------------
-- Terrain
------------------------------------------------------------------------------

local function terrain_y(x, y, z)
    if not XP.probe then return nil end
    local info = XP.probe_info
    info[0].structSize = XP.ffi.sizeof("cinematic_view_probe_t")
    if XP.lib.XPLMProbeTerrainXYZ(XP.probe, x, y, z, info) ~= 0 then return nil end -- 0: hit terrain
    return info[0].locationY
end

-- Keeps a camera position at least this far above the ground.
local function above_ground(x, y, z, margin)
    local g = terrain_y(x, y, z)
    if g and y < g + margin then return g + margin end
    return y
end

------------------------------------------------------------------------------
-- Shots
--
-- Outside shots compute a camera position and direction every frame from
-- where the aircraft is (c: position, attitude, velocity, size). Cockpit
-- shots return the pilot's head pose as an offset from the eye point (e).
--
-- Each shot has a weight for each flight phase (w), so takeoff and landing
-- get runway-level and wheel shots and cruise gets air-to-air ones, and a
-- shake factor: how much it feels turbulence, runway rumble and touchdowns.
------------------------------------------------------------------------------

-- Weights for: parked, taxiing, takeoff or landing roll, low (below about
-- 2000 ft), cruise.
local function W(parked, taxi, roll, low, cruise)
    return { parked = parked, taxi = taxi, roll = roll, low = low, cruise = cruise }
end

-- Point at an offset from the aircraft in a frame turned only by heading.
local function yaw_point(c, hdg, ox, oy, oz)
    local wx, wy, wz = M.body_to_world(ox, oy, oz, hdg, 0, 0)
    return c.x + wx, c.y + wy, c.z + wz
end

-- Point at an offset from the aircraft in its own axes.
local function body_point(c, ox, oy, oz)
    local wx, wy, wz = M.body_to_world(ox, oy, oz, c.psi, c.the, c.phi)
    return c.x + wx, c.y + wy, c.z + wz
end

local function aim(out, cx, cy, cz, tx, ty, tz, roll, zoom, margin)
    cy = above_ground(cx, cy, cz, margin or 1.0)
    out.x, out.y, out.z = cx, cy, cz
    out.heading, out.pitch = M.look_at(cx, cy, cz, tx, ty, tz)
    out.roll = roll or 0
    out.zoom = zoom or 1
end

-- A camera bolted to the airframe: it pitches and rolls with the aircraft.
local function mounted(out, c, ox, oy, oz, tx, ty, tz)
    local cx, cy, cz = body_point(c, ox, oy, oz)
    local px, py, pz = body_point(c, tx, ty, tz)
    cy = above_ground(cx, cy, cz, 0.8)
    local h, p = M.look_at(cx, cy, cz, px, py, pz)
    local ux, uy, uz = M.body_to_world(0, 1, 0, c.psi, c.the, c.phi)
    out.x, out.y, out.z = cx, cy, cz
    out.heading, out.pitch, out.roll = h, p, M.roll_for(h, p, ux, uy, uz)
    out.zoom = 1
end

-- A tilted horizon now and then, as racing games do on trackside shots.
local function maybe_dutch(chance, most)
    if math.random() < chance then return M.sign() * M.rand(most * 0.4, most) end
    return 0
end

-- A camera standing on the ground beside where the aircraft will be in T
-- seconds: lat metres to the right of its track (negative: left), ahead
-- metres further along it.
local function ground_camera(s, c, T, lat, ahead)
    local tr = rad(c.track)
    local fx, fz = sin(tr), -cos(tr)
    local rx, rz = cos(tr), sin(tr)
    s.px = c.x + c.vx * T + rx * lat + fx * ahead
    s.pz = c.z + c.vz * T + rz * lat + fz * ahead
    s.ground = true
    s.height = s.height or 1.6
end

-- Trackside cameras stay put and follow the aircraft, zooming so it stays a
-- similar size as it comes and goes.
local function trackside_update(s, c, t, out)
    local py = s.py
    if s.ground then
        local g = terrain_y(s.px, c.y, s.pz) or (c.y - c.agl)
        py = g + s.height
    end
    local d = sqrt((c.x - s.px) ^ 2 + (c.y - py) ^ 2 + (c.z - s.pz) ^ 2)
    local zoom = M.clamp((d / (2.5 * c.size + 25)) ^ 0.85, 1, s.max_zoom or 5)
    s.zoom = s.zoom and (s.zoom + (zoom - s.zoom) * M.smooth(c.dt, 0.35)) or zoom
    aim(out, s.px, py, s.pz, c.x + c.vx * 0.1, c.y, c.z + c.vz * 0.1, s.dutch or 0, s.zoom)
end

local OUTSIDE_SHOTS = {
    {
        -- springy: falls back as the aircraft accelerates and widens with speed
        id = "chase", label = "Chase cam", w = W(1, 2, 3, 3, 3), shake = 0.35,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.rand(-0.15, 0.15) * c.size
            s.phase = M.rand(0, 6.28)
            s.drop = 0
            s.gs = c.gs
            s.acc = 0
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 0.8))
            if c.dt > 0 then
                local acc = (c.gs - s.gs) / c.dt
                s.acc = s.acc + (acc - s.acc) * M.smooth(c.dt, 0.6)
            end
            s.gs = c.gs
            local dist = 1.5 * S + 12 + math.min(c.gs, 150) * 0.04 + M.clamp(s.acc * 1.5, -4, 10)
            -- sit on the flight path behind: lower in a climb, higher in a descent
            local drop = dist * M.clamp(c.vy / math.max(c.gs, 30), -0.25, 0.25)
            s.drop = s.drop + (drop - s.drop) * M.smooth(c.dt, 1.0)
            local lat = s.side + sin(t * 0.35 * s.speed + s.phase) * 0.1 * S
            local cx, cy, cz = yaw_point(c, s.hdg, lat, 0.22 * S + 2.5 - s.drop, dist)
            local tx, ty, tz = yaw_point(c, s.hdg, 0, 0.1 * S, -0.5 * S)
            aim(out, cx, cy, cz, tx, ty, tz, c.phi * 0.25, 1 - 0.15 * M.clamp(c.gs / 120, 0, 1))
        end,
    },
    {
        id = "longlens", label = "Long lens", w = W(0, 1, 2, 2, 3), shake = 0,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.sign()
            s.phase = M.rand(0, 6.28)
            s.dist = 7 * c.size + 80
            s.dutch = maybe_dutch(0.4, 4)
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 1.6))
            local cx, cy, cz = yaw_point(c, s.hdg, s.side * (0.9 * S + 8), 0.25 * S + 3, s.dist)
            local zoom = M.clamp(s.dist / (2.4 * S + 20), 1.5, 5)
            aim(out, cx, cy, cz, c.x, c.y, c.z, s.dutch, zoom)
            -- a hand-held long lens never sits perfectly still
            local w = t * s.speed
            out.heading = out.heading + sin(w * 1.7 + s.phase) * 0.12 + sin(w * 0.9) * 0.08
            out.pitch = out.pitch + sin(w * 1.3 + s.phase * 2) * 0.08
        end,
    },
    {
        id = "tracking", label = "Tracking", w = W(1, 2, 2, 2, 2), shake = 0.3,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.sign()
            s.dir = M.sign()
            s.height = M.rand(-0.03, 0.2) * c.size + 1
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 0.5))
            local reach = (S + 8) * s.speed
            local z = M.lerp(-reach, reach, M.ease(t / s.duration)) * s.dir
            local cx, cy, cz = yaw_point(c, s.hdg, s.side * (S + 8), s.height, z)
            local tx, ty, tz = yaw_point(c, s.hdg, 0, 0, -0.1 * S)
            aim(out, cx, cy, cz, tx, ty, tz, 0, 1)
        end,
    },
    {
        -- a camera waiting by the flight path, at runway level near the ground
        id = "flyby", label = "Flyby", w = W(0, 2, 4, 3, 2), min_gs = 5, shake = 0,
        init = function(s, c)
            local gs = math.max(c.gs, 1)
            local T = M.clamp(gs * 4.5, 60, 900) / gs
            s.side = M.sign()
            local lat = (0.8 * c.size + 12 + gs * 0.06) * s.side
            if c.agl < 40 then
                ground_camera(s, c, T, lat, 0)
                s.height = M.rand(1.2, 3.0)
            else
                local tr = rad(c.track)
                s.px = c.x + c.vx * T + cos(tr) * lat
                s.pz = c.z + c.vz * T + sin(tr) * lat
                s.py = c.y + c.vy * T + M.rand(-0.35, 0.55) * c.size
            end
            s.duration = M.clamp(T + 3.5, 5, 15)
            s.dutch = maybe_dutch(0.4, 5)
        end,
        update = trackside_update,
    },
    {
        -- someone on the ground with a long lens, like a plane spotter by the runway
        id = "spotter", label = "Spotter", w = W(0, 0, 0, 4, 0), min_gs = 20, shake = 0,
        init = function(s, c)
            local T = math.min(M.rand(4, 7), 900 / math.max(c.gs, 1))
            ground_camera(s, c, T, (0.8 * c.size + 40 + c.agl * 0.25) * M.sign(), 0)
            s.max_zoom = 6
            s.duration = M.clamp(T + 4, 6, 16)
            s.dutch = maybe_dutch(0.5, 4)
        end,
        update = trackside_update,
    },
    {
        id = "orbit", label = "Orbit", w = W(3, 1, 0, 1, 2), shake = 0,
        init = function(s, c)
            s.r = 1.5 * c.size + 14
            s.a0 = M.rand(0, 360)
            s.rate = M.sign() * M.rand(6, 11) -- degrees a second
            s.height = M.rand(0.05, 0.35) * c.size + 2
            s.phase = M.rand(0, 6.28)
        end,
        update = function(s, c, t, out)
            local a = rad(s.a0 + s.rate * s.speed * t)
            local cx = c.x + sin(a) * s.r
            local cz = c.z - cos(a) * s.r
            local cy = c.y + s.height + sin(t * 0.25 * s.speed + s.phase) * 0.08 * c.size
            aim(out, cx, cy, cz, c.x, c.y + 0.05 * c.size, c.z, 0, 1)
        end,
    },
    {
        -- starts ahead looking back at the nose and swings out as the
        -- aircraft overtakes it
        id = "passby", label = "Pass-by", w = W(2, 2, 1, 2, 2), shake = 0.25,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.sign()
            s.low = c.agl > 30
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 0.6))
            local k = M.ease(t / s.duration)
            -- the same end point; a faster camera starts further away
            local reach = M.clamp(s.speed, 0.4, 1.6)
            local x1, z1 = 1.2 * S + 8, 0.7 * S
            local x = M.lerp(x1 + (0.3 * S - x1) * reach, x1, k) * s.side
            local y = M.lerp(s.low and -0.12 * S or 0.15 * S + 1, 0.08 * S + 1, k)
            local z = M.lerp(z1 + (-(2.8 * S + 20) - z1) * reach, z1, k)
            local cx, cy, cz = yaw_point(c, s.hdg, x, y, z)
            aim(out, cx, cy, cz, c.x, c.y, c.z, c.phi * 0.15, M.lerp(1.5, 1, k))
        end,
    },
    {
        -- rises from low beside the aircraft up and over it, like a camera crane
        id = "crane", label = "Crane", w = W(2, 1, 1, 1, 1), shake = 0.2,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.sign()
            s.rise = M.rand(1.2, 1.8)
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 0.6))
            local k = M.ease(t / s.duration)
            local reach = M.clamp(s.speed, 0.4, 1.6)
            local x = M.lerp(0.9 * S + 8, 0.35 * S, k) * s.side
            local y = M.lerp(-0.08 * S, (s.rise * S + 12) * reach, k)
            local z = M.lerp(0.6 * S + 6, 1.1 * S + 12, k)
            local cx, cy, cz = yaw_point(c, s.hdg, x, y, z)
            aim(out, cx, cy, cz, c.x, c.y, c.z, 0, 1)
        end,
    },
    {
        -- low beside the main wheels, like a camera car running alongside
        id = "wheels", label = "Wheels", w = W(1, 3, 3, 0, 0), ground_only = true, shake = 0.7,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.sign()
            s.dir = M.sign()
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 0.3))
            local z = 0.1 * S + s.dir * M.lerp(-0.08, 0.08, M.ease(t / s.duration)) * S * s.speed
            local cx, cy, cz = yaw_point(c, s.hdg, (0.32 * S + 2.5) * s.side, 0.6 - c.agl, z)
            local tx, ty, tz = yaw_point(c, s.hdg, 0.1 * S * s.side, 0.9 - c.agl, 0.05 * S)
            aim(out, cx, cy, cz, tx, ty, tz, 0, 1, 0.4)
        end,
    },
    {
        id = "tail", label = "Tail mount", w = W(1, 1, 2, 1, 1.5), shake = 1,
        init = function(s, c) s.phase = M.rand(0, 6.28) end,
        update = function(s, c, t, out)
            local S = c.size
            mounted(out, c, 0, 0.24 * S + 1.5, 0.55 * S + 2.5,
                sin(t * 0.2 * s.speed + s.phase) * 0.05 * S, 0.05 * S, -1.5 * S)
        end,
    },
    {
        id = "wing", label = "Wing mount", w = W(1, 1, 2, 1.5, 1.5), shake = 1,
        init = function(s, c) s.side = M.sign() end,
        update = function(s, c, t, out)
            local S = c.size
            mounted(out, c, s.side * (0.56 * S + 0.6), 0.08 * S + 0.4, 0.1 * S,
                0, 0.05 * S, -0.3 * S + sin(t * 0.15 * s.speed) * 0.05 * S)
        end,
    },
    {
        -- a camera on a boom ahead of the nose, looking back
        id = "nose", label = "Nose boom", w = W(1, 1, 1, 1, 1), shake = 1,
        init = function(s, c) end,
        update = function(s, c, t, out)
            local S = c.size
            mounted(out, c, 0, 0.1 * S + 0.8, -(0.65 * S + 3), 0, 0.03 * S, 0.3 * S)
        end,
    },
    {
        id = "drone", label = "Drone", w = W(2, 1, 0, 1, 1.5), shake = 0,
        init = function(s, c)
            s.height = 3 * c.size + 30
            s.back = 0.8 * c.size + 4
            s.a0 = c.psi + 180
            s.spin = M.sign() * M.rand(3, 7)
        end,
        update = function(s, c, t, out)
            local a = rad(s.a0 + s.spin * s.speed * t)
            local cx = c.x + sin(a) * s.back
            local cz = c.z - cos(a) * s.back
            aim(out, cx, c.y + s.height, cz, c.x, c.y, c.z, 0, 1)
        end,
    },
}

-- Moments: these cut in when they happen instead of waiting their turn.
local EVENT_SHOTS = {
    -- by the runway a little past where the aircraft is about to touch down
    -- (allowing for the flare)
    touchdown = {
        id = "touchdown", label = "Touchdown", event = true, shake = 0,
        init = function(s, c)
            local T = M.clamp(c.agl / math.max(-c.vy, 0.5), 2, 16)
            s.height = M.rand(1.0, 1.8)
            ground_camera(s, c, T, (0.6 * c.size + 25) * M.sign(), 0.3 * c.size + 15 + c.gs * 1.5)
            s.max_zoom = 6
            s.duration = T + 5
            s.dutch = maybe_dutch(0.5, 3)
        end,
        update = trackside_update,
    },
    -- low by the runway as the aircraft lifts off and climbs away
    liftoff = {
        id = "liftoff", label = "Liftoff", event = true, shake = 0,
        init = function(s, c)
            s.height = M.rand(0.8, 1.5)
            ground_camera(s, c, 0.6, (0.6 * c.size + 25) * M.sign(), 0)
            s.max_zoom = 6
            s.duration = 7
            s.dutch = maybe_dutch(0.5, 3)
        end,
        update = trackside_update,
    },
}

-- Opening shots: a cinematic starts with a reveal.
local HERO_SHOTS = { passby = true, crane = true, orbit = true }

-- Used when the plugin SDK can't be loaded: X-Plane's own outside views.
local BUILTIN_SHOTS = {
    { id = "xp_chase", label = "Chase cam", command = "sim/view/chase", w = W(1, 2, 3, 3, 3) },
    { id = "xp_circle", label = "Orbit", command = "sim/view/circle", w = W(3, 1, 0, 1, 2) },
    { id = "xp_spot", label = "Flyby", command = "sim/view/still_spot", w = W(0, 1, 3, 3, 2), min_gs = 15 },
    { id = "xp_linear", label = "Tracking", command = "sim/view/linear_spot", w = W(0, 1, 2, 2, 2), min_gs = 15 },
}

-- Head pose: dx, dy, dz from the eye point (x right, y up, z aft, metres),
-- then heading, pitch and roll in degrees relative to the aircraft.
local COCKPIT_SHOTS = {
    {
        id = "eye", label = "Pilot's eye", w = W(2, 2, 3, 2, 2),
        init = function(s, e)
            s.amp = M.rand(12, 26)
            s.w = 2 * math.pi / M.rand(16, 24)
            s.phase = M.rand(0, 6.28)
            s.pitch = M.rand(-7, -3)
        end,
        update = function(s, e, t)
            local w = s.w * s.speed * t
            return 0, 0.006 * sin(t * 1.3), 0, s.amp * sin(w + s.phase), s.pitch + 2 * sin(w * 0.7), 0
        end,
    },
    {
        id = "shoulder", label = "Over the shoulder", w = W(2, 2, 2, 2, 2),
        init = function(s, e)
            s.inward = e.seat ~= 0 and -e.seat or 1
            s.from = M.rand(-8, -2) * s.inward * s.speed
        end,
        update = function(s, e, t)
            local k = M.ease(t / s.duration)
            return 0.18 * s.inward, 0.12, 0.32, M.lerp(s.from, -s.from, k), -8 + sin(t * 0.4) * 1.5, 0
        end,
    },
    {
        id = "window", label = "Side window", w = W(2, 2, 2, 3, 2),
        init = function(s, e)
            s.out = e.seat ~= 0 and e.seat or M.sign()
            s.look = M.rand(65, 85)
            s.phase = M.rand(0, 6.28)
        end,
        update = function(s, e, t)
            local w = t * s.speed
            return 0, 0, 0, s.out * (s.look + 5 * sin(w * 0.25 + s.phase)), -6 + 2 * sin(w * 0.3), 0
        end,
    },
    {
        id = "panel", label = "Panel", w = W(2, 1.5, 0.5, 1, 2),
        init = function(s, e)
            s.pitch = -M.rand(22, 30)
            s.span = math.min(M.rand(16, 26) * s.speed, 45) * M.sign()
        end,
        update = function(s, e, t)
            local k = M.ease(t / s.duration)
            return 0, -0.04, -0.06, M.lerp(-s.span, s.span, k), s.pitch, 0
        end,
    },
    {
        id = "copilot", label = "Co-pilot's seat", w = W(1.5, 1.5, 1, 1.5, 1.5), side_by_side = true,
        init = function(s, e)
            s.look = M.rand(10, 22)
            s.phase = M.rand(0, 6.28)
        end,
        update = function(s, e, t)
            return -2 * e.x, 0, 0, e.seat * (s.look + 6 * sin(t * 0.2 * s.speed + s.phase)), -6, 0
        end,
    },
}

for _, d in ipairs(OUTSIDE_SHOTS) do d.kind = "outside" end
for _, d in pairs(EVENT_SHOTS) do d.kind = "outside" end
for _, d in ipairs(BUILTIN_SHOTS) do d.kind = "builtin" end
for _, d in ipairs(COCKPIT_SHOTS) do d.kind = "cockpit" end

------------------------------------------------------------------------------
-- Camera shake: turbulence (changes in g-load), runway rumble and the thump
-- of a touchdown, scaled by each shot's shake factor
------------------------------------------------------------------------------

local SH = { g_lp = 1, turb = 0, impact = 0, impact_t = -100 }

local function shake_level(c, dt, t)
    SH.g_lp = SH.g_lp + (c.g - SH.g_lp) * M.smooth(dt, 0.5)
    SH.turb = SH.turb + (abs(c.g - SH.g_lp) - SH.turb) * M.smooth(dt, 0.3)
    local rumble = c.onground and M.clamp(c.gs / 50, 0, 1) or 0
    local impact = SH.impact * math.exp(-(t - SH.impact_t) / 0.35)
    return M.clamp(SH.turb * 5, 0, 1.5) + rumble * 0.6 + impact * 2.5 + 0.04
end

-- Smooth jitter between about -1 and 1; k picks a different pattern.
local function jitter(t, k)
    return (sin(t * 9.1 + k * 1.7) + 0.6 * sin(t * 15.3 + k * 4.1) + 0.4 * sin(t * 23.9 + k * 2.3)) / 2
end

------------------------------------------------------------------------------
-- Camera control
------------------------------------------------------------------------------

local cam_ctx = {}
local cam_out = { x = 0, y = 0, z = 0, heading = 0, pitch = 0, roll = 0, zoom = 1 }

local function on_ground(agl)
    if R.onground then return gi(R.onground) ~= 0 end
    return agl < math.max(3, 0.15 * CV.size)
end

-- What the aircraft is doing, for choosing shots.
local function flight_phase(gs, agl, onground)
    if onground then
        if gs < 2 then return "parked" end
        if gs < 15 then return "taxi" end
        return "roll"
    end
    if agl < 600 then return "low" end
    return "cruise"
end

local function read_aircraft(c)
    c.x, c.y, c.z = gd(R.x), gd(R.y), gd(R.z)
    c.psi, c.the, c.phi = gf(R.psi), gf(R.the), gf(R.phi)
    c.vx, c.vy, c.vz = gf(R.vx), gf(R.vy), gf(R.vz)
    c.gs = sqrt(c.vx * c.vx + c.vz * c.vz)
    c.agl = gf(R.agl, 100)
    c.track = c.gs > 3 and deg(atan2(c.vx, -c.vz)) or c.psi
    c.size = CV.size
    c.onground = on_ground(c.agl)
    c.g = gf(R.g_nrml, 1)
end

-- Called by X-Plane every frame while we hold the camera.
local function camera_func(pos, losing)
    if losing ~= 0 then
        CV.cam_active = false
        if not CV.cam_releasing then CV.cam_lost = true end
        return 0
    end
    local t_now = now()
    local s = CV.shot
    -- Give the camera back if the script has stopped running (a FlyWithLua
    -- error elsewhere, say) or the shot isn't an outside one.
    if CV.disabled or not CV.active or t_now - CV.heartbeat > 2.5 or not s or s.def.kind ~= "outside" then
        CV.cam_active = false
        return 0
    end
    if pos == nil then return 1 end
    local c = cam_ctx
    read_aircraft(c)
    c.dt = M.clamp(t_now - (CV.cam_last or t_now), 0, 0.1)
    CV.cam_last = t_now
    if not s.inited then
        s.def.init(s, c)
        s.inited = true
    end
    s.def.update(s, c, t_now - s.t0, cam_out)
    local level = shake_level(c, c.dt, t_now)
    local amount = settings.shake and (s.def.shake or 0) or 0
    if amount > 0 then
        local a = amount * level * 0.6
        cam_out.heading = cam_out.heading + a * 0.5 * jitter(t_now, 1)
        cam_out.pitch = cam_out.pitch + a * 0.5 * jitter(t_now, 2)
        cam_out.roll = cam_out.roll + a * 0.7 * jitter(t_now, 3)
    end
    pos.x, pos.y, pos.z = cam_out.x, cam_out.y, cam_out.z
    pos.heading, pos.pitch, pos.roll = cam_out.heading, cam_out.pitch, cam_out.roll
    pos.zoom = M.clamp(cam_out.zoom * CV.user_zoom, 0.4, 12)
    return 1
end

if XP.lib then
    local ok = pcall(function()
        local ffi = XP.ffi
        XP.cam_cb = ffi.cast("cinematic_view_cam_f", function(pos, losing, refcon)
            local fine, keep = pcall(camera_func, pos, losing)
            if fine then return keep end
            CV.cam_error = tostring(keep)
            CV.cam_active = false
            return 0
        end)
        XP.cam_ptr = ffi.cast("void *", XP.cam_cb)
        XP.probe = XP.lib.XPLMCreateProbe(0) -- xplm_ProbeY
        if XP.probe == nil then XP.probe = nil end
        XP.probe_info = ffi.new("cinematic_view_probe_t[1]")
    end)
    XP.camera_ok = ok and XP.cam_cb ~= nil
end

-- Kept out of JIT-compiled code: X-Plane may call back into Lua from these.
local function sdk_control_camera() XP.lib.XPLMControlCamera(2, XP.cam_ptr, nil) end -- xplm_ControlCameraForever
local function sdk_release_camera() XP.lib.XPLMDontControlCamera() end
if jit and jit.off then
    jit.off(sdk_control_camera)
    jit.off(sdk_release_camera)
end

local function take_camera()
    if CV.cam_active then return true end
    if not XP.camera_ok then return false end
    CV.cam_lost = false
    CV.cam_last = nil
    if pcall(sdk_control_camera) then CV.cam_active = true end
    return CV.cam_active
end

local function release_camera()
    if not CV.cam_active then return end
    CV.cam_releasing = true
    pcall(sdk_release_camera)
    CV.cam_releasing = false
    CV.cam_active = false
end

------------------------------------------------------------------------------
-- Choosing and running shots
------------------------------------------------------------------------------

local function conditions()
    local vx, vz = gf(R.vx), gf(R.vz)
    local gs, agl = sqrt(vx * vx + vz * vz), gf(R.agl, 100)
    local ground = on_ground(agl)
    return {
        gs = gs, agl = agl, vy = gf(R.vy), g = gf(R.g_nrml, 1), onground = ground,
        paused = gi(R.paused, 0) ~= 0, phase = flight_phase(gs, agl, ground),
    }
end

local function eligible(def, cond)
    if (def.w[cond.phase] or 0) <= 0 then return false end
    if def.min_gs and (cond.paused or cond.gs < def.min_gs) then return false end
    if def.ground_only and not cond.onground then return false end
    if def.side_by_side and (not CV.eye or CV.eye.seat == 0 or abs(CV.eye.x) < 0.2) then return false end
    return true
end

local function pick_from(pool, cond)
    local candidates, fresh = {}, {}
    for _, def in ipairs(pool) do
        if eligible(def, cond) then
            candidates[#candidates + 1] = def
            local used = false
            for _, id in ipairs(CV.recent) do if id == def.id then used = true end end
            if not used then fresh[#fresh + 1] = def end
        end
    end
    if #fresh > 0 then candidates = fresh end
    local total = 0
    for _, def in ipairs(candidates) do total = total + def.w[cond.phase] end
    local r = math.random() * total
    for _, def in ipairs(candidates) do
        r = r - def.w[cond.phase]
        if r <= 0 then return def end
    end
    return candidates[#candidates]
end

local function pick_shot()
    if not CV.eye then CV.eye = find_eye() end
    local cond = conditions()
    local outside = XP.camera_ok and OUTSIDE_SHOTS or BUILTIN_SHOTS
    if CV.first_shot then
        -- open with a reveal
        CV.first_shot = false
        if XP.camera_ok and settings.mode ~= "cockpit" then
            local heroes = {}
            for _, def in ipairs(OUTSIDE_SHOTS) do
                if HERO_SHOTS[def.id] then heroes[#heroes + 1] = def end
            end
            local def = pick_from(heroes, cond)
            if def then return def end
        end
    end
    local cockpit
    if settings.mode == "cockpit" then
        cockpit = true
    elseif settings.mode == "outside" then
        cockpit = false
    else
        cockpit = math.random(100) <= settings.cockpit_share
    end
    return pick_from(cockpit and COCKPIT_SHOTS or outside, cond) or pick_from(outside, cond)
end

local function begin_shot(def)
    -- quicker cuts on takeoff and landing, longer shots in the calm
    local lo, hi = settings.shot_min, settings.shot_max
    local mid = (lo + hi) / 2
    local busy = CV.phase == "roll" or CV.phase == "low"
    local s = {
        def = def, t0 = now(), duration = busy and M.rand(lo, mid) or M.rand(mid, hi),
        speed = settings.camera_speed, inited = false,
    }
    if def.kind == "cockpit" then
        release_camera()
        if view_type() ~= VIEW_3D_COCKPIT then command_once(CMD_COCKPIT) end
        CV.base_view = "cockpit"
        def.init(s, CV.eye)
        s.inited = true
    elseif def.kind == "outside" then
        if CV.base_view ~= "chase" then command_once(CMD_CHASE) end
        CV.base_view = "chase"
        take_camera()
    else
        release_camera()
        command_once(def.command)
        CV.base_view = def.command
    end
    CV.shot = s
    CV.settle = 3
    CV.view_retries = 0
    CV.expected_view = nil
    table.insert(CV.recent, 1, def.id)
    while #CV.recent > 3 do table.remove(CV.recent) end
end

local FADE_TIME = 0.4

-- A hard cut, for moments that can't wait.
local function cut_to(def)
    CV.trans = nil
    CV.fade = 0
    begin_shot(def)
end

local function next_shot(force_fade)
    local def = pick_shot()
    if not def then return end
    local switching = CV.shot == nil or CV.shot.def.kind ~= def.kind
    if settings.fades and (force_fade or switching or math.random() < 0.2) then
        CV.trans = { phase = "out", t0 = now(), def = def }
    else
        CV.trans = nil
        CV.fade = 0
        begin_shot(def)
    end
end

------------------------------------------------------------------------------
-- Zoom: in outside shots the camera is ours, so the script zooms it; in the
-- cockpit and X-Plane's own views, X-Plane's zoom does
------------------------------------------------------------------------------

local function outside_shot()
    return CV.active and CV.shot ~= nil and CV.shot.def.kind == "outside"
end

local function zoom_end()
    CV.zoom_dir = 0
    CV.zoom_vk = nil
    if CV.native_zoom then
        command_end(CV.native_zoom)
        CV.native_zoom = nil
    end
end

local function zoom_begin(dir)
    zoom_end()
    if outside_shot() then
        CV.zoom_dir = dir
        CV.user_zoom = M.clamp(CV.user_zoom * (dir > 0 and 1.06 or 1 / 1.06), 0.5, 4) -- a tap still zooms a little
    else
        CV.native_zoom = dir > 0 and "sim/general/zoom_in" or "sim/general/zoom_out"
        command_begin(CV.native_zoom)
    end
end

local function start(reason)
    if CV.active or CV.disabled then return end
    if vr_on() then
        toast("Cinematic view isn't available in VR")
        return
    end
    CV.active = true
    CV.reason = reason
    CV.started_at = now()
    CV.saved_view = view_type()
    CV.saved_head = read_head()
    CV.restore_frames = 0
    CV.restore_view_check = 0
    CV.size = aircraft_size()
    CV.eye = find_eye()
    CV.base_view = (CV.saved_view == VIEW_3D_COCKPIT) and "cockpit" or nil
    CV.recent = {}
    CV.shot = nil
    CV.first_shot = true
    CV.input_flag = false
    zoom_end()
    CV.user_zoom = 1
    next_shot(true)
end

local function stop(reason)
    if not CV.active then return end
    CV.active = false
    CV.trans = nil
    CV.fade = 0
    CV.shot = nil
    CV.settle = 0
    CV.expected_view = nil
    zoom_end()
    release_camera()
    -- put the user back in the view they were in, unless they just picked one
    if reason ~= "view" and CV.saved_view and CV.saved_view ~= 0 and view_type() ~= CV.saved_view then
        if R.view_type then XP.seti(R.view_type, CV.saved_view) end
        CV.restore_view_check = 3
    end
    CV.restore_frames = 4 -- and the head where it was, for the next time they're in the cockpit
    CV.base_view = nil
    CV.last_input = now()
    if reason == "input" or reason == "view" then CV.input_stop_at = now() end
end

------------------------------------------------------------------------------
-- Input and idle detection
------------------------------------------------------------------------------

local JOY = {}

local function joystick_setup()
    if XP.lib then
        local ffi = XP.ffi
        if R.axes then
            JOY.axes_n = math.min(XP.lib.XPLMGetDatavf(R.axes, nil, 0, 0), 1024)
            if JOY.axes_n > 0 then
                JOY.axes = ffi.new("float[?]", JOY.axes_n)
                JOY.axes_ref = ffi.new("float[?]", JOY.axes_n)
                XP.lib.XPLMGetDatavf(R.axes, JOY.axes_ref, 0, JOY.axes_n)
            end
        end
        if R.buttons then
            JOY.buttons_n = math.min(XP.lib.XPLMGetDatavi(R.buttons, nil, 0, 0), 8192)
            if JOY.buttons_n > 0 then
                JOY.buttons = ffi.new("int[?]", JOY.buttons_n)
                JOY.buttons_prev = ffi.new("int[?]", JOY.buttons_n)
                XP.lib.XPLMGetDatavi(R.buttons, JOY.buttons_prev, 0, JOY.buttons_n)
            end
        end
    else
        if R.axes and XPLMGetDatavf then JOY.axes_ref = XPLMGetDatavf(R.axes, 0, 100) end
        if button then
            JOY.buttons_prev = {}
            for i = 0, 3199 do JOY.buttons_prev[i] = button(i) end
        end
    end
end

-- Axes count once they move past the deadband from where they last counted,
-- so sensor noise never does but a slow, steady push still does.
local function joystick_moved()
    local moved = false
    local band = settings.joystick_deadband
    local skip_buttons = now() < CV.ignore_buttons_until
    if XP.lib then
        if JOY.axes then
            local n = XP.lib.XPLMGetDatavf(R.axes, JOY.axes, 0, JOY.axes_n)
            for i = 0, n - 1 do
                local v = JOY.axes[i]
                if abs(v - JOY.axes_ref[i]) > band then
                    moved = true
                    JOY.axes_ref[i] = v
                end
            end
        end
        if JOY.buttons then
            local n = XP.lib.XPLMGetDatavi(R.buttons, JOY.buttons, 0, JOY.buttons_n)
            for i = 0, n - 1 do
                if JOY.buttons[i] ~= JOY.buttons_prev[i] then
                    moved = moved or not skip_buttons
                    JOY.buttons_prev[i] = JOY.buttons[i]
                end
            end
        end
    else
        if JOY.axes_ref and XPLMGetDatavf then
            local values = XPLMGetDatavf(R.axes, 0, 100)
            for i = 0, 99 do
                local v, ref = values[i], JOY.axes_ref[i]
                if v and ref and abs(v - ref) > band then
                    moved = true
                    JOY.axes_ref[i] = v
                end
            end
        end
        if JOY.buttons_prev then
            for i = 0, 3199 do
                local b = button(i)
                if b ~= JOY.buttons_prev[i] then
                    moved = moved or not skip_buttons
                    JOY.buttons_prev[i] = b
                end
            end
        end
    end
    return moved
end

local function had_input(t)
    local any = CV.input_flag
    CV.input_flag = false
    -- mouse movement
    local mx, my = MOUSE_X or 0, MOUSE_Y or 0
    if CV.mx and abs(mx - CV.mx) + abs(my - CV.my) >= 3 then any = true end
    CV.mx, CV.my = mx, my
    -- joystick, ten times a second
    if t - CV.joy_t >= 0.1 then
        CV.joy_t = t
        if joystick_moved() then any = true end
    end
    -- looking around the cockpit (hat switch, head tracking) while not in a cinematic
    if not CV.active and CV.restore_frames == 0 and view_type() == VIEW_3D_COCKPIT then
        local psi, the = gf(R.head_psi), gf(R.head_the)
        local prev = CV.head_prev
        if prev and abs(M.wrap180(psi - prev.psi)) + abs(the - prev.the) > 0.5 then any = true end
        CV.head_prev = { psi = psi, the = the }
    else
        CV.head_prev = nil
    end
    return any
end

------------------------------------------------------------------------------
-- The per-frame tick
------------------------------------------------------------------------------

local function report_error(where, err)
    local msg = where .. ": " .. tostring(err)
    if not CV.logged[msg] then
        CV.logged[msg] = true
        log("error in " .. msg)
    end
    CV.errors = CV.errors + 1
    if CV.errors >= 20 and not CV.disabled then
        CV.disabled = true
        CV.active = false
        release_camera()
        log("too many errors, cinematic view switched off until scripts are reloaded")
    end
end

local function update_cockpit_shot(s, t, cond, dt)
    local dx, dy, dz, psi, the, phi = s.def.update(s, CV.eye, t)
    if settings.shake then
        local a = 0.2 * shake_level(cond, dt, now())
        psi = psi + a * 0.5 * jitter(t, 4)
        the = the + a * 0.5 * jitter(t, 5)
    end
    local e = CV.eye
    write_head(e.x + dx, e.y + dy, e.z + dz, psi, the, phi)
end

-- Liftoff and touchdown cut straight to shots of their own, and a touchdown
-- shakes the cameras.
local function watch_flight(t)
    local cond = conditions()
    CV.phase = cond.phase
    if cond.onground then
        if CV.was_on_ground == false and CV.last_vy then
            SH.impact = M.clamp(-CV.last_vy / 2, 0.15, 1.5)
            SH.impact_t = t
        end
        if CV.was_on_ground ~= true then CV.ground_since = t end
    elseif cond.agl > 150 then
        CV.landing_shown = false -- ready for the next approach
    end
    local event
    if CV.was_on_ground == true and not cond.onground and cond.gs > 25 and t - (CV.ground_since or t) > 3 then
        event = EVENT_SHOTS.liftoff
    elseif not cond.onground and not CV.landing_shown and cond.agl < 40 and cond.vy < -0.8 and cond.gs > 20 then
        event = EVENT_SHOTS.touchdown
    end
    CV.was_on_ground = cond.onground
    CV.last_vy = cond.vy
    if event and CV.active and XP.camera_ok and settings.mode ~= "cockpit" and not cond.paused
        and not (CV.shot and CV.shot.def.event) then
        if event == EVENT_SHOTS.touchdown then CV.landing_shown = true end
        cut_to(event)
    end
    return cond
end

local function watch_view()
    if CV.settle > 0 then
        CV.settle = CV.settle - 1
        if CV.settle == 0 and CV.shot then
            local vt = view_type()
            if CV.shot.def.kind == "cockpit" and vt ~= VIEW_3D_COCKPIT and CV.view_retries < 2 and R.view_type then
                -- the command didn't switch to the 3D cockpit; set the view directly
                CV.view_retries = CV.view_retries + 1
                XP.seti(R.view_type, VIEW_3D_COCKPIT)
                CV.settle = 3
            else
                CV.expected_view = vt
            end
        end
    elseif CV.expected_view and view_type() ~= CV.expected_view then
        stop("view") -- the user picked another view: leave them in it
    end
end

local function tick()
    if not XP.lib then CV.fclock = CV.fclock + gf(R.frame_period, 1 / 30) end
    local t = now()
    local dt = M.clamp(t - (CV.tick_last or t), 0, 0.1)
    CV.tick_last = t
    CV.heartbeat = t
    CV.last_tick = t

    if CV.disabled then return end

    if CV.cam_error then
        report_error("camera", CV.cam_error)
        CV.cam_error = nil
        stop("error")
    end

    local input = had_input(t)
    if input then
        CV.last_input = t
        CV.afk_armed = true
    end
    local cond = watch_flight(t)

    -- after a cinematic: put the head back where it was and check the view
    if not CV.active then
        if CV.restore_frames > 0 and CV.saved_head then
            local h = CV.saved_head
            write_head(h.x, h.y, h.z, h.psi, h.the, h.phi)
            CV.restore_frames = CV.restore_frames - 1
        end
        if CV.restore_view_check > 0 then
            CV.restore_view_check = CV.restore_view_check - 1
            if CV.restore_view_check == 0 and view_type() ~= CV.saved_view then
                if CV.saved_view == VIEW_3D_COCKPIT then command_once(CMD_COCKPIT) end
            end
        end
    end

    if CV.active then
        local grace = t - CV.started_at > 1.0
        local exits_on_input = CV.reason == "afk" or settings.manual_exit_on_input
        if input and grace and exits_on_input then
            stop("input")
            return
        end
        if vr_on() then
            stop("vr")
            return
        end
        if CV.shot and CV.shot.def.kind == "outside" and not CV.cam_active then
            if CV.cam_lost then
                -- another plugin took the camera; don't fight it
                stop("lost")
                CV.afk_armed = false
                return
            end
            take_camera()
        end

        watch_view()
        if not CV.active then return end

        -- fades
        local tr = CV.trans
        if tr then
            local e = t - tr.t0
            if tr.phase == "out" then
                CV.fade = M.clamp(e / FADE_TIME, 0, 1)
                if e >= FADE_TIME then
                    begin_shot(tr.def)
                    tr.phase = "in"
                    tr.t0 = t
                end
            else
                if CV.settle > 0 then tr.t0 = t end -- stay black until the view has switched
                CV.fade = 1 - M.clamp((t - tr.t0) / FADE_TIME, 0, 1)
                if t - tr.t0 >= FADE_TIME then
                    CV.trans = nil
                    CV.fade = 0
                end
            end
        end

        if CV.zoom_dir ~= 0 and outside_shot() then
            CV.user_zoom = M.clamp(CV.user_zoom * math.exp(CV.zoom_dir * dt), 0.5, 4)
        end

        local s = CV.shot
        if s then
            if s.def.kind == "cockpit" then update_cockpit_shot(s, t - s.t0, cond, dt) end
            if not CV.trans and t - s.t0 >= s.duration then next_shot(false) end
        end
    elseif settings.afk_enabled and CV.afk_armed and t - CV.last_input >= settings.afk_timeout then
        local paused = gi(R.paused, 0) ~= 0
        if not vr_on() and (settings.afk_when_paused or not paused) then start("afk") end
    end

    if CV.dirty and t - CV.dirty_t > 1.5 then
        CV.dirty = false
        save_settings()
    end
end

------------------------------------------------------------------------------
-- Drawing: letterbox, fades, messages
------------------------------------------------------------------------------

local function text_width(text)
    if measure_string then
        local w = measure_string(text)
        if type(w) == "number" then return w end
    end
    return #text * 7
end

local function draw_text(x, y, text)
    draw_string(math.floor(x), math.floor(y), text, 1, 1, 1)
end

local function draw()
    local t = now()
    CV.heartbeat = t
    local dt = M.clamp(t - (CV.draw_last or t), 0, 0.1)
    CV.draw_last = t
    -- the letterbox slides in and out
    local target = (CV.active and settings.letterbox) and 1 or 0
    if CV.bars < target then
        CV.bars = math.min(target, CV.bars + dt / 0.6)
    elseif CV.bars > target then
        CV.bars = math.max(target, CV.bars - dt / 0.35)
    end
    local toast_on = CV.toast_text and t < CV.toast_until
    -- if the frame loop has stopped, draw nothing rather than risk a stuck black screen
    local ticking = t - CV.last_tick < 1.0
    local fade = (CV.active and ticking) and CV.fade or 0
    if CV.bars <= 0 and fade <= 0 and not toast_on then return end

    local w, h = SCREEN_WIDTH or 1920, SCREEN_HEIGHT or 1080
    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)

    local bar = 0
    if CV.bars > 0 then
        bar = math.max(0, (h - w / 2.39) / 2) * M.ease(CV.bars)
        if bar > 0 then
            glColor4f(0, 0, 0, 1)
            glRectf(0, 0, w, bar)
            glRectf(0, h - bar, w, h)
        end
    end

    if fade > 0 then
        glColor4f(0, 0, 0, fade)
        glRectf(0, 0, w, h)
    end

    if toast_on then
        local tw = text_width(CV.toast_text)
        local x, y = (w - tw) / 2, math.max(bar, 0) + 60
        glColor4f(0, 0, 0, 0.6)
        glRectf(x - 16, y - 12, x + tw + 16, y + 26)
        draw_text(x, y, CV.toast_text)
    end
end

------------------------------------------------------------------------------
-- Settings window
------------------------------------------------------------------------------

local function status_text()
    if CV.disabled then return "Switched off after errors (see X-Plane's Log.txt)" end
    if CV.active then
        local label = CV.shot and CV.shot.def.label or "starting"
        return "Running (" .. (CV.reason == "afk" and "you were away" or "started by you") .. "): " .. label
    end
    if not settings.afk_enabled then return "Off. Auto-start when away is off." end
    if vr_on() then return "Off. Not available in VR." end
    local left = math.max(0, settings.afk_timeout - (now() - CV.last_input))
    return string.format("Off. Starts after %d s with no input (%d s to go).", settings.afk_timeout, math.ceil(left))
end

local function toggle_settings()
    CV.capturing = nil
    if CV.wnd then
        float_wnd_destroy(CV.wnd)
        CV.wnd = nil
        return
    end
    if not float_wnd_create then
        toast("The settings window needs FlyWithLua NG+; edit cinematic_view.ini instead", 4)
        return
    end
    CV.wnd = float_wnd_create(480, 660, 1, true)
    float_wnd_set_title(CV.wnd, "Cinematic View " .. VERSION)
    float_wnd_set_imgui_builder(CV.wnd, "CinematicView_build_settings")
    float_wnd_set_onclose(CV.wnd, "CinematicView_settings_closed")
end

------------------------------------------------------------------------------
-- Actions and their keys
------------------------------------------------------------------------------

local function toggle_cinematic()
    if CV.active then
        stop("manual")
    elseif now() - CV.input_stop_at > 0.5 then
        -- (the key that just ended a cinematic shouldn't start it again)
        start("manual")
    end
end

local function toggle_afk()
    settings.afk_enabled = not settings.afk_enabled
    mark_dirty()
    toast(settings.afk_enabled
        and string.format("Cinematic view starts after %d s away", settings.afk_timeout)
        or "Cinematic view won't start by itself")
end

local function cycle_mode()
    local i = 1
    for k, mode in ipairs(MODES) do if mode == settings.mode then i = k end end
    settings.mode = MODES[i % #MODES + 1]
    mark_dirty()
    toast("Cinematic shots: " .. MODE_LABELS[settings.mode])
    if CV.active then next_shot(true) end
end

-- id: the X-Plane command (FlyWithLua/cinematic_view/<id>) and the ini key (bind_<id>)
local ACTIONS = {
    { id = "toggle", label = "Start / stop", desc = "start/stop", press = toggle_cinematic },
    { id = "next_shot", label = "Next shot", desc = "cut to the next shot",
        press = function() if CV.active then next_shot(false) end end },
    { id = "toggle_afk", label = "Auto-start on/off", desc = "auto-start when away on/off", press = toggle_afk },
    { id = "cycle_mode", label = "Cycle shot types", desc = "cycle mixed/outside/cockpit shots", press = cycle_mode },
    { id = "zoom_in", label = "Zoom in", desc = "zoom in (hold)",
        press = function() zoom_begin(1) end, release = zoom_end },
    { id = "zoom_out", label = "Zoom out", desc = "zoom out (hold)",
        press = function() zoom_begin(-1) end, release = zoom_end },
    { id = "settings", label = "This window", desc = "show/hide the settings window", press = toggle_settings },
}
local ACTION_BY_ID = {}
for _, a in ipairs(ACTIONS) do ACTION_BY_ID[a.id] = a end

local KEY_NAMES = {
    [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Return", [0x20] = "Space",
    [0x21] = "Page Up", [0x22] = "Page Down", [0x23] = "End", [0x24] = "Home",
    [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down", [0x2D] = "Insert", [0x2E] = "Delete",
    [0x6A] = "Num *", [0x6B] = "Num +", [0x6D] = "Num -", [0x6E] = "Num .", [0x6F] = "Num /",
    [0xB0] = "=", [0xB1] = "-", [0xB2] = "]", [0xB3] = "[", [0xB4] = "'", [0xB5] = ";", [0xB6] = "\\",
    [0xB7] = ",", [0xB8] = "/", [0xB9] = ".", [0xBA] = "`", [0xBB] = "Enter", [0xBC] = "Num Enter", [0xBD] = "Num =",
}

-- mods: 1 shift, 2 ctrl, 4 alt
local function key_name(vk, mods)
    local name = KEY_NAMES[vk]
    if not name then
        if (vk >= 0x30 and vk <= 0x39) or (vk >= 0x41 and vk <= 0x5A) then
            name = string.char(vk)
        elseif vk >= 0x60 and vk <= 0x69 then
            name = "Num " .. (vk - 0x60)
        elseif vk >= 0x70 and vk <= 0x87 then
            name = "F" .. (vk - 0x6F)
        else
            name = "Key " .. vk
        end
    end
    local prefix = ""
    if math.floor(mods / 2) % 2 == 1 then prefix = prefix .. "Ctrl+" end
    if math.floor(mods / 4) % 2 == 1 then prefix = prefix .. "Alt+" end
    if mods % 2 == 1 then prefix = prefix .. "Shift+" end
    return prefix .. name
end

-- A key as stored in the ini: "<virtual key> <modifiers> <name>".
local function parse_bind(v)
    local vk, mods, name = (v or ""):match("^(%d+) (%d+) (.+)$")
    if vk then return tonumber(vk), tonumber(mods), name end
end

local function action_for_key(vk, mods)
    for _, a in ipairs(ACTIONS) do
        local bvk, bmods = parse_bind(settings["bind_" .. a.id])
        if bvk == vk and bmods == mods then return a end
    end
end

-- One key does one thing: setting it here takes it off any other action.
local function set_bind(id, vk, mods)
    for _, a in ipairs(ACTIONS) do
        local bvk, bmods = parse_bind(settings["bind_" .. a.id])
        if bvk == vk and bmods == mods then settings["bind_" .. a.id] = "" end
    end
    settings["bind_" .. id] = string.format("%d %d %s", vk, mods, key_name(vk, mods))
    mark_dirty()
end

local function press_action(a, from_command)
    if from_command then
        -- whatever ran the command (a key X-Plane maps to it, a joystick
        -- button) isn't "input" that ends the cinematic
        CV.input_flag = false
        CV.ignore_buttons_until = now() + 0.5
    end
    a.press()
end

local function release_action(a, from_command)
    if from_command then CV.ignore_buttons_until = now() + 0.5 end
    if a.release then a.release() end
end

-- X-Plane's zoom keys: = and - on the main keyboard, + and - on the keypad.
local ZOOM_KEYS = { [0xB0] = 1, [0x6B] = 1, [0xB1] = -1, [0x6D] = -1 }

local function on_key()
    local vk = VKEY or 0
    if vk < 0 then vk = vk + 256 end -- FlyWithLua passes it as a signed char
    local mods = (SHIFT_KEY and 1 or 0) + (CONTROL_KEY and 2 or 0) + (OPTION_KEY and 4 or 0)
    if KEY_ACTION ~= "pressed" then
        if CV.keys_down[vk] then
            CV.keys_down[vk] = nil
            RESUME_KEY = true
        end
        if CV.held[vk] then
            release_action(CV.held[vk], false)
            CV.held[vk] = nil
        end
        if CV.zoom_vk == vk then
            zoom_end()
            RESUME_KEY = true
        end
        return
    end

    if CV.capturing then
        if vk ~= 0x1B then set_bind(CV.capturing, vk, mods) end -- Esc cancels
        CV.capturing = nil
        RESUME_KEY = true
        return
    end

    local a = action_for_key(vk, mods)
    if a then
        RESUME_KEY = true -- ours, not X-Plane's
        local t = now()
        local down = CV.keys_down[vk]
        CV.keys_down[vk] = t
        if down and t - down < 3 then return end -- auto-repeat
        if a.release then CV.held[vk] = a end
        press_action(a, false)
        return
    end

    -- zooming doesn't end the cinematic
    if ZOOM_KEYS[vk] and CV.active and not CONTROL_KEY and not OPTION_KEY then
        if outside_shot() then
            RESUME_KEY = true -- X-Plane's zoom can't move our camera, so we zoom it
            if CV.zoom_vk ~= vk then
                zoom_begin(ZOOM_KEYS[vk])
                CV.zoom_vk = vk
            end
        end
        return
    end

    CV.input_flag = true
end

------------------------------------------------------------------------------
-- What's in the settings window
------------------------------------------------------------------------------

local function checkbox(label, key)
    local changed, v = imgui.Checkbox(label, settings[key])
    if changed then
        settings[key] = v
        mark_dirty()
    end
end

local function build_settings()
    local changed, v
    imgui.TextUnformatted(status_text())
    if imgui.Button(CV.active and "Stop" or "Start now") then
        if CV.active then stop("manual") else start("manual") end
    end
    if CV.active then
        imgui.SameLine()
        if imgui.Button("Next shot") then next_shot(false) end
    end
    imgui.Separator()

    imgui.TextUnformatted("When you're away")
    checkbox("Start when I'm away from the controls", "afk_enabled")
    changed, v = imgui.SliderInt("Away for", settings.afk_timeout, 15, 900, "%d s")
    if changed then settings.afk_timeout = v; mark_dirty() end
    checkbox("Also start while the sim is paused", "afk_when_paused")
    checkbox("Any input also ends a cinematic I started", "manual_exit_on_input")
    imgui.Separator()

    imgui.TextUnformatted("Shots")
    for i, mode in ipairs(MODES) do
        if i > 1 then imgui.SameLine() end
        if imgui.RadioButton(MODE_LABELS[mode], settings.mode == mode) then
            settings.mode = mode
            mark_dirty()
        end
    end
    if settings.mode == "mixed" then
        changed, v = imgui.SliderInt("In the cockpit", settings.cockpit_share, 0, 100, "%d%%")
        if changed then settings.cockpit_share = v; mark_dirty() end
    end
    changed, v = imgui.SliderFloat("Shortest shot", settings.shot_min, 3, 30, "%.0f s")
    if changed then
        settings.shot_min = v
        settings.shot_max = math.max(settings.shot_max, v)
        mark_dirty()
    end
    changed, v = imgui.SliderFloat("Longest shot", settings.shot_max, 3, 45, "%.0f s")
    if changed then
        settings.shot_max = v
        settings.shot_min = math.min(settings.shot_min, v)
        mark_dirty()
    end
    changed, v = imgui.SliderFloat("Camera speed", settings.camera_speed, 0.25, 2.5, "%.2fx")
    if changed then settings.camera_speed = v; mark_dirty() end
    checkbox("Letterbox bars", "letterbox")
    imgui.SameLine()
    checkbox("Fades", "fades")
    imgui.SameLine()
    checkbox("Camera shake", "shake")
    imgui.Separator()

    imgui.TextUnformatted("Keys")
    for _, a in ipairs(ACTIONS) do
        local _, _, name = parse_bind(settings["bind_" .. a.id])
        local capturing = CV.capturing == a.id
        imgui.TextUnformatted(a.label)
        imgui.SameLine(150)
        imgui.TextUnformatted(capturing and "Press a key..." or (name or "-"))
        imgui.SameLine(320)
        if imgui.Button((capturing and "Cancel" or "Set") .. "##set_" .. a.id) then
            CV.capturing = (not capturing) and a.id or nil
        end
        if name and not capturing then
            imgui.SameLine()
            if imgui.Button("Clear##clear_" .. a.id) then
                settings["bind_" .. a.id] = ""
                mark_dirty()
            end
        end
    end
    imgui.TextWrapped("Keys set here take priority over X-Plane's own (Esc cancels setting one). "
        .. "+ and - zoom during a cinematic. For joystick buttons, assign the "
        .. "FlyWithLua/cinematic_view commands under Settings > Joystick.")

    if not XP.camera_ok then
        imgui.Separator()
        imgui.TextWrapped("The X-Plane SDK couldn't be loaded, so outside shots use X-Plane's own chase, orbit and flyby views.")
    end
end

------------------------------------------------------------------------------
-- Global entry points for FlyWithLua (commands, menu, callbacks)
------------------------------------------------------------------------------

local function guarded(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then report_error(name, err) end
    end
end

CinematicView_tick = guarded("frame", tick)
CinematicView_draw = guarded("draw", draw)
CinematicView_on_key = guarded("keyboard", on_key)

CinematicView_command = guarded("command", function(id, down)
    local a = ACTION_BY_ID[id]
    if not a then return end
    if down then press_action(a, true) else release_action(a, true) end
end)

CinematicView_toggle_settings = guarded("settings", toggle_settings)
CinematicView_build_settings = guarded("settings window", build_settings)
function CinematicView_settings_closed()
    CV.wnd = nil
    CV.capturing = nil
end

CinematicView_on_mouse = guarded("mouse", function()
    CV.input_flag = true
end)

function CinematicView_on_exit()
    pcall(function()
        if CV.active then stop("exit") end
        if CV.saved_head and CV.restore_frames > 0 then
            local h = CV.saved_head
            write_head(h.x, h.y, h.z, h.psi, h.the, h.phi)
        end
    end)
    pcall(zoom_end)
    pcall(release_camera)
    if XP.probe then
        pcall(function() XP.lib.XPLMDestroyProbe(XP.probe) end)
        XP.probe = nil
    end
    if CV.dirty then pcall(save_settings) end
end

------------------------------------------------------------------------------
-- Start up
------------------------------------------------------------------------------

math.randomseed(os.time())
math.random(); math.random()
load_settings()
pcall(joystick_setup)
CV.last_input = now()
CV.heartbeat = now()
CV.last_tick = now()
CV.size = aircraft_size()

do_every_frame("CinematicView_tick()")
do_every_draw("CinematicView_draw()")
do_on_keystroke("CinematicView_on_key()")
do_on_mouse_click("CinematicView_on_mouse()")
do_on_mouse_wheel("CinematicView_on_mouse()")
do_on_exit("CinematicView_on_exit()")

-- every action as an X-Plane command too, for joystick buttons (the release
-- is handled for all of them, so letting go of the button isn't "input")
for _, a in ipairs(ACTIONS) do
    create_command("FlyWithLua/cinematic_view/" .. a.id, "Cinematic view: " .. a.desc,
        string.format('CinematicView_command("%s", true)', a.id), "",
        string.format('CinematicView_command("%s", false)', a.id))
end

-- one menu entry: the window has everything else
add_macro("Cinematic View", "CinematicView_toggle_settings()")

log(string.format("version %s loaded (%s)", VERSION,
    XP.camera_ok and "custom outside cameras" or "X-Plane's built-in outside views"))
