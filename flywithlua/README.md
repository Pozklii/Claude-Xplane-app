# Cinematic Views for X-Plane 12

A [FlyWithLua NG+](https://github.com/X-Friese/FlyWithLua) script for screenshots and videos. It's an automatic cinematic camera that works outside and inside the aircraft. Pick a shot and the camera works on its own: it follows, zooms and frames the aircraft for you.

Everything is in one file, [`Cinematic_Views.lua`](./Cinematic_Views.lua).

## Install

1. Install FlyWithLua NG+ for X-Plane 12 if you don't have it yet.
2. Copy `Cinematic_Views.lua` to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`, replacing any older copy.
3. Start a flight, or use **Plugins → FlyWithLua → Reload all Lua script files** if X-Plane is already running.

Open **Plugins → FlyWithLua → FlyWithLua Macros → Cinematic Views: settings window**. Everything is in that one window.

Only run one camera script at a time. If you also have other cinematic camera scripts installed (for example `CineCam.lua` or `cinematic_camera.lua`), they'll fight over the camera.

## The window

The window has these sections, from top to bottom:

- **Start camera / Camera ON**, **< Previous** and **Next >**, plus the shot that's running and its zoom.
- **Exterior shots** and **Cockpit shots**: a button for each shot. You can also choose whether **Next / Previous** include the cockpit shots.
- **Controls**: your own key or joystick button for **Camera on/off**, **Next view** and **Previous view**.
  - Press **Assign**, then the key or button you want. **Esc** cancels.
  - Assigned keys only control the camera, so X-Plane won't also act on them.
  - X-Plane still sees joystick buttons, so pick ones that have no X-Plane assignment.
  - + and − can't be assigned, because they're kept for zoom.
- **Exterior camera**: distance, orbit speed, handheld shake, telephoto limit, glide time between shots, aircraft size and lens framing. There are also buttons to adjust the live shot: around, up, down, in or out.
- **Cockpit camera**: how much the head moves, and the pilot's eye point.
- **Look**: letterbox bars (1.85:1, 2:1 or 2.39:1 scope) and shot titles.

Settings, assignments and size corrections save automatically to `Cinematic_Views.ini` next to the script.

## Shots

### Exterior

| Shot | What it does |
| --- | --- |
| Chase | Follows behind and a little to one side. It swings out lazily in turns, follows climbs and descents, and banks a little with you. |
| Orbit | Circles the aircraft slowly, rising and falling as it goes. |
| Flyby | Sets up ahead of you, off to one side, and tracks you past with a zoom that keeps the aircraft a steady size in frame. When you've gone by, it sets up the next pass. |
| Spotter | A handheld camera on the ground with up to 8× telephoto, also repeating pass after pass. Best on takeoff and landing. |
| Air-to-air | A photo ship in loose formation. It drifts slowly around its slot and banks with you, the classic air-to-air look. Airborne only. |
| Crane sweep | A slow, eased crane move around the aircraft along one of three paths, then back again. |
| Tail, wing, nose, top and gear cams | Fixed to the airframe, rolling and pitching with it, with a little vibration from speed and runway roughness. The gear cam is for the ground and low flying. |

Exterior shots fit the aircraft. The script reads its span and length from X-Plane, checks them against its weight, and works out whether they're in metres or feet. If X-Plane doesn't provide usable dimensions, it estimates the size from the weight instead. Distances use the larger of span and length. Mounted cameras use each separately: the wing cam sits off the wingtip, and the tail, nose, top and gear cams follow the fuselage. The window shows what the script is using. If an aircraft looks off, adjust **Aircraft size**; the correction is remembered for that aircraft.

### Cockpit

| Shot | What it does |
| --- | --- |
| Pilot's eye | Your seat, with natural glances out of the windows and down at the panel. |
| Panel sweep | A slow pan across the instrument panel and back. |
| Side window | Looking out of your side window, slowly scanning. |
| Cockpit pan | A slow pan from one side window, across the panel, to the other. |
| First officer | From the other seat, looking across. Only for side-by-side seats. |

Cockpit shots look around rather than move around, so they can't clip through the aircraft. The head never moves more than 8 cm sideways, 5 cm up, 4 cm down, 8 cm forward or 6 cm back from the seat. That keeps the view inside the cockpit, clear of the panel, the seat and the walls.

Inside that space there's a little natural motion: a lean into a glance, a nudge from G-forces, turbulence and a firm touchdown, and some runway rumble. **Head movement** sets how much, and at 0 the head doesn't move from the seat at all.

The eye point is your head position when filming starts in the cockpit, so start from your normal seat view. **Use my current head position as the pilot's eye** resets it. When you stop, your head goes back exactly where it was.

## Zoom

- **Exterior shots:** + (or =) and − zoom the camera, top row or keypad. A tap zooms one step, holding zooms smoothly, and Shift zooms faster. The mouse wheel and X-Plane's zoom commands (for example on a joystick) zoom it too. Zoom is remembered for each shot, so a flyby keeps your zoom from one pass to the next.
- **Cockpit shots:** +, − and the mouse wheel are X-Plane's own zoom, exactly as normal.
- **When you're not filming,** the script doesn't touch +, − or the mouse wheel at all.

## Commands

You can also bind commands in X-Plane's **Settings → Keyboard** or **Joystick**: search for `cinematic`. Every command starts with `FlyWithLua/cinematic_views/`.

| Command | Action |
| --- | --- |
| `toggle` | Camera on (with your last shot) or off |
| `stop` | Stop and return to your view |
| `next_shot`, `previous_shot` | Next or previous view; with the camera off they start it with your last shot |
| `shot_<name>` | A specific shot: `chase`, `orbit`, `flyby`, `spotter`, `a2a`, `sweep`, `tail`, `wing`, `nose`, `top`, `gear`, `pilot`, `panel`, `side`, `cpan`, `fo` |
| `orbit_left`, `orbit_right`, `camera_up`, `camera_down`, `zoom_in`, `zoom_out` | Adjust the live shot while held |
| `reset_adjustments` | Undo those adjustments for the current shot |
| `toggle_letterbox`, `toggle_window` | Toggles |

## Tips

- For video, fly or load a flight, then film X-Plane's replay. The script reads the aircraft's motion directly in replays.
- The camera keeps moving while the sim is paused, so you can pause for screenshots.
- If you start from the cockpit, stopping takes you back to it. If you change the view yourself (a view key, or the View menu), the script hands the camera straight back to you.
- It switches itself off in VR.

## How it works

Exterior shots use the SDK's `XPLMControlCamera` through LuaJIT's FFI. The camera callback reads the aircraft position itself, so the camera never lags the drawn aircraft. Fixed cameras are stored as latitude and longitude, so they stay put when X-Plane moves its local coordinate origin. A terrain probe keeps every camera above the ground.

Cockpit shots write the `sim/graphics/view/pilots_head_*` datarefs, clamped to the safe space around the seat.

Keys, the mouse wheel and joystick buttons use FlyWithLua's own key and wheel hooks and X-Plane's joystick button values. The script only holds back a key or the wheel when it uses them. X-Plane's zoom commands are taken over only during exterior shots. The letterbox uses FlyWithLua's built-in drawing.

When you stop, or reload scripts, the script releases the camera and the zoom commands and puts your head back. If FlyWithLua stops running the script for any reason, it releases them on its own.

If something isn't working, look for lines starting with `Cinematic Views:` in X-Plane's `Log.txt`.

## Tests

`test/run_tests.sh` runs the script under LuaJIT against a small C stand-in for X-Plane's SDK (`test/mock_xplm.c`). Keys and the wheel are delivered the way FlyWithLua 2.8 delivers them. The tests fly simulated taxi, takeoff, cruise, approach and landing segments and check a range of behaviour:

- Every exterior shot keeps the aircraft in frame and above ground, and the mounted cameras stay rigid.
- Cockpit shots never leave the safe space around the seat, through takeoff rolls, turbulence and firm landings.
- Key and joystick assignments work, + and − and the mouse wheel do the right thing inside, outside and when not filming, and zoom is remembered per shot.
- Cameras fit both an airliner and a glider, view changes hand the camera over correctly, and your head is restored.
- Pause, replay, the window and saved settings work.

The tests need `cc` and `luajit`. Because they run against a mock, they check the script's logic but not X-Plane's own behaviour, so try changes in the sim too.
