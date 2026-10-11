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
  "sim/aircraft/engine/acf_num_engines", "sim/flightmodel2/gear/deploy_ratio",
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
set("sim/aircraft/engine/acf_num_engines", 2)
set("sim/flightmodel2/gear/deploy_ratio", 1)
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
local GROUND_H = 4.0     -- height of the aircraft's centre above the ground when on it
local plane = { e = 0, u = GROUND_H, s = 0, psi = 90, the = 0, phi = 0, ve = 0, vu = 0, vs = 0, ground = true, ias = 0 }
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
  set("sim/flightmodel/position/y_agl", plane.u - GROUND_H)
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
      if plane.ground then plane.u = GROUND_H end
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
check(commands["FlyWithLua/cinematic_views/shot_close_engine"] ~= nil and commands["FlyWithLua/cinematic_views/shot_overhead"] ~= nil,
      "per-shot commands exist")
for _, l in ipairs(logs) do check(not l:find("not started") and not l:find("failed") and not l:find("off"), "log: " .. l) end

local cine, A, S, BIND, getB = CinematicViews._state()
local SHOTS, ORDER = CinematicViews._shots()
local RT = CinematicViews._geometry()
local n_wide, n_close, n_int = 0, 0, 0
for _, id in ipairs(ORDER) do
  if id:sub(1, 5) == "wide_" then n_wide = n_wide + 1
  elseif id:sub(1, 6) == "close_" then n_close = n_close + 1
  elseif SHOTS[id].kind == "int" then n_int = n_int + 1 end
end
check(n_wide == 5 and n_close == 8 and n_int == 6, ("5 wide, 8 close-up and 6 cockpit shots (%d, %d, %d)"):format(n_wide, n_close, n_int))
check(#ORDER == n_wide + n_close + n_int, "and nothing else")

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

section("the mouse wheel and + / - are X-Plane's when not filming")
check(wheel(2) == false, "wheel passed on to X-Plane")
local a, b = tap(0xB0, "=")
check(a == false and b == false, "= passed on to X-Plane")
check(tap(0xB1, "-") == false, "- passed on to X-Plane")
check(tap(0x41, "a") == false, "other keys passed on")
check(X.mock_handler_count() == 0 and X.mock_press("sim/general/zoom_in", 0) == 1, "zoom commands left alone")

-- ---------------------------------------------------------------------------
section("it films where you are: cockpit views in the cockpit, exterior views outside")
check(in_cockpit(), "starting in the cockpit")
run_command("toggle")
step(3)
check(cine.active and cine.def and cine.def.id == "scan", "Camera on in the cockpit starts a cockpit shot (" .. tostring(cine.def and cine.def.id) .. ")")
for _ = 1, 8 do
  CinematicViews.next_shot()
  step(3)
  check(cine.def.kind == "int" and in_cockpit(), "Next stays in the cockpit (" .. cine.def.id .. ")")
end
for _ = 1, 8 do
  CinematicViews.previous_shot()
  step(3)
  check(cine.def.kind == "int" and in_cockpit(), "Previous stays in the cockpit (" .. cine.def.id .. ")")
end
run_command("toggle")
step(3)
check(not cine.active and in_cockpit(), "Camera off")
X.mock_set_view(1017, 1)
step(3)
run_command("toggle")
step(3)
check(cine.active and cine.def and cine.def.id == "wide_rear" and X.mock_camera_controlled() == 1,
      "Camera on outside starts an exterior shot (" .. tostring(cine.def and cine.def.id) .. ")")
CinematicViews.previous_shot()
step(3)
check(cine.active and cine.def.id == "close_nosegear" and X.mock_camera_controlled() == 1,
      "Previous from the first exterior shot goes to the last one (" .. cine.def.id .. ")")
for _ = 1, 15 do
  CinematicViews.previous_shot()
  step(3)
  check(cine.active and cine.def.kind == "ext" and X.mock_camera_controlled() == 1, "Previous stays outside (" .. cine.def.id .. ")")
end
for _ = 1, 15 do
  CinematicViews.next_shot()
  step(3)
  check(cine.active and cine.def.kind == "ext" and X.mock_camera_controlled() == 1, "Next stays outside (" .. cine.def.id .. ")")
end
run_command("toggle")
step(3)
check(not cine.active and X.mock_camera_controlled() == 0 and get("sim/graphics/view/view_is_external") == 1,
      "Camera off leaves you outside")
X.mock_set_view(1026, 0)
step(3)
run_command("toggle")
step(3)
check(cine.active and cine.def.id == "scan", "back in the cockpit, Camera on picks up the cockpit shots again")
run_command("toggle")
step(3)

-- X-Plane 12 may give the cockpit a different view number: any view that
-- isn't an exterior one is the cockpit.
X.mock_set_view(1000, 0)
step(3)
CinematicViews.next_shot()
step(60)
local hd = head()
check(cine.active and cine.def.kind == "int" and (math.abs(hd[4] - EYE[4]) > 0.01 or math.abs(hd[5] - EYE[5]) > 0.01),
      "cockpit shots work whatever number the cockpit view has")
CinematicViews.previous_shot()
step(200)
check(cine.active and cine.def.kind == "int", "and Previous works there too")
CinematicViews.stop()
step(6)
X.mock_set_view(1026, 0)
step(3)
for _, l in ipairs(logs) do check(not l:find("could not"), "log: " .. l) end

-- ---------------------------------------------------------------------------
-- Measure the running exterior shot over n frames: is its subject in the
-- picture (and, for a wide shot, the whole aircraft), is the camera outside
-- the aircraft and above the ground, and does it keep moving?
local function measure_exterior(n, each)
  local m = { frames = 0, out = 0, too_big = 0, inside = 0, under = 0, bad = 0, still = 0, zoom_min = 99, worst = 0, fill = 9 }
  local hist = {}
  step(n, function()
    if each then each() end
    if not cam then m.bad = m.bad + 1 return end
    for _, k in ipairs({ "x", "y", "z", "pit", "hdg", "rol", "zoom" }) do
      if not finite(cam[k]) then m.bad = m.bad + 1 return end
    end
    if cine.blend < 1 or not cine.st or not cine.st.r then return end
    m.frames = m.frames + 1
    local r = cine.st.r
    local tx, ty, tz, _, _, _, size = RT.subject(r)
    local ax, ay, az = tx - cam.x, ty - cam.y, tz - cam.z
    local d = math.sqrt(ax * ax + ay * ay + az * az)
    local hh, pp = math.rad(cam.hdg), math.rad(cam.pit)
    local c = (ax * math.sin(hh) * math.cos(pp) + ay * math.sin(pp) - az * math.cos(hh) * math.cos(pp)) / d
    local off = math.deg(math.acos(math.max(-1, math.min(1, c))))
    local half = math.deg(math.atan(math.tan(math.rad(37.5)) / cam.zoom))
    m.worst = math.max(m.worst, off / half)
    if off > half then m.out = m.out + 1 end
    if r.family == "wide" and off + math.deg(math.atan2(A.R * 0.9, d)) > half * 1.05 then m.too_big = m.too_big + 1 end
    m.zoom_min = math.min(m.zoom_min, cam.zoom)
    m.fill = math.min(m.fill, math.deg(math.atan2(size, d)) / half)   -- how much of the frame the subject fills
    local lx, ly, lz = world_to_body(cam.x - (plane.e - origin.e), cam.y - plane.u, cam.z - (plane.s - origin.s),
                                     plane.psi, plane.the, plane.phi)
    local ex, ey, ez = RT.box()
    if math.abs(lx) < ex * 0.97 and math.abs(ly) < ey * 0.97 and math.abs(lz) < ez * 0.97 then m.inside = m.inside + 1 end
    if cam.y < 0.3 then m.under = m.under + 1 end
    hist[#hist + 1] = { lx, ly, lz }
    if #hist > 60 then
      local p = hist[#hist - 60]
      local moved = math.sqrt((lx - p[1]) ^ 2 + (ly - p[2]) ^ 2 + (lz - p[3]) ^ 2)
      if moved < 0.002 * d then
        m.still = m.still + 1
        if os.getenv("DEBUG_STILL") and m.still == 1 then
          local r = cine.st.r
          print(("   still: t %.1f moved %.3f d %.1f  body now (%.1f %.1f %.1f) then (%.1f %.1f %.1f)  az %.1f amp %.1f el %.1f amp %.1f per %.0f dir %d side %d ph %.2f damp %.3f  st.h %.1f psi %.1f trk %.1f"):format(
            cine.st.t, moved, d, lx, ly, lz, p[1], p[2], p[3], r.az, r.az_amp, r.el, r.el_amp, r.per, r.dir, r.side, r.ph1, r.d_amp, cine.st.h, plane.psi, A.trk))
        end
      end
    end
  end)
  return m
end

local function report(label, m, close)
  if os.getenv("VERBOSE") then
    print(("   %-34s frames %4d  out %3d  too big %3d  inside %3d  still %3d  zoom>=%.1f  worst %.2f"):format(
      label, m.frames, m.out, m.too_big, m.inside, m.still, m.zoom_min, m.worst))
  end
  check(m.bad == 0, label .. ": camera missing or non-finite on " .. m.bad .. " frames")
  check(m.frames > 100, label .. ": only " .. m.frames .. " frames")
  check(m.out <= m.frames * 0.02, ("%s: subject out of frame on %d/%d frames"):format(label, m.out, m.frames))
  check(m.too_big <= m.frames * 0.02, ("%s: whole aircraft not in frame on %d/%d frames"):format(label, m.too_big, m.frames))
  check(m.inside == 0, label .. ": camera inside the aircraft on " .. m.inside .. " frames")
  check(m.under == 0, label .. ": camera underground on " .. m.under .. " frames")
  check(m.still == 0, label .. ": camera stood still on " .. m.still .. " frames")
end

section("every exterior shot frames its subject, keeps moving, and stays outside the aircraft")
local scenes = {
  { name = "taxi", setup = function() plane.u = GROUND_H steer(8, 90, 0, 0, true) end },
  { name = "takeoff roll", setup = function() plane.u = GROUND_H steer(60, 90, 0, 0, true) end },
  -- the turn carries on from shot to shot (no snapping the heading back)
  { name = "cruise turn", setup = function() plane.u = 3000 steer(230, plane.psi, 0, 25, false) end, turn = 2 },
  { name = "approach", setup = function() plane.u = 300 steer(70, 270, -3.5, 0, false) end },
}
local close_fill = 9
for _, sc in ipairs(scenes) do
  sc.setup()
  CinematicViews.shot("wide_rear")
  step(240, function()                      -- let the cameras settle on the new heading (and turn)
    if sc.turn then steer(230, plane.psi + sc.turn * DT, 0, 25, false) end
  end)
  for _, id in ipairs(ORDER) do
    local def = SHOTS[id]
    if def.kind == "ext" then
      sc.setup()
      CinematicViews.shot(id)
      step(3)
      local m = measure_exterior(60 * 8, function()
        if sc.turn then steer(math.sqrt(plane.ve ^ 2 + plane.vs ^ 2), plane.psi + sc.turn * DT, 0, 25, false) end
      end)
      report(sc.name .. " / " .. id, m)
      if id:sub(1, 6) == "close_" then close_fill = math.min(close_fill, m.fill) end
    end
  end
end
check(close_fill > 0.35, ("close-ups are close: the part always fills at least %.0f%% of the frame"):format(100 * close_fill))

-- ---------------------------------------------------------------------------
-- Run the current cockpit shot and measure the head.
local function measure_cockpit(n, each)
  local m = { frames = 0, outside_space = 0, bad = 0, jump = 0, fast = 0, still = 0, pitches = {}, headings = {} }
  local prev, hist = nil, {}
  step(n, function()
    if each then each() end
    local h = head()
    for k = 1, 6 do if not finite(h[k]) then m.bad = m.bad + 1 return end end
    if cine.int_from then return end
    m.frames = m.frames + 1
    local dx, dy, dz = h[1] - EYE[1], h[2] - EYE[2], h[3] - EYE[3]
    if math.abs(dx) > 0.0801 or dy > 0.0501 or dy < -0.0401 or dz < -0.0801 or dz > 0.0601 then
      m.outside_space = m.outside_space + 1
    end
    local hd = ((h[4] - EYE[4] + 180) % 360) - 180
    local pt = h[5] - EYE[5]
    m.pitches[#m.pitches + 1], m.headings[#m.headings + 1] = pt, hd
    if prev then
      local turn = math.max(math.abs(hd - prev[1]), math.abs(pt - prev[2]))
      if turn > 4 then m.jump = m.jump + 1 end                   -- more than 4 degrees in one frame
      if turn / DT > 200 then m.fast = m.fast + 1 end            -- faster than a head turns
    end
    hist[#hist + 1] = prev and (math.abs(hd - prev[1]) + math.abs(pt - prev[2])) or 0
    if #hist > 180 then
      local path = 0
      for k = #hist - 179, #hist do path = path + hist[k] end
      if path < 0.5 then m.still = m.still + 1 end            -- under half a degree of movement in 3 s
    end
    prev = { hd, pt }
    if X.mock_camera_controlled() ~= 0 then m.bad = m.bad + 1 end
  end)
  return m
end

local function share(list, test)
  local n = 0
  for _, v in ipairs(list) do if test(v) then n = n + 1 end end
  return n / math.max(#list, 1)
end

section("cockpit shots: realistic head movement, inside the safe space, through rough moments")
CinematicViews.stop()
step(6)
check(in_cockpit(), "back in the cockpit after stop")
local h0 = head()
local same = true
for i = 1, 6 do if math.abs(h0[i] - EYE[i]) > 1e-3 then same = false end end
check(same, "exterior filming left the pilot's head alone")
local rough = {
  { name = "takeoff roll", run = function(i) plane.u = GROUND_H steer(math.min(10 + i * 0.05, 75), 90, 0, 0, true) end },
  { name = "turbulent climb", run = function(i) steer(120, 90, 8 + 6 * math.sin(i * 0.9), 15 * math.sin(i * 0.05), false) end },
  { name = "firm landing", run = function(i)
      if plane.u > GROUND_H + 0.5 then steer(70, 90, -3.0, 0, false) else steer(70, 90, 0, 0, true) end
    end },
}
for _, id in ipairs(ORDER) do
  if SHOTS[id].kind == "int" then
    for _, ph in ipairs(rough) do
      if ph.name == "turbulent climb" then plane.u = 400 elseif ph.name == "firm landing" then plane.u = GROUND_H + 10 end
      ph.run(0)
      CinematicViews.shot(id)
      step(3)
      local i = 0
      local m = measure_cockpit(60 * 8, function() i = i + 1 ph.run(i) end)
      local label = id .. " / " .. ph.name
      check(in_cockpit(), label .. ": in the 3D cockpit")
      check(m.bad == 0, label .. ": non-finite head or camera controlled on " .. m.bad .. " frames")
      check(m.outside_space == 0, label .. ": head left the safe space on " .. m.outside_space .. " frames")
      check(m.jump == 0 and m.fast == 0, ("%s: head jumped (%d) or turned too fast (%d)"):format(label, m.jump, m.fast))
      check(m.still == 0, label .. ": head froze on " .. m.still .. " frames")
    end
  end
end

section("cockpit shots focus where they should")
plane.u = 3000
steer(200, 90, 0, 0, false)
local focus = {
  { "panel", "the instrument panel", function(hd, pt) return pt < -10 and pt > -32 end, 0.6 },
  { "overhead", "the overhead panel", function(hd, pt) return pt > 25 end, 0.5 },
  { "throttle", "the throttle and pedestal", function(hd, pt) return pt < -26 end, 0.55 },
  { "window", "out of the side window", function(hd, pt) return hd < -50 end, 0.5 },     -- the captain's window is on the left
  { "autopilot", "the glareshield and FMC", function(hd, pt) return pt < -2 and pt > -44 end, 0.6 },
  { "scan", "outside and the instruments", function(hd, pt) return pt > -30 and pt < 12 end, 0.85 },
}
for _, f in ipairs(focus) do
  CinematicViews.shot(f[1])
  step(3)
  local m = measure_cockpit(60 * 120)
  local pts, hds = m.pitches, m.headings
  local n, hit = #pts, 0
  for k = 1, n do if f[3](hds[k], pts[k]) then hit = hit + 1 end end
  if os.getenv("VERBOSE") then print(("   %s %.1f%%"):format(f[1], 100 * hit / math.max(n, 1))) end
  check(hit / math.max(n, 1) >= f[4], ("%s looks at %s %.0f%% of the time"):format(f[1], f[2], 100 * hit / math.max(n, 1)))
end
check(share({ 1 }, function() return true end) == 1, "share helper")

section("stopping restores the pilot's head exactly")
CinematicViews.stop()
step(6)
local h = head()
for i = 1, 6 do check(math.abs(h[i] - EYE[i]) < 1e-3, ("head[%d] restored (%.4f vs %.4f)"):format(i, h[i], EYE[i])) end
check(not cine.active, "stopped")

section("switching between exterior and cockpit shots")
plane.u = 1000
steer(150, 0, 0, 0, false)
CinematicViews.shot("wide_rear")
step(2)
check(X.mock_camera_controlled() == 1 and get("sim/graphics/view/view_is_external") == 1, "exterior shot takes the camera")
CinematicViews.shot("scan")
step(2)
check(X.mock_camera_controlled() == 0 and in_cockpit(), "cockpit shot hands the camera back")
check(cine.active, "still running after our own view change")
CinematicViews.shot("close_tail")
step(2)
check(X.mock_camera_controlled() == 1, "and takes it again")
run_command("toggle")
step(3)
check(not cine.active and in_cockpit() and X.mock_camera_controlled() == 0, "toggle stops and returns to the cockpit")

section("you changing the view hands the camera back")
CinematicViews.shot("wide_side")
step(5)
X.mock_set_view(1018, 1)
step(3)
check(not cine.active and X.mock_camera_controlled() == 0, "exterior shot stops after a view change")
X.mock_set_view(1026, 0)
step(3)
CinematicViews.shot("window")
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
section("next and previous step through the shots, skipping parts that aren't there")
plane.u = 3000
steer(200, 90, 0, 0, false)
set("sim/flightmodel2/gear/deploy_ratio", 0)       -- gear up
CinematicViews.shot("close_tail")
step(3)
CinematicViews.next_shot()
step(3)
check(cine.def.id == "wide_rear", "with the gear up, Next from the tail skips the gear close-ups (" .. cine.def.id .. ")")
CinematicViews.previous_shot()
step(3)
check(cine.def.id == "close_tail", "and Previous comes back (" .. cine.def.id .. ")")
set("sim/flightmodel2/gear/deploy_ratio", 1)
CinematicViews.next_shot()
step(3)
check(cine.def.id == "close_gear", "gear down: the main gear close-up is there (" .. cine.def.id .. ")")
CinematicViews.shot("autopilot")
step(3)
CinematicViews.next_shot()
step(3)
check(cine.def.id == "scan", "after the last cockpit shot, back to the first (" .. cine.def.id .. ")")
CinematicViews.previous_shot()
step(3)
check(cine.def.id == "autopilot", "and Previous goes back round (" .. cine.def.id .. ")")
CinematicViews.stop()
step(3)

-- ---------------------------------------------------------------------------
section("assign a key to camera on/off")
CinematicViews.toggle_window()
check(windows == 1, "window opened")
build("Assign##toggle")
tap(0x78, "")
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
check(BIND.next == nil, "= not assigned")
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
local last = cine.last[in_cockpit() and "int" or "ext"]
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
CinematicViews.shot("wide_rear")
step(5)
CinematicViews.reset_nudge()
step(120)
-- The biggest change in our zoom from one frame to the next (the shot's own
-- framing zoom changes slowly too, so it is taken out).
local function user_zoom() return cam.zoom / cine.st.zoom end
local function watch_zoom(n)
  local prev, biggest = user_zoom(), 0
  step(n, function()
    local z = user_zoom()
    biggest = math.max(biggest, math.abs(math.log(z / prev)))
    prev = z
  end)
  return biggest
end
local z0 = user_zoom()
check(key(0xB0, "=", "pressed") == true, "= kept from X-Plane while filming outside")
local jump = watch_zoom(60)
check(key(0xB0, "=", "released") == true, "and its release")
local z_release = user_zoom()
jump = math.max(jump, watch_zoom(60))
check(user_zoom() > z0 * 1.5, ("holding = zooms in (%.2f -> %.2f)"):format(z0, user_zoom()))
check(jump < 0.02, ("holding = zooms smoothly (largest change in a frame %.3f)"):format(jump))
check(user_zoom() > z_release, "and eases to a stop after you let go")
local z1 = user_zoom()
tap(0x6D, "-")
jump = watch_zoom(60)
check(user_zoom() < z1 and user_zoom() > z1 * 0.9, ("a tap on keypad - zooms out a little (%.2f -> %.2f)"):format(z1, user_zoom()))
check(jump < 0.01, ("a tap glides rather than jumps (%.3f)"):format(jump))
local z2 = user_zoom()
check(wheel(3) == true, "wheel kept from X-Plane while filming outside")
jump = watch_zoom(60)
check(user_zoom() > z2 * 1.2 and jump < 0.03, ("the wheel zooms in, gliding (%.2f -> %.2f, %.3f)"):format(z2, user_zoom(), jump))
local z3 = user_zoom()
check(X.mock_handler_count() == 4 and X.mock_press("sim/general/zoom_out", 0) == 0, "zoom commands (e.g. joystick) zoom the camera too")
jump = watch_zoom(45)
X.mock_press("sim/general/zoom_out", 2)
jump = math.max(jump, watch_zoom(60))
check(user_zoom() < z3 * 0.75 and jump < 0.02, ("held zoom command zooms out smoothly (%.2f -> %.2f, %.3f)"):format(z3, user_zoom(), jump))
local z4 = user_zoom()
step(60)
check(math.abs(user_zoom() - z4) < 0.01, "and stops when released")

section("in the cockpit, + / - and the wheel are X-Plane's own zoom")
CinematicViews.shot("scan")
step(5)
check(tap(0xB0, "=") == false, "= passed to X-Plane in the cockpit")
check(wheel(2) == false, "wheel passed to X-Plane in the cockpit")
check(X.mock_press("sim/general/zoom_in", 0) == 1, "zoom commands passed to X-Plane in the cockpit")

section("zoom is remembered for each shot")
CinematicViews.shot("wide_rear")
step(200)
local chase_zoom = user_zoom()
CinematicViews.shot("wide_side")
step(200)
CinematicViews.shot("wide_rear")
step(200)
check(math.abs(user_zoom() - chase_zoom) < 0.05, ("back to the shot, its zoom is back (%.2f)"):format(user_zoom()))
CinematicViews.stop()
step(3)
check(X.mock_handler_count() == 0, "zoom commands handed back when stopped")
check(tap(0xB0, "=") == false and wheel(1) == false, "+ and the wheel are X-Plane's again")

-- ---------------------------------------------------------------------------
section("shots fit a long-winged, short glider")
X.mock_set_aircraft("ASK21.acf")
set("sim/aircraft/weight/acf_m_max", 600)
set("sim/aircraft/view/acf_size_x", 8.5) set("sim/aircraft/view/acf_size_z", 4.2)
set("sim/aircraft/engine/acf_num_engines", 0)
often()
check(A.size_source == "dimensions" and math.abs(A.Rs - 8.5) < 0.01, "glider measured")
plane.u = 800
steer(30, 0, 0, 0, false)
plane.the = 0
CinematicViews.shot("close_wingtip")
step(10)
local tx = RT.subject(cine.st.r)
check(math.abs(math.abs(tx - (plane.e - origin.e)) - 0.95 * 8.5) < 0.5, "the wingtip close-up looks at the wingtip")
local m = measure_exterior(60 * 6)
report("glider / wingtip", m)
CinematicViews.shot("close_tail")
step(10)
m = measure_exterior(60 * 6)
report("glider / tail", m)
local _, _, tz = RT.subject(cine.st.r)
check(tz - (plane.s - origin.s) > 3 and tz - (plane.s - origin.s) < 5, "the tail close-up looks at the short tail")
check(not SHOTS.overhead.available(), "no overhead panel in a glider")
check(not SHOTS.close_engine.available(), "and no engine")

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
set("sim/aircraft/engine/acf_num_engines", 2)
often()
check(math.abs(A.Rs - 17.9) < 0.01, "another aircraft keeps its own size")
CinematicViews.toggle_window()
f = io.open(SCRIPT_DIRECTORY .. "Cinematic_Views.ini")
ini = f and f:read("*a") or ""
if f then f:close() end
check(ini:find("size.ASK21 = 1.50", 1, true) ~= nil, "correction saved per aircraft")

-- ---------------------------------------------------------------------------
section("glides between shots go round the aircraft, never through it")
plane.u = 1500
steer(150, 0, 0, 0, false)
S.blend_time = 2.5
local through = 0
for _, pair in ipairs({ { "wide_rear", "close_cockpit" }, { "close_wingtip", "close_tail" }, { "close_engine", "wide_high" },
                        { "close_nose", "close_wing" }, { "wide_front", "close_tail" } }) do
  CinematicViews.shot(pair[1])
  step(180)
  CinematicViews.shot(pair[2])
  step(2, function() end)
  step(60 * 3, function()
    if cam then
      local lx, ly, lz = world_to_body(cam.x - (plane.e - origin.e), cam.y - plane.u, cam.z - (plane.s - origin.s),
                                       plane.psi, plane.the, plane.phi)
      local ex, ey, ez = RT.box()
      if math.abs(lx) < ex * 0.97 and math.abs(ly) < ey * 0.97 and math.abs(lz) < ez * 0.97 then through = through + 1 end
    end
  end)
end
check(through == 0, "glide passed through the aircraft on " .. through .. " frames")

-- ---------------------------------------------------------------------------
section("paused: drawing alone keeps the camera alive and moving")
plane.u = 1000
steer(150, 0, 0, 0, false)
CinematicViews.shot("wide_side")
step(10)
paused_no_flightloop = true
set("sim/time/paused", 1)
local p0 = { cam.x, cam.y, cam.z }
step(120)
check(cine.active and cam ~= nil, "keeps rendering while paused")
check(math.sqrt((cam.x - p0[1]) ^ 2 + (cam.y - p0[2]) ^ 2 + (cam.z - p0[3]) ^ 2) > 0.1, "and keeps moving")
paused_no_flightloop = false
set("sim/time/paused", 0)

section("if FlyWithLua stops running the script, the camera is handed back")
CinematicViews.shot("wide_rear")
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
local want = { "Camera OFF", "< Previous", "Next >", "Camera on/off", "Next view", "Previous view",
               "Open/close window", "Camera distance", "Camera shake", "Shot transition", "Cockpit head movement",
               "Aircraft size" }
for _, w in ipairs(want) do
  local found = false
  for _, l in ipairs(labels) do if l:find(w, 1, true) then found = true end end
  check(found, "window shows " .. w)
end
check(#labels < 36, "window kept small (" .. #labels .. " items)")
for _, l in ipairs(labels) do
  check(not l:find("Random", 1, true) and not l:find("Save", 1, true), "no random views or saving (" .. l .. ")")
end
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

section("an optional key or button opens and closes the window")
CinematicViews.toggle_window()
build("Assign##window")
tap(0x57, "w", { ctrl = true })
check(BIND.window and BIND.window.vk == 0x57 and BIND.window.ctrl, "Ctrl+W assigned to the window")
check(windows == 1, "assigning doesn't close it")
check(tap(0x57, "w", { ctrl = true }) == true and windows == 0, "Ctrl+W closes the window (and X-Plane doesn't get it)")
tap(0x57, "w", { ctrl = true })
check(windows == 1, "and opens it again")
check(tap(0x57, "w") == false and windows == 1, "plain W is left to X-Plane")
build("Assign##window")
X.mock_set_button(60, 1)
step(2)
X.mock_set_button(60, 0)
step(2)
check(BIND.window and BIND.window.kind == "joy" and BIND.window.n == 60 and windows == 1, "or a joystick button")
X.mock_set_button(60, 1) step(2) X.mock_set_button(60, 0) step(2)
check(windows == 0, "the button closes the window")
X.mock_set_button(60, 1) step(2) X.mock_set_button(60, 0) step(2)
check(windows == 1, "and opens it")
CinematicViews.toggle_window()
check(windows == 0, "closed")
f = io.open(SCRIPT_DIRECTORY .. "Cinematic_Views.ini")
ini = f and f:read("*a") or ""
if f then f:close() end
check(ini:find("bind.window = joy:60", 1, true) ~= nil, "the window button is saved")
check(ini:find("myshot", 1, true) == nil and ini:find("random", 1, true) == nil, "nothing about random views in the settings")

-- ---------------------------------------------------------------------------
section("no random views")
for name in pairs(commands) do check(not name:find("random") and not name:find("save_shot"), "command " .. name) end
check(CinematicViews.random_shot == nil and CinematicViews.save_shot == nil, "no random or save functions")

-- ---------------------------------------------------------------------------
section("no errors logged")
local seen = {}
for _, l in ipairs(logs) do
  if l:find("error") and not seen[l] then seen[l] = true check(false, "log: " .. l) end
end

section("shutdown (reload or quit)")
CinematicViews.shot("wide_rear")
step(3)
for _, fn in ipairs(hooks.exit) do fn() end
check(X.mock_camera_controlled() == 0, "camera released on exit")
check(X.mock_handler_count() == 0, "zoom commands released on exit")

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
