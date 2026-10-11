--[[
    Cinematic View for X-Plane 12
    A FlyWithLua NG+ script

    A self-directing camera in the style of the Need for Speed and Forza
    Horizon attract modes. Every shot is generated as it starts rather than
    picked from a list: cameras moving around the aircraft, standing by the
    flight path, or fixed to the airframe, and the pilot's view in the
    cockpit, with letterbox bars and fades. Shots suit what the aircraft is
    doing (runway-level shots on takeoff and landing, air-to-air in cruise),
    and liftoff and touchdown get shots of their own.

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

local VERSION = "2.1"

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

local DEFAULTS = {
    afk_enabled = true,           -- start by itself when you're away
    afk_timeout = 120,            -- seconds without input before it starts
    mode = "mixed",               -- "mixed", "outside" or "cockpit"
    cockpit_share = 30,           -- % of shots in the cockpit in mixed mode
    shot_min = 7,                 -- shortest shot, seconds
    shot_max = 14,                -- longest shot, seconds
    camera_pace = 0.5,            -- camera speed: how fast cameras move (0.1 to 2)
    pan_pace = 0.5,               -- panning speed: how fast cameras turn (0.1 to 2)
    letterbox = true,             -- cinema bars top and bottom
    fades = true,                 -- dip to black between some shots
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
    -- learned, not set: X-Plane's number for its chase view, so views can be
    -- switched without X-Plane announcing each change (0 until learned)
    chase_view = 0,
}

local MODES = { "mixed", "outside", "cockpit" }
local MODE_LABELS = { mixed = "Mixed", outside = "Outside only", cockpit = "Cockpit only" }

local settings = {}
for k, v in pairs(DEFAULTS) do settings[k] = v end

-- Aircraft sizes set by hand, by aircraft file, saved in the ini as
-- "size:<file> = <metres>".
local aircraft_sizes = {}

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
    s.camera_pace = math.max(0.1, math.min(2, s.camera_pace))
    s.pan_pace = math.max(0.1, math.min(2, s.pan_pace))
    s.chase_view = math.max(0, math.floor(s.chase_view))
    s.joystick_deadband = math.max(0.001, math.min(0.5, s.joystick_deadband))
    for k, v in pairs(s) do
        if k:match("^bind_") and v ~= "" and not v:match("^%d+ %d+ .+$") then s[k] = "" end
    end
end

local function load_settings()
    local f = io.open(settings_path(), "r")
    if not f then return end
    for line in f:lines() do
        local plane, metres = line:match("^size:(.-)%s*=%s*([%d%.]+)%s*$")
        if plane and tonumber(metres) then aircraft_sizes[plane] = tonumber(metres) end
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
    local planes = {}
    for plane in pairs(aircraft_sizes) do planes[#planes + 1] = plane end
    table.sort(planes)
    for _, plane in ipairs(planes) do
        f:write("size:", plane, " = ", string.format("%.1f", aircraft_sizes[plane]), "\n")
    end
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
        fov = "sim/graphics/view/field_of_view_deg",
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
    user_zoom = 1,          -- zoom set with + and - during a cinematic, as shown (eased)
    zoom_target = 1,        -- where the zoom is heading
    zoom_from = 1,          -- the target when this zoom began, so a tap still makes a step
    zoom_dir = 0,           -- +1 zooming in, -1 zooming out
    zoom_held = 0,          -- seconds this zoom has been held; it ramps up
    native_zoom = nil,      -- X-Plane zoom command held for a bound key or joystick button
    taken = {},             -- keys we're holding on to, by virtual key (see take_key)
    taken_recent = {},      -- keys let go of in the last second
    view_target = nil,      -- a view being switched to, checked once it has settled
    view_before = nil,
    view_by_command = false,
    learned_views = {},     -- X-Plane's numbers for its own views, by command
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

-- Which aircraft this is, for its size setting.
local function aircraft_key()
    local key = (type(AIRCRAFT_FILENAME) == "string" and AIRCRAFT_FILENAME ~= "" and AIRCRAFT_FILENAME)
        or (type(PLANE_ICAO) == "string" and PLANE_ICAO ~= "" and PLANE_ICAO) or "aircraft"
    return (key:gsub("[\r\n=]", ""))
end

-- The size shots are framed and kept clear by: set for this aircraft, or worked out.
local function current_size()
    local set = aircraft_sizes[aircraft_key()]
    if set then return M.clamp(set, 4, 100) end
    return aircraft_size()
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
-- Shots, generated
--
-- No fixed list: every shot is made up as it starts, from random choices
-- within limits that suit what the aircraft is doing. Outside there are three
-- kinds, and each covers a whole family of shots:
--   orbiting   a camera moving around the aircraft, in a frame that turns
--              with its heading: where it starts (round, up, how far), how it
--              moves (round, up or down, in or out), the lens, how it lags
--              turns. Chase, tracking, orbit, crane, pass-by, drone and
--              long-lens shots are all versions of it.
--   trackside  a camera standing still by the flight path, on the ground or
--              in the air, that the aircraft passes, comes towards or leaves.
--   mounted    a camera fixed just off the airframe, rolling and pitching
--              with it.
-- Inside, the pilot's head looks somewhere and pans slowly, holding still
-- otherwise.
--
-- Two settings limit how fast the picture moves. Camera speed: how far an
-- orbiting camera travels over a shot. Panning speed: how fast cameras turn,
-- trackside ones following the aircraft (so they stand further back from fast
-- aircraft), mounted ones drifting and the pilot's head panning. Zooming in
-- magnifies motion, so a zoomed-in camera moves less.
--
-- Cameras keep outside a sphere round the aircraft sized from its span (the
-- aircraft size setting), so they don't clip it.
------------------------------------------------------------------------------

-- Weights for: parked, taxiing, takeoff or landing roll, low (below about
-- 2000 ft), cruise. (X-Plane's own views, without the SDK, use these.)
local function W(parked, taxi, roll, low, cruise)
    return { parked = parked, taxi = taxi, roll = roll, low = low, cruise = cruise }
end

local MOTION_RATE = 5 -- degrees a second of camera movement or panning at speed 1

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

-- Cameras stay outside this distance from the aircraft's centre.
local function clearance(c) return 0.65 * c.size + 2 end

local function keep_clear(c, x, y, z)
    local dx, dy, dz = x - c.x, y - c.y, z - c.z
    local d = sqrt(dx * dx + dy * dy + dz * dz)
    local r = clearance(c)
    if d >= r then return x, y, z end
    if d < 0.01 then dx, dy, dz, d = 0, 1, 0, 1 end
    return c.x + dx * r / d, c.y + dy * r / d, c.z + dz * r / d
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

-- A tilted horizon now and then, as racing games do.
local function maybe_dutch(chance, most)
    if math.random() < chance then return M.sign() * M.rand(most * 0.4, most) end
    return 0
end

-- Tangent of half X-Plane's horizontal field of view, for framing.
local function fov_tan()
    local fov = gf(R.fov, 60)
    if fov < 20 or fov > 140 then fov = 60 end
    return math.tan(rad(fov) / 2)
end

-- The distance at normal zoom, and the zoom at a distance, at which the
-- aircraft fills fraction f of the picture's width.
local function framing_distance(S, f) return S / (2 * f * fov_tan()) end
local function framing_zoom(S, d, f) return 2 * d * f * fov_tan() / S end

-- A round-the-aircraft direction (0 behind, 90 right, 180 ahead) away from
-- the last few shots'.
local function fresh_azimuth()
    local az
    for _ = 1, 8 do
        az = M.rand(0, 360)
        if not CV.last_az or abs(M.wrap180(az - CV.last_az)) > 60 then break end
    end
    return az
end

local ELEVATION = { parked = { 3, 35 }, taxi = { 2, 30 }, roll = { 1, 20 }, low = { -12, 35 }, cruise = { -25, 60 } }
local LONG_LENS = { parked = 0.1, taxi = 0.15, roll = 0.25, low = 0.25, cruise = 0.3 }

local ORBITING = {
    id = "orbiting", kind = "outside",
    init = function(s, c)
        local S = c.size
        local phase = CV.phase or "cruise"
        local el = ELEVATION[phase]
        s.f = M.rand(0.32, 0.62) -- how much of the picture's width the aircraft fills
        s.zoom = math.random() < LONG_LENS[phase] and M.rand(2.5, 6) or 1
        s.d0 = math.max(framing_distance(S, s.f) * s.zoom, clearance(c) + 3)
        s.az0 = s.def.reveal and (180 + M.rand(-40, 40)) or fresh_azimuth()
        s.el0 = M.rand(el[1], el[2])
        if (phase == "cruise" or phase == "parked") and not s.def.reveal and math.random() < 0.12 then
            s.el0 = M.rand(50, 72) -- now and then from high above
        end
        -- the movement this shot has, shared between going round, up or down,
        -- and in or out
        local B = MOTION_RATE * s.pace * s.duration / s.zoom
        local wa, we, wd = math.random(), math.random() * 0.6, math.random() * 0.5
        if s.def.reveal then wa, we, wd = 1, 0.15, 0.1 end
        local sum = wa + we + wd
        s.daz = M.sign() * B * wa / sum
        s.del = M.clamp(s.el0 + M.sign() * B * we / sum, math.min(el[1], s.el0), 75) - s.el0
        s.kd = math.exp(M.sign() * (B * wd / sum) / 50)
        s.tau = M.rand(0.4, 1.8) -- how much it lags the aircraft's turns
        s.behind = abs(M.wrap180(s.az0)) < 50 and s.zoom == 1
        s.bank = s.behind and M.rand(0, 0.25) or 0
        s.lead = M.rand(0, 0.25) * S -- aim a little ahead, leaving room in front
        s.offh, s.offp = M.rand(-4, 4) / s.zoom, M.rand(-2, 2) / s.zoom
        s.dutch = maybe_dutch(0.2, 5)
        s.hdg = c.track
        s.gs, s.acc = c.gs, 0
        CV.last_az = s.az0 + s.daz / 2
    end,
    update = function(s, c, t, out)
        s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, s.tau))
        if c.dt > 0 then
            s.acc = s.acc + ((c.gs - s.gs) / c.dt - s.acc) * M.smooth(c.dt, 0.6)
        end
        s.gs = c.gs
        local k = M.ease(t / s.duration)
        local d = s.d0 * s.kd ^ k
        if s.behind then d = d + M.clamp(s.acc * 1.5, -4, 10) end -- springs back as it accelerates
        local a, e = rad(s.az0 + s.daz * k), rad(s.el0 + s.del * k)
        local cx, cy, cz = yaw_point(c, s.hdg, sin(a) * cos(e) * d, sin(e) * d, cos(a) * cos(e) * d)
        cx, cy, cz = keep_clear(c, cx, cy, cz)
        local fx, fz = sin(rad(c.track)), -cos(rad(c.track))
        aim(out, cx, cy, cz, c.x + fx * s.lead, c.y, c.z + fz * s.lead, s.dutch + c.phi * s.bank, s.zoom)
        out.heading = out.heading + s.offh
        out.pitch = out.pitch + s.offp
    end,
}

-- The opening shot: from ahead, swinging round.
local REVEAL = setmetatable({ reveal = true }, { __index = ORBITING })

-- The fastest a camera at (px, py, pz) turns to follow the aircraft over the
-- next t seconds, in degrees a second.
local function peak_turn(c, px, py, pz, t)
    local peak, lh, lp = 0, nil, nil
    local n = 40
    for i = 0, n do
        local tt = t * i / n
        local h, p = M.look_at(px, py, pz, c.x + c.vx * tt, c.y + c.vy * tt, c.z + c.vz * tt)
        if lh then peak = math.max(peak, sqrt(M.wrap180(h - lh) ^ 2 + (p - lp) ^ 2) * n / t) end
        lh, lp = h, p
    end
    return peak
end

-- Stands the camera beside where the aircraft will be in T seconds, lat
-- metres to the right of its track (left if negative) and ahead metres along
-- it, on the ground or at its height; then moves it further out until it
-- never has to turn faster than the pan limit.
local function plan_trackside(s, c, T, lat, ahead, ground)
    local tr = rad(c.track)
    local fx, fz, rx, rz = sin(tr), -cos(tr), cos(tr), sin(tr)
    local side = lat < 0 and -1 or 1
    lat = M.clamp(abs(lat), clearance(c) + 10, 700)
    s.ground = ground
    s.height = s.height or M.rand(1.2, 3.0)
    local rise = M.rand(-0.3, 0.6) * c.size
    for _ = 1, 12 do
        s.px = c.x + c.vx * T + rx * lat * side + fx * ahead
        s.pz = c.z + c.vz * T + rz * lat * side + fz * ahead
        s.py = not ground and (c.y + c.vy * T + rise) or nil
        local py = s.py or (c.y - c.agl + s.height)
        if lat >= 700 or peak_turn(c, s.px, py, s.pz, s.duration) <= s.pan_cap then break end
        lat = math.min(700, lat * 1.3)
    end
end

-- Trackside cameras follow the aircraft and zoom to keep it a similar size,
-- but zoom out when they're turning fast (or about to), so the picture never
-- sweeps faster than the pan limit.
local function trackside_update(s, c, t, out)
    local py = s.py
    if s.ground then
        local g = terrain_y(s.px, c.y, s.pz) or (c.y - c.agl)
        py = g + s.height
    end
    local d = sqrt((c.x - s.px) ^ 2 + (c.y - py) ^ 2 + (c.z - s.pz) ^ 2)
    local h, p = M.look_at(s.px, py, s.pz, c.x, c.y, c.z)
    if s.lh and c.dt > 0 then
        local turn = sqrt(M.wrap180(h - s.lh) ^ 2 + (p - s.lp) ^ 2) / c.dt
        s.turn = s.turn and (s.turn + (turn - s.turn) * M.smooth(c.dt, 0.2)) or turn
    end
    s.lh, s.lp = h, p
    local turn = math.max(s.turn or 0, peak_turn(c, s.px, py, s.pz, 0.6))
    local zoom = framing_zoom(c.size, d, s.f)
    if turn > 0.01 then zoom = math.min(zoom, s.pan_cap / turn) end
    zoom = M.clamp(zoom, 1, 10)
    -- out quickly, in gently
    local tau = (s.zoom and zoom < s.zoom) and 0.12 or 0.4
    s.zoom = s.zoom and (s.zoom + (zoom - s.zoom) * M.smooth(c.dt, tau)) or zoom
    aim(out, s.px, py, s.pz, c.x + c.vx * 0.1, c.y, c.z + c.vz * 0.1, s.dutch or 0, s.zoom)
end

-- How fast (degrees a second) trackside cameras may turn to follow.
local function pan_cap(s) return M.clamp(40 * s.pan, 4, 80) end

local TRACKSIDE = {
    id = "trackside", kind = "outside", min_gs = 5,
    init = function(s, c)
        local v = math.max(c.gs, 1)
        s.pan_cap = pan_cap(s)
        s.f = M.rand(0.3, 0.55)
        local ground = c.agl < 300 and CV.phase ~= "cruise"
        local r, T, lat = math.random()
        if r < 0.5 then
            -- the aircraft passes the camera
            T = M.rand(3, 6)
            lat = v / rad(s.pan_cap)
            s.duration = T + M.rand(2, 4)
        elseif r < 0.8 then
            -- it comes towards the camera, and the shot ends before it passes
            T = M.rand(8, 12)
            lat = v * T * math.tan(rad(M.rand(4, 10)))
            s.duration = M.rand(4, T - 3)
        else
            -- it leaves the camera behind
            T = -M.rand(1.5, 3)
            lat = M.rand(0.5, 1.0) * v
            s.duration = M.rand(5, 8)
        end
        plan_trackside(s, c, T, M.sign() * lat, 0, ground)
        s.dutch = maybe_dutch(0.35, 4)
    end,
    update = trackside_update,
}

-- Mount points just off the airframe (azimuth from the nose, elevation) and
-- where each looks, in spans from the centre.
local MOUNTS = {
    { az = { 150, 210 }, el = { 10, 35 }, look = { 0, 0.03, -0.8 } },          -- above and behind the tail
    { az = { 60, 120 }, el = { -5, 15 }, look = { 0, 0.03, -0.25 }, sides = true }, -- off a wingtip
    { az = { -25, 25 }, el = { 0, 20 }, look = { 0, 0.03, 0.3 } },             -- ahead of the nose, looking back
    { az = { 30, 150 }, el = { -25, -10 }, look = { 0, 0, 0 }, sides = true, airborne = true }, -- below, off to one side
}

local MOUNTED = {
    id = "mounted", kind = "outside",
    init = function(s, c)
        local pool = {}
        for _, m in ipairs(MOUNTS) do
            if not (m.airborne and c.onground) then pool[#pool + 1] = m end
        end
        local m = pool[math.random(#pool)]
        local az, el = M.rand(m.az[1], m.az[2]), M.rand(m.el[1], m.el[2])
        if m.sides then az = az * M.sign() end
        local r = clearance(c) * M.rand(1.0, 1.15)
        local a, e = rad(az), rad(el)
        s.mx, s.my, s.mz = sin(a) * cos(e) * r, sin(e) * r, -cos(a) * cos(e) * r
        s.lx, s.ly, s.lz = m.look[1] * c.size, m.look[2] * c.size, m.look[3] * c.size
        -- the look point drifts sideways a little over the shot
        local reach = sqrt((s.mx - s.lx) ^ 2 + (s.my - s.ly) ^ 2 + (s.mz - s.lz) ^ 2)
        s.drift = M.sign() * math.tan(rad(math.min(MOTION_RATE * s.pan * s.duration * 0.5, 15))) * reach
    end,
    update = function(s, c, t, out)
        local k = M.ease(t / s.duration) - 0.5
        mounted(out, c, s.mx, s.my, s.mz, s.lx + s.drift * k, s.ly, s.lz)
    end,
}

-- How the outside kinds mix in each phase: orbiting, trackside, mounted.
local GENERATED = { ORBITING, TRACKSIDE, MOUNTED }
local OUTSIDE_MIX = {
    parked = { 0.8, 0, 0.2 }, taxi = { 0.6, 0.2, 0.2 }, roll = { 0.45, 0.35, 0.2 },
    low = { 0.4, 0.4, 0.2 }, cruise = { 0.65, 0.15, 0.2 },
}

-- Moments: these cut in when they happen instead of waiting their turn.
local EVENT_SHOTS = {
    -- by the runway a little past where the aircraft is about to touch down
    -- (allowing for the flare)
    touchdown = {
        id = "touchdown", kind = "outside", event = true,
        init = function(s, c)
            local T = M.clamp(c.agl / math.max(-c.vy, 0.5), 2, 16)
            s.duration = T + 5
            s.pan_cap = pan_cap(s)
            s.f = M.rand(0.3, 0.5)
            s.height = M.rand(1.0, 1.8)
            plan_trackside(s, c, T, M.sign() * math.max(c.gs, 1) / rad(s.pan_cap),
                0.3 * c.size + 15 + c.gs * 1.5, true)
            s.dutch = maybe_dutch(0.5, 3)
        end,
        update = trackside_update,
    },
    -- low by the runway as the aircraft lifts off and climbs away
    liftoff = {
        id = "liftoff", kind = "outside", event = true,
        init = function(s, c)
            s.duration = 7
            s.pan_cap = pan_cap(s)
            s.f = M.rand(0.3, 0.5)
            s.height = M.rand(0.8, 1.5)
            plan_trackside(s, c, 0.6, M.sign() * math.max(c.gs, 1) / rad(s.pan_cap), 0, true)
            s.dutch = maybe_dutch(0.5, 3)
        end,
        update = trackside_update,
    },
}

-- Used when the plugin SDK can't be loaded: X-Plane's own outside views.
local BUILTIN_SHOTS = {
    { id = "xp_chase", command = "sim/view/chase", w = W(1, 2, 3, 3, 3) },
    { id = "xp_circle", command = "sim/view/circle", w = W(3, 1, 0, 1, 2) },
    { id = "xp_spot", command = "sim/view/still_spot", w = W(0, 1, 3, 3, 2), min_gs = 15 },
    { id = "xp_linear", command = "sim/view/linear_spot", w = W(0, 1, 2, 2, 2), min_gs = 15 },
}
for _, d in ipairs(BUILTIN_SHOTS) do d.kind = "builtin" end

-- Inside: where the pilot's head is (dx, dy, dz from the eye point: right,
-- up, aft, metres) and a slow pan from one heading to another, at a steady
-- pitch. No bobbing.
local COCKPIT = {
    id = "cockpit", kind = "cockpit",
    init = function(s, e)
        local side = e.seat ~= 0 and e.seat or M.sign() -- the pilot's side: -1 left
        s.dx, s.dy, s.dz = 0, 0, 0
        local r = math.random()
        if r < 0.3 then
            -- forward through the windscreen
            s.psi0, s.the = M.rand(-15, 15), M.rand(-8, -2)
        elseif r < 0.5 then
            -- out of the side window
            s.psi0, s.the = side * M.rand(55, 95), M.rand(-10, 0)
        elseif r < 0.65 then
            -- across the panel
            s.psi0, s.the = M.rand(-20, 20), M.rand(-32, -20)
            s.dy, s.dz = -0.03, -0.05
        elseif r < 0.82 then
            -- over the shoulder
            s.dx, s.dy, s.dz = -side * M.rand(0.12, 0.2), M.rand(0.08, 0.14), M.rand(0.25, 0.38)
            s.psi0, s.the = M.rand(-10, 10), M.rand(-10, -4)
        elseif e.seat ~= 0 and abs(e.x) >= 0.2 then
            -- from the other seat, looking across
            s.dx = -2 * e.x
            s.psi0, s.the = side * M.rand(10, 35), M.rand(-10, -4)
        else
            s.psi0, s.the = -side * M.rand(20, 45), M.rand(-10, -4)
        end
        local B = math.min(MOTION_RATE * s.pan * s.duration * 1.5, 40)
        s.dpsi = M.sign() * B
        s.psi0 = s.psi0 - s.dpsi / 2
    end,
    update = function(s, e, t)
        return s.dx, s.dy, s.dz, s.psi0 + s.dpsi * M.ease(t / s.duration), s.the, 0
    end,
}

------------------------------------------------------------------------------
-- Camera control
------------------------------------------------------------------------------

local update_zoom -- (below, with the rest of the zoom)
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
    pos.x, pos.y, pos.z = cam_out.x, cam_out.y, cam_out.z
    pos.heading, pos.pitch, pos.roll = cam_out.heading, cam_out.pitch, cam_out.roll
    update_zoom(c.dt)
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
        gs = gs, agl = agl, vy = gf(R.vy), onground = ground,
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

-- Which kind of outside shot to generate next.
local function pick_outside(cond)
    if not XP.camera_ok then return pick_from(BUILTIN_SHOTS, cond) end
    local mix = OUTSIDE_MIX[cond.phase]
    local weights, total = {}, 0
    for i, def in ipairs(GENERATED) do
        local w = mix[i]
        if def.min_gs and (cond.paused or cond.gs < def.min_gs) then w = 0 end
        if CV.recent[1] == def.id and CV.recent[2] == def.id then w = 0 end -- not three in a row
        weights[i] = w
        total = total + w
    end
    if total <= 0 then return ORBITING end
    local r = math.random() * total
    for i, def in ipairs(GENERATED) do
        r = r - weights[i]
        if r <= 0 and weights[i] > 0 then return def end
    end
    return ORBITING
end

local function pick_shot()
    if not CV.eye then CV.eye = find_eye() end
    local cond = conditions()
    if CV.first_shot then
        CV.first_shot = false
        if XP.camera_ok and settings.mode ~= "cockpit" then return REVEAL end -- open with a reveal
    end
    if settings.mode == "cockpit" or (settings.mode == "mixed" and math.random(100) <= settings.cockpit_share) then
        return COCKPIT
    end
    return pick_outside(cond)
end

-- Views are switched by setting X-Plane's view number directly where it's
-- known, rather than with the view commands, so X-Plane doesn't announce each
-- change on screen. The chase view's number is learned the first time (with
-- its command) and remembered; a direct switch that doesn't take falls back
-- to the command.
local function view_number(kind)
    if kind == "cockpit" then return VIEW_3D_COCKPIT end
    if kind == "chase" then return settings.chase_view > 0 and settings.chase_view or nil end
    return CV.learned_views[kind]
end

local function view_command(kind)
    if kind == "cockpit" then return CMD_COCKPIT end
    if kind == "chase" then return CMD_CHASE end
    return kind
end

local function switch_view(kind)
    local known = view_number(kind)
    local vt = view_type()
    if known and vt == known then return end
    CV.view_target, CV.view_before = kind, vt
    if known and R.view_type then
        XP.seti(R.view_type, known)
        CV.view_by_command = false
    else
        command_once(view_command(kind))
        CV.view_by_command = true
    end
end

local function begin_shot(def)
    -- quicker cuts on takeoff and landing, longer shots in the calm
    local lo, hi = settings.shot_min, settings.shot_max
    local mid = (lo + hi) / 2
    local busy = CV.phase == "roll" or CV.phase == "low"
    local s = {
        def = def, t0 = now(), duration = busy and M.rand(lo, mid) or M.rand(mid, hi),
        pace = settings.camera_pace, pan = settings.pan_pace, inited = false,
    }
    CV.view_target = nil
    if def.kind == "cockpit" then
        release_camera()
        switch_view("cockpit")
        CV.base_view = "cockpit"
        def.init(s, CV.eye)
        s.inited = true
    elseif def.kind == "outside" then
        if CV.base_view ~= "chase" then switch_view("chase") end
        CV.base_view = "chase"
        take_camera()
    else
        release_camera()
        switch_view(def.command)
        CV.base_view = def.command
    end
    CV.shot = s
    CV.settle = 3
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

local ZOOM_MIN, ZOOM_MAX = 0.5, 4
local ZOOM_RATE = 0.7  -- while held: about 2x a second once it has ramped up
local ZOOM_STEP = 1.1  -- the least a tap zooms

local function zoom_end()
    if CV.zoom_dir ~= 0 then
        -- a tap still makes a step (eased in like the rest)
        local step = math.log(CV.zoom_target / CV.zoom_from) * CV.zoom_dir
        if step < math.log(ZOOM_STEP) then
            CV.zoom_target = M.clamp(CV.zoom_from * ZOOM_STEP ^ CV.zoom_dir, ZOOM_MIN, ZOOM_MAX)
        end
    end
    CV.zoom_dir = 0
    if CV.native_zoom then
        command_end(CV.native_zoom)
        CV.native_zoom = nil
    end
end

local function zoom_begin(dir)
    zoom_end()
    if outside_shot() then
        CV.zoom_dir = dir
        CV.zoom_held = 0
        CV.zoom_from = CV.zoom_target
    else
        CV.native_zoom = dir > 0 and "sim/general/zoom_in" or "sim/general/zoom_out"
        command_begin(CV.native_zoom)
    end
end

-- Each frame of an outside shot: the target moves while a zoom is held,
-- ramping up over a quarter of a second, and the zoom shown eases after it,
-- so starting and stopping are smooth.
function update_zoom(dt)
    if CV.zoom_dir ~= 0 then
        CV.zoom_held = CV.zoom_held + dt
        local rate = ZOOM_RATE * math.min(1, CV.zoom_held / 0.25)
        CV.zoom_target = M.clamp(CV.zoom_target * math.exp(CV.zoom_dir * rate * dt), ZOOM_MIN, ZOOM_MAX)
    end
    CV.user_zoom = CV.user_zoom + (CV.zoom_target - CV.user_zoom) * M.smooth(dt, 0.12)
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
    CV.size = current_size()
    CV.eye = find_eye()
    CV.base_view = (CV.saved_view == VIEW_3D_COCKPIT) and "cockpit" or nil
    CV.recent = {}
    CV.shot = nil
    CV.first_shot = true
    CV.input_flag = false
    zoom_end()
    CV.user_zoom, CV.zoom_target, CV.zoom_from = 1, 1, 1
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

local function update_cockpit_shot(s, t)
    local dx, dy, dz, psi, the, phi = s.def.update(s, CV.eye, t)
    local e = CV.eye
    write_head(e.x + dx, e.y + dy, e.z + dz, psi, the, phi)
end

-- Liftoff and touchdown cut straight to shots of their own.
local function watch_flight(t)
    local cond = conditions()
    CV.phase = cond.phase
    if cond.onground then
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
            local kind = CV.view_target
            if kind then
                local switched = (kind == "cockpit") and vt == VIEW_3D_COCKPIT or (kind ~= "cockpit" and vt ~= CV.view_before)
                if not switched and not CV.view_by_command then
                    -- setting the view directly didn't take: use the command
                    command_once(view_command(kind))
                    CV.view_by_command = true
                    CV.settle = 3
                    return
                end
                if switched and CV.view_by_command and kind ~= "cockpit" and vt ~= VIEW_3D_COCKPIT then
                    -- remember the number, to switch directly from now on
                    if kind == "chase" then
                        if settings.chase_view ~= vt then
                            settings.chase_view = vt
                            mark_dirty()
                        end
                    else
                        CV.learned_views[kind] = vt
                    end
                end
                CV.view_target = nil
            end
            CV.expected_view = vt
        end
    elseif CV.expected_view and view_type() ~= CV.expected_view then
        stop("view") -- the user picked another view: leave them in it
    end
end

local check_taken_keys -- (below, with the keys)

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
    check_taken_keys(t)

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

        local s = CV.shot
        if s then
            if s.def.kind == "cockpit" then update_cockpit_shot(s, t - s.t0) end
            if not CV.trans and t - s.t0 >= s.duration then next_shot(false) end
        end
    elseif settings.afk_enabled and CV.afk_armed and t - CV.last_input >= settings.afk_timeout then
        local paused = gi(R.paused, 0) ~= 0
        if not vr_on() and not paused then start("afk") end
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
        return "Running (" .. (CV.reason == "afk" and "you were away" or "started by you") .. ")"
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

-- Keys we take (bound keys, and + and - while they zoom our camera) stay ours
-- until they're let go. FlyWithLua reports X-Plane's key repeats as releases,
-- so a release doesn't mean the key is up: a key counts as held until it's
-- let go quickly after the press (a tap) or its events stop coming.
local TAP_TIME = 0.2 -- key repeats never start this soon after a press

local function take_key(vk, on_end, on_resume)
    local t = now()
    CV.taken[vk] = { t0 = t, last = t, events = 0, gap = 0.2, on_end = on_end, on_resume = on_resume }
    CV.taken_recent[vk] = nil
end

local function let_go(vk)
    local k = CV.taken[vk]
    if not k then return end
    CV.taken[vk] = nil
    CV.taken_recent[vk] = { t = now(), k = k }
    if k.on_end then k.on_end() end
end

-- An event for a key we've taken (true), or for none (false).
local function taken_key_event(vk, pressed)
    local t = now()
    local k = CV.taken[vk]
    if not k then
        -- events just after we let go: the real release, or slow key repeats
        -- (in which case the key is still held after all)
        local r = CV.taken_recent[vk]
        if pressed or not r or t - r.t > 1.0 then return false end
        if r.k.on_resume then
            local k2 = r.k
            CV.taken[vk], CV.taken_recent[vk] = k2, nil
            k2.gap = M.clamp(2.5 * (t - k2.last), 0.12, 1.5)
            k2.last = t
            k2.events = k2.events + 1
            k2.on_resume()
        end
        return true
    end
    if not pressed and k.events == 0 and t - k.t0 < TAP_TIME then
        let_go(vk)
        return true
    end
    -- the gap that means "let go": a few key repeats' worth
    if k.events >= 1 then k.gap = M.clamp(2.5 * (t - k.last), 0.12, 1.5) end
    k.events = k.events + 1
    k.last = t
    return true
end

-- Each frame: let go of keys whose events have stopped.
function check_taken_keys(t)
    for vk, k in pairs(CV.taken) do
        if (k.events > 0 and t - k.last > k.gap) or t - k.last > 8 then let_go(vk) end
    end
    for vk, r in pairs(CV.taken_recent) do
        if t - r.t > 1.0 then CV.taken_recent[vk] = nil end
    end
end

local function on_key()
    local vk = VKEY or 0
    if vk < 0 then vk = vk + 256 end -- FlyWithLua passes it as a signed char
    local mods = (SHIFT_KEY and 1 or 0) + (CONTROL_KEY and 2 or 0) + (OPTION_KEY and 4 or 0)
    local pressed = KEY_ACTION == "pressed"
    if taken_key_event(vk, pressed) then
        RESUME_KEY = true
        return
    end
    if not pressed then return end

    if CV.capturing then
        if vk ~= 0x1B then set_bind(CV.capturing, vk, mods) end -- Esc cancels
        CV.capturing = nil
        RESUME_KEY = true
        return
    end

    local a = action_for_key(vk, mods)
    if a then
        RESUME_KEY = true -- ours, not X-Plane's
        if a.release then
            take_key(vk, function() release_action(a, false) end, a.press)
        else
            take_key(vk) -- (so holding it doesn't repeat the action)
        end
        press_action(a, false)
        return
    end

    -- zooming doesn't end the cinematic
    if ZOOM_KEYS[vk] and CV.active and not CONTROL_KEY and not OPTION_KEY then
        if outside_shot() then
            RESUME_KEY = true -- X-Plane's zoom can't move our camera, so we zoom it
            local dir = ZOOM_KEYS[vk]
            take_key(vk, zoom_end, function() if outside_shot() then CV.zoom_dir = dir end end)
            zoom_begin(dir)
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
    changed, v = imgui.SliderFloat("Camera speed", settings.camera_pace, 0.1, 2, "%.2fx")
    if changed then settings.camera_pace = v; mark_dirty() end
    changed, v = imgui.SliderFloat("Panning speed", settings.pan_pace, 0.1, 2, "%.2fx")
    if changed then settings.pan_pace = v; mark_dirty() end
    changed, v = imgui.SliderFloat("Aircraft size", CV.size, 4, 100, "%.0f m")
    if changed then
        aircraft_sizes[aircraft_key()] = v
        CV.size = v
        mark_dirty()
    end
    imgui.SameLine()
    if aircraft_sizes[aircraft_key()] then
        if imgui.Button("Auto##size") then
            aircraft_sizes[aircraft_key()] = nil
            CV.size = current_size()
            mark_dirty()
        end
    else
        imgui.TextUnformatted("(auto)")
    end
    imgui.TextWrapped("Raise the aircraft size if cameras clip the aircraft. It's kept for this aircraft.")
    checkbox("Letterbox bars", "letterbox")
    imgui.SameLine()
    checkbox("Fades", "fades")
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
CV.size = current_size()

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
