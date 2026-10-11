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
AIRCRAFT_FILENAME = "Test A320.acf"
local chunks = { frame = {}, draw = {}, key = {}, click = {}, wheel = {} }
local exit_code = {}
local commands, command_ends, macros, logs, drawn = {}, {}, {}, {}, { rects = 0, strings = {} }
local in_draw = false
function do_every_frame(c) table.insert(chunks.frame, c) end
function do_every_draw(c) table.insert(chunks.draw, c) end
function do_on_keystroke(c) table.insert(chunks.key, c) end
function do_on_mouse_click(c) table.insert(chunks.click, c) end
function do_on_mouse_wheel(c) table.insert(chunks.wheel, c) end
function do_on_exit(c) table.insert(exit_code, c) end
function create_command(name, desc, b, c, e) commands[name] = b command_ends[name] = e end
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

-- imgui stubs: record widgets, simulate clicks on demand (not on disabled
-- widgets), and keep count of everything pushed or begun so a frame can be
-- checked for balance
local imgui_clicks = {}
local widgets, checkboxes = {}, {}
local ui = { colors = 0, vars = 0, disabled = 0, tabbar = 0, tabitem = 0 }
local function clicked(l) return ui.disabled == 0 and imgui_clicks[l] end
local function num(v, what) assert(type(v) == "number" and v == v, what .. " needs a number") end
imgui = { constant = { Col = {}, StyleVar = {} } }
for i, name in ipairs({ "Text", "FrameBg", "FrameBgHovered", "FrameBgActive", "SliderGrab", "SliderGrabActive",
    "CheckMark", "Button", "ButtonHovered", "ButtonActive", "Separator", "Tab", "TabHovered", "TabSelected",
    "TabSelectedOverline", "PlotHistogram", "Border" }) do imgui.constant.Col[name] = i end
for i, name in ipairs({ "FrameRounding", "GrabRounding", "TabRounding", "FramePadding", "ItemSpacing", "FrameBorderSize" }) do
    imgui.constant.StyleVar[name] = i
end
function imgui.TextUnformatted(s) assert(type(s) == "string") table.insert(widgets, s) end
function imgui.TextWrapped(s) assert(type(s) == "string") table.insert(widgets, s) end
function imgui.SeparatorText(s) assert(type(s) == "string") table.insert(widgets, s) end
function imgui.Separator() end
function imgui.Spacing() end
function imgui.Bullet() end
function imgui.AlignTextToFramePadding() end
function imgui.SameLine(x, sp) if x then num(x, "SameLine") end end
function imgui.Indent(w) num(w, "Indent") end
function imgui.Unindent(w) num(w, "Unindent") end
function imgui.SetNextItemWidth(w) num(w, "SetNextItemWidth") end
function imgui.GetWindowWidth() return 480 end
function imgui.GetContentRegionAvail() return 464, 400 end
function imgui.CalcTextSize(s) assert(type(s) == "string") return #s * 7, 13 end
function imgui.ProgressBar(f, w, h, overlay) num(f, "ProgressBar") assert(f >= 0 and f <= 1, "progress 0..1") num(w, "bar width") num(h, "bar height") assert(type(overlay) == "string") end
function imgui.PushStyleColor(idx, col) num(idx, "colour index") num(col, "colour") assert(col >= 0 and col < 2 ^ 32) ui.colors = ui.colors + 1 end
function imgui.PopStyleColor(n) n = n or 1 ui.colors = ui.colors - n assert(ui.colors >= 0, "popped more colours than pushed") end
function imgui.PushStyleVar(idx, v) num(idx, "style index") num(v, "style value") ui.vars = ui.vars + 1 end
function imgui.PushStyleVar_2(idx, x, y) num(idx, "style index") num(x, "style x") num(y, "style y") ui.vars = ui.vars + 1 end
function imgui.PopStyleVar(n) assert(n == nil, "pop style vars one at a time") ui.vars = ui.vars - 1 assert(ui.vars >= 0, "popped more style vars than pushed") end
function imgui.BeginDisabled(d) assert(d == nil or type(d) == "boolean") ui.disabled = ui.disabled + ((d == false) and 0 or 1) ui.dstack = ui.dstack or {} table.insert(ui.dstack, d ~= false) end
function imgui.EndDisabled() local d = table.remove(ui.dstack) assert(d ~= nil, "EndDisabled without BeginDisabled") if d then ui.disabled = ui.disabled - 1 end end
function imgui.BeginTabBar(id) assert(type(id) == "string") ui.tabbar = ui.tabbar + 1 return true end
function imgui.EndTabBar() ui.tabbar = ui.tabbar - 1 assert(ui.tabbar >= 0) end
function imgui.BeginTabItem(l, ...) assert(type(l) == "string" and select("#", ...) == 0, "tab items take just a label") table.insert(widgets, l) ui.tabitem = ui.tabitem + 1 return true end
function imgui.EndTabItem() ui.tabitem = ui.tabitem - 1 assert(ui.tabitem >= 0) end
function imgui.Button(l, w, h) assert(type(l) == "string") table.insert(widgets, l) return clicked(l) == true end
function imgui.SmallButton(l) assert(type(l) == "string") table.insert(widgets, l) return clicked(l) == true end
function imgui.Checkbox(l, v) assert(type(v) == "boolean", l) table.insert(widgets, l) table.insert(checkboxes, l) if clicked(l) then return true, not v end return false, v end
function imgui.SliderInt(l, v, a, b, f) assert(type(v) == "number", l) table.insert(widgets, l) if clicked(l) then return true, imgui_clicks[l] end return false, v end
function imgui.SliderFloat(l, v, a, b, f) assert(type(v) == "number", l) table.insert(widgets, l) if clicked(l) then return true, imgui_clicks[l] end return false, v end
function imgui.RadioButton(l, active) table.insert(widgets, l) return clicked(l) == true end
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
        void mock_set_wall(float z0, float z1, float h); void mock_set_cloud(int i, float base, float tops, float cover);
        void *XPLMFindDataRef(const char *); int XPLMGetDatai(void *); void XPLMSetDatai(void *, int);
        float XPLMGetDataf(void *); void XPLMSetDataf(void *, float); double XPLMGetDatad(void *);
    ]]
    set_i = function(n, v) lib.XPLMSetDatai(lib.XPLMFindDataRef(n), v) end
    set_f = function(n, v) lib.XPLMSetDataf(lib.XPLMFindDataRef(n), v) end
    get_i = function(n) return lib.XPLMGetDatai(lib.XPLMFindDataRef(n)) end
    get_f = function(n) return lib.XPLMGetDataf(lib.XPLMFindDataRef(n)) end
    get_d = function(n) return lib.XPLMGetDatad(lib.XPLMFindDataRef(n)) end
    -- doubles: the mock has no setter, so write the field through its struct layout
    ffi.cdef("typedef struct { char name[128]; int type; int i; float f; double d; float *vf; int *vi; int n; int readonly; } mock_dr_t;")
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
        "sim/joystick/joystick_axis_values", "sim/flightmodel/failures/onground_any",
        "sim/flightmodel/forces/g_nrml" }) do known[n] = true store[n] = 0 end
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
local held_commands = {}
function command_begin(c) table.insert(command_log, "begin " .. c) held_commands[c] = true end
function command_end(c) table.insert(command_log, "end " .. c) held_commands[c] = nil end
function command_once(c)
    table.insert(command_log, c)
    if VIEWS[c] then set_i("sim/graphics/view/view_type", VIEWS[c]) end
end

local function run(list) for _, c in ipairs(list) do local f = assert(loadstring(c)) f() end end

-- aircraft state ----------------------------------------------------------
local T = 0
local ac = { x = 1000, y = 3000, z = -2000, psi = 90, the = 3, phi = 0, vx = 120, vy = 2, vz = 0, agl = 2900,
    onground = false, g = 1 }
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
    set_i("sim/flightmodel/failures/onground_any", ac.onground and 1 or 0)
    set_f("sim/flightmodel/forces/g_nrml", ac.g)
end

set_f("sim/aircraft/view/acf_peX", -0.55)
set_f("sim/aircraft/view/acf_peY", 2.3)
set_f("sim/aircraft/view/acf_peZ", -16.5)
set_f("sim/graphics/view/pilots_head_x", -0.55)
set_f("sim/graphics/view/pilots_head_y", 2.3)
set_f("sim/graphics/view/pilots_head_z", -16.5)
set_f("sim/aircraft/weight/acf_m_max", 78000)
if mode == "ffi" then
    set_f("mock/camera/focus_distance_m", 500)
    set_i("mock/camera/auto_focus", 1)
    set_f("sim/graphics/scenery/sun_pitch_degrees", 45) -- midday, until the light tests
    set_f("sim/graphics/scenery/sun_heading_degrees", 180)
end
set_f("sim/operation/misc/frame_rate_period", 1 / 30)
set_i("sim/graphics/view/view_type", 1026)
push_aircraft()

-- load the script ----------------------------------------------------------
local ok, err = pcall(dofile, script)
check(ok, "script loads: " .. tostring(err))
check(commands["FlyWithLua/cinematic_view/toggle"] ~= nil, "toggle command created")
for _, id in ipairs({ "toggle", "next_shot", "hold", "toggle_afk", "settings" }) do
    check(commands["FlyWithLua/cinematic_view/" .. id] and command_ends["FlyWithLua/cinematic_view/" .. id] ~= "",
        id .. " command with press and release")
end
for _, id in ipairs({ "cycle_mode", "zoom_in", "zoom_out" }) do
    check(commands["FlyWithLua/cinematic_view/" .. id] == nil, "no " .. id .. " command")
end
local macro_count = 0
for name in pairs(macros) do macro_count = macro_count + 1 end
check(macro_count == 1 and macros["Cinematic View"] == "CinematicView_toggle_settings()", "one menu entry, opening the window")
check(#chunks.frame == 1 and #chunks.draw == 1 and #chunks.key == 1 and #chunks.click == 1, "callbacks registered")
for _, l in ipairs(logs) do print("log: " .. l) end

local cam = mode == "ffi" and ffi.new("mock_cam_t") or nil
local function upvalue(f, name)
    for i = 1, 200 do local n, v = debug.getupvalue(f, i) if not n then return nil end if n == name then return v end end
end
local CVt = upvalue(upvalue(CinematicView_tick, "fn"), "CV")
local per_shot = {}
local shots_seen, shot_log = {}, {}
local function shots_since(i)
    local seen = {}
    for k = i + 1, #shot_log do seen[shot_log[k]] = true end
    return seen
end
-- FlyWithLua passes VKEY as a signed char
local function key(vk, action, mods)
    mods = mods or {}
    VKEY = vk >= 128 and vk - 256 or vk
    CKEY = ""
    SHIFT_KEY, CONTROL_KEY, OPTION_KEY = mods.shift or false, mods.ctrl or false, mods.alt or false
    KEY_ACTION = action
    RESUME_KEY = false
    run(chunks.key)
    return RESUME_KEY
end
local function tap(vk, mods)
    local consumed = key(vk, "pressed", mods)
    key(vk, "released", mods)
    return consumed
end
local function command(id)
    run({ commands["FlyWithLua/cinematic_view/" .. id] })
    run({ command_ends["FlyWithLua/cinematic_view/" .. id] })
end
local MODE_BUTTONS = { mixed = "Mixed##mode", outside = "Outside##mode", cockpit = "Cockpit##mode" }
local function set_mode(m)
    local opened = next(windows) == nil
    if opened then command("settings") end
    local w = next(windows)
    imgui_clicks[MODE_BUTTONS[m]] = true
    _G[w.builder](w, 0, 0)
    imgui_clicks = {}
    if opened then command("settings") end
end
local function ini_text()
    local f = io.open(SCRIPT_DIRECTORY .. "/cinematic_view.ini", "r")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    return text
end
local stats = { shots = {}, cam_frames = 0, cockpit_frames = 0, min_dist = 1e9, max_dist = 0, below_ground = 0,
    too_close = 0, cruise_ground_trackside = 0, focus_frames = 0, focus_off = 0, focus_kept = 0, focus_back = 0 }
local S_expected = 0.9 * 78000 ^ (1 / 3)
-- generated shots, as they start
local orbiting_shots, cockpit_shots = {}, {}
-- how fast the picture moves, per kind of shot, only while `measuring`
local measuring, motion, prev = false, {}, nil
local function note_motion(kind, rate, limit)
    local m = motion[kind] or { peak = 0, over = 0, n = 0 }
    motion[kind] = m
    m.n = m.n + 1
    m.peak = math.max(m.peak, rate / limit)
    if rate > limit then m.over = m.over + 1 end
end

local function frame(dt)
    T = T + dt
    if lib then lib.mock_set_time(T) end
    ac.x = ac.x + ac.vx * dt
    ac.y = ac.y + ac.vy * dt
    ac.z = ac.z + ac.vz * dt
    push_aircraft()
    run(chunks.frame)
    if CVt.shot and CVt.shot ~= shot_log.last then
        shots_seen[CVt.shot.def.id] = true
        table.insert(shot_log, CVt.shot.def.id)
        shot_log.last = CVt.shot
        if CVt.shot.def.kind == "cockpit" then table.insert(cockpit_shots, CVt.shot) end
    end
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
            local shot_zoom = cam.zoom / CVt.user_zoom -- framing as the shot set it, before + and -
            ps.ang = math.max(ps.ang, ang * shot_zoom)
            ps.dmin, ps.dmax = math.min(ps.dmin, d), math.max(ps.dmax, d)
            ps.zmax = math.max(ps.zmax, cam.zoom)
            ps.rollmax = math.max(ps.rollmax, math.abs(cam.roll))
            check(shot_zoom >= 0.99 and shot_zoom <= 10.01 and cam.zoom >= 0.4 and cam.zoom <= 12, "zoom in range " .. cam.zoom)
            if d < 0.65 * CVt.size + 2 - 0.5 then stats.too_close = stats.too_close + 1 end
            if mode == "ffi" then
                stats.focus_frames = stats.focus_frames + 1
                if math.abs(get_f("mock/camera/focus_distance_m") - math.max(d, 1)) > 0.05 * d + 0.5 then stats.focus_off = stats.focus_off + 1 end
                if get_i("mock/camera/auto_focus") ~= 0 then stats.focus_kept = stats.focus_kept + 1 end
            end
            local sh = CVt.shot
            if sh and sh.def.id == "orbiting" and sh.inited and not sh.counted then
                sh.counted = true
                table.insert(orbiting_shots, sh)
            end
            if sh and sh.def.id == "trackside" and CVt.phase == "cruise" and sh.ground then
                stats.cruise_ground_trackside = stats.cruise_ground_trackside + 1
            end
            -- how fast the picture moves: an orbiting camera going round the
            -- aircraft, a trackside camera turning, both magnified by zoom
            if measuring and sh and prev and prev.shot == sh and T - sh.t0 > 0.2 then
                if sh.def.id == "orbiting" then
                    local a = math.rad(-sh.hdg)
                    local rx, ry, rz = cam.x - ac.x, cam.y - ac.y, cam.z - ac.z
                    rx, rz = rx * math.cos(a) + rz * math.sin(a), -rx * math.sin(a) + rz * math.cos(a)
                    local len = math.sqrt(rx * rx + ry * ry + rz * rz)
                    rx, ry, rz = rx / len, ry / len, rz / len
                    if prev.rx then
                        local dot = math.max(-1, math.min(1, rx * prev.rx + ry * prev.ry + rz * prev.rz))
                        local rate = math.deg(math.acos(dot)) / dt * shot_zoom
                        note_motion("orbiting", rate, 5 * sh.pace * 1.5 + 1)
                    end
                    prev.rx, prev.ry, prev.rz = rx, ry, rz
                elseif sh.def.id == "trackside" then
                    local dh = ((cam.heading - prev.h + 180) % 360) - 180
                    local rate = math.sqrt(dh * dh + (cam.pitch - prev.p) ^ 2) / dt * shot_zoom
                    note_motion("trackside", rate, sh.pan_cap * 1.5 + 2)
                end
            end
            if not prev or prev.shot ~= sh then prev = { shot = sh } end
            prev.h, prev.p = cam.heading, cam.pitch
        end
    end
    -- and back to X-Plane's own focus whenever the camera isn't ours
    if mode == "ffi" and (not CVt.shot or CVt.shot.def.kind ~= "outside") and lib.mock_camera_controlled() == 0 then
        if get_i("mock/camera/auto_focus") ~= 1 or math.abs(get_f("mock/camera/focus_distance_m") - 500) > 1e-3 then
            stats.focus_back = stats.focus_back + 1
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
local head_moved = false
check(CVt.shot and CVt.shot.pace == 0.5 and CVt.shot.pan == 0.5, "camera and panning speeds start at 0.5")
measuring = true
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
measuring = false
local n = 0
for _ in pairs(shots_seen) do n = n + 1 end
print(string.format("cam frames %d, cockpit frames %d, camera distance %.1f..%.1f m (span %.1f), below ground %d, distinct shots %d",
    stats.cam_frames, stats.cockpit_frames, stats.min_dist, stats.max_dist, S_expected, stats.below_ground, n))
if mode == "ffi" then
    check(stats.cam_frames > 1000, "outside shots drove the camera")
    check(stats.too_close == 0, "cameras stay outside the aircraft's clearance: " .. stats.too_close .. " frames inside")
    for kind, m in pairs(motion) do
        print(string.format("  %s motion: peak %.2f of the limit over %d frames", kind, m.peak, m.n))
        check(m.over == 0, kind .. " shots move within the camera speed limit (peak " .. m.peak .. ")")
    end
    check(motion.orbiting, "orbiting motion measured")
    check(stats.focus_frames > 1000 and stats.focus_off == 0, "outside shots focus on the aircraft (" .. stats.focus_off .. " frames off)")
    check(stats.focus_kept == 0, "X-Plane's auto-focus is paused during outside shots")
    check(stats.focus_back == 0, "and X-Plane's focus settings are back otherwise (" .. stats.focus_back .. " frames not)")
    local found_log = false
    for _, l in ipairs(logs) do if l:find("focusing outside shots with mock/camera/focus_distance_m, pausing mock/camera/auto_focus", 1, true) then found_log = true end end
    check(found_log, "the focus settings it found are logged")
    check(lib.mock_camera_duration() == 0 or lib.mock_camera_duration() == 2, "camera controlled forever mode")
else
    local builtin = 0
    for _, c in ipairs(command_log) do if c == "sim/view/circle" or c == "sim/view/still_spot" or c == "sim/view/linear_spot" then builtin = builtin + 1 end end
    check(builtin > 0, "fallback used built-in views")
    -- in X-Plane's own views the wheel runs X-Plane's zoom, like + and -
    set_mode("outside")
    local tries = 0
    while not (CVt.active and CVt.shot and CVt.shot.def.kind == "builtin") and tries < 600 do
        frame(1 / 30)
        tries = tries + 1
    end
    check(CVt.shot and CVt.shot.def.kind == "builtin", "a built-in view running")
    MOUSE_WHEEL_CLICKS, MOUSE_WHEEL_NUMBER, RESUME_MOUSE_WHEEL = 1, 0, false
    run(chunks.wheel)
    check(RESUME_MOUSE_WHEEL == true and held_commands["sim/general/zoom_in"], "the wheel zooms X-Plane's own views")
    seconds(0.5)
    check(not held_commands["sim/general/zoom_in"] and CVt.active, "for a moment, without ending the cinematic")
    set_mode("mixed")
end
check(stats.cockpit_frames > 300, "cockpit shots ran")
check(head_moved, "head moved in cockpit shots")
check(stats.below_ground == 0, "camera never below ground")
local view_commands = {}
for _, c in ipairs(command_log) do if c:find("^sim/view/") then view_commands[c] = (view_commands[c] or 0) + 1 end end
check(not view_commands["sim/view/3d_cockpit_cmnd_look_forward"], "the cockpit view is set directly, not with its command")
for c, count in pairs(view_commands) do check(count == 1, c .. " used once, to learn its view number, then set directly: " .. count) end
if mode == "ffi" then
    seconds(2)
    check(ini_text():find("chase_view = 1017", 1, true), "the chase view number is remembered")
end
check(stats.cruise_ground_trackside == 0, "no ground-level trackside shots in cruise")
check(#drawn.strings == 0, "no text drawn during the cinematic")

-- 4. a key press ends the AFK cinematic and restores view and head
check(not tap(0x41), "an ordinary key goes on to X-Plane")
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
tap(0x41)
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
    set_mode("outside")
    run({ commands["FlyWithLua/cinematic_view/toggle"] })
    seconds(3)
    check(lib.mock_camera_controlled() ~= 0, "outside-only mode holds the camera")
    lib.mock_call_camera(nil, 1) -- losing control
    seconds(1)
    check(lib.mock_camera_controlled() == 0, "doesn't fight for the camera")
    local r5 = drawn.rects seconds(2)
    check(drawn.rects == r5, "cinematic stopped after losing the camera")
    set_mode("mixed")
end

-- 8. a stalled script hands the camera back (heartbeat)
if lib then
    set_mode("outside")
    run({ commands["FlyWithLua/cinematic_view/toggle"] })
    seconds(3)
    T = T + 5 lib.mock_set_time(T)
    local r = lib.mock_call_camera(cam, 0)
    check(r == 0, "camera callback lets go when the script stops ticking")
    seconds(1)
    check(lib.mock_camera_controlled() ~= 0, "camera taken back once ticking resumes")
    run({ commands["FlyWithLua/cinematic_view/toggle"] })
    seconds(1)
    set_mode("mixed")
end

-- 9. ground: on a runway at takeoff speed, camera stays above ground
ac.y, ac.agl, ac.vy, ac.the, ac.phi, ac.onground = 2.5, 2.5, 0, 0, 0, true
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
local before = #shot_log
seconds(90)
local parked_shots = shots_since(before)
check(not parked_shots.trackside and not parked_shots.xp_spot, "no trackside shots while parked")
run({ commands["FlyWithLua/cinematic_view/toggle"] })
-- 10a. it doesn't start by itself while paused
MOUSE_X = MOUSE_X + 40
seconds(1)
seconds(150)
check(not CVt.active, "no auto-start while paused")
set_i("sim/time/paused", 0)
seconds(2)
check(CVt.active and CVt.reason == "afk", "but starts once unpaused")
tap(0x41)
seconds(1)
check(not CVt.active, "and a key ends it")

-- 10b. a landing gets a touchdown shot by the runway
if lib then
    ac.x, ac.z, ac.y, ac.agl, ac.vx, ac.vy, ac.vz, ac.the, ac.phi, ac.psi, ac.onground = 0, 0, 300, 300, 70, -3.5, 0, 2, 0, 90, false
    command("toggle")
    local touchdown_seen, touchdown_closest, touchdown_cam_low, touched_at = false, 1e9, true, nil
    for _ = 1, 30 * 140 do
        if not ac.onground then
            if ac.y <= 2.5 then
                ac.y, ac.vy, ac.onground = 2.5, 0, true
                touched_at = T
            end
        else
            ac.vx = math.max(0, ac.vx - 2 / 30)
        end
        ac.agl = ac.y
        frame(1 / 30)
        if CVt.shot and CVt.shot.def.id == "touchdown" and lib.mock_camera_controlled() ~= 0 then
            touchdown_seen = true
            local d = math.sqrt((cam.x - ac.x) ^ 2 + (cam.z - ac.z) ^ 2)
            touchdown_closest = math.min(touchdown_closest, d)
            if cam.y < 0.9 or cam.y > 2.0 then touchdown_cam_low = false end
        end
    end
    check(touched_at ~= nil, "simulated landing touched down")
    check(touchdown_seen, "a touchdown shot cut in on short final")
    check(touchdown_cam_low, "the touchdown camera stands by the runway")
    -- (far enough back that it never has to turn faster than the camera speed allows)
    check(touchdown_closest > 30 and touchdown_closest < 300, "and the aircraft passes by it: " .. touchdown_closest)
    command("toggle")

    -- 10c. a takeoff gets a liftoff shot
    command("toggle")
    seconds(5)
    local liftoff_seen, liftoff_cam_low = false, true
    for _ = 1, 30 * 70 do
        if ac.onground then
            ac.vx = ac.vx + 2.5 / 30
            if ac.vx >= 75 then ac.onground, ac.vy, ac.the = false, 5, 8 end
        end
        ac.agl = ac.y
        frame(1 / 30)
        if CVt.shot and CVt.shot.def.id == "liftoff" and lib.mock_camera_controlled() ~= 0 then
            liftoff_seen = true
            if cam.y > 1.6 then liftoff_cam_low = false end
        end
    end
    check(liftoff_seen, "a liftoff shot cut in")
    check(liftoff_cam_low, "the liftoff camera is low by the runway")
    command("toggle")

    -- 10d. low and level: trackside cameras on the ground (generated at random, so fly until some come up)
    ac.y, ac.agl, ac.vy, ac.the, ac.onground = 200, 200, 0, 0, false
    set_mode("outside")
    command("toggle")
    local ground_frames, ground_high = 0, 0
    measuring = true
    for _ = 1, 30 * 900 do
        frame(1 / 30)
        local sh = CVt.shot
        if sh and sh.def.id == "trackside" and sh.ground and lib.mock_camera_controlled() ~= 0 then
            ground_frames = ground_frames + 1
            if cam.y > 3.5 then ground_high = ground_high + 1 end
        end
        if ground_frames > 600 then break end
    end
    measuring = false
    check(ground_frames > 0, "trackside cameras on the ground come up flying low")
    check(ground_high == 0, "and stand on the ground")
    check(motion.trackside and motion.trackside.over == 0, "trackside cameras turn within the camera speed limit")
    command("toggle")

    -- 10e. a ridge beside the flight path: terrain never hides the aircraft for long
    ac.x, ac.z, ac.y, ac.agl, ac.vx, ac.vy, ac.vz, ac.the, ac.phi, ac.psi, ac.onground = 0, 0, 200, 200, 75, 0, 0, 0, 0, 90, false
    lib.mock_set_wall(-185, -150, 500)
    -- whether the line from a camera to a point crosses the ridge below its crest
    local function ridge_hides(cx, cy, cz, tx, ty, tz)
        if math.abs(tz - cz) < 1e-6 then return cz > -185 and cz < -150 and math.min(cy, ty) < 500 end
        local ka, kb = (-185 - cz) / (tz - cz), (-150 - cz) / (tz - cz)
        if ka > kb then ka, kb = kb, ka end
        ka, kb = math.max(ka, 0), math.min(kb, 1)
        if ka >= kb then return false end
        return math.min(cy + (ty - cy) * ka, cy + (ty - cy) * kb) < 500
    end
    command("toggle")
    local outside_frames, hidden_frames, hidden_run, hidden_worst, ridge_trackside = 0, 0, 0, 0, 0
    for _ = 1, 30 * 360 do
        frame(1 / 30)
        if lib.mock_camera_controlled() ~= 0 and CVt.shot and CVt.shot.def.kind == "outside" then
            outside_frames = outside_frames + 1
            if ridge_hides(cam.x, cam.y, cam.z, ac.x, ac.y + 0.1 * CVt.size + 1, ac.z) then
                hidden_frames = hidden_frames + 1
                hidden_run = hidden_run + 1 / 30
                hidden_worst = math.max(hidden_worst, hidden_run)
            else
                hidden_run = 0
            end
            if CVt.shot.def.id == "trackside" then ridge_trackside = ridge_trackside + 1 end
        else
            hidden_run = 0
        end
    end
    command("toggle")
    lib.mock_set_wall(0, 0, 0)
    print(string.format("  ridge: aircraft hidden %d of %d outside frames, longest %.2f s; trackside frames %d",
        hidden_frames, outside_frames, hidden_worst, ridge_trackside))
    check(hidden_worst < 1.5, "terrain never hides the aircraft for long: " .. hidden_worst .. " s")
    check(hidden_frames < 0.03 * outside_frames, "nor often: " .. hidden_frames .. " of " .. outside_frames .. " frames")
    check(ridge_trackside > 0, "trackside cameras still find spots that see it")

    -- 10f. golden hour: cameras line up with the low sun
    set_f("sim/graphics/scenery/sun_pitch_degrees", 6)
    set_f("sim/graphics/scenery/sun_heading_degrees", 250)
    ac.x, ac.z, ac.y, ac.agl, ac.vx, ac.vy, ac.vz, ac.the, ac.phi, ac.psi, ac.onground = 0, 0, 3000, 3000, 120, 0, 0, 2, 0, 90, false
    local sun_r, sun_e = math.rad(250), math.rad(6)
    local sx, sy, sz = math.cos(sun_e) * math.sin(sun_r), math.sin(sun_e), -math.cos(sun_e) * math.cos(sun_r)
    -- whether the sun is in the picture, inside the letterbox
    local function sun_in_picture()
        local h, p = math.rad(cam.heading), math.rad(cam.pitch)
        local fx, fy, fz = math.cos(p) * math.sin(h), math.sin(p), -math.cos(p) * math.cos(h)
        local rx, ry, rz = math.cos(h), 0, math.sin(h)
        local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
        local f = sx * fx + sy * fy + sz * fz
        if f <= 0 then return false end
        local across, up = (sx * rx + sy * ry + sz * rz) / f, (sx * ux + sy * uy + sz * uz) / f
        local t = math.tan(math.rad(30)) / cam.zoom
        return math.abs(across) < t and math.abs(up) < t / 2.39
    end
    command("toggle")
    local golden = { shots = 0, into = 0, lit = 0, into_frames = 0, sun_seen = 0, lit_frames = 0, lit_ok = 0 }
    for _ = 1, 30 * 800 do
        frame(1 / 30)
        local sh = CVt.shot
        if sh and sh.def.id == "orbiting" and sh.inited and not sh.golden then
            sh.golden = true
            golden.shots = golden.shots + 1
            if sh.light == "into_sun" then golden.into = golden.into + 1 elseif sh.light == "lit" then golden.lit = golden.lit + 1 end
        end
        if sh and sh.light and lib.mock_camera_controlled() ~= 0 and T - sh.t0 > 0.1 then
            if sh.light == "into_sun" then
                golden.into_frames = golden.into_frames + 1
                if sun_in_picture() then golden.sun_seen = golden.sun_seen + 1 end
            else
                golden.lit_frames = golden.lit_frames + 1
                local b = math.deg(math.atan2(cam.x - ac.x, -(cam.z - ac.z)))
                if math.abs(((b - 250 + 180) % 360) - 180) < 60 then golden.lit_ok = golden.lit_ok + 1 end
            end
        end
    end
    command("toggle")
    print(string.format("  golden hour: %d orbiting shots, %d into the sun (sun in the picture %d of %d frames), %d lit by it",
        golden.shots, golden.into, golden.sun_seen, golden.into_frames, golden.lit))
    local lined = (golden.into + golden.lit) / math.max(golden.shots, 1)
    check(golden.shots >= 20 and golden.into > 0 and golden.lit > 0, "golden hour: shots into the sun and lit by it")
    check(lined > 0.35 and lined < 0.9, "most, not all, line up with the sun: " .. lined)
    check(golden.sun_seen > 0.8 * golden.into_frames, "looking into the sun, it's in the picture")
    check(golden.lit_ok > 0.9 * golden.lit_frames, "lit shots have the sun behind the camera")

    -- 10g. night: close shots, few distant ones
    local pick_outside = upvalue(upvalue(upvalue(upvalue(CinematicView_tick, "fn"), "next_shot"), "pick_shot"), "pick_outside")
    local function outside_mix()
        CVt.recent, CVt.prefer_close = {}, false
        local n = { orbiting = 0, trackside = 0, mounted = 0 }
        for _ = 1, 3000 do
            local def = pick_outside({ phase = "cruise", gs = 120, agl = 3000, paused = false })
            n[def.id] = n[def.id] + 1
        end
        return n.trackside / 3000, n.mounted / 3000
    end
    set_f("sim/graphics/scenery/sun_pitch_degrees", -20)
    frame(1 / 30)
    local night_track, night_mounted = outside_mix()
    set_f("sim/graphics/scenery/sun_pitch_degrees", 45)
    frame(1 / 30)
    local day_track, day_mounted = outside_mix()
    print(string.format("  trackside / mounted shots: by day %.2f / %.2f, at night %.2f / %.2f", day_track, day_mounted, night_track, night_mounted))
    check(night_track < 0.07 and day_track > 0.11, "fewer distant trackside shots at night")
    check(night_mounted > 0.35 and day_mounted < 0.25, "more close mounted ones")
    set_f("sim/graphics/scenery/sun_pitch_degrees", -20)
    command("toggle")
    local night_orbits, night_wide = 0, 0
    for _ = 1, 30 * 400 do
        frame(1 / 30)
        local sh = CVt.shot
        if sh and sh.def.id == "orbiting" and sh.inited and not sh.night_seen then
            sh.night_seen = true
            night_orbits = night_orbits + 1
            if sh.zoom > 1 or sh.f < 0.5 then night_wide = night_wide + 1 end
        end
    end
    command("toggle")
    check(night_orbits >= 5 and night_wide == 0, "orbiting shots at night are close, without long lenses (" .. night_orbits .. " shots)")
    set_f("sim/graphics/scenery/sun_pitch_degrees", 45)

    -- 10h. in cloud: the shots move into the cockpit until it's out
    local found_cloud_log = false
    for _, l in ipairs(logs) do if l:find("checks for cloud with sim/weather/aircraft/cloud_*", 1, true) then found_cloud_log = true end end
    check(found_cloud_log, "the cloud datarefs it uses are logged")
    lib.mock_set_cloud(1, 2500, 3600, 0.9)
    command("toggle")
    seconds(4)
    check(CVt.in_cloud, "in cloud")
    seconds(2)
    check(CVt.shot and CVt.shot.def.kind == "cockpit", "into the cockpit, even showing outside shots only")
    local outside_in_cloud = 0
    for _ = 1, 30 * 60 do
        frame(1 / 30)
        if lib.mock_camera_controlled() ~= 0 then outside_in_cloud = outside_in_cloud + 1 end
    end
    check(outside_in_cloud == 0, "no outside shots in cloud: " .. outside_in_cloud .. " frames")
    lib.mock_set_cloud(1, 2500, 3600, 0.3) -- thinned to scattered
    seconds(5)
    check(not CVt.in_cloud, "scattered cloud doesn't count")
    local back_outside = false
    for _ = 1, 30 * 30 do
        frame(1 / 30)
        if CVt.shot and CVt.shot.def.kind == "outside" then back_outside = true break end
    end
    check(back_outside, "and outside shots come back")
    lib.mock_set_cloud(1, 2000, 2900, 0.9) -- the aircraft just above the tops
    seconds(10)
    check(not CVt.in_cloud and CVt.shot.def.kind == "outside", "above the tops, outside shots carry on")
    command("toggle")
    lib.mock_set_cloud(1, 0, 0, 0)
    set_mode("mixed")
    -- back to parked on the ground for the tests that follow
    ac.y, ac.agl, ac.vx, ac.vy, ac.vz, ac.the, ac.phi, ac.onground = 2.5, 2.5, 0, 0, 0, 0, 0, true
    seconds(2)
end

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

-- 12. + and - zoom an outside shot without ending an AFK cinematic
if lib then
    set_mode("outside")
    MOUSE_X = MOUSE_X + 40
    seconds(1)
    seconds(125)
    check(CVt.active and CVt.reason == "afk", "AFK started for the zoom test")
    seconds(2)
    check(CVt.shot.def.kind == "outside", "outside shot running")
    -- Hold a key for `duration` seconds the way X-Plane sends it: a press,
    -- then (after the repeat delay) key repeats, which FlyWithLua reports as
    -- "released" (style "released") or "pressed", or no repeats at all
    -- ("none"); then the real release. Records the zoom shown every frame.
    local function hold(vk, duration, style, interval)
        interval = interval or 1 / 30
        local trace = {}
        local t0 = T
        check(key(vk, "pressed") == true, "zoom key taken (" .. style .. ")")
        local next_repeat = t0 + 0.4
        while T - t0 < duration do
            frame(1 / 60)
            if style ~= "none" and T >= next_repeat and T - t0 < duration then
                key(vk, style)
                next_repeat = next_repeat + interval
            end
            trace[#trace + 1] = CVt.user_zoom
        end
        key(vk, "released")
        local released_at = T
        local stopped_at
        local last_target = CVt.zoom_target
        while T - released_at < 1.5 do
            frame(1 / 60)
            if CVt.zoom_target ~= last_target then stopped_at = nil else stopped_at = stopped_at or T end
            last_target = CVt.zoom_target
            trace[#trace + 1] = CVt.user_zoom
        end
        return trace, (stopped_at or T) - released_at
    end
    local function smooth_trace(trace, dir, label, limit)
        local worst = 0
        for i = 2, #trace do
            local step = math.log(trace[i] / trace[i - 1]) * dir
            check(step > -1e-9, label .. ": zoom never jumps back")
            worst = math.max(worst, step)
        end
        check(worst < (limit or 0.03), label .. ": no frame-to-frame jumps (largest step " .. worst .. ")")
    end
    for _, style in ipairs({ "released", "pressed", "none" }) do
        local from = CVt.zoom_target
        local trace, stop_delay = hold(0xB0, 1.0, style)
        local ratio = CVt.zoom_target / from
        check(ratio > 1.6 and ratio < 2.3, style .. " repeats: holding = for a second zooms about 2x: " .. ratio)
        check(stop_delay < 0.3, style .. " repeats: stops within 0.3 s of letting go: " .. stop_delay)
        check(math.abs(CVt.user_zoom - CVt.zoom_target) < 0.01, style .. " repeats: the zoom shown settles on it")
        smooth_trace(trace, 1, style .. " repeats")
        hold(0xB1, 1.0, style) -- back out
    end
    -- slow key repeats (2 a second) still count as one long hold
    local from = CVt.zoom_target
    hold(0xB0, 2.0, "released", 0.5)
    check(CVt.zoom_target / from > 2.5, "slow key repeats still hold the zoom: " .. CVt.zoom_target / from)
    hold(0xB1, 2.0, "released", 0.5)
    -- a tap makes a small smooth step
    from = CVt.zoom_target
    local before_tap = CVt.user_zoom
    key(0xB0, "pressed")
    frame(1 / 60) frame(1 / 60)
    key(0xB0, "released")
    local tap_trace = { before_tap }
    for _ = 1, 60 do frame(1 / 60) tap_trace[#tap_trace + 1] = CVt.user_zoom end
    check(math.abs(CVt.zoom_target / from - 1.1) < 0.01, "a tap zooms a 10% step: " .. CVt.zoom_target / from)
    smooth_trace(tap_trace, 1, "tap")
    check(cam.zoom >= CVt.user_zoom * 0.84, "camera zoom includes it: " .. cam.zoom)
    local zoomed = CVt.zoom_target
    hold(0x6D, 0.5, "released") -- keypad -
    check(CVt.zoom_target < zoomed, "keypad - zooms out")
    -- the mouse wheel: a step a notch, eased in, without ending the cinematic
    local function wheel(notches)
        MOUSE_WHEEL_CLICKS, MOUSE_WHEEL_NUMBER, RESUME_MOUSE_WHEEL = notches, 0, false
        run(chunks.wheel)
        return RESUME_MOUSE_WHEEL
    end
    local before_wheel = CVt.zoom_target
    check(wheel(2) == true, "the wheel is taken by the cinematic camera")
    check(math.abs(CVt.zoom_target / before_wheel - 1.12 ^ 2) < 1e-6, "two notches zoom 1.25x: " .. CVt.zoom_target / before_wheel)
    MOUSE_X = MOUSE_X + 2 -- the hand on the mouse moves it a little
    local wheel_trace = { CVt.user_zoom }
    for _ = 1, 60 do frame(1 / 60) wheel_trace[#wheel_trace + 1] = CVt.user_zoom end
    -- two notches at once (a 25% step) spread over frames: none takes a fifth of it
    smooth_trace(wheel_trace, 1, "wheel", math.log(1.12 ^ 2) / 5)
    check(math.abs(CVt.user_zoom - CVt.zoom_target) < 0.01, "the zoom settles on it")
    wheel(-2)
    seconds(1)
    check(math.abs(CVt.zoom_target - before_wheel) < 1e-6, "and back out")
    check(CVt.active, "scrolling didn't end the AFK cinematic")
    -- a joystick button that runs one of our commands isn't input either
    lib.mock_set_button(40, 1)
    run({ commands["FlyWithLua/cinematic_view/next_shot"] })
    seconds(0.2)
    lib.mock_set_button(40, 0)
    run({ command_ends["FlyWithLua/cinematic_view/next_shot"] })
    seconds(1)
    check(CVt.active, "a joystick button bound to next shot doesn't end it")
    -- in the cockpit, + and - go on to X-Plane's own zoom
    set_mode("cockpit")
    seconds(2)
    check(CVt.shot.def.kind == "cockpit", "cockpit shot running")
    check(key(0xB0, "pressed") == false, "= goes on to X-Plane in the cockpit")
    key(0xB0, "released")
    -- and the wheel runs X-Plane's zoom (rather than turning a knob under the pointer)
    local function wheel_commands(notches, label)
        local from = #command_log
        check(wheel(notches) == true, label .. ": the wheel is taken in the cockpit")
        local zoom_in = held_commands["sim/general/zoom_in"]
        local zoom_out = held_commands["sim/general/zoom_out"]
        check((notches > 0 and zoom_in and not zoom_out) or (notches < 0 and zoom_out and not zoom_in),
            label .. ": it holds X-Plane's zoom " .. (notches > 0 and "in" or "out"))
        local start = T
        while held_commands["sim/general/zoom_in"] or held_commands["sim/general/zoom_out"] do
            frame(1 / 60)
            if T - start > 2 then break end
        end
        return T - start, from
    end
    local held = wheel_commands(1, "one notch")
    check(held > 0.08 and held < 0.2, "one notch zooms as long as a tap: " .. held)
    held = wheel_commands(3, "three notches")
    check(held > 0.3 and held < 0.45, "three notches zoom three times as long: " .. held)
    wheel(2)
    frame(1 / 60)
    local _, from = wheel_commands(-1, "turning back")
    check(command_log[from + 1] == "end sim/general/zoom_in" and command_log[from + 2] == "begin sim/general/zoom_out",
        "turning the wheel back lets go of zooming in first")
    wheel(1)
    MOUSE_WHEEL_CLICKS, MOUSE_WHEEL_NUMBER, RESUME_MOUSE_WHEEL = 1, 1, false
    run(chunks.wheel)
    check(RESUME_MOUSE_WHEEL == false, "a sideways wheel goes on to X-Plane")
    seconds(0.5)
    check(CVt.active, "and neither ends the cinematic")
    check(not next(held_commands), "nothing left held down")
    wheel(5)
    tap(0x41)
    seconds(0.5)
    check(not CVt.active, "other keys still end it")
    check(not next(held_commands), "and ending it lets go of X-Plane's zoom")
    set_mode("mixed")
    -- when it isn't running, the wheel is input like any other
    local idle_from = CVt.last_input
    seconds(2)
    MOUSE_WHEEL_CLICKS, MOUSE_WHEEL_NUMBER, RESUME_MOUSE_WHEEL = 1, 0, false
    run(chunks.wheel)
    seconds(0.1)
    check(CVt.last_input > idle_from + 1.5 and RESUME_MOUSE_WHEEL == false, "the wheel counts as input when not running")
end

-- 13. keys set in the settings window
command("settings")
local wnd = next(windows)
check(wnd and wnd.builder == "CinematicView_build_settings", "settings window opened")
local function build()
    _G[wnd.builder](wnd, 0, 0)
    check(ui.colors == 0 and ui.vars == 0 and ui.disabled == 0 and ui.tabbar == 0 and ui.tabitem == 0,
        string.format("window frame balanced (colours %d, styles %d, disabled %d, tabs %d/%d)",
            ui.colors, ui.vars, ui.disabled, ui.tabbar, ui.tabitem))
end
local function click(label) imgui_clicks[label] = true build() imgui_clicks = {} end
widgets = {}
build()
local labels = table.concat(widgets, "|")
check(labels:find("Running", 1, true) == nil or not labels:find("Running %(.-%):"), "no shot names in the status line")
for _, l in ipairs({ "Cycle shot types", "Zoom in", "Zoom out", "never starts", "while the sim is paused" }) do
    check(not labels:find(l, 1, true), "window no longer has " .. l)
end
for _, l in ipairs({ "Start / stop", "Next shot", "Hold shot", "Auto-start on/off", "This window",
    "Camera speed", "Panning speed", "Letterbox bars", "Fades", "Window seat shots" }) do
    check(labels:find(l, 1, true), "window shows " .. l)
end
check(not labels:find("Caption"), "no captions option")
for _, l in ipairs(checkboxes) do check(not l:find("paused"), "no option to start while paused") end
check(not labels:find("shake"), "no camera shake option")
check(labels:find("AIRCRAFT", 1, true) and labels:find("|Size|", 1, true), "window shows the aircraft size")
for _, l in ipairs({ "Camera", "Shots", "Auto-start", "Keys", "MOVEMENT", "PICTURE", "Start cinematic##startstop",
    "Mixed##mode", "Outside##mode", "Cockpit##mode" }) do
    check(labels:find(l, 1, true), "window has " .. l)
end
check(labels:find("Auto-start in", 1, true) or labels:find("Ready", 1, true), "status line shows the countdown or readiness")
-- Start and Stop from the window
click("Start cinematic##startstop")
check(CVt.active and CVt.reason == "manual", "Start cinematic starts it")
seconds(1)
widgets = {}
build()
check(table.concat(widgets, "|"):find("Stop##startstop", 1, true), "the button turns into Stop")
click("Stop##startstop")
check(not CVt.active, "Stop stops it")
seconds(1)
click("Set##set_toggle")
check(CVt.capturing == "toggle", "waiting for a key")
check(tap(0x78, { ctrl = true }) == true, "the key being set is swallowed")
check(CVt.capturing == nil, "captured")
seconds(2)
check(ini_text():find("bind_toggle = 120 2 Ctrl+F9", 1, true), "Ctrl+F9 saved for start/stop:\n" .. ini_text())
check(tap(0x78, { ctrl = true }) == true, "Ctrl+F9 is ours now")
seconds(1)
check(CVt.active and CVt.reason == "manual", "Ctrl+F9 starts the cinematic")
key(0x78, "pressed", { ctrl = true })
key(0x78, "pressed", { ctrl = true }) -- auto-repeat
key(0x78, "pressed", { ctrl = true })
key(0x78, "released", { ctrl = true })
seconds(1)
check(not CVt.active, "Ctrl+F9 stops it, holding it doesn't flip it back")
check(tap(0x78) == false, "plain F9 isn't bound")
click("Set##set_next_shot")
tap(0x1B)
check(CVt.capturing == nil and not ini_text():find("bind_next_shot = %d"), "Esc cancels")
click("Set##set_next_shot")
tap(0x78, { ctrl = true })
seconds(2)
check(ini_text():find("bind_next_shot = 120 2 Ctrl+F9", 1, true) and ini_text():find("bind_toggle = \n", 1, true),
    "a key set on another action moves there:\n" .. ini_text())
click("Clear##clear_next_shot")
seconds(2)
check(ini_text():find("bind_next_shot = \n", 1, true), "Clear removes it")
-- a held key set for Next shot cuts once, however long it's held
click("Set##set_next_shot")
tap(0x4E) -- N
command("toggle")
seconds(2)
local shots_before = #shot_log
check(key(0x4E, "pressed") == true, "N is ours now")
for _ = 1, 20 do
    seconds(1 / 30)
    key(0x4E, "released") -- key repeats, as FlyWithLua reports them
end
key(0x4E, "released")
seconds(1.2) -- (time for a fade)
check(#shot_log - shots_before == 1, "holding N cut to the next shot once: " .. (#shot_log - shots_before))
command("toggle")
click("Clear##clear_next_shot")

-- 13a. holding a shot
command("toggle")
seconds(2)
local held = CVt.shot
command("hold")
check(CVt.hold, "Hold shot holds it")
seconds(40)
check(CVt.shot == held, "a held shot goes on past its length")
widgets = {}
build()
local held_labels = table.concat(widgets, "|")
check(held_labels:find("Holding##hold", 1, true) and held_labels:find("holding this shot", 1, true), "the window shows it's holding")
command("hold")
seconds(1)
check(not CVt.hold and CVt.shot ~= held, "let go of, it moves on")
click("Hold shot##hold")
check(CVt.hold, "the window's Hold shot button holds it too")
held = CVt.shot
click("Next shot")
seconds(1)
check(not CVt.hold and CVt.shot ~= held, "Next shot lets go and cuts")
click("Hold shot##hold")
command("toggle")
check(not CVt.hold, "stopping lets go")
click("Set##set_hold")
tap(0x48) -- H
command("toggle")
seconds(1)
check(tap(0x48) == true and CVt.hold, "a key set for Hold shot holds it")
seconds(0.5)
tap(0x48)
check(not CVt.hold, "and lets go")
command("toggle")
click("Clear##clear_hold")

-- 14. camera speed
imgui_clicks["##camera_pace"] = 2 build() imgui_clicks = {}
command("toggle")
seconds(40)
check(CVt.shot and CVt.shot.pace == 2, "shots use the camera speed")
command("toggle")
imgui_clicks["##camera_pace"] = 0.1 build() imgui_clicks = {}
command("toggle")
seconds(40)
check(CVt.shot and CVt.shot.pace == 0.1, "slow camera speed too")
command("toggle")
imgui_clicks["##camera_pace"] = 0.5 build() imgui_clicks = {}

-- 14a. panning speed, separately
imgui_clicks["##pan_pace"] = 2 build() imgui_clicks = {}
command("toggle")
seconds(40)
check(CVt.shot and CVt.shot.pan == 2 and CVt.shot.pace == 0.5, "shots use the panning speed, apart from the camera speed")
command("toggle")
imgui_clicks["##pan_pace"] = 0.1 build() imgui_clicks = {}
command("toggle")
seconds(40)
check(CVt.shot and CVt.shot.pan == 0.1, "slow panning too")
command("toggle")
imgui_clicks["##pan_pace"] = 0.5 build() imgui_clicks = {}
seconds(2)
check(ini_text():find("pan_pace = 0.5", 1, true) and not ini_text():find("shake"), "panning speed saved, no shake setting")

-- 14b. aircraft size, kept for this aircraft
local auto_size = CVt.size
imgui_clicks["##size"] = 60 build() imgui_clicks = {}
check(CVt.size == 60, "the aircraft size slider sets the size")
seconds(2)
check(ini_text():find("size:Test A320.acf = 60.0", 1, true), "and it's saved for this aircraft:\n" .. ini_text())
command("toggle")
seconds(30)
check(stats.too_close == 0, "cameras keep clear of the bigger aircraft too")
command("toggle")
click("Auto##size")
check(math.abs(CVt.size - auto_size) < 1e-6, "Auto goes back to the worked-out size")
seconds(2)
check(not ini_text():find("size:Test A320.acf", 1, true), "and forgets the setting")

-- 14c. window seat shots: from a passenger window, looking out at the wing
set_mode("cockpit")
local first_cockpit = #cockpit_shots
command("toggle")
seconds(600)
check(CVt.active, "the cockpit run kept going")
command("toggle")
local window_shots, window_bad = 0, 0
for i = first_cockpit + 1, #cockpit_shots do
    local sh = cockpit_shots[i]
    if sh.window then
        window_shots = window_shots + 1
        local e = CVt.eye
        local x, z = e.x + sh.dx, e.z + sh.dz
        local look = sh.psi0 + sh.dpsi / 2
        if z <= 0 or math.abs(x) < 0.3 or (x > 0) ~= (look > 0) or math.abs(look) < 60 or math.abs(look) > 125 then
            window_bad = window_bad + 1
        end
    end
end
check(window_shots >= 1 and window_shots <= 0.4 * (#cockpit_shots - first_cockpit) and window_bad == 0,
    string.format("window seat shots: behind the wing's leading edge, out to one side, looking out (%d of %d cockpit shots, %d off)",
        window_shots, #cockpit_shots - first_cockpit, window_bad))
click("Window seat shots")
first_cockpit = #cockpit_shots
command("toggle")
seconds(200)
command("toggle")
local windows_after = 0
for i = first_cockpit + 1, #cockpit_shots do if cockpit_shots[i].window then windows_after = windows_after + 1 end end
check(#cockpit_shots - first_cockpit > 5 and windows_after == 0, "none once they're turned off")
seconds(2)
check(ini_text():find("window_seat = false", 1, true), "and that's saved")
click("Window seat shots")
set_mode("mixed")
command("settings")

-- 15. settings window
command("settings")
wnd = next(windows)
build()
check(#widgets > 10, "settings window built")
imgui_clicks["##afk_timeout"] = 300
imgui_clicks["Cockpit##mode"] = true
build()
imgui_clicks = {}
click("Start when I'm away from the controls")
imgui_clicks["##afk_timeout"] = 500 -- disabled now: no effect
build()
imgui_clicks = {}
seconds(3)
local ini = ini_text()
check(ini:find("afk_enabled = false") and ini:find("afk_timeout = 300") and ini:find("mode = cockpit"), "settings saved:\n" .. ini)
command("settings")
check(next(windows) == nil, "settings window closed")

-- 16. exit hook
run({ commands["FlyWithLua/cinematic_view/toggle"] })
seconds(2)
run(exit_code)
check(lib == nil or lib.mock_camera_controlled() == 0, "camera released on exit")

if mode == "ffi" then
    local sectors, zoomed, wide, el_lo, el_hi = {}, false, false, 90, -90
    local nsec = 0
    for _, sh in ipairs(orbiting_shots) do
        local sec = math.floor((sh.az0 % 360) / 45)
        if not sectors[sec] then sectors[sec] = true nsec = nsec + 1 end
        if sh.zoom > 1 then zoomed = true else wide = true end
        el_lo, el_hi = math.min(el_lo, sh.el0), math.max(el_hi, sh.el0)
    end
    print(string.format("  %d orbiting shots generated: %d of 8 directions, elevations %.0f..%.0f", #orbiting_shots, nsec, el_lo, el_hi))
    check(#orbiting_shots >= 20 and nsec >= 6, "orbiting shots come from all round the aircraft")
    check(zoomed and wide, "with long lenses and wide ones")
    check(el_hi - el_lo > 40, "from low and high")
end
local bobbing = 0
for _, sh in ipairs(cockpit_shots) do
    local _, y0, _, _, the0 = sh.def.update(sh, CVt.eye or { x = -0.55, seat = -1 }, 0)
    for i = 1, 10 do
        local _, y, _, _, the = sh.def.update(sh, CVt.eye or { x = -0.55, seat = -1 }, sh.duration * i / 10)
        if math.abs(y - y0) > 1e-9 or math.abs(the - the0) > 1e-9 then bobbing = bobbing + 1 end
    end
end
check(#cockpit_shots > 5 and bobbing == 0, "cockpit shots hold the head steady (" .. #cockpit_shots .. " shots)")
local fast_pans = 0
for _, sh in ipairs(cockpit_shots) do
    if math.abs(sh.dpsi) > math.min(5 * sh.pan * sh.duration * 1.5, 40) + 1e-6 then fast_pans = fast_pans + 1 end
end
check(fast_pans == 0, "cockpit pans keep to the panning speed")
for id, ps in pairs(per_shot) do
    print(string.format("  %-9s frames %5d  max off-axis (x zoom) %5.1f deg  dist %6.1f..%6.1f m  zoom<=%.2f  |roll|<=%.1f",
        id, ps.n, ps.ang, ps.dmin, ps.dmax, ps.zmax, ps.rollmax))
    check(ps.ang < 40, id .. " keeps the aircraft in frame")
end
local kinds = 0
for _ in pairs(shots_seen) do kinds = kinds + 1 end
check(kinds >= 3, "several kinds of shot (" .. kinds .. ")")
for _, l in ipairs(logs) do if l:find("error") then print("log: " .. l) check(false, "no errors logged") end end
print(string.format("%s: %d checks, %d failed", mode, checks, fails))
os.exit(fails == 0 and 0 or 1)
