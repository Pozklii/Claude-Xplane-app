-- Runs Cinematic_Views.lua against mock_xplm.c and simulated flights, checking
-- what the camera does. Start it with run_tests.sh.

local ffi = require("ffi")
local SCRIPT = assert(arg[1], "usage: run_tests.lua <path to Cinematic_Views.lua> <work dir>")
local WORK = assert(arg[2])

ffi.cdef [[
  void mock_define(const char *name, double value);
  double mock_get(const char *name);
  void mock_define_command(const char *name);
  void mock_set_ground(double y);
  void mock_shift_origin(double dx, double dz);
  const char *mock_last_command(void);
  int mock_command_count(void);
  int mock_camera_controlled(void);
  void mock_set_view(int view_type, int external);
  int mock_render(double *out);
  void mock_set_aircraft(const char *file_name);
  int mock_handler_count(void);
  int mock_press(const char *name, int phase);
]]
local X = ffi.load(WORK .. "/Resources/plugins/XPLM_64.so")

-- ---------------------------------------------------------------------------
-- Tiny test framework
-- ---------------------------------------------------------------------------
local failures, checks = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end
local function section(name) print("-- " .. name) end

-- ---------------------------------------------------------------------------
-- FlyWithLua stand-ins
-- ---------------------------------------------------------------------------
local logs = {}
local hooks = { frame = {}, draw = {}, often = {}, exit = {}, wheel = {} }
local commands, macros = {}, {}
local drawn = { rects = 0, strings = {} }

SYSTEM = "LIN"
SYSTEM_ARCHITECTURE = 64
SCRIPT_DIRECTORY = WORK .. "/Resources/plugins/FlyWithLua/Scripts/"
SCREEN_WIDTH, SCREEN_HIGHT = 2560, 1440
SUPPORTS_FLOATING_WINDOWS = true

function logMsg(s) logs[#logs + 1] = s end
local function compile(code) return assert(loadstring(code)) end
function do_every_frame(code) hooks.frame[#hooks.frame + 1] = compile(code) end
function do_every_draw(code) hooks.draw[#hooks.draw + 1] = compile(code) end
function do_often(code) hooks.often[#hooks.often + 1] = compile(code) end
function do_on_exit(code) hooks.exit[#hooks.exit + 1] = compile(code) end
function do_on_mouse_wheel(code) hooks.wheel[#hooks.wheel + 1] = compile(code) end
function create_command(name, desc, b, c, e)
  commands[name] = { desc = desc, b = compile(b), c = compile(c), e = compile(e) }
end
function add_macro(name, code) macros[name] = compile(code) end
function XPLMSetGraphicsState() end
graphics = {
  set_color = function() end,
  draw_rectangle = function(x1, y1, x2, y2)
    assert(x2 >= x1 and y2 >= y1, "bad rectangle")
    drawn.rects = drawn.rects + 1
  end,
}
function draw_string(x, y, s, col) drawn.strings[#drawn.strings + 1] = s end

-- imgui: records labels; "click" makes one labelled button return true once,
-- "set" makes one slider return a new value once.
local ui = { labels = {}, click = nil, set = nil, tree_open = true }
local function ui_label(l) ui.labels[#ui.labels + 1] = l end
imgui = {
  constant = { Col = { Button = 21, Text = 0 } },
  TextUnformatted = function(s) ui_label(s) end,
  Button = function(l) ui_label(l) if ui.click and l:find(ui.click, 1, true) == 1 then ui.click = nil return true end return false end,
  SameLine = function() end, Separator = function() end,
  PushStyleColor = function() ui.depth = (ui.depth or 0) + 1 end,
  PopStyleColor = function() ui.depth = ui.depth - 1 end,
  SliderFloat = function(l, v)
    ui_label(l)
    if ui.set and l:find(ui.set[1], 1, true) == 1 then
      local nv = ui.set[2]
      ui.set = nil
      return true, nv
    end
    return false, v
  end,
  Checkbox = function(l, v) ui_label(l) return false, v end,
  TreeNode = function(l) ui_label(l) return ui.tree_open end,
  TreePop = function() end,
}
local windows = 0
function float_wnd_create() windows = windows + 1 return { id = windows } end
function float_wnd_set_title() end
function float_wnd_set_imgui_builder(w, name) w.builder = name end
function float_wnd_set_onclose(w, name) w.onclose = name end
function float_wnd_destroy() windows = windows - 1 end

-- ---------------------------------------------------------------------------
-- Simulated X-Plane
-- ---------------------------------------------------------------------------
local REFS = {
  "sim/flightmodel/position/local_x", "sim/flightmodel/position/local_y", "sim/flightmodel/position/local_z",
  "sim/flightmodel/position/psi", "sim/flightmodel/position/theta", "sim/flightmodel/position/phi",
  "sim/flightmodel/position/local_vx", "sim/flightmodel/position/local_vy", "sim/flightmodel/position/local_vz",
  "sim/flightmodel/position/y_agl", "sim/flightmodel/position/indicated_airspeed",
  "sim/flightmodel/failures/onground_any", "sim/aircraft/weight/acf_m_max", "sim/flightmodel/weight/m_total",
  "sim/aircraft/view/acf_size_x", "sim/aircraft/view/acf_size_z",
  "sim/graphics/view/view_type", "sim/graphics/view/view_is_external", "sim/graphics/view/field_of_view_deg",
  "sim/graphics/view/pilots_head_x", "sim/graphics/view/pilots_head_y", "sim/graphics/view/pilots_head_z",
  "sim/graphics/view/pilots_head_psi", "sim/graphics/view/pilots_head_the", "sim/graphics/view/pilots_head_phi",
  "sim/time/total_running_time_sec", "sim/operation/misc/frame_rate_period", "sim/time/paused",
  "sim/time/is_in_replay", "sim/graphics/VR/enabled",
}
for _, r in ipairs(REFS) do X.mock_define(r, 0) end
X.mock_define_command("sim/view/3d_cockpit_cmnd_look")
X.mock_define_command("sim/view/chase")
X.mock_define_command("sim/view/circle")
for _, c in ipairs({ "zoom_in", "zoom_out", "zoom_in_fast", "zoom_out_fast" }) do X.mock_define_command("sim/general/" .. c) end

local function set(name, v) X.mock_define(name, v) end
local function get(name) return X.mock_get(name) end

-- A320-ish, sitting in the captain's seat.
local EYE = { -0.55, 1.6, -16.5, 0, -5, 0 }
local HEAD_REFS = { "x", "y", "z", "psi", "the", "phi" }
set("sim/aircraft/weight/acf_m_max", 78000)
set("sim/aircraft/view/acf_size_x", 17.9)   -- half span (m)
set("sim/aircraft/view/acf_size_z", 18.8)   -- half length (m)
set("sim/graphics/view/field_of_view_deg", 75)
set("sim/operation/misc/frame_rate_period", 1 / 60)
for i, k in ipairs(HEAD_REFS) do set("sim/graphics/view/pilots_head_" .. k, EYE[i]) end
X.mock_set_view(1026, 0)
X.mock_set_ground(0)

-- Aircraft in "world" metres (east, up, south); local = world - origin.
local plane = { e = 0, u = 2.5, s = 0, psi = 90, the = 0, phi = 0, ve = 0, vu = 0, vs = 0, ground = true, ias = 0 }
local origin = { e = 0, s = 0 }
local sim_t = 0
local DT = 1 / 60

local function publish()
  set("sim/flightmodel/position/local_x", plane.e - origin.e)
  set("sim/flightmodel/position/local_y", plane.u)
  set("sim/flightmodel/position/local_z", plane.s - origin.s)
  set("sim/flightmodel/position/psi", plane.psi)
  set("sim/flightmodel/position/theta", plane.the)
  set("sim/flightmodel/position/phi", plane.phi)
  set("sim/flightmodel/position/local_vx", plane.ve)
  set("sim/flightmodel/position/local_vy", plane.vu)
  set("sim/flightmodel/position/local_vz", plane.vs)
  set("sim/flightmodel/position/y_agl", plane.u - 2.5)
  set("sim/flightmodel/position/indicated_airspeed", plane.ias)
  set("sim/flightmodel/failures/onground_any", plane.ground and 1 or 0)
  set("sim/time/total_running_time_sec", sim_t)
end

-- Fly with a given ground speed (m/s), heading, vertical speed and bank.
local function steer(speed, hdg, vs, bank, ground)
  plane.psi, plane.phi, plane.ground = hdg % 360, bank or 0, ground or false
  local h = math.rad(plane.psi)
  plane.ve, plane.vs, plane.vu = speed * math.sin(h), -speed * math.cos(h), vs or 0
  plane.the = ground and 0 or math.deg(math.atan2(plane.vu, math.max(speed, 1))) + 2
  plane.ias = speed * 1.94
end

local cam_buf = ffi.new("double[7]")
local cam = nil
local paused_no_flightloop = false
local hooks_dead = false

local function step(n, each)
  for _ = 1, n or 1 do
    sim_t = sim_t + DT
    if not paused_no_flightloop then
      plane.e, plane.u, plane.s = plane.e + plane.ve * DT, plane.u + plane.vu * DT, plane.s + plane.vs * DT
      if plane.ground then plane.u = 2.5 end
    end
    publish()
    if not paused_no_flightloop and not hooks_dead then for _, f in ipairs(hooks.frame) do f() end end
    if X.mock_render(cam_buf) == 1 then
      cam = { x = cam_buf[0], y = cam_buf[1], z = cam_buf[2], pit = cam_buf[3], hdg = cam_buf[4], rol = cam_buf[5], zoom = cam_buf[6] }
    else
      cam = nil
    end
    if not hooks_dead then for _, f in ipairs(hooks.draw) do f() end end
    if each then each() end
  end
end

local function run_command(name) commands["FlyWithLua/cinematic_views/" .. name].b() end
local function often() for _, f in ipairs(hooks.often) do f() end end

-- Camera position relative to the aircraft, in its body axes (for a level
-- aircraft heading north: x right, y up, z aft).
local function cam_body()
  return cam.x - (plane.e - origin.e), cam.y - plane.u, cam.z - (plane.s - origin.s)
end

-- Where is the aircraft in the camera picture? Returns the angle (deg) between
-- the view direction and the aircraft, the half-width of the view, and the distance.
local function aircraft_off_axis()
  local ax, ay, az = plane.e - origin.e - cam.x, plane.u - cam.y, plane.s - origin.s - cam.z
  local n = math.sqrt(ax * ax + ay * ay + az * az)
  local h, p = math.rad(cam.hdg), math.rad(cam.pit)
  local fx, fy, fz = math.sin(h) * math.cos(p), math.sin(p), -math.cos(h) * math.cos(p)
  local c = (ax * fx + ay * fy + az * fz) / n
  local fov = get("sim/graphics/view/field_of_view_deg")
  local half = math.deg(math.atan(math.tan(math.rad(fov / 2)) / cam.zoom))
  return math.deg(math.acos(math.max(-1, math.min(1, c)))), half, n
end

local function finite(v) return v == v and v > -1e12 and v < 1e12 end
local function in_cockpit() return get("sim/graphics/view/view_type") == 1026 and get("sim/graphics/view/view_is_external") == 0 end

-- ---------------------------------------------------------------------------
section("loading")
publish()
dofile(SCRIPT)
check(type(CinematicViews) == "table", "script did not create CinematicViews")
check(#hooks.frame == 1 and #hooks.draw == 1 and #hooks.exit == 1, "frame/draw/exit hooks registered")
check(commands["FlyWithLua/cinematic_views/toggle"] ~= nil, "toggle command exists")
check(commands["FlyWithLua/cinematic_views/shot_spotter"] ~= nil, "per-shot commands exist")
check(commands["FlyWithLua/cinematic_views/director"] == nil, "no Director command")
for _, l in ipairs(logs) do check(not l:find("not started") and not l:find("failed"), "log: " .. l) end

local cine, A, S = CinematicViews._state()
local SHOTS, ORDER = CinematicViews._shots()
check(#ORDER == 11, "11 exterior shots, got " .. #ORDER)

section("aircraft size from its dimensions, with the weight as a check and fallback")
step(5)
check(A.size_source == "dimensions", "A320 measured from its dimensions")
check(math.abs(A.Rs - 17.9) < 0.01 and math.abs(A.Rl - 18.8) < 0.01, ("half span %.1f, half length %.1f"):format(A.Rs, A.Rl))
set("sim/aircraft/view/acf_size_x", 58.7) set("sim/aircraft/view/acf_size_z", 61.7)   -- the same in feet
often()
check(math.abs(A.Rs - 17.9) < 0.1 and math.abs(A.Rl - 18.8) < 0.1, ("feet converted (%.1f, %.1f)"):format(A.Rs, A.Rl))
set("sim/aircraft/view/acf_size_x", 0) set("sim/aircraft/view/acf_size_z", 0)
often()
check(A.size_source == "weight" and A.R > 17 and A.R < 24, ("no dimensions: from the weight (%.1f m)"):format(A.R))
set("sim/aircraft/view/acf_size_x", 500) set("sim/aircraft/view/acf_size_z", 3)
often()
check(A.size_source == "weight", "nonsense dimensions are ignored")
set("sim/aircraft/view/acf_size_x", 17.9) set("sim/aircraft/view/acf_size_z", 18.8)
often()

-- ---------------------------------------------------------------------------
section("every shot frames the aircraft (taxi, takeoff roll, cruise, approach)")
local cases = {
  { name = "taxi", setup = function() plane.u = 2.5 steer(8, 90, 0, 0, true) end },
  { name = "runway", setup = function() plane.u = 2.5 steer(60, 90, 0, 0, true) end },
  { name = "cruise turn", setup = function() plane.u = 3000 steer(230, 45, 0, 25, false) end, turn = 2 },
  { name = "approach", setup = function() plane.u = 300 steer(70, 270, -3.5, 0, false) end },
}
for _, case in ipairs(cases) do
  for _, id in ipairs(ORDER) do
    local def = SHOTS[id]
    case.setup()
    CinematicViews.shot(id)
    local worst, frames, out, bad, dist_max, dist_min = 0, 0, 0, 0, 0, 1e9
    step(2)
    step(60 * 8, function()
      if case.turn then steer(math.sqrt(plane.ve ^ 2 + plane.vs ^ 2), plane.psi + case.turn * DT, 0, 25, false) end
      if cine.def ~= def then return end
      if not cam then bad = bad + 1 return end
      for _, k in ipairs({ "x", "y", "z", "pit", "hdg", "rol", "zoom" }) do
        if not finite(cam[k]) then bad = bad + 1 return end
      end
      frames = frames + 1
      local off, half, dist = aircraft_off_axis()
      dist_max, dist_min = math.max(dist_max, dist), math.min(dist_min, dist)
      if not def.vib and cine.blend >= 1 then
        worst = math.max(worst, off / half)
        if off > half then out = out + 1 end
      end
      if cam.y < 0.3 then bad = bad + 1 end
    end)
    local label = ("%s / %s"):format(case.name, id)
    if os.getenv("VERBOSE") then
      print(("   %-12s %-8s dist %6.1f..%6.1f m  zoom %4.1f  worst %.2f  out %d/%d"):format(
        case.name, id, dist_min, dist_max, cam and cam.zoom or 0, worst, out, frames))
    end
    check(bad == 0, label .. ": camera missing, non-finite or underground on " .. bad .. " frames")
    check(frames > 100, label .. ": only " .. frames .. " camera frames")
    if not def.vib then
      check(out <= frames * 0.03, ("%s: aircraft out of frame on %d/%d frames (worst %.2f of half-width)"):format(label, out, frames, worst))
    else
      check(dist_max < 3 * A.R, ("%s: mounted camera %.0f m away"):format(label, dist_max))
    end
    check(dist_min > 0.3 * A.R or def.vib, ("%s: camera %.1f m from the aircraft centre"):format(label, dist_min))
  end
end

-- ---------------------------------------------------------------------------
section("mounted cameras are rigid with the airframe")
plane.u = 2000
steer(200, 30, 0, 20, false)
plane.the = 10
CinematicViews.shot("tail")
step(3)
check(cam ~= nil and math.abs(((cam.hdg - 30 + 180) % 360) - 180) < 2, "tail cam heading follows the aircraft")
check(cam ~= nil and math.abs(cam.rol - 20) < 1.5, ("tail cam rolls with the aircraft (%.1f)"):format(cam and cam.rol or -1))
check(cam ~= nil and math.abs(cam.pit - (10 - 4)) < 2, ("tail cam pitch %.1f"):format(cam and cam.pit or -1))

-- ---------------------------------------------------------------------------
section("starting from the cockpit and stopping takes you back there")
CinematicViews.stop()
step(5)
check(in_cockpit(), "back in the cockpit after stop")
check(X.mock_camera_controlled() == 0, "camera released")
CinematicViews.shot("chase")
step(2)
check(X.mock_camera_controlled() == 1 and get("sim/graphics/view/view_is_external") == 1, "a shot switches to an exterior view and takes the camera")
CinematicViews.shot("orbit")
step(2)
check(X.mock_camera_controlled() == 1 and cine.def.id == "orbit", "switching shots keeps the camera")
run_command("toggle")
step(3)
check(not cine.active and in_cockpit() and X.mock_camera_controlled() == 0, "toggle stops and returns to the cockpit")
run_command("toggle")
step(3)
check(cine.active and cine.def.id == "orbit", "toggle starts again with the last shot")
CinematicViews.stop()
step(3)

section("starting from an exterior view stays exterior when you stop")
X.mock_set_view(1018, 1)
step(2)
CinematicViews.shot("wing")
step(3)
check(X.mock_camera_controlled() == 1, "camera taken without a view change")
CinematicViews.stop()
step(3)
check(get("sim/graphics/view/view_is_external") == 1 and X.mock_camera_controlled() == 0, "left in your exterior view")
X.mock_set_view(1026, 0)
step(3)

section("you changing the view hands the camera back")
CinematicViews.shot("chase")
step(5)
X.mock_set_view(1018, 1)      -- e.g. pressing a view key
step(3)
check(not cine.active, "session stopped after a user view change")
check(X.mock_camera_controlled() == 0, "camera not controlled")
X.mock_set_view(1026, 0)
step(3)

section("the pilot's head is never touched")
local untouched = true
for i, k in ipairs(HEAD_REFS) do
  if math.abs(get("sim/graphics/view/pilots_head_" .. k) - EYE[i]) > 1e-6 then untouched = false end
end
check(untouched, "pilot's head datarefs unchanged")

-- ---------------------------------------------------------------------------
section("next and previous step through the shots, skipping ones that don't apply")
plane.u = 2.5
steer(10, 90, 0, 0, true)
CinematicViews.shot("sweep")    -- air-to-air comes next in the list but needs to be airborne
step(3)
CinematicViews.previous_shot()
step(3)
check(cine.def.id == "spotter", "previous from Crane sweep skips Air-to-air on the ground (" .. cine.def.id .. ")")
CinematicViews.next_shot()
step(3)
check(cine.def.id == "sweep", "next from Spotter skips Air-to-air on the ground (" .. cine.def.id .. ")")
CinematicViews.stop()
step(3)

-- ---------------------------------------------------------------------------
section("glides between related shots without passing through the aircraft")
plane.u = 1500
steer(150, 0, 0, 0, false)
S.blend_time = 2
CinematicViews.shot("chase")
step(60)
CinematicViews.shot("a2a")
step(2)
local min_d = 1e9
step(60 * 3, function()
  if cam then
    local _, _, d = aircraft_off_axis()
    min_d = math.min(min_d, d)
  end
end)
check(min_d > 0.9 * A.R, ("glide stayed %.1f m clear (R %.1f)"):format(min_d, A.R))

-- ---------------------------------------------------------------------------
section("fixed cameras survive X-Plane moving its local origin")
plane.u = 400
steer(80, 180, 0, 0, false)
CinematicViews.shot("flyby")
step(30)
local before = cam and { x = cam.x + origin.e, z = cam.z + origin.s }
origin.e, origin.s = origin.e + 20000, origin.s - 15000
X.mock_shift_origin(20000, -15000)
step(1)
local after = cam and { x = cam.x + origin.e, z = cam.z + origin.s }
check(before and after and math.abs(before.x - after.x) < 0.5 and math.abs(before.z - after.z) < 0.5,
      "flyby camera stayed put in the world")

section("a flyby sets up the next pass once the aircraft has gone by")
local passes, last_st = 0, cine.st
step(60 * 40, function()
  steer(80, 180, 0, 0, false)
  if cine.st ~= last_st then passes, last_st = passes + 1, cine.st end
end)
check(passes >= 3, "flyby repeated " .. passes .. " times in 40 s")
check(cine.active and cine.def.id == "flyby", "and stayed on the flyby shot")

-- ---------------------------------------------------------------------------
section("paused: drawing alone keeps the camera alive")
plane.u = 1000
steer(150, 0, 0, 0, false)
CinematicViews.shot("orbit")
step(10)
paused_no_flightloop = true
set("sim/time/paused", 1)
local a0 = cine.st and cine.st.ang
step(60)
check(cine.active and cam ~= nil, "orbit keeps rendering while paused")
check(a0 and cine.st.ang ~= a0, "and keeps moving")
paused_no_flightloop = false
set("sim/time/paused", 0)

section("if FlyWithLua stops running the script, the camera is handed back")
CinematicViews.shot("chase")
step(10)
check(X.mock_camera_controlled() == 1, "camera controlled")
hooks_dead = true
step(60)
check(X.mock_camera_controlled() == 1, "still controlled after 1 s")
step(90)
check(X.mock_camera_controlled() == 0, "released after the script stopped ticking")
check(X.mock_handler_count() == 0, "and its zoom commands")
hooks_dead = false
step(5)
check(not cine.active, "session ended when the script came back")

section("replay: velocity from the motion")
set("sim/time/is_in_replay", 1)
steer(150, 0, 0, 0, false)
local saved = { plane.ve, plane.vu, plane.vs }
step(60, function()
  plane.ve, plane.vs = saved[1], saved[3]
  set("sim/flightmodel/position/local_vx", 0) set("sim/flightmodel/position/local_vz", 0)
end)
check(math.abs(A.gs - 150) < 10, ("ground speed from replay motion %.1f"):format(A.gs))
set("sim/time/is_in_replay", 0)

-- ---------------------------------------------------------------------------
section("letterbox and titles")
CinematicViews.shot("orbit")
step(2)
drawn.rects, drawn.strings = 0, {}
step(60)
check(drawn.rects > 0, "letterbox bars drawn while active")
check(#drawn.strings > 0 and drawn.strings[1] == "Orbit", "shot title drawn")
CinematicViews.stop()
step(120)
drawn.rects = 0
step(5)
check(drawn.rects == 0, "letterbox gone after stop")

-- ---------------------------------------------------------------------------
section("settings window")
CinematicViews.toggle_window()
check(windows == 1, "window opened")
ui.labels = {}
cinematic_views_build_window()
check(#ui.labels > 20, "window built " .. #ui.labels .. " widgets")
check(ui.depth == 0, "style colours balanced")
local cockpit_words = false
for _, l in ipairs(ui.labels) do
  if l:find("Director") or l:find("Cockpit") or l:find("Living") then cockpit_words = true end
end
check(not cockpit_words, "no Director or cockpit controls left in the window")
ui.click = "Start ("
cinematic_views_build_window()
step(3)
check(cine.active, "Start button works")
ui.click = "Stop"
cinematic_views_build_window()
step(3)
check(not cine.active, "Stop button works")
ui.click = "Wing cam"
cinematic_views_build_window()
step(3)
check(cine.active and cine.def and cine.def.id == "wing", "shot buttons work")
ui.set = { "Handheld shake", 0.8 }
cinematic_views_build_window()
check(S.shake == 0.8, "slider changes the setting")
CinematicViews.stop()
step(3)
CinematicViews.toggle_window()
check(windows == 0, "window closed")
local f = io.open(SCRIPT_DIRECTORY .. "Cinematic_Views.ini")
check(f ~= nil, "settings saved")
if f then
  local text = f:read("*a")
  f:close()
  check(text:find("shake = 0.8", 1, true) ~= nil, "saved value present")
end

-- ---------------------------------------------------------------------------
section("hold commands adjust the live shot")
plane.u = 1000
steer(150, 0, 0, 0, false)
CinematicViews.shot("chase")
step(30)
local z0 = cam.zoom
for _ = 1, 60 do commands["FlyWithLua/cinematic_views/zoom_in"].c() step(1) end
check(cam.zoom > z0 * 1.5, ("zoom_in zooms (%.2f -> %.2f)"):format(z0, cam.zoom))

-- ---------------------------------------------------------------------------
section("cameras fit a long-winged, short glider")
CinematicViews.stop()
step(3)
X.mock_set_aircraft("ASK21.acf")
set("sim/aircraft/weight/acf_m_max", 600)
set("sim/aircraft/view/acf_size_x", 8.5) set("sim/aircraft/view/acf_size_z", 4.2)
often()
check(A.size_source == "dimensions" and math.abs(A.Rs - 8.5) < 0.01, ("glider measured (span %.0f m, length %.0f m)"):format(2 * A.Rs, 2 * A.Rl))
plane.u = 800
steer(30, 0, 0, 0, false)
plane.the = 0
CinematicViews.shot("wing")
step(5)
local wx, wy, wz = cam_body()
check(math.abs(math.abs(wx) - 1.05 * 8.5) < 0.3, ("wing cam out at the wingtip (%.1f m)"):format(math.abs(wx)))
CinematicViews.shot("tail")
step(5)
wx, wy, wz = cam_body()
check(wz > 3.5 and wz < 5.5, ("tail cam just behind a short tail (%.1f m aft)"):format(wz))
CinematicViews.shot("chase")
step(60)
local _, _, d = aircraft_off_axis()
check(d > 2 * 8.5, ("chase stands off far enough to frame the span (%.0f m)"):format(d))

section("a size correction is remembered for each aircraft")
CinematicViews.toggle_window()
ui.set = { "Aircraft size", 1.5 }
cinematic_views_build_window()
check(math.abs(A.Rs - 8.5 * 1.5) < 0.01, ("glider scaled 1.5x (%.1f)"):format(A.Rs))
CinematicViews.stop()
step(3)
X.mock_set_aircraft("A320.acf")
set("sim/aircraft/weight/acf_m_max", 78000)
set("sim/aircraft/view/acf_size_x", 17.9) set("sim/aircraft/view/acf_size_z", 18.8)
often()
check(math.abs(A.Rs - 17.9) < 0.01, "another aircraft keeps its own size")
X.mock_set_aircraft("ASK21.acf")
set("sim/aircraft/weight/acf_m_max", 600)
set("sim/aircraft/view/acf_size_x", 8.5) set("sim/aircraft/view/acf_size_z", 4.2)
often()
check(math.abs(A.Rs - 8.5 * 1.5) < 0.01, "and the glider gets its correction back")
CinematicViews.toggle_window()
f = io.open(SCRIPT_DIRECTORY .. "Cinematic_Views.ini")
local ini = f and f:read("*a") or ""
if f then f:close() end
check(ini:find("size.ASK21 = 1.50", 1, true) ~= nil, "correction saved per aircraft")
X.mock_set_aircraft("A320.acf")
set("sim/aircraft/weight/acf_m_max", 78000)
set("sim/aircraft/view/acf_size_x", 17.9) set("sim/aircraft/view/acf_size_z", 18.8)
often()

-- ---------------------------------------------------------------------------
section("X-Plane's own zoom keys zoom the camera while filming")
check(X.mock_handler_count() == 0, "zoom commands left alone while not filming")
check(X.mock_press("sim/general/zoom_in", 0) == 1, "X-Plane handles its zoom when not filming")
plane.u = 1000
steer(150, 0, 0, 0, false)
CinematicViews.shot("chase")
step(10)
check(X.mock_handler_count() == 4, "zoom commands taken over while filming (" .. X.mock_handler_count() .. ")")
CinematicViews.reset_nudge()
step(2)
local zbase = cam.zoom
check(X.mock_press("sim/general/zoom_in", 0) == 0, "zoom key used by the camera, not passed on")
for _ = 1, 60 do X.mock_press("sim/general/zoom_in", 1) step(1) end
X.mock_press("sim/general/zoom_in", 2)
step(1)
check(cam.zoom > zbase * 1.8, ("holding zoom in zooms (%.2f -> %.2f)"):format(zbase, cam.zoom))
local zin = cam.zoom
X.mock_press("sim/general/zoom_out_fast", 0)
for _ = 1, 20 do X.mock_press("sim/general/zoom_out_fast", 1) step(1) end
check(cam.zoom < zin * 0.6, ("fast zoom out (%.2f -> %.2f)"):format(zin, cam.zoom))

section("the mouse wheel zooms while filming and is left alone otherwise")
CinematicViews.reset_nudge()
step(2)
zbase = cam.zoom
MOUSE_WHEEL_NUMBER, MOUSE_WHEEL_CLICKS = 0, 3
for _, fn in ipairs(hooks.wheel) do fn() end
step(1)
check(RESUME_MOUSE_WHEEL == false, "wheel used by the camera")
check(cam.zoom > zbase * 1.25, ("wheel zooms in (%.2f -> %.2f)"):format(zbase, cam.zoom))

section("zoom is remembered for each shot")
local chase_zoom = cam.zoom
CinematicViews.shot("orbit")
step(3)
check(math.abs(cam.zoom - zbase) < 0.05, "orbit has its own zoom")
CinematicViews.shot("chase")
step(3)
check(math.abs(cam.zoom - chase_zoom) < 0.05, ("back to the chase, its zoom is back (%.2f)"):format(cam.zoom))
plane.u = 400
steer(80, 180, 0, 0, false)
CinematicViews.shot("flyby")
step(2)
local fly_st = cine.st
MOUSE_WHEEL_CLICKS = 4
for _, fn in ipairs(hooks.wheel) do fn() end
local fly_zoom = cine and CinematicViews and 1.1 ^ 4
step(60 * 30, function() steer(80, 180, 0, 0, false) end)
check(cine.st ~= fly_st, "flyby set up a new pass")
local found = false
step(1, function() end)
CinematicViews.toggle_window()
ui.labels = {}
cinematic_views_build_window()
for _, l in ipairs(ui.labels) do if l:find(("zoom %.1fx"):format(fly_zoom), 1, true) then found = true end end
CinematicViews.toggle_window()
check(found, "and kept your zoom for it")

CinematicViews.stop()
step(3)
check(X.mock_handler_count() == 0, "zoom commands handed back when stopped")
MOUSE_WHEEL_CLICKS = 2
for _, fn in ipairs(hooks.wheel) do fn() end
check(RESUME_MOUSE_WHEEL == true, "wheel passed on when not filming")

-- ---------------------------------------------------------------------------
section("no errors logged")
local seen = {}
for _, l in ipairs(logs) do
  if l:find("error") and not seen[l] then seen[l] = true check(false, "log: " .. l) end
end

section("shutdown (reload or quit)")
CinematicViews.shot("orbit")
step(3)
for _, fn in ipairs(hooks.exit) do fn() end
check(X.mock_camera_controlled() == 0, "camera released on exit")
check(X.mock_handler_count() == 0, "zoom commands released on exit")

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
