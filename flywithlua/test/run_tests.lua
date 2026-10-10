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
  void mock_set_aircraft(const char *file_name);
  int mock_handler_count(void);
  int mock_press(const char *name, int phase);
  void mock_set_button(int i, int down);
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
-- FlyWithLua stand-ins (behaving like FlyWithLua NG+ 2.8)
-- ---------------------------------------------------------------------------
local logs = {}
local hooks = { frame = {}, draw = {}, often = {}, exit = {}, wheel = {}, key = {} }
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
function do_on_keystroke(code) hooks.key[#hooks.key + 1] = compile(code) end
function create_command(name, desc, b, c, e)
  commands[name] = { desc = desc, b = compile(b), c = compile(c), e = compile(e) }
end
function add_macro(name, code) macros[name] = compile(code) end
function XPLMSetGraphicsState() end
local drawing = false
function glColor4f() assert(drawing, "OpenGL call outside drawing") end
function glRectf(x1, y1, x2, y2)
  assert(drawing, "OpenGL call outside drawing")
  assert(x2 >= x1 and y2 >= y1, "bad rectangle")
  drawn.rects = drawn.rects + 1
end
function draw_string(x, y, s, col)
  assert(drawing, "draw_string outside drawing")
  drawn.strings[#drawn.strings + 1] = s
end

-- A key event the way FlyWithLua delivers it: RESUME_KEY starts false and a
-- script sets it true to keep the key from X-Plane. VKEY is a signed char.
-- Returns true if the key was kept from X-Plane.
local function key(vk, ch, action, mods)
  mods = mods or {}
  RESUME_KEY = false
  VKEY = (vk >= 128) and (vk - 256) or vk
  CKEY = ch or ""
  SHIFT_KEY, CONTROL_KEY, OPTION_KEY = mods.shift == true, mods.ctrl == true, mods.alt == true
  KEY_ACTION = action
  for _, f in ipairs(hooks.key) do f() end
  return RESUME_KEY == true
end
local function tap(vk, ch, mods)
  local a = key(vk, ch, "pressed", mods)
  local b = key(vk, ch, "released", mods)
  return a, b
end

-- The mouse wheel, the same way: true if kept from X-Plane.
local function wheel(clicks)
  RESUME_MOUSE_WHEEL = false
  MOUSE_WHEEL_NUMBER, MOUSE_WHEEL_CLICKS = 0, clicks
  for _, f in ipairs(hooks.wheel) do f() end
  return RESUME_MOUSE_WHEEL == true
end

-- imgui: records labels; "click" makes one labelled button return true once,
-- "set" makes one slider return a new value once.
local ui = { labels = {}, click = nil, set = nil }
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
  Checkbox = function(l, v)
    ui_label(l)
    if ui.set and l:find(ui.set[1], 1, true) == 1 then
      local nv = ui.set[2]
      ui.set = nil
      return true, nv
    end
    return false, v
  end,
}
local windows = 0
function float_wnd_create() windows = windows + 1 return { id = windows } end
function float_wnd_set_title() end
function float_wnd_set_imgui_builder(w, name) w.builder = name end
function float_wnd_set_onclose(w, name) w.onclose = name end
function float_wnd_destroy() windows = windows - 1 end
local function build(click)
  ui.labels, ui.click = {}, click
  cinematic_views_build_window()
  return ui.labels
end

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
  "sim/cockpit2/engine/actuators/throttle_ratio_all",
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
local function put_head(h) for i, k in ipairs(HEAD_REFS) do set("sim/graphics/view/pilots_head_" .. k, h[i]) end end
local function head()
  local h = {}
  for i, k in ipairs(HEAD_REFS) do h[i] = get("sim/graphics/view/pilots_head_" .. k) end
  return h
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
    if not hooks_dead then
      drawing = true
      for _, f in ipairs(hooks.draw) do f() end
      drawing = false
    end
    if each then each() end
  end
end

local function run_command(name) commands["FlyWithLua/cinematic_views/" .. name].b() end
local function often() for _, f in ipairs(hooks.often) do f() end end

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

-- Camera position relative to the aircraft (level, heading north: x right, y up, z aft).
local function cam_body()
  return cam.x - (plane.e - origin.e), cam.y - plane.u, cam.z - (plane.s - origin.s)
end

local function finite(v) return v == v and v > -1e12 and v < 1e12 end

-- X-Plane local axes to the aircraft's body axes (x right, y up, z aft).
local function world_to_body(wx, wy, wz, psi, the, phi)
  local p, t, r = math.rad(psi), math.rad(the), math.rad(phi)
  local x1, z1 = wx * math.cos(p) + wz * math.sin(p), -wx * math.sin(p) + wz * math.cos(p)
  local y2, z2 = wy * math.cos(t) + z1 * math.sin(t), -wy * math.sin(t) + z1 * math.cos(t)
  return x1 * math.cos(r) - y2 * math.sin(r), x1 * math.sin(r) + y2 * math.cos(r), z2
end
local function in_cockpit() return get("sim/graphics/view/view_type") == 1026 and get("sim/graphics/view/view_is_external") == 0 end

-- ---------------------------------------------------------------------------
section("loading")
publish()
if os.getenv("SEED") then
  -- Reproduce a run: the script seeds its random numbers from os.time().
  local seed, real_time = tonumber(os.getenv("SEED")), os.time
  os.time = function(...) if select("#", ...) == 0 then return seed end return real_time(...) end
end
dofile(SCRIPT)
check(type(CinematicViews) == "table", "script did not create CinematicViews")
check(#hooks.frame == 1 and #hooks.draw == 1 and #hooks.exit == 1, "frame/draw/exit hooks registered")
check(#hooks.key == 1 and #hooks.wheel == 1, "key and wheel hooks registered")
local macro_names = {}
for name in pairs(macros) do macro_names[#macro_names + 1] = name end
check(#macro_names == 1 and macros["Cinematic Views"] ~= nil, "one menu entry, Cinematic Views (" .. table.concat(macro_names, ", ") .. ")")
if macros["Cinematic Views"] then
  macros["Cinematic Views"]()
  check(windows == 1, "it opens the window")
  macros["Cinematic Views"]()
  check(windows == 0, "and closes it")
end
check(commands["FlyWithLua/cinematic_views/toggle"] ~= nil, "toggle command exists")
check(commands["FlyWithLua/cinematic_views/shot_pilot"] ~= nil, "per-shot commands exist")
for _, l in ipairs(logs) do check(not l:find("not started") and not l:find("failed") and not l:find("off"), "log: " .. l) end

local cine, A, S, BIND, getB = CinematicViews._state()
local SHOTS, ORDER = CinematicViews._shots()
local n_ext, n_int = 0, 0
for _, id in ipairs(ORDER) do if SHOTS[id].kind == "ext" then n_ext = n_ext + 1 else n_int = n_int + 1 end end
check(n_ext == 11 and n_int == 5, ("11 exterior and 5 cockpit shots (%d, %d)"):format(n_ext, n_int))

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
section("the mouse wheel and + / - are X-Plane's when not filming")
check(wheel(2) == false, "wheel passed on to X-Plane")
local a, b = tap(0xB0, "=")
check(a == false and b == false, "= passed on to X-Plane")
a = tap(0xB1, "-")
check(a == false, "- passed on to X-Plane")
check(tap(0x41, "a") == false, "other keys passed on")
check(X.mock_handler_count() == 0 and X.mock_press("sim/general/zoom_in", 0) == 1, "zoom commands left alone")

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
section("cockpit shots look around but stay within a few cm of the seat")
CinematicViews.stop()
step(6)
check(in_cockpit(), "back in the cockpit after stop")
local h0 = head()
local same = true
for i = 1, 6 do if math.abs(h0[i] - EYE[i]) > 1e-3 then same = false end end
check(same, "exterior filming left the pilot's head alone")
local SAFE_SIDE, SAFE_UP, SAFE_DOWN, SAFE_FWD, SAFE_BACK = 0.08, 0.05, 0.04, 0.08, 0.06
local phases = {
  { name = "takeoff roll", run = function(i) plane.u = 2.5 steer(math.min(10 + i * 0.05, 75), 90, 0, 0, true) end },
  { name = "turbulent climb", run = function(i) steer(120, 90, 8 + 6 * math.sin(i * 0.9), 15 * math.sin(i * 0.05), false) end },
  { name = "firm landing", run = function(i)
      if plane.u > 3 then steer(70, 90, -3.0, 0, false) else steer(70, 90, 0, 0, true) end
    end },
}
for _, id in ipairs(ORDER) do
  local def = SHOTS[id]
  if def.kind == "int" then
    for _, ph in ipairs(phases) do
      if ph.name == "turbulent climb" then plane.u = 400 elseif ph.name == "firm landing" then plane.u = 12 end
      ph.run(0)
      CinematicViews.shot(id)
      step(3)
      local worst, bad, turned = 0, 0, 0
      local i = 0
      step(60 * 6, function()
        i = i + 1
        ph.run(i)
        if cine.def ~= def then return end
        local h = head()
        for k = 1, 6 do if not finite(h[k]) then bad = bad + 1 end end
        local cx = (id == "fo") and -EYE[1] or EYE[1]
        local dx, dy, dz = h[1] - cx, h[2] - EYE[2], h[3] - EYE[3]
        if math.abs(dx) > SAFE_SIDE + 1e-4 or dy > SAFE_UP + 1e-4 or dy < -SAFE_DOWN - 1e-4
           or dz < -SAFE_FWD - 1e-4 or dz > SAFE_BACK + 1e-4 then bad = bad + 1 end
        worst = math.max(worst, math.sqrt(dx * dx + dy * dy + dz * dz))
        turned = math.max(turned, math.abs(((h[4] - EYE[4] + 180) % 360) - 180))
        if X.mock_camera_controlled() ~= 0 then bad = bad + 1 end
      end)
      local label = id .. " / " .. ph.name
      check(in_cockpit(), label .. ": in the 3D cockpit")
      check(bad == 0, label .. ": head left the safe space or camera still controlled on " .. bad .. " frames")
      check(worst < 0.12, ("%s: head moved at most %.3f m"):format(label, worst))
      if id == "panel" or id == "cpan" or id == "side" then
        check(turned > 20, ("%s: looks around (%.0f deg)"):format(label, turned))
      end
    end
  end
end

section("stopping restores the pilot's head exactly")
CinematicViews.stop()
step(6)
local h = head()
for i = 1, 6 do check(math.abs(h[i] - EYE[i]) < 1e-3, ("head[%d] restored (%.4f vs %.4f)"):format(i, h[i], EYE[i])) end
check(not cine.active, "stopped")

section("switching between exterior and cockpit shots")
plane.u = 1000
steer(150, 0, 0, 0, false)
CinematicViews.shot("chase")
step(2)
check(X.mock_camera_controlled() == 1 and get("sim/graphics/view/view_is_external") == 1, "exterior shot takes the camera")
CinematicViews.shot("pilot")
step(2)
check(X.mock_camera_controlled() == 0 and in_cockpit(), "cockpit shot hands the camera back")
check(cine.active, "still running after our own view change")
CinematicViews.shot("orbit")
step(2)
check(X.mock_camera_controlled() == 1, "and takes it again")
run_command("toggle")
step(3)
check(not cine.active and in_cockpit() and X.mock_camera_controlled() == 0, "toggle stops and returns to the cockpit")

section("you changing the view hands the camera back")
CinematicViews.shot("chase")
step(5)
X.mock_set_view(1018, 1)
step(3)
check(not cine.active and X.mock_camera_controlled() == 0, "exterior shot stops after a view change")
X.mock_set_view(1026, 0)
step(3)
CinematicViews.shot("side")
step(60)
X.mock_set_view(1018, 1)
step(3)
check(not cine.active, "cockpit shot stops when you leave the cockpit")
X.mock_set_view(1026, 0)
step(1)
h = head()
check(math.abs(h[3] - EYE[3]) < 1e-3 and math.abs(h[4] - EYE[4]) < 1e-3, "and your head is back at the eye point")
step(3)

-- ---------------------------------------------------------------------------
section("next and previous step through all the shots")
plane.u = 2.5
steer(10, 90, 0, 0, true)
CinematicViews.shot("sweep")
step(3)
CinematicViews.previous_shot()
step(3)
check(cine.def.id == "spotter", "previous from Crane sweep skips Air-to-air on the ground (" .. cine.def.id .. ")")
CinematicViews.next_shot()
step(3)
check(cine.def.id == "sweep", "next from Spotter skips Air-to-air on the ground (" .. cine.def.id .. ")")
CinematicViews.shot("gear")
step(3)
CinematicViews.next_shot()
step(3)
check(cine.def.id == "pilot", "after the last exterior shot comes the first cockpit shot (" .. cine.def.id .. ")")
CinematicViews.shot("fo")
step(3)
CinematicViews.next_shot()
step(3)
check(cine.def.id == "chase", "and after the last cockpit shot, back to the start (" .. cine.def.id .. ")")
S.cockpit_in_cycle = false
CinematicViews.shot("gear")
step(3)
CinematicViews.next_shot()
step(3)
check(cine.def.id == "chase", "cockpit shots can be left out of Next/Previous (" .. cine.def.id .. ")")
S.cockpit_in_cycle = true
CinematicViews.stop()
step(3)

-- ---------------------------------------------------------------------------
section("assign a key to camera on/off")
CinematicViews.toggle_window()
check(windows == 1, "window opened")
build("Assign##toggle")
check(cine and select(2, tap(0x78, "")) ~= nil, "pressed F9")
check(BIND.toggle and BIND.toggle.kind == "key" and BIND.toggle.vk == 0x78, "F9 assigned to camera on/off")
local consumed = tap(0x78, "")
step(3)
check(consumed and cine.active, "F9 starts the camera (and X-Plane doesn't get it)")
tap(0x78, "")
step(3)
check(not cine.active, "F9 again stops it")
key(0x78, "", "pressed")
key(0x78, "", "pressed")    -- key repeat
key(0x78, "", "pressed")
key(0x78, "", "released")
step(3)
check(cine.active, "holding F9 toggles once, not on every repeat")
tap(0x78, "")
step(3)
check(tap(0x78, "", { ctrl = true }) == false and not cine.active, "Ctrl+F9 is a different key, left to X-Plane")

section("assigning refuses + and -, and Esc cancels")
build("Assign##next")
tap(0xB0, "=")
check(BIND.next == nil and cine and true, "= not assigned")
local labels = build()
local warned = false
for _, l in ipairs(labels) do if l:find("kept for zoom", 1, true) then warned = true end end
check(warned, "says + and - are kept for zoom")
tap(0x1B, "")
check(BIND.next == nil, "Esc cancels")

section("assign joystick buttons to next and previous view")
build("Assign##next")
X.mock_set_button(57, 1)
step(2)
check(BIND.next and BIND.next.kind == "joy" and BIND.next.n == 57, "joystick button 57 assigned to next view")
X.mock_set_button(57, 0)
step(2)
check(not cine.active, "assigning did not trigger it")
build("Assign##prev")
X.mock_set_button(58, 1)
step(2)
X.mock_set_button(58, 0)
step(2)
check(BIND.prev and BIND.prev.n == 58, "button 58 assigned to previous view")
plane.u = 1000
steer(150, 0, 0, 0, false)
local last = cine.last_id
X.mock_set_button(57, 1) step(3) X.mock_set_button(57, 0) step(3)
check(cine.active and cine.def.id == last, "with the camera off, next view starts it with your last shot (" .. tostring(cine.def and cine.def.id) .. ")")
X.mock_set_button(57, 1) step(30)
local after_next = cine.def.id
check(after_next ~= last, "button 57: next view")
X.mock_set_button(57, 0) step(3)
check(cine.def.id == after_next, "holding the button steps once")
X.mock_set_button(58, 1) step(3) X.mock_set_button(58, 0) step(3)
check(cine.def.id == last, "button 58: previous view")
build("Clear##prev")
check(BIND.prev == nil, "Clear removes an assignment")
CinematicViews.toggle_window()
local f = io.open(SCRIPT_DIRECTORY .. "Cinematic_Views.ini")
local ini = f and f:read("*a") or ""
if f then f:close() end
check(ini:find("bind.toggle = key:120:0:0:0", 1, true) ~= nil and ini:find("bind.next = joy:57", 1, true) ~= nil,
      "assignments saved")

-- ---------------------------------------------------------------------------
section("+ and - zoom the exterior camera smoothly, like X-Plane's own zoom")
CinematicViews.shot("chase")
step(5)
CinematicViews.reset_nudge()
step(60)
-- The biggest change in zoom from one frame to the next (in log terms) while
-- running n frames: a smooth zoom never jumps.
local function watch_zoom(n)
  local prev, biggest = cam.zoom, 0
  step(n, function()
    biggest = math.max(biggest, math.abs(math.log(cam.zoom / prev)))
    prev = cam.zoom
  end)
  return biggest
end
local z0 = cam.zoom
check(key(0xB0, "=", "pressed") == true, "= kept from X-Plane while filming outside")
local jump = watch_zoom(60)
check(key(0xB0, "=", "released") == true, "and its release")
local z_release = cam.zoom
jump = math.max(jump, watch_zoom(60))
check(cam.zoom > z0 * 1.5, ("holding = zooms in (%.2f -> %.2f)"):format(z0, cam.zoom))
check(jump < 0.02, ("holding = zooms smoothly (largest change in a frame %.3f)"):format(jump))
check(cam.zoom > z_release, "and eases to a stop after you let go")
local z1 = cam.zoom
tap(0x6D, "-")
jump = watch_zoom(60)
check(cam.zoom < z1 and cam.zoom > z1 * 0.9, ("a tap on keypad - zooms out a little (%.2f -> %.2f)"):format(z1, cam.zoom))
check(jump < 0.01, ("a tap glides rather than jumps (%.3f)"):format(jump))
local z2 = cam.zoom
check(wheel(3) == true, "wheel kept from X-Plane while filming outside")
jump = watch_zoom(60)
check(cam.zoom > z2 * 1.2 and jump < 0.03, ("the wheel zooms in, gliding (%.2f -> %.2f, %.3f)"):format(z2, cam.zoom, jump))
local z3 = cam.zoom
check(X.mock_handler_count() == 4 and X.mock_press("sim/general/zoom_out", 0) == 0, "zoom commands (e.g. joystick) zoom the camera too")
jump = watch_zoom(45)
X.mock_press("sim/general/zoom_out", 2)
jump = math.max(jump, watch_zoom(60))
check(cam.zoom < z3 * 0.75 and jump < 0.02, ("held zoom command zooms out smoothly (%.2f -> %.2f, %.3f)"):format(z3, cam.zoom, jump))
local z4 = cam.zoom
step(60)
check(math.abs(cam.zoom - z4) < 0.01, "and stops when released")
CinematicViews.shot("orbit")
step(3)
CinematicViews.shot("chase")
jump = watch_zoom(3)
check(math.abs(cam.zoom - z4) < 0.02, "switching shots snaps to the shot's zoom instead of zooming")

section("in the cockpit, + / - and the wheel are X-Plane's own zoom")
CinematicViews.shot("pilot")
step(5)
check(tap(0xB0, "=") == false, "= passed to X-Plane in the cockpit")
check(wheel(2) == false, "wheel passed to X-Plane in the cockpit")
check(X.mock_press("sim/general/zoom_in", 0) == 1, "zoom commands passed to X-Plane in the cockpit")

section("zoom is remembered for each shot")
CinematicViews.shot("chase")
step(3)
local chase_zoom = cam.zoom
CinematicViews.shot("orbit")
step(3)
CinematicViews.shot("chase")
step(3)
check(math.abs(cam.zoom - chase_zoom) < 0.05, ("back to the chase, its zoom is back (%.2f)"):format(cam.zoom))
CinematicViews.stop()
step(3)
check(X.mock_handler_count() == 0, "zoom commands handed back when stopped")
check(tap(0xB0, "=") == false and wheel(1) == false, "+ and the wheel are X-Plane's again")

-- ---------------------------------------------------------------------------
section("cameras fit a long-winged, short glider")
X.mock_set_aircraft("ASK21.acf")
set("sim/aircraft/weight/acf_m_max", 600)
set("sim/aircraft/view/acf_size_x", 8.5) set("sim/aircraft/view/acf_size_z", 4.2)
often()
check(A.size_source == "dimensions" and math.abs(A.Rs - 8.5) < 0.01, "glider measured")
plane.u = 800
steer(30, 0, 0, 0, false)
plane.the = 0
CinematicViews.shot("wing")
step(5)
local wx, _, wz = cam_body()
check(math.abs(math.abs(wx) - 1.05 * 8.5) < 0.3, ("wing cam out at the wingtip (%.1f m)"):format(math.abs(wx)))
CinematicViews.shot("tail")
step(5)
wx, _, wz = cam_body()
check(wz > 3.5 and wz < 5.5, ("tail cam just behind a short tail (%.1f m aft)"):format(wz))

section("a size correction is remembered for each aircraft")
CinematicViews.toggle_window()
ui.set = { "Aircraft size", 1.5 }
build()
check(math.abs(A.Rs - 8.5 * 1.5) < 0.01, ("glider scaled 1.5x (%.1f)"):format(A.Rs))
CinematicViews.stop()
step(3)
X.mock_set_aircraft("A320.acf")
set("sim/aircraft/weight/acf_m_max", 78000)
set("sim/aircraft/view/acf_size_x", 17.9) set("sim/aircraft/view/acf_size_z", 18.8)
often()
check(math.abs(A.Rs - 17.9) < 0.01, "another aircraft keeps its own size")
CinematicViews.toggle_window()
f = io.open(SCRIPT_DIRECTORY .. "Cinematic_Views.ini")
ini = f and f:read("*a") or ""
if f then f:close() end
check(ini:find("size.ASK21 = 1.50", 1, true) ~= nil, "correction saved per aircraft")

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
hooks_dead = true
step(150)
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

section("nothing is ever drawn over the picture")
check(drawn.rects == 0 and #drawn.strings == 0, ("no bars or text drawn (%d, %d)"):format(drawn.rects, #drawn.strings))

-- ---------------------------------------------------------------------------
section("a small window with the basics")
CinematicViews.stop()
step(3)
CinematicViews.toggle_window()
labels = build()
local want = { "Camera OFF", "< Previous", "Next >", "Random", "Save", "Camera on/off", "Next view", "Previous view",
               "New random view", "Camera distance", "Camera shake", "Shot transition", "Cockpit head movement",
               "Aircraft size" }
for _, w in ipairs(want) do
  local found = false
  for _, l in ipairs(labels) do if l:find(w, 1, true) then found = true end end
  check(found, "window shows " .. w)
end
local gone = { "Letterbox", "EXTERIOR SHOTS", "Orbit speed", "Telephoto", "Wing cam", "Use my current head" }
for _, w in ipairs(gone) do
  local found = false
  for _, l in ipairs(labels) do if l:find(w, 1, true) then found = true end end
  check(not found, "window no longer has " .. w)
end
check(#labels < 40, "window kept small (" .. #labels .. " items)")
check(ui.depth == 0, "style colours balanced")
build("Camera OFF")
step(3)
check(cine.active, "Camera OFF button starts it")
build("Camera ON")
step(3)
check(not cine.active, "Camera ON button stops it")
ui.set = { "Camera shake", 0.8 }
build()
check(S.shake == 0.8, "sliders change settings")
CinematicViews.toggle_window()
f = io.open(SCRIPT_DIRECTORY .. "Cinematic_Views.ini")
ini = f and f:read("*a") or ""
if f then f:close() end
check(ini:find("shake = 0.8", 1, true) ~= nil, "settings saved")
check(not ini:find("letterbox", 1, true), "no letterbox setting any more")

-- ---------------------------------------------------------------------------
section("random exterior shots: endless, framed, never inside the aircraft or the ground")
local RT = CinematicViews._random()
plane.u = 1500
steer(150, 0, 0, 0, false)
local kinds = { orbit = 0, pass = 0, mount = 0 }
local frames, out, inside, under, bad, names = 0, 0, 0, 0, 0, {}
local scenes = {
  function() plane.u = 2.5 steer(40, 90, 0, 0, true) end,
  function() plane.u = 1500 steer(150, 30, 0, 20, false) end,
  function() plane.u = 200 steer(70, 270, -3.5, 0, false) end,
}
local by_kind = {}
for n = 1, 240 do
  if n % 80 == 1 then
    scenes[math.floor(n / 80) + 1]()        -- a new scene: give the cameras time to settle on it
    CinematicViews.shot("chase")
    step(240)
  end
  local r = RT.exterior()
  kinds[r.anchor] = kinds[r.anchor] + 1
  local look = r.look .. (r.anchor == "orbit" and (r.motion .. math.floor(((r.az0 % 360) + 45) / 90)) or r.anchor)
  names[look] = true
  RT.start(r)
  step(2)
  step(150, function()
    if not cam then bad = bad + 1 return end
    for _, k in ipairs({ "x", "y", "z", "pit", "hdg", "rol", "zoom" }) do if not finite(cam[k]) then bad = bad + 1 return end end
    if cine.blend < 1 then return end
    frames = frames + 1
    -- the target point is in the picture
    local tx, ty, tz = RT.look_point(r)
    if r.anchor == "pass" then tx, ty, tz = plane.e - origin.e, plane.u, plane.s - origin.s end
    local ax, ay, az = tx - cam.x, ty - cam.y, tz - cam.z
    local d = math.sqrt(ax * ax + ay * ay + az * az)
    local hh, pp = math.rad(cam.hdg), math.rad(cam.pit)
    local c = (ax * math.sin(hh) * math.cos(pp) + ay * math.sin(pp) - az * math.cos(hh) * math.cos(pp)) / d
    local half = math.deg(math.atan(math.tan(math.rad(37.5)) / cam.zoom))
    local key = r.anchor .. "/" .. r.look
    by_kind[key] = by_kind[key] or { 0, 0 }
    by_kind[key][1] = by_kind[key][1] + 1
    if math.deg(math.acos(math.max(-1, math.min(1, c)))) > half then
      out = out + 1
      by_kind[key][2] = by_kind[key][2] + 1
    end
    -- outside the box around the airframe, in the aircraft's own axes
    local lx, by, lz = world_to_body(cam.x - (plane.e - origin.e), cam.y - plane.u, cam.z - (plane.s - origin.s),
                                     plane.psi, plane.the, plane.phi)
    if math.abs(lx) < A.Rs * 0.95 and math.abs(by) < A.Rl * 0.3 and math.abs(lz) < A.Rl * 0.95 then
      inside = inside + 1
      by_kind[key][3] = (by_kind[key][3] or 0) + 1
      if os.getenv("DEBUG_INSIDE") and not r._reported then
        r._reported = true
        print(("   inside: %s  body(%.1f, %.1f, %.1f)  Rs %.1f Rl %.1f  plane y %.1f psi %.0f phi %.0f  %s"):format(
          r.anchor, lx, by, lz, A.Rs, A.Rl, plane.u, plane.psi, plane.phi, RT.serialize(r)))
      end
    end
    if cam.y < 0.3 then under = under + 1 end
  end)
end
local distinct = 0
for _ in pairs(names) do distinct = distinct + 1 end
check(kinds.orbit > 80 and kinds.pass > 20 and kinds.mount > 15,
      ("all kinds generated (orbit %d, pass %d, mount %d)"):format(kinds.orbit, kinds.pass, kinds.mount))
check(distinct > 40, distinct .. " different kinds of shot (movement, target, side) from 240 random shots")
check(bad == 0, "random shots: camera missing or non-finite on " .. bad .. " frames")
check(out <= frames * 0.03, ("random shots: target out of frame on %d/%d frames"):format(out, frames))
if os.getenv("VERBOSE") or out > frames * 0.03 or inside > 0 then
  for k, v in pairs(by_kind) do print(("   %-16s out %5d / %5d   inside %d"):format(k, v[2], v[1], v[3] or 0)) end
end
check(inside == 0, "random shots: camera inside the aircraft on " .. inside .. " frames")
check(under == 0, "random shots: camera underground on " .. under .. " frames")

section("cameras are kept out of the aircraft even when pushed in")
plane.u = 1500
steer(150, 0, 0, 0, false)
S.distance = 0.5
CinematicViews.shot("chase")
step(240)
RT.start(RT.parse("kind=ext,anchor=orbit,motion=hold,az0=90,az1=90,el0=0,el1=0,d0=1.5,d1=1.5,z0=1,z1=1,look=centre"))
step(240)
local bx = cam.x - (plane.e - origin.e)
check(math.abs(bx) >= A.Rs * 1.1, ("camera pushed out beside the wingtip (%.1f m, half span %.1f)"):format(math.abs(bx), A.Rs))
S.distance = 1

section("random cockpit shots look around inside the safe space")
CinematicViews.stop()
step(6)
plane.u = 2.5
steer(30, 90, 0, 0, true)
local worst_c, turned_c = 0, 0
for n = 1, 40 do
  local r = RT.cockpit()
  RT.start(r)
  step(2)
  step(120, function()
    local hd = head()
    local dx, dy, dz = hd[1] - EYE[1], hd[2] - EYE[2], hd[3] - EYE[3]
    if math.abs(dx) > 0.0801 or dy > 0.0501 or dy < -0.0401 or dz < -0.0801 or dz > 0.0601 then worst_c = worst_c + 1 end
    turned_c = math.max(turned_c, math.abs(((hd[4] - EYE[4] + 180) % 360) - 180))
  end)
end
check(worst_c == 0, "random cockpit shots left the safe space on " .. worst_c .. " frames")
check(turned_c > 60, ("random cockpit shots look around (%.0f deg)"):format(turned_c))
check(in_cockpit(), "in the cockpit")

section("recipes save and load exactly")
local r = RT.exterior()
local back = RT.parse(RT.serialize(r))
local same_r = true
for k, v in pairs(r) do
  if type(v) == "number" then
    if math.abs(v - back[k]) > math.max(1e-3, math.abs(v) * 1e-3) then same_r = false end
  elseif v ~= back[k] then same_r = false end
end
check(same_r, "a recipe survives the settings file")
check(RT.parse("kind=ext,anchor=orbit,d0=-50,az0=nonsense,zz=1").d0 == 1.5, "bad values are clamped")
check(RT.parse("garbage") == nil, "garbage is ignored")

section("Random, Save, and saved shots in Next / Previous")
plane.u = 1500
steer(150, 0, 0, 0, false)
CinematicViews.shot("orbit")
step(3)
CinematicViews.random_shot("ext")
step(3)
check(cine.def.id:sub(1, 3) == "rnd", "Random makes a random shot (" .. cine.def.name .. ")")
CinematicViews.next_shot()
step(3)
check(cine.def.id == "flyby", "Next from a random shot carries on the list after Orbit (" .. cine.def.id .. ")")
CinematicViews.random_shot("ext")
step(3)
local rrecipe = RT.serialize(cine.def.recipe)
CinematicViews.toggle_window()
build("Save")
step(3)
check(#RT.MY == 1, "Save keeps the random shot")
CinematicViews.toggle_window()
f = io.open(SCRIPT_DIRECTORY .. "Cinematic_Views.ini")
ini = f and f:read("*a") or ""
if f then f:close() end
check(ini:find("myshot = ", 1, true) ~= nil, "saved shot written to the settings file")
CinematicViews.shot("fo")
step(3)
CinematicViews.next_shot()
step(3)
check(cine.def.id == RT.MY[1].id and RT.serialize(cine.def.recipe) == rrecipe, "saved shot joins Next / Previous after the last listed shot")
CinematicViews.toggle_window()
build("Delete")
step(3)
CinematicViews.toggle_window()
check(#RT.MY == 0, "Delete removes it")
CinematicViews.toggle_window()
build("Assign##random")
tap(0x52, "r")
check(BIND.random and BIND.random.vk == 0x52, "a key assigned to New random view")
CinematicViews.toggle_window()
local before_id = cine.def.id
tap(0x52, "r")
step(3)
check(cine.def.id ~= before_id and cine.def.id:sub(1, 3) == "rnd", "the key makes a new random view")
CinematicViews.stop()
step(3)

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
