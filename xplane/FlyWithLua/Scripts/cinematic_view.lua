--[[
    Cinematic View for X-Plane 12
    A FlyWithLua NG+ script

    A self-directing camera in the style of the Need for Speed and Forza
    Horizon attract modes: it cuts between chase, trackside, orbit, tracking,
    mounted and drone shots outside the aircraft, and pilot's-eye, over-the-
    shoulder, side window and panel shots inside the cockpit, with letterbox
    bars and fades.

    It can be switched on and off by hand, and it starts by itself after a
    while with no keyboard, mouse or joystick input (any input ends it again).

    Install: copy this file to X-Plane 12/Resources/plugins/FlyWithLua/Scripts/

    Commands (Settings > Keyboard or Joystick, search for "cinematic"):
        FlyWithLua/cinematic_view/toggle       start/stop
        FlyWithLua/cinematic_view/next_shot    cut to the next shot
        FlyWithLua/cinematic_view/toggle_afk   auto-start when away on/off
        FlyWithLua/cinematic_view/cycle_mode   mixed / outside / cockpit shots
        FlyWithLua/cinematic_view/settings     show/hide the settings window

    Menu: Plugins > FlyWithLua > FlyWithLua Macros > "Cinematic View: ..."

    Settings are saved next to this script in cinematic_view.ini.

    How it moves the camera: outside shots take control of X-Plane's camera
    through the plugin SDK (XPLMControlCamera, called through LuaJIT's FFI),
    and cockpit shots move the pilot's head in the 3D cockpit. If the SDK
    library can't be loaded, outside shots fall back to X-Plane's own chase,
    circle and flyby views.
--]]

local VERSION = "1.0"

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
    letterbox = true,             -- cinema bars top and bottom
    fades = true,                 -- dip to black between some shots
    caption = true,               -- shot name and flight info in the bars
    manual_exit_on_input = false, -- any input also ends a cinematic you started yourself
    joystick_deadband = 0.03,     -- how far an axis must move to count as input
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
    s.joystick_deadband = math.max(0.001, math.min(0.5, s.joystick_deadband))
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
        elevation = "sim/flightmodel/position/elevation",
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
    size = 15,
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
------------------------------------------------------------------------------

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

local function aim(out, cx, cy, cz, tx, ty, tz, roll, zoom)
    cy = above_ground(cx, cy, cz, 1.0)
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

local OUTSIDE_SHOTS = {
    {
        id = "chase", label = "Chase cam", weight = 3,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.rand(-0.15, 0.15) * c.size
            s.phase = M.rand(0, 6.28)
            s.drop = 0
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 0.8))
            local dist = 1.5 * S + 12 + math.min(c.gs, 150) * 0.04
            -- sit on the flight path behind: lower in a climb, higher in a descent
            local drop = dist * M.clamp(c.vy / math.max(c.gs, 30), -0.25, 0.25)
            s.drop = s.drop + (drop - s.drop) * M.smooth(c.dt, 1.0)
            local lat = s.side + sin(t * 0.35 + s.phase) * 0.1 * S
            local cx, cy, cz = yaw_point(c, s.hdg, lat, 0.22 * S + 2.5 - s.drop, dist)
            local tx, ty, tz = yaw_point(c, s.hdg, 0, 0.1 * S, -0.5 * S)
            aim(out, cx, cy, cz, tx, ty, tz, c.phi * 0.25, 1)
        end,
    },
    {
        id = "longlens", label = "Long lens", weight = 2,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.sign()
            s.phase = M.rand(0, 6.28)
            s.dist = 7 * c.size + 80
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 1.6))
            local cx, cy, cz = yaw_point(c, s.hdg, s.side * (0.9 * S + 8), 0.25 * S + 3, s.dist)
            local zoom = M.clamp(s.dist / (2.4 * S + 20), 1.5, 5)
            aim(out, cx, cy, cz, c.x, c.y, c.z, 0, zoom)
            -- a hand-held long lens never sits perfectly still
            out.heading = out.heading + sin(t * 1.7 + s.phase) * 0.12 + sin(t * 0.9) * 0.08
            out.pitch = out.pitch + sin(t * 1.3 + s.phase * 2) * 0.08
        end,
    },
    {
        id = "tracking", label = "Tracking", weight = 2,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.sign()
            s.dir = M.sign()
            s.height = M.rand(-0.03, 0.2) * c.size + 1
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 0.5))
            local reach = S + 8
            local z = M.lerp(-reach, reach, M.ease(t / s.duration)) * s.dir
            local cx, cy, cz = yaw_point(c, s.hdg, s.side * (S + 8), s.height, z)
            local tx, ty, tz = yaw_point(c, s.hdg, 0, 0, -0.1 * S)
            aim(out, cx, cy, cz, tx, ty, tz, 0, 1)
        end,
    },
    {
        -- a camera waiting by the flight path; the aircraft passes it
        id = "flyby", label = "Flyby", weight = 3, needs_motion = true,
        init = function(s, c)
            local gs = math.max(c.gs, 1)
            local lead = M.clamp(gs * 4.5, 60, 900)
            local T = lead / gs
            s.side = M.sign()
            local lat = (0.8 * c.size + 12 + gs * 0.06) * s.side
            local tr = rad(c.track)
            s.px = c.x + c.vx * T + cos(tr) * lat
            s.pz = c.z + c.vz * T + sin(tr) * lat
            s.ground = c.agl < 40
            s.py = c.y + c.vy * T + M.rand(-0.35, 0.55) * c.size
            s.height = M.rand(1.2, 3.0)
            s.duration = M.clamp(T + 3.5, 5, 15)
            s.zoom = nil
        end,
        update = function(s, c, t, out)
            local py = s.py
            if s.ground then
                local g = terrain_y(s.px, c.y, s.pz) or (c.y - c.agl)
                py = g + s.height
            end
            local d = sqrt((c.x - s.px) ^ 2 + (c.y - py) ^ 2 + (c.z - s.pz) ^ 2)
            local zoom = M.clamp((d / (2.5 * c.size + 25)) ^ 0.85, 1, 5)
            s.zoom = s.zoom and (s.zoom + (zoom - s.zoom) * M.smooth(c.dt, 0.35)) or zoom
            aim(out, s.px, py, s.pz, c.x + c.vx * 0.1, c.y, c.z + c.vz * 0.1, 0, s.zoom)
        end,
    },
    {
        id = "orbit", label = "Orbit", weight = 2,
        init = function(s, c)
            s.r = 1.5 * c.size + 14
            s.a0 = M.rand(0, 360)
            s.speed = M.sign() * M.rand(6, 11)
            s.height = M.rand(0.05, 0.35) * c.size + 2
            s.phase = M.rand(0, 6.28)
        end,
        update = function(s, c, t, out)
            local a = rad(s.a0 + s.speed * t)
            local cx = c.x + sin(a) * s.r
            local cz = c.z - cos(a) * s.r
            local cy = c.y + s.height + sin(t * 0.25 + s.phase) * 0.08 * c.size
            aim(out, cx, cy, cz, c.x, c.y + 0.05 * c.size, c.z, 0, 1)
        end,
    },
    {
        -- starts ahead looking back at the nose and swings out as the
        -- aircraft overtakes it
        id = "passby", label = "Pass-by", weight = 2,
        init = function(s, c)
            s.hdg = c.track
            s.side = M.sign()
            s.low = c.agl > 30
        end,
        update = function(s, c, t, out)
            local S = c.size
            s.hdg = M.approach_angle(s.hdg, c.track, M.smooth(c.dt, 0.6))
            local k = M.ease(t / s.duration)
            local x = M.lerp(0.3 * S, 1.2 * S + 8, k) * s.side
            local y = M.lerp(s.low and -0.12 * S or 0.15 * S + 1, 0.08 * S + 1, k)
            local z = M.lerp(-(2.8 * S + 20), 0.7 * S, k)
            local cx, cy, cz = yaw_point(c, s.hdg, x, y, z)
            aim(out, cx, cy, cz, c.x, c.y, c.z, c.phi * 0.15, M.lerp(1.5, 1, k))
        end,
    },
    {
        id = "tail", label = "Tail mount", weight = 1.5,
        init = function(s, c) s.phase = M.rand(0, 6.28) end,
        update = function(s, c, t, out)
            local S = c.size
            mounted(out, c, 0, 0.24 * S + 1.5, 0.55 * S + 2.5,
                sin(t * 0.2 + s.phase) * 0.05 * S, 0.05 * S, -1.5 * S)
        end,
    },
    {
        id = "wing", label = "Wing mount", weight = 1.5,
        init = function(s, c) s.side = M.sign() end,
        update = function(s, c, t, out)
            local S = c.size
            mounted(out, c, s.side * (0.56 * S + 0.6), 0.08 * S + 0.4, 0.1 * S,
                0, 0.05 * S, -0.3 * S + sin(t * 0.15) * 0.05 * S)
        end,
    },
    {
        -- a camera on a boom ahead of the nose, looking back
        id = "nose", label = "Nose boom", weight = 1,
        init = function(s, c) end,
        update = function(s, c, t, out)
            local S = c.size
            mounted(out, c, 0, 0.1 * S + 0.8, -(0.65 * S + 3), 0, 0.03 * S, 0.3 * S)
        end,
    },
    {
        id = "drone", label = "Drone", weight = 1,
        init = function(s, c)
            s.height = 3 * c.size + 30
            s.back = 0.8 * c.size + 4
            s.a0 = c.psi + 180
            s.spin = M.sign() * M.rand(3, 7)
        end,
        update = function(s, c, t, out)
            local a = rad(s.a0 + s.spin * t)
            local cx = c.x + sin(a) * s.back
            local cz = c.z - cos(a) * s.back
            aim(out, cx, c.y + s.height, cz, c.x, c.y, c.z, 0, 1)
        end,
    },
}

-- Used when the plugin SDK can't be loaded: X-Plane's own outside views.
local BUILTIN_SHOTS = {
    { id = "xp_chase", label = "Chase cam", command = "sim/view/chase", weight = 3 },
    { id = "xp_circle", label = "Orbit", command = "sim/view/circle", weight = 2 },
    { id = "xp_spot", label = "Flyby", command = "sim/view/still_spot", weight = 2, needs_motion = true },
    { id = "xp_linear", label = "Tracking", command = "sim/view/linear_spot", weight = 1, needs_motion = true },
}

-- Head pose: dx, dy, dz from the eye point (x right, y up, z aft, metres),
-- then heading, pitch and roll in degrees relative to the aircraft.
local COCKPIT_SHOTS = {
    {
        id = "eye", label = "Pilot's eye", weight = 2,
        init = function(s, e)
            s.amp = M.rand(12, 26)
            s.w = 2 * math.pi / M.rand(16, 24)
            s.phase = M.rand(0, 6.28)
            s.pitch = M.rand(-7, -3)
        end,
        update = function(s, e, t)
            return 0, 0.006 * sin(t * 1.3), 0,
                s.amp * sin(s.w * t + s.phase), s.pitch + 2 * sin(s.w * 0.7 * t), 0
        end,
    },
    {
        id = "shoulder", label = "Over the shoulder", weight = 2,
        init = function(s, e)
            s.inward = e.seat ~= 0 and -e.seat or 1
            s.from = M.rand(-8, -2) * s.inward
        end,
        update = function(s, e, t)
            local k = M.ease(t / s.duration)
            return 0.18 * s.inward, 0.12, 0.32, M.lerp(s.from, -s.from, k), -8 + sin(t * 0.4) * 1.5, 0
        end,
    },
    {
        id = "window", label = "Side window", weight = 2,
        init = function(s, e)
            s.out = e.seat ~= 0 and e.seat or M.sign()
            s.look = M.rand(65, 85)
            s.phase = M.rand(0, 6.28)
        end,
        update = function(s, e, t)
            return 0, 0, 0, s.out * (s.look + 5 * sin(t * 0.25 + s.phase)), -6 + 2 * sin(t * 0.3), 0
        end,
    },
    {
        id = "panel", label = "Panel", weight = 1.5,
        init = function(s, e)
            s.pitch = -M.rand(22, 30)
            s.span = M.rand(16, 26) * M.sign()
        end,
        update = function(s, e, t)
            local k = M.ease(t / s.duration)
            return 0, -0.04, -0.06, M.lerp(-s.span, s.span, k), s.pitch, 0
        end,
    },
    {
        id = "copilot", label = "Co-pilot's seat", weight = 1.5, side_by_side = true,
        init = function(s, e)
            s.look = M.rand(10, 22)
            s.phase = M.rand(0, 6.28)
        end,
        update = function(s, e, t)
            return -2 * e.x, 0, 0, e.seat * (s.look + 6 * sin(t * 0.2 + s.phase)), -6, 0
        end,
    },
}

for _, d in ipairs(OUTSIDE_SHOTS) do d.kind = "outside" end
for _, d in ipairs(BUILTIN_SHOTS) do d.kind = "builtin" end
for _, d in ipairs(COCKPIT_SHOTS) do d.kind = "cockpit" end

------------------------------------------------------------------------------
-- Camera control
------------------------------------------------------------------------------

local cam_ctx = {}
local cam_out = { x = 0, y = 0, z = 0, heading = 0, pitch = 0, roll = 0, zoom = 1 }

local function read_aircraft(c)
    c.x, c.y, c.z = gd(R.x), gd(R.y), gd(R.z)
    c.psi, c.the, c.phi = gf(R.psi), gf(R.the), gf(R.phi)
    c.vx, c.vy, c.vz = gf(R.vx), gf(R.vy), gf(R.vz)
    c.gs = sqrt(c.vx * c.vx + c.vz * c.vz)
    c.agl = gf(R.agl, 100)
    c.track = c.gs > 3 and deg(atan2(c.vx, -c.vz)) or c.psi
    c.size = CV.size
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
    pos.zoom = cam_out.zoom
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
    return { gs = sqrt(vx * vx + vz * vz), paused = gi(R.paused, 0) ~= 0 }
end

local function eligible(def, cond)
    if def.needs_motion and (cond.paused or cond.gs < 15) then return false end
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
    for _, def in ipairs(candidates) do total = total + def.weight end
    local r = math.random() * total
    for _, def in ipairs(candidates) do
        r = r - def.weight
        if r <= 0 then return def end
    end
    return candidates[#candidates]
end

local function pick_shot()
    if not CV.eye then CV.eye = find_eye() end
    local cond = conditions()
    local outside = XP.camera_ok and OUTSIDE_SHOTS or BUILTIN_SHOTS
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
    local s = { def = def, t0 = now(), duration = M.rand(settings.shot_min, settings.shot_max), inited = false }
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
    CV.input_flag = false
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
                    moved = true
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
                    moved = true
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
        if not vr_on() and (settings.afk_when_paused or not paused) then start("afk") end
    end

    if CV.dirty and t - CV.dirty_t > 1.5 then
        CV.dirty = false
        save_settings()
    end
end

------------------------------------------------------------------------------
-- Drawing: letterbox, fades, captions, messages
------------------------------------------------------------------------------

local function format_altitude(m)
    local ft = m * 3.28084
    if ft >= 18000 then return string.format("FL%03d", math.floor(ft / 100 + 0.5)) end
    local rounded = math.floor(ft / 10 + 0.5) * 10
    local s = tostring(rounded):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return s .. " FT"
end

local function text_width(text)
    if measure_string then
        local w = measure_string(text)
        if type(w) == "number" then return w end
    end
    return #text * 7
end

-- Text over black: a grey level stands in for transparency.
local function draw_text(x, y, text, alpha)
    local a = M.clamp(alpha, 0, 1)
    if a > 0.02 then draw_string(math.floor(x), math.floor(y), text, a, a, a) end
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

    if CV.active and ticking and settings.caption and CV.shot and CV.bars >= 1 and bar >= 40 then
        local age = t - CV.shot.t0
        local alpha = M.clamp(age / 0.8, 0, 1) * M.clamp((CV.shot.duration - age) / 0.6, 0, 1) * 0.85
        if alpha > 0 then
            local y = bar * 0.5 - 6
            draw_text(40, y, string.upper(CV.shot.def.label), alpha)
            local parts = {}
            if PLANE_ICAO and PLANE_ICAO ~= "" then parts[#parts + 1] = PLANE_ICAO end
            if PLANE_TAILNUMBER and PLANE_TAILNUMBER ~= "" then parts[#parts + 1] = PLANE_TAILNUMBER end
            parts[#parts + 1] = format_altitude(gd(R.elevation))
            local vx, vz = gf(R.vx), gf(R.vz)
            parts[#parts + 1] = string.format("%d KT", math.floor(sqrt(vx * vx + vz * vz) * 1.94384 + 0.5))
            local info = table.concat(parts, "   ")
            draw_text(w - 40 - text_width(info), y, info, alpha)
        end
        if CV.reason == "afk" and t - CV.started_at < 6 then
            local hint = "Press a key or move the mouse to take back control"
            local a = M.clamp((6 - (t - CV.started_at)) / 1.0, 0, 1) * 0.7
            draw_text((w - text_width(hint)) / 2, h - bar * 0.5 - 6, hint, a)
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
        draw_text(x, y, CV.toast_text, 1)
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
    if CV.wnd then
        float_wnd_destroy(CV.wnd)
        CV.wnd = nil
        return
    end
    if not float_wnd_create then
        toast("The settings window needs FlyWithLua NG+; edit cinematic_view.ini instead", 4)
        return
    end
    CV.wnd = float_wnd_create(460, 430, 1, true)
    float_wnd_set_title(CV.wnd, "Cinematic View " .. VERSION)
    float_wnd_set_imgui_builder(CV.wnd, "CinematicView_build_settings")
    float_wnd_set_onclose(CV.wnd, "CinematicView_settings_closed")
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

    changed, v = imgui.Checkbox("Start when I'm away from the controls", settings.afk_enabled)
    if changed then settings.afk_enabled = v; mark_dirty() end
    changed, v = imgui.SliderInt("Away for", settings.afk_timeout, 15, 900, "%d s")
    if changed then settings.afk_timeout = v; mark_dirty() end
    changed, v = imgui.Checkbox("Also start while the sim is paused", settings.afk_when_paused)
    if changed then settings.afk_when_paused = v; mark_dirty() end
    changed, v = imgui.Checkbox("Any input also ends a cinematic I started", settings.manual_exit_on_input)
    if changed then settings.manual_exit_on_input = v; mark_dirty() end
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
    imgui.Separator()

    changed, v = imgui.Checkbox("Letterbox bars", settings.letterbox)
    if changed then settings.letterbox = v; mark_dirty() end
    imgui.SameLine()
    changed, v = imgui.Checkbox("Fades", settings.fades)
    if changed then settings.fades = v; mark_dirty() end
    imgui.SameLine()
    changed, v = imgui.Checkbox("Captions", settings.caption)
    if changed then settings.caption = v; mark_dirty() end
    imgui.Separator()

    if not XP.camera_ok then
        imgui.TextWrapped("The X-Plane SDK couldn't be loaded, so outside shots use X-Plane's own chase, orbit and flyby views.")
    end
    imgui.TextWrapped("Assign keys under Settings > Keyboard: search for \"cinematic\".")
end

------------------------------------------------------------------------------
-- Global entry points for FlyWithLua (commands, macros, callbacks)
------------------------------------------------------------------------------

local function guarded(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then report_error(name, err) end
    end
end

CinematicView_tick = guarded("frame", tick)
CinematicView_draw = guarded("draw", draw)

CinematicView_toggle = guarded("toggle", function()
    if CV.active then
        stop("manual")
    elseif now() - CV.input_stop_at > 0.5 then
        -- (the key that just ended a cinematic shouldn't start it again)
        start("manual")
    end
end)

CinematicView_next = guarded("next", function()
    if CV.active then next_shot(false) end
end)

CinematicView_toggle_afk = guarded("toggle_afk", function()
    settings.afk_enabled = not settings.afk_enabled
    mark_dirty()
    toast(settings.afk_enabled
        and string.format("Cinematic view starts after %d s away", settings.afk_timeout)
        or "Cinematic view won't start by itself")
end)

CinematicView_cycle_mode = guarded("cycle_mode", function()
    local i = 1
    for k, mode in ipairs(MODES) do if mode == settings.mode then i = k end end
    settings.mode = MODES[i % #MODES + 1]
    mark_dirty()
    toast("Cinematic shots: " .. MODE_LABELS[settings.mode])
    if CV.active then next_shot(true) end
end)

CinematicView_toggle_settings = guarded("settings", toggle_settings)
CinematicView_build_settings = guarded("settings window", build_settings)
function CinematicView_settings_closed() CV.wnd = nil end

CinematicView_on_key = guarded("keyboard", function()
    if KEY_ACTION == "pressed" then CV.input_flag = true end
end)

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

create_command("FlyWithLua/cinematic_view/toggle", "Cinematic view: start/stop",
    "CinematicView_toggle()", "", "")
create_command("FlyWithLua/cinematic_view/next_shot", "Cinematic view: cut to the next shot",
    "CinematicView_next()", "", "")
create_command("FlyWithLua/cinematic_view/toggle_afk", "Cinematic view: auto-start when away on/off",
    "CinematicView_toggle_afk()", "", "")
create_command("FlyWithLua/cinematic_view/cycle_mode", "Cinematic view: cycle mixed/outside/cockpit shots",
    "CinematicView_cycle_mode()", "", "")
create_command("FlyWithLua/cinematic_view/settings", "Cinematic view: show/hide settings",
    "CinematicView_toggle_settings()", "", "")

add_macro("Cinematic View: start/stop", "CinematicView_toggle()")
add_macro("Cinematic View: next shot", "CinematicView_next()")
add_macro("Cinematic View: settings", "CinematicView_toggle_settings()")

log(string.format("version %s loaded (%s)", VERSION,
    XP.camera_ok and "custom outside cameras" or "X-Plane's built-in outside views"))
