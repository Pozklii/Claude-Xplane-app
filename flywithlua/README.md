# Cinematic Views for X-Plane 12

A [FlyWithLua NG+](https://github.com/X-Friese/FlyWithLua) script with cinematic exterior cameras for your flights. You pick from 11 shots, and the cameras fit the aircraft you're flying, from a glider to an A380. X-Plane's own zoom keys and the mouse wheel zoom them.

Everything is in one file, [`Cinematic_Views.lua`](./Cinematic_Views.lua).

## Install

1. Install FlyWithLua NG+ for X-Plane 12 if you don't have it yet.
2. Copy `Cinematic_Views.lua` to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`.
3. Start a flight, or use **Plugins → FlyWithLua → Reload all Lua script files** if X-Plane is already running.

To start filming, choose **Plugins → FlyWithLua → FlyWithLua Macros → Cinematic Views: start/stop**. Run it again to stop and get your own view back. **Cinematic Views: next shot** moves on to the next shot, and **Cinematic Views: settings window** opens the controls.

For one-key control, bind the commands in **Settings → Keyboard** (or Joystick) and search for `cinematic`. Good ones to bind are `FlyWithLua/cinematic_views/toggle`, `next_shot` and `previous_shot`, and the hold-to-adjust `orbit_left`/`orbit_right`/`camera_up`/`camera_down`, for example on a hat switch.

Only run one camera script at a time. If you also have other cinematic camera scripts installed (for example `CineCam.lua` or `cinematic_camera.lua`), they will fight over the camera.

## Shots

All shots use X-Plane's camera API. They're framed for a 60° lens whatever your FOV.

| Shot | What it does |
| --- | --- |
| Chase | Follows behind and a little to one side. It swings out lazily in turns, follows climbs and descents, and banks a little with you. |
| Orbit | Circles the aircraft slowly, rising and falling as it goes. |
| Flyby | Sets up ahead of you, off to one side, and tracks you past with a zoom that keeps the aircraft a steady size in frame. When you've gone by, it sets up the next pass. |
| Spotter | A handheld camera on the ground with up to 8× telephoto, also repeating pass after pass. Best on takeoff and landing. |
| Air-to-air | A photo ship in loose formation. It drifts slowly around its slot and banks with you, the classic air-to-air look. Airborne only. |
| Crane sweep | A slow, eased crane move around the aircraft along one of three paths, then back again. |
| Tail, wing, nose, top and gear cams | Fixed to the airframe, rolling and pitching with it, with a little vibration from speed and runway roughness. The gear cam is for the ground and low flying. |

Pick a shot from the settings window or with its command. You can also step through them with **Next** and **Previous**, which skip shots that don't apply right now, such as air-to-air on the ground. Related shots glide into each other; other changes are hard cuts.

## Fitting the aircraft

Cameras scale to the aircraft's size. The script reads its span and length from X-Plane, checks them against the aircraft's weight, and works out whether they're in metres or feet. If X-Plane doesn't provide usable dimensions, it estimates the size from the weight instead. Distances use the larger of span and length. Mounted cameras use each separately: the wing cam sits off the wingtip, and the tail, nose, top and gear cams follow the fuselage. That way a glider's wing cam is out at its long wingtip, and its tail cam is just behind its short tail.

The settings window shows the span and length the script is using and where they came from. If the cameras sit too close or too far away on an aircraft, adjust **Aircraft size**. The correction is remembered for that aircraft and saved.

## Zoom

While a shot is running:

- X-Plane's own zoom commands (`sim/general/zoom_in` and `zoom_out`, and their fast versions) zoom the camera. A tap zooms one step, and holding zooms smoothly.
- The mouse wheel zooms too.
- The settings window has **Zoom +** and **Zoom -** buttons, and there are `zoom_in` and `zoom_out` commands.

Zoom, along with orbit-around and height adjustments, is remembered for each shot. Going back to a shot, or a flyby setting up its next pass, keeps the zoom you chose. **Reset adjustments** clears it for the current shot. When you're not filming, the zoom keys and mouse wheel work as normal.

## Settings window

The window has the shot buttons, Start/Stop and Previous/Next, plus these settings:

- **Camera**: distance, orbit speed, handheld shake, telephoto limit, glide time between shots (0 for hard cuts only), aircraft size, and lens framing. There are also buttons to adjust the live shot: around, up, down, in or out.
- **Look**: letterbox bars (1.85:1, 2:1 or 2.39:1 scope) and shot titles.

Settings are saved to `Cinematic_Views.ini` next to the script.

## Commands

Every command starts with `FlyWithLua/cinematic_views/`.

| Command | Action |
| --- | --- |
| `toggle` | Start with the last shot, or stop and hand the camera back |
| `stop` | Stop and return to your view |
| `next_shot`, `previous_shot` | Step through the shots |
| `shot_<name>` | A specific shot: `chase`, `orbit`, `flyby`, `spotter`, `a2a`, `sweep`, `tail`, `wing`, `nose`, `top`, `gear` |
| `orbit_left`, `orbit_right`, `camera_up`, `camera_down`, `zoom_in`, `zoom_out` | Adjust the live shot while held |
| `reset_adjustments` | Undo those adjustments for the current shot |
| `toggle_letterbox`, `toggle_window` | Toggles |

## Tips

- For video, fly or load a flight, then film X-Plane's replay. The script reads the aircraft's motion directly in replays.
- The camera keeps moving while the sim is paused, so you can pause for screenshots.
- If you start from the cockpit, stopping takes you back to it. If you change the view yourself (a view key, or the View menu), the script hands the camera straight back to you.
- The script never moves the pilot's head or changes your FOV.
- It switches itself off in VR.

## How it works

Shots use the SDK's `XPLMControlCamera` through LuaJIT's FFI. The camera callback reads the aircraft position itself, so the camera never lags the drawn aircraft. Fixed cameras are stored as latitude and longitude, so they stay put when X-Plane moves its local coordinate origin. A terrain probe keeps every camera above the ground.

The aircraft's dimensions come from `sim/aircraft/view/acf_size_x` and `acf_size_z`, with the maximum weight as a check and fallback. X-Plane's zoom commands are taken over with command handlers only while a shot runs.

When you stop, or reload scripts, the script releases the camera and the zoom commands. If FlyWithLua stops running the script for any reason, it releases them on its own.

If something isn't working, look for lines starting with `Cinematic Views:` in X-Plane's `Log.txt`.

## Tests

`test/run_tests.sh` runs the script under LuaJIT against a small C stand-in for X-Plane's SDK (`test/mock_xplm.c`). It flies simulated taxi, takeoff, cruise and approach segments and checks a range of behaviour:

- Every shot keeps the aircraft in frame and above ground, and the mounted cameras stay rigid.
- Cameras fit both an airliner and a glider. Dimensions in metres or feet, and missing or nonsense ones, are handled, and size corrections are kept per aircraft.
- X-Plane's zoom commands and the mouse wheel zoom while filming and are left alone otherwise, and zoom is remembered per shot.
- View changes hand the camera over correctly, and the pilot's head is never touched.
- Pause, replay, the settings window and saved settings work.

The tests need `cc` and `luajit`. Because they run against a mock, they check the script's logic but not X-Plane's own behaviour, so try changes in the sim too.
