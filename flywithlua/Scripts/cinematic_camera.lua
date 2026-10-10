--[[
    Cinematic Camera for X-Plane 12
    FlyWithLua NG / NG+ script

    Slow, smooth camera moves close to your aircraft for screenshots and video.

      * External views: the camera drifts and orbits slowly around the aircraft
        (nose, wing, engine, tail, overhead and low chase shots).
      * Internal (3D cockpit) views: the pilot's head pans slowly across the panel,
        pedestal, overhead, windows and an over-the-shoulder shot.

    The camera is driven through X-Plane's own camera API, so X-Plane's built-in
    screenshot command (sim/operation/screenshot) keeps working while it runs.

    Commands (bind them under Settings > Keyboard or Joystick, search "Cinematic"):
      FlyWithLua/CinematicCamera/toggle       Activate / deactivate the camera
      FlyWithLua/CinematicCamera/next_view    Next shot
      FlyWithLua/CinematicCamera/prev_view    Previous shot
      FlyWithLua/CinematicCamera/screenshot   Hide the window and take a screenshot
      FlyWithLua/CinematicCamera/window       Show / hide the control window

    Install: copy this file to  X-Plane 12/Resources/plugins/FlyWithLua/Scripts/
--]]

if not SUPPORTS_FLOATING_WINDOWS then
    logMsg("Cinematic Camera: this FlyWithLua version has no imgui support, please update FlyWithLua NG.")
    return
end

local ffi = require("ffi")

----------------------------------------------------------------------------------------------------
-- X-Plane SDK access through LuaJIT FFI
--
-- All FlyWithLua scripts share one Lua state, so every C name is given a CCAM_ prefix and
-- redirected to the real XPLM symbol with __asm__ to avoid clashing with other scripts.
----------------------------------------------------------------------------------------------------

if not CCAM_FFI_DEFINED then
    local ok, err = pcall(ffi.cdef, [[
        typedef struct {
            float x, y, z;
            float pitch, heading, roll;
            float zoom;
        } CCAM_CameraPosition_t;
        typedef int (*CCAM_CameraControl_f)(CCAM_CameraPosition_t *outCameraPosition,
                                            int inIsLosingControl, void *inRefcon);
        void   CCAM_ControlCamera(int inHowLong, CCAM_CameraControl_f inFunc, void *inRefcon) __asm__("XPLMControlCamera");
        void   CCAM_DontControlCamera(void) __asm__("XPLMDontControlCamera");
        void * CCAM_FindDataRef(const char *inName) __asm__("XPLMFindDataRef");
        int    CCAM_GetDatai(void *inRef) __asm__("XPLMGetDatai");
        float  CCAM_GetDataf(void *inRef) __asm__("XPLMGetDataf");
        void   CCAM_SetDataf(void *inRef, float inValue) __asm__("XPLMSetDataf");
        double CCAM_GetDatad(void *inRef) __asm__("XPLMGetDatad");
    ]])
    if not ok then
        logMsg("Cinematic Camera: ffi.cdef failed: " .. tostring(err))
    end
    CCAM_FFI_DEFINED = true
end

local function load_xplm()
    local root = SYSTEM_DIRECTORY or ""
    local candidates
    if SYSTEM == "IBM" then
        candidates = { "XPLM_64", root .. "Resources/plugins/XPLM_64.dll" }
    elseif SYSTEM == "LIN" then
        candidates = { root .. "Resources/plugins/XPLM_64.so", "Resources/plugins/XPLM_64.so" }
    else
        candidates = { root .. "Resources/plugins/XPLM.framework/XPLM", "Resources/plugins/XPLM.framework/XPLM" }
    end
    for _, path in ipairs(candidates) do
        local ok, lib = pcall(ffi.load, path)
        if ok then return lib end
    end
    return nil
end

local XPLM = load_xplm()
if not XPLM then
    logMsg("Cinematic Camera: could not load the XPLM library, script disabled.")
    return
end

local CONTROL_UNTIL_VIEW_CHANGES = 1

local function find_ref(name)
    local ref = XPLM.CCAM_FindDataRef(name)
    if ref == nil then
        logMsg("Cinematic Camera: dataref not found: " .. name)
        return nil
    end
    return ref
end

local DR = {
    local_x   = find_ref("sim/flightmodel/position/local_x"),
    local_y   = find_ref("sim/flightmodel/position/local_y"),
    local_z   = find_ref("sim/flightmodel/position/local_z"),
    psi       = find_ref("sim/flightmodel/position/psi"),
    theta     = find_ref("sim/flightmodel/position/theta"),
    phi       = find_ref("sim/flightmodel/position/phi"),
    y_agl     = find_ref("sim/flightmodel/position/y_agl"),
    is_ext    = find_ref("sim/graphics/view/view_is_external"),
    view_type = find_ref("sim/graphics/view/view_type"),
    head_x    = find_ref("sim/graphics/view/pilots_head_x"),
    head_y    = find_ref("sim/graphics/view/pilots_head_y"),
    head_z    = find_ref("sim/graphics/view/pilots_head_z"),
    head_psi  = find_ref("sim/graphics/view/pilots_head_psi"),
    head_the  = find_ref("sim/graphics/view/pilots_head_the"),
    head_phi  = find_ref("sim/graphics/view/pilots_head_phi"),
    pe_x      = find_ref("sim/aircraft/view/acf_peX"),
    pe_y      = find_ref("sim/aircraft/view/acf_peY"),
    pe_z      = find_ref("sim/aircraft/view/acf_peZ"),
    size_x    = find_ref("sim/aircraft/view/acf_size_x"),
    size_z    = find_ref("sim/aircraft/view/acf_size_z"),
    run_time  = find_ref("sim/time/total_running_time_sec"),
}

local function getf(ref, default)
    if ref == nil then return default end
    return XPLM.CCAM_GetDataf(ref)
end

local function getd(ref, default)
    if ref == nil then return default end
    return XPLM.CCAM_GetDatad(ref)
end

local function geti(ref, default)
    if ref == nil then return default end
    return XPLM.CCAM_GetDatai(ref)
end

local function setf(ref, value)
    if ref ~= nil then XPLM.CCAM_SetDataf(ref, value) end
end

local VIEW_3D_COCKPIT = 1026

----------------------------------------------------------------------------------------------------
-- Shots
--
-- External shots are described around the aircraft in a heading-aligned frame:
--   az     azimuth in degrees (0 = ahead of the nose, 90 = right wing, 180 = behind)
--   dist   distance as a multiple of the aircraft's half span / half length
--   h      height as a multiple of the aircraft's size
--   tgt    look-at point {x right, y up, z aft}, in multiples of half span / size / half length
--   zoom   camera zoom factor
-- Each value is {start, end}; the camera eases back and forth between them.
--
-- Internal shots move the pilot's head relative to the default eye point (metres) and pan
-- the view (degrees). x values flagged "center" move towards the aircraft centre line,
-- so the same shot works from the left or right seat.
----------------------------------------------------------------------------------------------------

local EXTERNAL_SHOTS = {
    { name = "Front quarter sweep",  az = { -25, -60 },  dist = { 1.5, 1.4 },  h = { 0.12, 0.20 }, tgt = { { 0, 0.02, -0.15 }, { 0, 0.02, 0.05 } },      zoom = { 1.0, 1.1 } },
    { name = "Nose close-up",        az = { 14, -14 },   dist = { 1.12, 1.1 }, h = { 0.04, 0.08 }, tgt = { { 0, 0.02, -0.75 }, { 0, 0.03, -0.55 } },     zoom = { 1.2, 1.3 } },
    { name = "Wing and engine",      az = { 62, 40 },    dist = { 0.95, 1.0 }, h = { 0.03, 0.10 }, tgt = { { 0.40, -0.04, -0.10 }, { 0.30, -0.02, 0.0 } }, zoom = { 1.1, 1.2 } },
    { name = "Low wing root",        az = { 105, 80 },   dist = { 1.25, 1.2 }, h = { -0.10, -0.04 }, tgt = { { 0.15, 0.0, 0.05 }, { 0.10, 0.0, -0.10 } }, zoom = { 1.0, 1.05 } },
    { name = "Tail orbit",           az = { 150, 205 },  dist = { 1.45, 1.4 }, h = { 0.25, 0.35 }, tgt = { { 0, 0.10, 0.55 }, { 0, 0.08, 0.35 } },        zoom = { 1.1, 1.2 } },
    { name = "Low rear chase",       az = { 172, 188 },  dist = { 2.1, 1.9 },  h = { 0.06, 0.10 }, tgt = { { 0, 0.04, 0.0 }, { 0, 0.04, -0.2 } },         zoom = { 1.0, 1.1 } },
    { name = "Overhead drift",       az = { 210, 260 },  dist = { 1.2, 1.3 },  h = { 1.10, 0.90 }, tgt = { { 0, 0, 0.1 }, { 0, 0, -0.1 } },               zoom = { 1.0, 1.0 } },
    { name = "Left side flyby",      az = { -115, -70 }, dist = { 1.7, 1.8 },  h = { 0.02, 0.05 }, tgt = { { 0, 0.03, 0.1 }, { 0, 0.03, -0.2 } },         zoom = { 1.0, 1.05 } },
    { name = "Wingtip to fuselage",  az = { -96, -86 },  dist = { 1.06, 1.06 }, h = { 0.14, 0.18 }, tgt = { { 0, 0.05, -0.25 }, { 0, 0.05, 0.10 } },      zoom = { 1.15, 1.2 } },
}

local INTERNAL_SHOTS = {
    { name = "Captain's scan",       pos = { { 0, 0, 0 }, { 0, 0.01, -0.03 } },        psi = { -38, 38 },  the = { -8, -6 } },
    { name = "Instrument panel",     pos = { { 0, -0.04, -0.14 }, { 0.02, -0.05, -0.18 } }, psi = { -22, 22 }, the = { -24, -18 } },
    { name = "Pedestal & throttles", pos = { { 0.18, -0.02, -0.05 }, { 0.24, -0.04, -0.08 } }, center = true, psi = { 28, 42 }, the = { -42, -36 } },
    { name = "Overhead panel",       pos = { { 0, -0.02, -0.04 }, { 0.06, -0.02, -0.06 } }, center = true, psi = { -12, 12 }, the = { 46, 56 } },
    { name = "Left window",          pos = { { -0.04, 0, 0 }, { -0.06, 0.01, -0.04 } },  psi = { -68, -100 }, the = { -3, 1 } },
    { name = "Right window",         pos = { { 0.04, 0, 0 }, { 0.06, 0.01, -0.04 } },    psi = { 68, 100 },  the = { -3, 1 } },
    { name = "Over the shoulder",    pos = { { 0.18, 0.10, 0.45 }, { 0.22, 0.12, 0.38 } }, center = true, psi = { -6, 8 }, the = { -12, -9 } },
    { name = "First officer's seat", pos = { { 0, 0, 0 }, { 0, 0.01, -0.04 } }, copilot = true, psi = { -42, -18 }, the = { -12, -8 } },
    { name = "Sky through the glass", pos = { { 0, 0.02, -0.10 }, { 0, 0.03, -0.14 } }, psi = { -16, 16 }, the = { 4, 10 } },
}

----------------------------------------------------------------------------------------------------
-- Settings (saved next to this script)
----------------------------------------------------------------------------------------------------

local SETTINGS_FILE = (SCRIPT_DIRECTORY or "") .. "cinematic_camera_settings.ini"

local DEFAULTS = {
    travel_speed     = 1.0,   -- how fast the camera position moves along its path
    look_speed       = 1.0,   -- how fast the camera pans its view / look-at point
    smoothing        = 0.8,   -- seconds of camera inertia
    shake            = 0.15,  -- subtle handheld motion
    distance         = 1.0,   -- external: distance multiplier
    zoom             = 1.0,   -- external: zoom multiplier
    auto_cycle       = 0,     -- seconds per shot, 0 = off
    glide            = false, -- glide to the next shot instead of cutting
    follow_attitude  = false, -- external: camera also follows pitch and roll
    hide_when_active = false, -- hide the window while the camera runs
}

local settings = {}
for k, v in pairs(DEFAULTS) do settings[k] = v end

local function load_settings()
    local f = io.open(SETTINGS_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key and DEFAULTS[key] ~= nil then
            if type(DEFAULTS[key]) == "boolean" then
                settings[key] = (value == "true")
            else
                settings[key] = tonumber(value) or DEFAULTS[key]
            end
        end
    end
    f:close()
end

local function save_settings()
    local f = io.open(SETTINGS_FILE, "w")
    if not f then return end
    local keys = {}
    for k in pairs(DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        f:write(k, " = ", tostring(settings[k]), "\n")
    end
    f:close()
end

load_settings()

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

local sin, cos, atan2, sqrt, rad, deg, exp, pi =
    math.sin, math.cos, math.atan2, math.sqrt, math.rad, math.deg, math.exp, math.pi

local BASE_SWEEP_SECONDS = 24 -- one-way sweep time at speed 1.0

local function lerp(a, b, t) return a + (b - a) * t end

-- Smooth back-and-forth 0..1..0 from an ever increasing phase angle.
local function ease(phase) return 0.5 - 0.5 * cos(phase) end

local function wrap180(a)
    a = (a + 180) % 360
    if a < 0 then a = a + 360 end
    return a - 180
end

-- Exponential smoothing towards a target; tau in seconds.
local function smooth(current, target, dt, tau)
    if tau <= 0.001 then return target end
    return current + (target - current) * (1 - exp(-dt / tau))
end

local function smooth_angle(current, target, dt, tau)
    return current + smooth(0, wrap180(target - current), dt, tau)
end

-- Rotate a vector from the aircraft frame (x right, y up, z aft) into OpenGL local
-- coordinates. Roll first, then pitch, then heading.
local function body_to_world(x, y, z, psi, theta, phi)
    local c, s
    -- roll: Rz(-phi)
    c, s = cos(-phi), sin(-phi)
    x, y = x * c - y * s, x * s + y * c
    -- pitch: Rx(theta)
    c, s = cos(theta), sin(theta)
    y, z = y * c - z * s, y * s + z * c
    -- heading: Ry(-psi)
    c, s = cos(-psi), sin(-psi)
    x, z = x * c + z * s, -x * s + z * c
    return x, y, z
end

local function now()
    return getf(DR.run_time, 0)
end

----------------------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------------------

local state = {
    active          = false,
    mode            = nil,     -- "external" or "internal"
    controlling     = false,   -- external: X-Plane is calling our camera function
    ext_index       = 1,
    int_index       = 1,
    pos_phase       = 0,
    look_phase      = 0,
    shot_timer      = 0,
    snap            = true,    -- next update jumps straight to the shot (a cut)
    glide_timer     = 0,
    ext_last_t      = nil,
    int_last_t      = nil,
    shake_t         = 0,
    saved_head      = nil,
    cam             = {},      -- smoothed external camera values
    head            = {},      -- smoothed internal head values
    window          = nil,
    window_wanted   = false,
    screenshot_wait = 0,
    restore_wait    = 0,
    restore_window  = false,
    error_msg       = nil,
}

local function reset_shot()
    state.pos_phase = 0
    state.look_phase = 0
    state.shot_timer = 0
    if settings.glide and state.active then
        state.snap = false
        state.glide_timer = 3.0
    else
        state.snap = true
    end
end

-- Effective smoothing time: longer while gliding between shots.
local function smoothing_tau()
    local tau = settings.smoothing
    if state.glide_timer > 0 then tau = math.max(tau, 1.6) end
    return tau
end

local function handheld(t, seed)
    return sin(t * 0.71 + seed) * 0.6 + sin(t * 1.93 + seed * 2.1) * 0.3 + sin(t * 3.7 + seed * 3.3) * 0.1
end

----------------------------------------------------------------------------------------------------
-- External camera (runs inside X-Plane's camera callback so it never lags the aircraft)
----------------------------------------------------------------------------------------------------

local function update_external(out)
    local t = now()
    local dt = state.ext_last_t and math.max(0, math.min(t - state.ext_last_t, 0.25)) or 0
    state.ext_last_t = t

    state.pos_phase  = state.pos_phase  + dt * settings.travel_speed * pi / BASE_SWEEP_SECONDS
    state.look_phase = state.look_phase + dt * settings.look_speed   * pi / BASE_SWEEP_SECONDS
    state.shake_t    = state.shake_t + dt

    local shot = EXTERNAL_SHOTS[state.ext_index]
    local ep, el = ease(state.pos_phase), ease(state.look_phase)

    -- Desired values (in polar form so glides go around the aircraft, not through it)
    local want = {
        az   = lerp(shot.az[1], shot.az[2], ep),
        dist = lerp(shot.dist[1], shot.dist[2], ep) * settings.distance,
        h    = lerp(shot.h[1], shot.h[2], ep),
        tx   = lerp(shot.tgt[1][1], shot.tgt[2][1], el),
        ty   = lerp(shot.tgt[1][2], shot.tgt[2][2], el),
        tz   = lerp(shot.tgt[1][3], shot.tgt[2][3], el),
        zoom = lerp(shot.zoom[1], shot.zoom[2], el) * settings.zoom,
    }

    local cam = state.cam
    if state.snap or cam.az == nil then
        for k, v in pairs(want) do cam[k] = v end
        state.snap = false
    else
        local tau = smoothing_tau()
        cam.az = smooth_angle(cam.az, want.az, dt, tau)
        for _, k in ipairs({ "dist", "h", "tx", "ty", "tz", "zoom" }) do
            cam[k] = smooth(cam[k], want[k], dt, tau)
        end
    end
    if state.glide_timer > 0 then state.glide_timer = state.glide_timer - dt end

    -- Aircraft size: half span (x), half length (z), overall size for heights
    local sx = math.max(getf(DR.size_x, 10), 4)
    local sz = math.max(getf(DR.size_z, 10), 4)
    local size = math.max(sx, sz)

    local az = rad(cam.az)
    local rx = sin(az) * cam.dist * sx
    local ry = cam.h * size
    local rz = -cos(az) * cam.dist * sz
    local lx, ly, lz = cam.tx * sx, cam.ty * size, cam.tz * sz

    local ax, ay, az_w = getd(DR.local_x, 0), getd(DR.local_y, 0), getd(DR.local_z, 0)
    local psi = rad(getf(DR.psi, 0))
    local theta, phi = 0, 0
    if settings.follow_attitude then
        theta, phi = rad(getf(DR.theta, 0)), rad(getf(DR.phi, 0))
    end

    local wx, wy, wz = body_to_world(rx, ry, rz, psi, theta, phi)
    local tx, ty, tz = body_to_world(lx, ly, lz, psi, theta, phi)
    wx, wy, wz = ax + wx, ay + wy, az_w + wz
    tx, ty, tz = ax + tx, ay + ty, az_w + tz

    -- Keep the camera above the ground (flat-ground approximation under the aircraft)
    local ground = ay - getf(DR.y_agl, 1000)
    if wy < ground + 0.7 then wy = ground + 0.7 end

    local dx, dy, dz = tx - wx, ty - wy, tz - wz
    local heading = deg(atan2(dx, -dz))
    local pitch = deg(atan2(dy, sqrt(dx * dx + dz * dz)))
    local roll = 0
    if settings.follow_attitude then roll = deg(phi) * 0.5 end

    if settings.shake > 0 then
        local amount = settings.shake * 0.8
        heading = heading + handheld(state.shake_t, 1.3) * amount
        pitch   = pitch   + handheld(state.shake_t, 4.7) * amount * 0.7
        roll    = roll    + handheld(state.shake_t, 8.1) * amount * 0.5
    end

    out.x, out.y, out.z = wx, wy, wz
    out.heading, out.pitch, out.roll = heading, pitch, roll
    out.zoom = math.max(cam.zoom, 0.2)
end

local function camera_func(out, losing_control, refcon)
    if losing_control ~= 0 or not state.active or state.mode ~= "external" or out == nil then
        state.controlling = false
        return 0
    end
    local ok, err = pcall(update_external, out)
    if not ok then
        state.error_msg = tostring(err)
        logMsg("Cinematic Camera error: " .. state.error_msg)
        state.controlling = false
        state.active = false
        return 0
    end
    return 1
end

-- Keep a global reference so the callback is never garbage collected. If the scripts are
-- reloaded into the same Lua state, point the existing callback at the new function.
if CCAM_CAMERA_CALLBACK then
    CCAM_CAMERA_CALLBACK:set(camera_func)
else
    CCAM_CAMERA_CALLBACK = ffi.cast("CCAM_CameraControl_f", camera_func)
end

local function acquire_camera()
    state.ext_last_t = nil
    state.controlling = true
    XPLM.CCAM_ControlCamera(CONTROL_UNTIL_VIEW_CHANGES, CCAM_CAMERA_CALLBACK, nil)
end

local function release_camera()
    if state.controlling then
        state.controlling = false
        XPLM.CCAM_DontControlCamera()
    end
end

----------------------------------------------------------------------------------------------------
-- Internal (3D cockpit) camera
----------------------------------------------------------------------------------------------------

local function save_head()
    state.saved_head = {
        x = getf(DR.head_x, 0), y = getf(DR.head_y, 0), z = getf(DR.head_z, 0),
        psi = getf(DR.head_psi, 0), the = getf(DR.head_the, 0), phi = getf(DR.head_phi, 0),
    }
end

local function restore_head()
    local h = state.saved_head
    if not h then return end
    setf(DR.head_x, h.x); setf(DR.head_y, h.y); setf(DR.head_z, h.z)
    setf(DR.head_psi, h.psi); setf(DR.head_the, h.the); setf(DR.head_phi, h.phi)
    state.saved_head = nil
end

local function update_internal(dt)
    state.pos_phase  = state.pos_phase  + dt * settings.travel_speed * pi / BASE_SWEEP_SECONDS
    state.look_phase = state.look_phase + dt * settings.look_speed   * pi / BASE_SWEEP_SECONDS
    state.shake_t    = state.shake_t + dt

    local shot = INTERNAL_SHOTS[state.int_index]
    local ep, el = ease(state.pos_phase), ease(state.look_phase)

    local pe_x, pe_y, pe_z = getf(DR.pe_x, 0), getf(DR.pe_y, 0), getf(DR.pe_z, 0)
    -- Direction towards the centre line: +x from the left seat, -x from the right seat
    local center_sign = 0
    if pe_x < -0.05 then center_sign = 1 elseif pe_x > 0.05 then center_sign = -1 end

    local base_x = pe_x
    local psi_sign = 1
    if shot.copilot then
        base_x = -pe_x
        -- look across towards the other seat
        if pe_x > 0.05 then psi_sign = -1 end
    end

    local ox = lerp(shot.pos[1][1], shot.pos[2][1], ep)
    if shot.center then ox = math.abs(ox) * (center_sign ~= 0 and center_sign or 1) end

    local want = {
        x   = base_x + ox,
        y   = pe_y + lerp(shot.pos[1][2], shot.pos[2][2], ep),
        z   = pe_z + lerp(shot.pos[1][3], shot.pos[2][3], ep),
        psi = lerp(shot.psi[1], shot.psi[2], el) * psi_sign,
        the = lerp(shot.the[1], shot.the[2], el),
    }
    -- Pedestal and overhead look towards the centre, mirrored for the right seat
    if shot.center and center_sign < 0 then want.psi = -want.psi end

    local head = state.head
    if state.snap or head.x == nil then
        for k, v in pairs(want) do head[k] = v end
        state.snap = false
    else
        local tau = smoothing_tau()
        head.x = smooth(head.x, want.x, dt, tau)
        head.y = smooth(head.y, want.y, dt, tau)
        head.z = smooth(head.z, want.z, dt, tau)
        head.psi = smooth_angle(head.psi, want.psi, dt, tau)
        head.the = smooth(head.the, want.the, dt, tau)
    end
    if state.glide_timer > 0 then state.glide_timer = state.glide_timer - dt end

    local psi, the, phi = head.psi, head.the, 0
    if settings.shake > 0 then
        local amount = settings.shake * 0.6
        psi = psi + handheld(state.shake_t, 2.2) * amount
        the = the + handheld(state.shake_t, 5.9) * amount * 0.7
        phi = handheld(state.shake_t, 9.4) * amount * 0.4
    end

    setf(DR.head_x, head.x); setf(DR.head_y, head.y); setf(DR.head_z, head.z)
    setf(DR.head_psi, psi); setf(DR.head_the, the); setf(DR.head_phi, phi)
end

----------------------------------------------------------------------------------------------------
-- Activation and shot selection
----------------------------------------------------------------------------------------------------

local hide_window, show_window

local function enter_mode()
    local external = geti(DR.is_ext, 0) ~= 0
    state.mode = external and "external" or "internal"
    state.cam, state.head = {}, {}
    state.snap = true
    state.pos_phase, state.look_phase, state.shot_timer = 0, 0, 0
    if external then
        acquire_camera()
    else
        if geti(DR.view_type, VIEW_3D_COCKPIT) ~= VIEW_3D_COCKPIT then
            command_once("sim/view/3d_cockpit_cmnd_look")
        end
        state.int_last_t = nil
        save_head()
    end
end

local function leave_mode()
    if state.mode == "external" then
        release_camera()
    elseif state.mode == "internal" then
        restore_head()
    end
    state.mode = nil
end

function CCAM_activate()
    if state.active then return end
    state.error_msg = nil
    state.active = true
    enter_mode()
    if settings.hide_when_active and state.window then
        state.restore_window = true
        hide_window()
    end
end

function CCAM_deactivate()
    if not state.active then return end
    state.active = false
    leave_mode()
    if state.restore_window then
        state.restore_window = false
        show_window()
    end
end

function CCAM_toggle()
    if state.active then CCAM_deactivate() else CCAM_activate() end
end

-- Without an active camera, next/previous pre-select a shot for the current view type.
local function step_shot(delta)
    local internal = state.mode == "internal"
    if not state.active then internal = geti(DR.is_ext, 0) == 0 end
    if internal then
        state.int_index = (state.int_index - 1 + delta) % #INTERNAL_SHOTS + 1
    else
        state.ext_index = (state.ext_index - 1 + delta) % #EXTERNAL_SHOTS + 1
    end
    reset_shot()
end

function CCAM_next_view() step_shot(1) end
function CCAM_prev_view() step_shot(-1) end

-- Hide the window for a few frames so it does not appear in the picture,
-- then call X-Plane's own screenshot command.
function CCAM_screenshot()
    if state.screenshot_wait > 0 or state.restore_wait > 0 then return end
    if state.window then
        state.window_wanted = true
        hide_window()
        state.screenshot_wait = 3
    else
        state.window_wanted = false
        state.screenshot_wait = 1
    end
end

----------------------------------------------------------------------------------------------------
-- Per-frame logic
----------------------------------------------------------------------------------------------------

function CCAM_every_frame()
    local t = now()
    local dt = state.int_last_t and math.max(0, math.min(t - state.int_last_t, 0.25)) or 0
    state.int_last_t = t

    -- Screenshot sequence
    if state.screenshot_wait > 0 then
        state.screenshot_wait = state.screenshot_wait - 1
        if state.screenshot_wait == 0 then
            command_once("sim/operation/screenshot")
            state.restore_wait = 3
        end
    elseif state.restore_wait > 0 then
        state.restore_wait = state.restore_wait - 1
        if state.restore_wait == 0 and state.window_wanted then
            state.window_wanted = false
            show_window()
        end
    end

    if not state.active then return end

    -- Follow view changes: switching between outside and cockpit views swaps the shot set.
    local external = geti(DR.is_ext, 0) ~= 0
    if (external and state.mode ~= "external") or (not external and state.mode ~= "internal") then
        leave_mode()
        enter_mode()
        return
    end

    if state.mode == "external" and not state.controlling then
        -- X-Plane took the camera back (e.g. another external view was selected): retake it.
        acquire_camera()
    end

    if state.mode == "internal" then
        update_internal(dt)
    end

    if settings.auto_cycle > 0 then
        state.shot_timer = state.shot_timer + dt
        if state.shot_timer >= settings.auto_cycle then
            step_shot(1)
        end
    end
end

function CCAM_on_exit()
    if state.active then
        state.active = false
        leave_mode()
    end
    save_settings()
end

----------------------------------------------------------------------------------------------------
-- User interface
----------------------------------------------------------------------------------------------------

local COLOR_ON  = 0xFF2E7D32 -- ImGui colours are 0xAABBGGRR
local COLOR_OFF = 0xFF8A4B1F

local function slider(label, key, min, max, fmt)
    local changed, value = imgui.SliderFloat(label, settings[key], min, max, fmt)
    if changed then settings[key] = value end
end

local function checkbox(label, key)
    local changed, value = imgui.Checkbox(label, settings[key])
    if changed then settings[key] = value end
end

function CCAM_build_window(wnd, x, y)
    local internal = state.mode == "internal"
    if not state.active then internal = geti(DR.is_ext, 0) == 0 end
    local shots = internal and INTERNAL_SHOTS or EXTERNAL_SHOTS
    local index = internal and state.int_index or state.ext_index

    local mode_label = internal and "Cockpit" or "External"
    imgui.TextUnformatted(string.format("Camera: %s   (%s views)", state.active and "ACTIVE" or "off", mode_label))
    imgui.TextUnformatted(string.format("Shot %d/%d: %s", index, #shots, shots[index].name))
    if state.error_msg then
        imgui.TextUnformatted("Error: " .. state.error_msg)
    end
    imgui.Separator()

    if imgui.Button("< Prev", 80, 32) then CCAM_prev_view() end
    imgui.SameLine()
    imgui.PushStyleColor(imgui.constant.Col.Button, state.active and COLOR_ON or COLOR_OFF)
    if imgui.Button(state.active and "Deactivate" or "Activate", 150, 32) then CCAM_toggle() end
    imgui.PopStyleColor()
    imgui.SameLine()
    if imgui.Button("Next >", 80, 32) then CCAM_next_view() end

    if imgui.Button("Screenshot (hides this window)", 318, 24) then CCAM_screenshot() end

    imgui.Separator()
    imgui.TextUnformatted("Movement")
    imgui.PushItemWidth(170)
    slider("Travel speed", "travel_speed", 0.05, 3.0, "%.2fx")
    slider("Pan / look speed", "look_speed", 0.05, 3.0, "%.2fx")
    slider("Smoothing", "smoothing", 0.0, 3.0, "%.1f s")
    slider("Handheld shake", "shake", 0.0, 1.0, "%.2f")
    slider("Auto next shot", "auto_cycle", 0, 120, settings.auto_cycle < 1 and "off" or "%.0f s")
    if settings.auto_cycle < 1 then settings.auto_cycle = 0 end

    imgui.TextUnformatted("External views")
    slider("Distance", "distance", 0.4, 3.0, "%.2fx")
    slider("Zoom", "zoom", 0.5, 3.0, "%.2fx")
    imgui.PopItemWidth()

    imgui.Separator()
    checkbox("Glide between shots", "glide")
    checkbox("Follow aircraft pitch & roll", "follow_attitude")
    checkbox("Hide this window while active", "hide_when_active")

    if imgui.Button("Reset defaults", 120, 22) then
        for k, v in pairs(DEFAULTS) do settings[k] = v end
    end
    imgui.SameLine()
    if imgui.Button("Save settings", 120, 22) then save_settings() end

    imgui.Separator()
    imgui.TextUnformatted("Bind keys / buttons to (search \"Cinematic\"):")
    imgui.TextUnformatted("  FlyWithLua/CinematicCamera/toggle")
    imgui.TextUnformatted("  FlyWithLua/CinematicCamera/next_view")
    imgui.TextUnformatted("  FlyWithLua/CinematicCamera/prev_view")
end

function CCAM_on_window_close(wnd)
    state.window = nil
    save_settings()
end

show_window = function()
    if state.window then return end
    state.window = float_wnd_create(340, 560, 1, true)
    float_wnd_set_title(state.window, "Cinematic Camera")
    float_wnd_set_imgui_builder(state.window, "CCAM_build_window")
    float_wnd_set_onclose(state.window, "CCAM_on_window_close")
end

hide_window = function()
    if state.window then
        local wnd = state.window
        state.window = nil
        float_wnd_destroy(wnd)
    end
end

function CCAM_show_window() show_window() end
function CCAM_hide_window() hide_window() end

function CCAM_toggle_window()
    if state.window then hide_window() else show_window() end
end

----------------------------------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------------------------------

create_command("FlyWithLua/CinematicCamera/toggle", "Cinematic Camera: activate / deactivate", "CCAM_toggle()", "", "")
create_command("FlyWithLua/CinematicCamera/next_view", "Cinematic Camera: next shot", "CCAM_next_view()", "", "")
create_command("FlyWithLua/CinematicCamera/prev_view", "Cinematic Camera: previous shot", "CCAM_prev_view()", "", "")
create_command("FlyWithLua/CinematicCamera/screenshot", "Cinematic Camera: hide window and take a screenshot", "CCAM_screenshot()", "", "")
create_command("FlyWithLua/CinematicCamera/window", "Cinematic Camera: show / hide control window", "CCAM_toggle_window()", "", "")

add_macro("Cinematic Camera: show window", "CCAM_show_window()", "CCAM_hide_window()", "deactivate")

do_every_frame("CCAM_every_frame()")
do_on_exit("CCAM_on_exit()")

logMsg("Cinematic Camera loaded.")
