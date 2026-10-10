-- Runs Cinematic_Views.lua against mock_xplm.c and simulated flights, checking
-- what the camera and the pilot's head do. Start it with run_tests.sh.

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
local hooks = { frame = {}, draw = {}, often = {}, exit = {} }
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

-- imgui: records labels; "click" makes one labelled button return true once.
local ui = { labels = {}, click = nil, tree_open = true }
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
  "sim/cockpit2/engine/actuators/throttle_ratio_all", "sim/graphics/view/view_type",
  "sim/graphics/view/view_is_external", "sim/graphics/view/field_of_view_deg",
  "sim/graphics/view/pilots_head_x", "sim/graphics/view/pilots_head_y", "sim/graphics/view/pilots_head_z",
  "sim/graphics/view/pilots_head_psi", "sim/graphics/view/pilots_head_the", "sim/graphics/view/pilots_head_phi",
  "sim/time/total_running_time_sec", "sim/operation/misc/frame_rate_period", "sim/time/paused",
  "sim/time/is_in_replay", "sim/graphics/VR/enabled",
}
for _, r in ipairs(REFS) do X.mock_define(r, 0) end
X.mock_define_command("sim/view/3d_cockpit_cmnd_look")
X.mock_define_command("sim/view/chase")
X.mock_define_command("sim/view/circle")

local function set(name, v) X.mock_define(name, v) end
local function get(name) return X.mock_get(name) end

-- A320-ish, captain's seat.
local EYE = { -0.55, 1.6, -16.5, 0, -5, 0 }
set("sim/aircraft/weight/acf_m_max", 78000)
set("sim/graphics/view/field_of_view_deg", 75)
set("sim/operation/misc/frame_rate_period", 1 / 60)
local function put_head(h)
  set("sim/graphics/view/pilots_head_x", h[1]) set("sim/graphics/view/pilots_head_y", h[2])
  set("sim/graphics/view/pilots_head_z", h[3]) set("sim/graphics/view/pilots_head_psi", h[4])
  set("sim/graphics/view/pilots_head_the", h[5]) set("sim/graphics/view/pilots_head_phi", h[6])
end
local function head()
  return { get("sim/graphics/view/pilots_head_x"), get("sim/graphics/view/pilots_head_y"),
           get("sim/graphics/view/pilots_head_z"), get("sim/graphics/view/pilots_head_psi"),
           get("sim/graphics/view/pilots_head_the"), get("sim/graphics/view/pilots_head_phi") }
end
put_head(EYE)
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

-- Where is the aircraft in the camera picture? Returns the angle (deg) between
-- the view direction and the aircraft, and the half-width of the view.
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

-- ---------------------------------------------------------------------------
section("loading")
publish()
dofile(SCRIPT)
check(type(CinematicViews) == "table", "script did not create CinematicViews")
check(#hooks.frame == 1 and #hooks.draw == 1 and #hooks.exit == 1, "frame/draw/exit hooks registered")
check(commands["FlyWithLua/cinematic_views/director"] ~= nil, "director command exists")
check(commands["FlyWithLua/cinematic_views/shot_spotter"] ~= nil, "per-shot commands exist")
for _, l in ipairs(logs) do check(not l:find("not started") and not l:find("failed"), "log: " .. l) end

local cine, A, S, PH = CinematicViews._state()
local SHOTS, ORDER = CinematicViews._shots()
check(#ORDER == 17, "17 shots, got " .. #ORDER)

-- ---------------------------------------------------------------------------
section("estimated size")
step(5)
check(A.R > 17 and A.R < 24, ("A320 size estimate %.1f m"):format(A.R))

-- ---------------------------------------------------------------------------
section("every exterior shot frames the aircraft (taxi, takeoff roll, cruise, approach)")
local cases = {
  { name = "taxi", setup = function() plane.u = 2.5 steer(8, 90, 0, 0, true) end },
  { name = "runway", setup = function() plane.u = 2.5 steer(60, 90, 0, 0, true) end },
  { name = "cruise turn", setup = function() plane.u = 3000 steer(230, 45, 0, 25, false) end, turn = 2 },
  { name = "approach", setup = function() plane.u = 300 steer(70, 270, -3.5, 0, false) end },
}
for _, case in ipairs(cases) do
  for _, id in ipairs(ORDER) do
    local def = SHOTS[id]
    if def.kind == "ext" then
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
section("cockpit shots move the head around the pilot's eye point")
S.living = false   -- so the head can be compared exactly
plane.u = 2.5
steer(10, 90, 0, 0, true)
CinematicViews.stop()
step(5)
check(get("sim/graphics/view/view_type") == 1026, "back in the cockpit after stop")
for _, id in ipairs(ORDER) do
  local def = SHOTS[id]
  if def.kind == "int" then
    S.use_cabin = true
    CinematicViews.shot(id)
    local maxd, bad = 0, 0
    step(3)
    step(60 * 6, function()
      if cine.def ~= def then return end
      local h = head()
      for i = 1, 6 do if not finite(h[i]) then bad = bad + 1 end end
      local d = math.sqrt((h[1] - EYE[1]) ^ 2 + (h[2] - EYE[2]) ^ 2 + (h[3] - EYE[3]) ^ 2)
      maxd = math.max(maxd, d)
      if X.mock_camera_controlled() ~= 0 then bad = bad + 1 end
    end)
    check(get("sim/graphics/view/view_type") == 1026, id .. ": in the 3D cockpit")
    check(bad == 0, id .. ": non-finite head or camera still controlled")
    if id == "cabin" then
      check(maxd > 10 and maxd < 25, ("cabin: head %.1f m back from the cockpit"):format(maxd))
    else
      check(maxd < 1.5, ("%s: head moved %.2f m from the eye point"):format(id, maxd))
    end
  end
end
S.use_cabin = false

section("stopping restores the pilot's head exactly")
CinematicViews.stop()
step(6)
local h = head()
for i = 1, 6 do check(math.abs(h[i] - EYE[i]) < 1e-3, ("head[%d] restored (%.4f vs %.4f)"):format(i, h[i], EYE[i])) end
check(not cine.active, "session stopped")

-- ---------------------------------------------------------------------------
section("switching between exterior and cockpit shots")
CinematicViews.shot("chase")
step(2)
check(X.mock_camera_controlled() == 1 and get("sim/graphics/view/view_is_external") == 1, "exterior shot takes the camera")
CinematicViews.shot("pilot")
step(2)
check(X.mock_camera_controlled() == 0 and get("sim/graphics/view/view_type") == 1026, "cockpit shot hands the camera back")
check(cine.active, "still running after our own view change")
CinematicViews.shot("orbit")
step(2)
check(X.mock_camera_controlled() == 1, "and takes it again")

section("you changing the view hands the camera back")
X.mock_set_view(1018, 1)      -- e.g. pressing a view key
step(3)
check(not cine.active, "session stopped after a user view change")
check(X.mock_camera_controlled() == 0, "camera not controlled")
X.mock_set_view(1026, 0)
step(3)
CinematicViews.shot("shoulder")
step(60)
X.mock_set_view(1018, 1)      -- you pick an exterior view mid-shot
step(3)
check(not cine.active, "cockpit shot stops when you leave the 3D cockpit")
X.mock_set_view(1026, 0)      -- and later come back
step(1)
local hb = head()
check(math.abs(hb[3] - EYE[3]) < 1e-3 and math.abs(hb[4] - EYE[4]) < 1e-3, "your head is back at the pilot's eye point")
step(5)

-- ---------------------------------------------------------------------------
section("blends glide between related shots without passing through the aircraft")
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
check(min_d > 0.9 * A.R, ("blend stayed %.1f m clear (R %.1f)"):format(min_d, A.R))

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

-- ---------------------------------------------------------------------------
section("the Director tells a story over a whole flight")
CinematicViews.stop()
step(5)
plane.e, plane.s, plane.u = 0, 0, 2.5
steer(0, 90, 0, 0, true)
S.shot_length, S.blend_time = 8, 1.5
run_command("director")
local used, kinds, repeats, last, last_st = {}, { ext = 0, int = 0 }, 0, nil, nil
local wrong = {}
local function watch()
  local d = cine.def
  if d and cine.st ~= last_st then
    last_st = cine.st
    if last == d.id then repeats = repeats + 1 end
    used[d.id] = (used[d.id] or 0) + 1
    kinds[d.kind] = kinds[d.kind] + 1
    if d.id == "a2a" and plane.ground then wrong[#wrong + 1] = "a2a on the ground" if os.getenv("VERBOSE") then print(("   a2a start t=%.1f u=%.1f A.on_ground=%s A.agl=%.1f phase=%s director=%s"):format(sim_t, plane.u, tostring(A.on_ground), A.agl, PH.cur, tostring(cine.director))) end end
    if d.id == "gear" and not plane.ground and plane.u > 400 then wrong[#wrong + 1] = "gear cam at altitude" end
    last = d.id
  end
end
-- taxi, line up, takeoff roll, climb, cruise with turns, descent, landing, rollout
local speed = 8
step(60 * 30, function() steer(speed, 90, 0, 0, true) watch() end)
step(60 * 30, function() speed = math.min(speed + 2.2 * DT, 75) steer(speed, 90, 0, 0, true) watch() end)
step(60 * 60, function() speed = math.min(speed + 1 * DT, 130) steer(speed, 90, 9, 0, false) watch() end)
step(60 * 120, function() steer(230, plane.psi + 1.5 * DT, plane.u < 8000 and 10 or 0, plane.u < 8000 and 0 or 20, false) watch() end)
step(60 * 90, function() steer(90, plane.psi, plane.u > 330 and -15 or -3.5, 0, false) watch() end)
step(60 * 80, function() steer(70, plane.psi, plane.u > 3 and -3.5 or 0, 0, plane.u <= 3) watch() end)
step(60 * 30, function() speed = 70 - (sim_t % 30) * 2 steer(math.max(speed, 8), plane.psi, 0, 0, true) watch() end)
local distinct = 0
for _ in pairs(used) do distinct = distinct + 1 end
check(distinct >= 10, "Director used " .. distinct .. " different shots")
check(kinds.ext > 5 and kinds.int > 2, ("Director mixes exterior (%d) and cockpit (%d) shots"):format(kinds.ext, kinds.int))
check(repeats == 0, "no shot repeated back to back")
check(#wrong == 0, "phase-appropriate shots: " .. table.concat(wrong, ", "))
if os.getenv("VERBOSE") then
  for id, n in pairs(used) do print(("   %-9s %d"):format(id, n)) end
end
local seen = {}
for _, l in ipairs(logs) do if l:find("error") and not seen[l] then seen[l] = true check(false, "log: " .. l) end end
run_command("director")
step(5)
check(not cine.active and X.mock_camera_controlled() == 0, "Director off hands everything back")

-- ---------------------------------------------------------------------------
section("living cockpit: accelerating pushes the head back, then it settles")
CinematicViews.stop()
step(10)
S.living = true
plane.u = 2.5
speed = 0
local max_back = 0
step(60 * 4, function()
  speed = speed + 3 * DT
  steer(speed, 90, 0, 0, true)
  max_back = math.max(max_back, get("sim/graphics/view/pilots_head_z") - EYE[3])
end)
check(max_back > 0.005 and max_back < 0.08, ("head pushed back %.3f m on the takeoff roll"):format(max_back))
step(60 * 3, function() steer(speed, 90, 0, 0, true) end)
plane.u = 1000
steer(0.1, 90, 0, 0, false)
step(60 * 4, function() steer(0.1, 90, 0, 0, false) end)
local hz = head()
check(math.abs(hz[3] - EYE[3]) < 0.01, ("head settles back (%.4f)"):format(hz[3] - EYE[3]))

section("living cockpit keeps your own head movement")
local looked = { EYE[1], EYE[2], EYE[3], 40, -10, 0 }
put_head(looked)   -- you look left with the mouse
step(30, function() steer(0.1, 90, 0, 0, false) end)
local hl = head()
check(math.abs(hl[4] - 40) < 2 and math.abs(hl[5] + 10) < 2, ("your look is kept (%.1f, %.1f)"):format(hl[4], hl[5]))

section("living cockpit never piles up while you drag the view")
put_head(EYE)
steer(150, 0, 0, 30, false)
step(60 * 3, function() steer(150, plane.psi + 4 * DT, 0, 30, false) end)   -- turning: big look-into-turn offset
local start = head()[4]
for _ = 1, 120 do
  set("sim/graphics/view/pilots_head_psi", get("sim/graphics/view/pilots_head_psi") + 0.5)   -- mouse look, step by step
  step(1, function() steer(150, plane.psi + 4 * DT, 0, 30, false) end)
end
local moved = head()[4] - start
check(math.abs(moved - 60) < 12, ("dragging 60 deg moved the view %.1f deg"):format(moved))
put_head(looked)
steer(0.1, 90, 0, 0, false)
step(60 * 4, function() steer(0.1, 90, 0, 0, false) end)

S.living = false
step(3)
local hoff = head()
check(math.abs(hoff[4] - 40) < 1e-3 and math.abs(hoff[3] - EYE[3]) < 1e-3, "switching it off removes only its own offset")
put_head(EYE)

-- ---------------------------------------------------------------------------
section("paused: drawing alone keeps the camera alive")
S.living = true
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
hooks_dead = false
step(5)
check(not cine.active, "session ended when the script came back")

section("replay: velocity from the motion")
set("sim/time/is_in_replay", 1)
steer(150, 0, 0, 0, false)
local vx, vy, vz = plane.ve, plane.vu, plane.vs
plane.ve, plane.vu, plane.vs = 0, 0, 0
publish()
local saved = { vx, vy, vz }
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
ui.click = "Start Director"
cinematic_views_build_window()
step(3)
check(cine.active and cine.director, "Start Director button works")
ui.click = "Stop"
cinematic_views_build_window()
step(3)
check(not cine.active, "Stop button works")
ui.click = "Wing cam"
cinematic_views_build_window()
step(3)
check(cine.active and cine.def and cine.def.id == "wing", "shot buttons work")
CinematicViews.stop()
step(3)
ui.set = { "Handheld shake", 0.8 }
cinematic_views_build_window()
check(S.shake == 0.8, "slider changes the setting")
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
section("shutdown (reload or quit)")
CinematicViews.shot("pilot")
step(3)
CinematicViews.shot("chase")
step(3)
for _, fn in ipairs(hooks.exit) do fn() end
check(X.mock_camera_controlled() == 0, "camera released on exit")

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
