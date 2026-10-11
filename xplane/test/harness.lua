-- Simulates FlyWithLua and X-Plane around cinematic_view.lua and checks what
-- it does: idle detection, shots, camera control, restoring the view, input,
-- the settings window. Run through run.sh.
-- usage: luajit harness.lua <script> ffi|fallback   (from the directory holding Resources/plugins/XPLM_64.so)
local script, mode = arg[1], arg[2] or "ffi"
local ffi = require("ffi")
local fails, checks = 0, 0
local function check(cond, msg) checks = checks + 1 if not cond then fails = fails + 1 print("FAIL: " .. msg) end end
local function finite(v) return type(v) == "number" and v == v and v > -1e30 and v < 1e30 end

-- FlyWithLua globals -------------------------------------------------------
SYSTEM = mode == "ffi" and "LIN" or "NONE"
SYSTEM_DIRECTORY = "./"
SCRIPT_DIRECTORY = os.getenv("TMPDIR_TEST") or "."
SCREEN_WIDTH, SCREEN_HEIGHT = 1920, 1080
MOUSE_X, MOUSE_Y = 500, 500
PLANE_ICAO, PLANE_TAILNUMBER = "A320", "D-AXLA"
local chunks = { frame = {}, draw = {}, key = {}, click = {}, wheel = {} }
local exit_code = {}
local commands, macros, logs, drawn = {}, {}, {}, { rects = 0, strings = {} }
local in_draw = false
function do_every_frame(c) table.insert(chunks.frame, c) end
function do_every_draw(c) table.insert(chunks.draw, c) end
function do_on_keystroke(c) table.insert(chunks.key, c) end
function do_on_mouse_click(c) table.insert(chunks.click, c) end
function do_on_mouse_wheel(c) table.insert(chunks.wheel, c) end
function do_on_exit(c) table.insert(exit_code, c) end
function create_command(name, desc, b, c, e) commands[name] = b end
function add_macro(name, a) macros[name] = a end
function logMsg(s) table.insert(logs, s) end
local function need_draw(fn) if not in_draw then error(fn .. " outside draw") end end
function XPLMSetGraphicsState() need_draw("XPLMSetGraphicsState") end
function glColor4f(r, g, b, a) need_draw("glColor4f") end
function glRectf(x1, y1, x2, y2) need_draw("glRectf") drawn.rects = drawn.rects + 1 end
function draw_string(x, y, s, r, g, b)
    need_draw("draw_string")
    assert(type(x) == "number" and type(y) == "number" and type(s) == "string", "draw_string args")
    assert(r == nil or (type(r) == "number" and type(g) == "number" and type(b) == "number"), "draw_string color")
    table.insert(drawn.strings, s)
end
function measure_string(s) return #s * 8 end

-- imgui stubs: record widgets, simulate clicks on demand
local imgui_clicks = {}
local widgets = {}
imgui = {}
function imgui.TextUnformatted(s) table.insert(widgets, s) end
function imgui.TextWrapped(s) table.insert(widgets, s) end
function imgui.Separator() end
function imgui.SameLine() end
function imgui.Button(l) table.insert(widgets, l) return imgui_clicks[l] == true end
function imgui.Checkbox(l, v) assert(type(v) == "boolean", l) table.insert(widgets, l) if imgui_clicks[l] then return true, not v end return false, v end
function imgui.SliderInt(l, v, a, b, f) assert(type(v) == "number", l) table.insert(widgets, l) if imgui_clicks[l] then return true, imgui_clicks[l] end return false, v end
function imgui.SliderFloat(l, v, a, b, f) assert(type(v) == "number", l) table.insert(widgets, l) if imgui_clicks[l] then return true, imgui_clicks[l] end return false, v end
function imgui.RadioButton(l, active) table.insert(widgets, l) return imgui_clicks[l] == true end
local windows = {}
function float_wnd_create(w, h, d, im) assert(im == true) local wnd = { w = w } windows[wnd] = true return wnd end
function float_wnd_set_title(w, t) end
function float_wnd_set_imgui_builder(w, name) w.builder = name end
function float_wnd_set_onclose(w, name) w.onclose = name end
function float_wnd_destroy(w) windows[w] = nil end

-- data store: through the mock XPLM in ffi mode, a Lua table in fallback mode
local lib
local store = {}
local set_i, set_f, set_d, get_i, get_f, get_d
if mode == "ffi" then
    lib = ffi.load("./Resources/plugins/XPLM_64.so")
    ffi.cdef[[
        void mock_set_time(float t); int mock_camera_controlled(void); int mock_camera_duration(void);
        typedef struct { float x, y, z, pitch, heading, roll, zoom; } mock_cam_t;
        int mock_call_camera(mock_cam_t *pos, int losing); void mock_set_ground(float g);
        void mock_set_axis(int i, float v); void mock_set_button(int i, int v);
        void *XPLMFindDataRef(const char *); int XPLMGetDatai(void *); void XPLMSetDatai(void *, int);
        float XPLMGetDataf(void *); void XPLMSetDataf(void *, float); double XPLMGetDatad(void *);
    ]]
    set_i = function(n, v) lib.XPLMSetDatai(lib.XPLMFindDataRef(n), v) end
    set_f = function(n, v) lib.XPLMSetDataf(lib.XPLMFindDataRef(n), v) end
    get_i = function(n) return lib.XPLMGetDatai(lib.XPLMFindDataRef(n)) end
    get_f = function(n) return lib.XPLMGetDataf(lib.XPLMFindDataRef(n)) end
    get_d = function(n) return lib.XPLMGetDatad(lib.XPLMFindDataRef(n)) end
    -- doubles: the mock has no setter, so write the field through its struct layout
    ffi.cdef("typedef struct { char name[128]; int type; int i; float f; double d; float *vf; int *vi; int n; } mock_dr_t;")
    set_d = function(n, v) ffi.cast("mock_dr_t *", lib.XPLMFindDataRef(n)).d = v end
else
    -- FlyWithLua's own wrappers
    local known = {}
    for _, n in ipairs({ "sim/flightmodel/position/local_x", "sim/flightmodel/position/local_y", "sim/flightmodel/position/local_z",
        "sim/flightmodel/position/elevation", "sim/flightmodel/position/psi", "sim/flightmodel/position/theta",
        "sim/flightmodel/position/phi", "sim/flightmodel/position/local_vx", "sim/flightmodel/position/local_vy",
        "sim/flightmodel/position/local_vz", "sim/flightmodel/position/y_agl", "sim/operation/misc/frame_rate_period",
        "sim/graphics/view/pilots_head_x", "sim/graphics/view/pilots_head_y", "sim/graphics/view/pilots_head_z",
        "sim/graphics/view/pilots_head_psi", "sim/graphics/view/pilots_head_the", "sim/graphics/view/pilots_head_phi",
        "sim/aircraft/view/acf_peX", "sim/aircraft/view/acf_peY", "sim/aircraft/view/acf_peZ",
        "sim/aircraft/weight/acf_m_max", "sim/time/paused", "sim/graphics/view/view_type", "sim/graphics/VR/enabled",
        "sim/joystick/joystick_axis_values" }) do known[n] = true store[n] = 0 end
    function XPLMFindDataRef(n) if known[n] then return n end return nil end
    function XPLMGetDatai(r) return math.floor(store[r]) end
    function XPLMGetDataf(r) return store[r] end
    function XPLMGetDatad(r) return store[r] end
    function XPLMSetDatai(r, v) store[r] = v end
    function XPLMSetDataf(r, v) store[r] = v end
    function XPLMGetDatavf(r, off, n) local t = {} for i = off, off + n - 1 do t[i] = 0 end return t end
    local btn = {}
    function button(i) return btn[i] == true end
    set_i = function(n, v) store[n] = v end
    set_f = set_i set_d = set_i
    get_i = function(n) return math.floor(store[n]) end
    get_f = function(n) return store[n] end
    get_d = get_f
end

-- view commands change view_type like X-Plane would
local VIEWS = { ["sim/view/chase"] = 1017, ["sim/view/circle"] = 1018, ["sim/view/still_spot"] = 1031,
    ["sim/view/linear_spot"] = 1032, ["sim/view/3d_cockpit_cmnd_look_forward"] = 1026 }
local command_log = {}
function command_once(c)
    table.insert(command_log, c)
    if VIEWS[c] then set_i("sim/graphics/view/view_type", VIEWS[c]) end
end

local function run(list) for _, c in ipairs(list) do local f = assert(loadstring(c)) f() end end

-- aircraft state ----------------------------------------------------------
local T = 0
local ac = { x = 1000, y = 3000, z = -2000, psi = 90, the = 3, phi = 0, vx = 120, vy = 2, vz = 0, agl = 2900 }
local function push_aircraft()
    set_d("sim/flightmodel/position/local_x", ac.x)
    set_d("sim/flightmodel/position/local_y", ac.y)
    set_d("sim/flightmodel/position/local_z", ac.z)
    set_d("sim/flightmodel/position/elevation", ac.y)
    set_f("sim/flightmodel/position/psi", ac.psi)
    set_f("sim/flightmodel/position/theta", ac.the)
    set_f("sim/flightmodel/position/phi", ac.phi)
    set_f("sim/flightmodel/position/local_vx", ac.vx)
    set_f("sim/flightmodel/position/local_vy", ac.vy)
    set_f("sim/flightmodel/position/local_vz", ac.vz)
    set_f("sim/flightmodel/position/y_agl", ac.agl)
end

set_f("sim/aircraft/view/acf_peX", -0.55)
set_f("sim/aircraft/view/acf_peY", 2.3)
set_f("sim/aircraft/view/acf_peZ", -16.5)
set_f("sim/graphics/view/pilots_head_x", -0.55)
set_f("sim/graphics/view/pilots_head_y", 2.3)
set_f("sim/graphics/view/pilots_head_z", -16.5)
set_f("sim/aircraft/weight/acf_m_max", 78000)
set_f("sim/operation/misc/frame_rate_period", 1 / 30)
set_i("sim/graphics/view/view_type", 1026)
push_aircraft()

-- load the script ----------------------------------------------------------
local ok, err = pcall(dofile, script)
check(ok, "script loads: " .. tostring(err))
check(commands["FlyWithLua/cinematic_view/toggle"] ~= nil, "toggle command created")
check(#chunks.frame == 1 and #chunks.draw == 1 and #chunks.key == 1 and #chunks.click == 1, "callbacks registered")
for _, l in ipairs(logs) do print("log: " .. l) end

local cam = mode == "ffi" and ffi.new("mock_cam_t") or nil
local function upvalue(f, name)
    for i = 1, 200 do local n, v = debug.getupvalue(f, i) if not n then return nil end if n == name then return v end end
end
local CVt = upvalue(upvalue(CinematicView_tick, "fn"), "CV")
local per_shot = {}
local stats = { shots = {}, cam_frames = 0, cockpit_frames = 0, min_dist = 1e9, max_dist = 0, below_ground = 0 }
local S_expected = 0.9 * 78000 ^ (1 / 3)

local function frame(dt)
    T = T + dt
    if lib then lib.mock_set_time(T) end
    ac.x = ac.x + ac.vx * dt
    ac.y = ac.y + ac.vy * dt
    ac.z = ac.z + ac.vz * dt
    push_aircraft()
    run(chunks.frame)
    if lib and lib.mock_camera_controlled() ~= 0 then
        local r = lib.mock_call_camera(cam, 0)
        if r == 1 then
            stats.cam_frames = stats.cam_frames + 1
            for _, f in ipairs({ "x", "y", "z", "heading", "pitch", "roll", "zoom" }) do
                check(finite(cam[f]), "camera " .. f .. " finite")
            end
            local d = math.sqrt((cam.x - ac.x) ^ 2 + (cam.y - ac.y) ^ 2 + (cam.z - ac.z) ^ 2)
            stats.min_dist = math.min(stats.min_dist, d)
            stats.max_dist = math.max(stats.max_dist, d)
            if cam.y < ac.y - ac.agl + 0.5 then stats.below_ground = stats.below_ground + 1 end
            local h, p = math.rad(cam.heading), math.rad(cam.pitch)
            local fx, fy, fz = math.cos(p) * math.sin(h), math.sin(p), -math.cos(p) * math.cos(h)
            local dx, dy, dz = (ac.x - cam.x) / d, (ac.y - cam.y) / d, (ac.z - cam.z) / d
            local ang = math.deg(math.acos(math.max(-1, math.min(1, fx * dx + fy * dy + fz * dz))))
            local id = CVt.shot and CVt.shot.def.id or "?"
            local ps = per_shot[id] or { n = 0, ang = 0, dmin = 1e9, dmax = 0, zmax = 0, rollmax = 0 }
            per_shot[id] = ps
            ps.n = ps.n + 1
            ps.ang = math.max(ps.ang, ang * cam.zoom)
            ps.dmin, ps.dmax = math.min(ps.dmin, d), math.max(ps.dmax, d)
            ps.zmax = math.max(ps.zmax, cam.zoom)
            ps.rollmax = math.max(ps.rollmax, math.abs(cam.roll))
            check(cam.zoom >= 1 and cam.zoom <= 6, "zoom in range " .. cam.zoom)
        end
    end
    in_draw = true
    run(chunks.draw)
    in_draw = false
end

local function seconds(n, dt) dt = dt or 1 / 30 for _ = 1, math.floor(n / dt + 0.5) do frame(dt) end end

-- 1. nothing happens before the timeout
seconds(60)
check(not drawn.strings[1], "nothing drawn while idle")
check(lib == nil or lib.mock_camera_controlled() == 0, "camera untouched while idle")

-- 2. mouse movement resets the idle timer
MOUSE_X = 530
seconds(1)
seconds(100)
check(get_i("sim/graphics/view/view_type") == 1026, "still in cockpit at 101 s after input")

-- 3. AFK start after 120 s of no input
seconds(25)
local started_view = get_i("sim/graphics/view/view_type")
local saw_letterbox = drawn.rects > 0
check(saw_letterbox, "letterbox drawn once active")

-- run a long cinematic and record what happens
local last_label
local head_moved = false
for i = 1, 30 * 240 do
    frame(1 / 30)
    local vt = get_i("sim/graphics/view/view_type")
    if vt == 1026 then
        local psi = get_f("sim/graphics/view/pilots_head_psi")
        if math.abs(psi) > 1 then head_moved = true end
        stats.cockpit_frames = stats.cockpit_frames + 1
    end
    -- bank and climb now and then
    ac.phi = 25 * math.sin(T * 0.05)
    ac.psi = (ac.psi + 0.02) % 360
end
local labels = {}
for _, s in ipairs(drawn.strings) do labels[s] = true end
local n = 0
for l in pairs(labels) do if l:match("^[A-Z' %-]+$") and #l > 3 then n = n + 1 end end
print(string.format("cam frames %d, cockpit frames %d, camera distance %.1f..%.1f m (span %.1f), below ground %d, distinct captions %d",
    stats.cam_frames, stats.cockpit_frames, stats.min_dist, stats.max_dist, S_expected, stats.below_ground, n))
if mode == "ffi" then
    check(stats.cam_frames > 1000, "outside shots drove the camera")
    check(stats.min_dist > 0.3 * S_expected, "camera never inside the aircraft")
    check(lib.mock_camera_duration() == 0 or lib.mock_camera_duration() == 2, "camera controlled forever mode")
else
    local builtin = 0
    for _, c in ipairs(command_log) do if c == "sim/view/circle" or c == "sim/view/still_spot" or c == "sim/view/linear_spot" then builtin = builtin + 1 end end
    check(builtin > 0, "fallback used built-in views")
end
check(stats.cockpit_frames > 300, "cockpit shots ran")
check(head_moved, "head moved in cockpit shots")
check(stats.below_ground == 0, "camera never below ground")
check(n >= 6, "several different shots captioned (" .. n .. ")")
local caption_has_info = false
for _, s in ipairs(drawn.strings) do if s:find("A320") and s:find("KT") then caption_has_info = true end end
check(caption_has_info, "flight info caption drawn")

-- 4. a key press ends the AFK cinematic and restores view and head
KEY_ACTION = "pressed"
run(chunks.key)
seconds(0.5)
check(get_i("sim/graphics/view/view_type") == 1026, "back in the 3D cockpit after key press: " .. get_i("sim/graphics/view/view_type"))
check(math.abs(get_f("sim/graphics/view/pilots_head_psi")) < 1e-3 and math.abs(get_f("sim/graphics/view/pilots_head_x") + 0.55) < 1e-3, "head restored")
check(lib == nil or lib.mock_camera_controlled() == 0, "camera released after exit")
seconds(2)
-- bars slide out then nothing more is drawn
local r1 = drawn.rects
seconds(2)
check(drawn.rects == r1, "nothing drawn once stopped")

-- 5. manual start: input doesn't end it; toggling does
run({ commands["FlyWithLua/cinematic_view/toggle"] })
seconds(3)
MOUSE_X = MOUSE_X + 50
KEY_ACTION = "pressed"; run(chunks.key)
seconds(3)
local active_after_input = false
-- active if the letterbox is still being drawn
local r2 = drawn.rects seconds(0.5) active_after_input = drawn.rects > r2
check(active_after_input, "manual cinematic survives input")
run({ commands["FlyWithLua/cinematic_view/next_shot"] })
seconds(2)
run({ commands["FlyWithLua/cinematic_view/toggle"] })
seconds(3)
local r3 = drawn.rects seconds(1)
check(drawn.rects == r3, "manual cinematic stops on toggle")
check(get_i("sim/graphics/view/view_type") == 1026, "view restored after manual stop")

-- 6. user picks another view during a cinematic: stop and leave them there
run({ commands["FlyWithLua/cinematic_view/toggle"] })
seconds(5)
set_i("sim/graphics/view/view_type", 1000) -- e.g. the 2D panel
seconds(1)
check(get_i("sim/graphics/view/view_type") == 1000, "user's view choice kept")
local r4 = drawn.rects seconds(2)
check(drawn.rects == r4, "cinematic stopped after the user picked a view")

-- 7. another plugin takes the camera
if lib then
    run({ commands["FlyWithLua/cinematic_view/cycle_mode"] }) -- outside only
    run({ commands["FlyWithLua/cinematic_view/toggle"] })
    seconds(3)
    check(lib.mock_camera_controlled() ~= 0, "outside-only mode holds the camera")
    lib.mock_call_camera(nil, 1) -- losing control
    seconds(1)
    check(lib.mock_camera_controlled() == 0, "doesn't fight for the camera")
    local r5 = drawn.rects seconds(2)
    check(drawn.rects == r5, "cinematic stopped after losing the camera")
    run({ commands["FlyWithLua/cinematic_view/cycle_mode"] })
    run({ commands["FlyWithLua/cinematic_view/cycle_mode"] }) -- back to mixed
end

-- 8. a stalled script hands the camera back (heartbeat)
if lib then
    run({ commands["FlyWithLua/cinematic_view/cycle_mode"] }) -- outside
    run({ commands["FlyWithLua/cinematic_view/toggle"] })
    seconds(3)
    T = T + 5 lib.mock_set_time(T)
    local r = lib.mock_call_camera(cam, 0)
    check(r == 0, "camera callback lets go when the script stops ticking")
    seconds(1)
    check(lib.mock_camera_controlled() ~= 0, "camera taken back once ticking resumes")
    run({ commands["FlyWithLua/cinematic_view/toggle"] })
    seconds(1)
    run({ commands["FlyWithLua/cinematic_view/cycle_mode"] })
    run({ commands["FlyWithLua/cinematic_view/cycle_mode"] })
end

-- 9. ground: on a runway at takeoff speed, camera stays above ground
ac.y, ac.agl, ac.vy, ac.the, ac.phi = 2.5, 2.5, 0, 0, 0
if lib then lib.mock_set_ground(0) end
stats.below_ground = 0
run({ commands["FlyWithLua/cinematic_view/toggle"] })
seconds(120)
run({ commands["FlyWithLua/cinematic_view/toggle"] })
check(stats.below_ground == 0, "camera above ground on the runway")

-- 10. parked and paused: no flyby, still works
ac.vx, ac.vy, ac.vz = 0, 0, 0
set_i("sim/time/paused", 1)
run({ commands["FlyWithLua/cinematic_view/toggle"] })
local before = #drawn.strings
seconds(90)
local flyby = false
for i = before + 1, #drawn.strings do if drawn.strings[i] == "FLYBY" then flyby = true end end
check(not flyby, "no flyby shots while parked")
run({ commands["FlyWithLua/cinematic_view/toggle"] })
set_i("sim/time/paused", 0)

-- 11. joystick input ends an AFK cinematic
if lib then
    MOUSE_X = MOUSE_X + 40 -- the user is back (re-arms auto-start after the camera was taken)
    seconds(1)
    seconds(125)
    local r6 = drawn.rects seconds(0.5)
    check(drawn.rects > r6, "AFK started again")
    seconds(2)
    lib.mock_set_axis(3, 0.4)
    seconds(1)
    local r7 = drawn.rects seconds(1)
    check(drawn.rects == r7, "joystick axis ended the AFK cinematic")
    -- noise below the deadband doesn't count
    seconds(125)
    for i = 1, 200 do lib.mock_set_axis(3, 0.4 + (i % 2) * 0.01) frame(1 / 30) end
    local r8 = drawn.rects seconds(0.5)
    check(drawn.rects > r8, "axis noise doesn't end it")
    lib.mock_set_button(17, 1)
    seconds(1)
    local r9 = drawn.rects seconds(1)
    check(drawn.rects == r9, "joystick button ended it")
end

-- 12. settings window
run({ commands["FlyWithLua/cinematic_view/settings"] })
local wnd = next(windows)
check(wnd and wnd.builder == "CinematicView_build_settings", "settings window opened")
_G[wnd.builder](wnd, 0, 0)
check(#widgets > 10, "settings window built")
imgui_clicks["Start when I'm away from the controls"] = true
imgui_clicks["Away for"] = 300
imgui_clicks["Cockpit only"] = true
_G[wnd.builder](wnd, 0, 0)
imgui_clicks = {}
seconds(3)
local f = io.open((SCRIPT_DIRECTORY .. "/cinematic_view.ini"), "r")
local ini = f and f:read("*a") or ""
if f then f:close() end
check(ini:find("afk_enabled = false") and ini:find("afk_timeout = 300") and ini:find("mode = cockpit"), "settings saved:\n" .. ini)
run({ commands["FlyWithLua/cinematic_view/settings"] })
check(next(windows) == nil, "settings window closed")

-- 13. exit hook
run({ commands["FlyWithLua/cinematic_view/toggle"] })
seconds(2)
run(exit_code)
check(lib == nil or lib.mock_camera_controlled() == 0, "camera released on exit")

for id, ps in pairs(per_shot) do
    print(string.format("  %-9s frames %5d  max off-axis (x zoom) %5.1f deg  dist %6.1f..%6.1f m  zoom<=%.2f  |roll|<=%.1f",
        id, ps.n, ps.ang, ps.dmin, ps.dmax, ps.zmax, ps.rollmax))
    check(ps.ang < 40, id .. " keeps the aircraft in frame")
end
for _, l in ipairs(logs) do if l:find("error") then print("log: " .. l) check(false, "no errors logged") end end
print(string.format("%s: %d checks, %d failed", mode, checks, fails))
os.exit(fails == 0 and 0 or 1)
