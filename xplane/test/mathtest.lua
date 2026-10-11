-- Checks the script's camera math against X-Plane's conventions (heading,
-- pitch, roll, local OpenGL axes). Run through run.sh.
local script = arg[1]
SYSTEM = "NONE"; SCRIPT_DIRECTORY = os.getenv("TMPDIR_TEST")
for _, n in ipairs({ "do_every_frame", "do_every_draw", "do_on_keystroke", "do_on_mouse_click", "do_on_mouse_wheel",
    "do_on_exit", "create_command", "add_macro", "logMsg", "command_once" }) do _G[n] = function() end end
function XPLMFindDataRef() return nil end
dofile(script)
local function upvalue(f, name)
    for i = 1, 200 do
        local n, v = debug.getupvalue(f, i)
        if not n then return nil end
        if n == name then return v end
    end
end
local tick = upvalue(CinematicView_tick, "fn")
local M = upvalue(tick, "M")
local fails = 0
local function near(a, b, tol, msg) if math.abs(a - b) > (tol or 1e-6) then fails = fails + 1 print("FAIL " .. msg .. ": " .. a .. " vs " .. b) end end

-- heading 90 (east): nose (0,0,-1) points to +x
local x, y, z = M.body_to_world(0, 0, -1, 90, 0, 0)
near(x, 1, 1e-9, "east x") near(z, 0, 1e-9, "east z")
-- pitch up 10: nose rises
x, y, z = M.body_to_world(0, 0, -1, 0, 10, 0)
near(y, math.sin(math.rad(10)), 1e-9, "pitch up")
-- roll right 30: right wing (1,0,0) goes down
x, y, z = M.body_to_world(1, 0, 0, 0, 0, 30)
near(y, -0.5, 1e-9, "roll right")
-- SDK camera sample: camera 200 m south of the plane looking north = heading 0, pitch 0
local h, p = M.look_at(0, 0, 200, 0, 0, 0)
near(h, 0, 1e-9, "look north") near(p, 0, 1e-9, "level")
h, p = M.look_at(-200, 0, 0, 0, 0, 0)
near(h, 90, 1e-9, "look east")
h, p = M.look_at(0, -100, 100, 0, 0, 0)
near(p, 45, 1e-9, "look up")
-- a camera bolted to the airframe looking forward rolls with the aircraft
for _, att in ipairs({ { 0, 0, 25 }, { 120, 8, -40 }, { 250, -5, 60 } }) do
    local psi, the, phi = att[1], att[2], att[3]
    local fx, fy, fz = M.body_to_world(0, 0, -1, psi, the, phi)
    local hh, pp = M.look_at(0, 0, 0, fx, fy, fz)
    local ux, uy, uz = M.body_to_world(0, 1, 0, psi, the, phi)
    near(hh, psi > 180 and psi - 360 or psi, 1e-6, "mounted heading")
    near(pp, the, 1e-6, "mounted pitch")
    near(M.roll_for(hh, pp, ux, uy, uz), phi, 1e-6, "mounted roll")
end
near(M.wrap180(350), -10, 1e-9, "wrap") near(M.wrap180(-190), 170, 1e-9, "wrap neg")
print(fails == 0 and "math OK" or (fails .. " math failures"))
os.exit(fails == 0 and 0 or 1)
