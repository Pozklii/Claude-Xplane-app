# Cinematic Views for X-Plane 12

A [FlyWithLua NG+](https://github.com/X-Friese/FlyWithLua) script that works as a film crew for your flights. It films from outside and inside the aircraft. A **Director** picks shots to suit the phase of flight, so the replay looks edited, and you can also pick any shot yourself.

Everything is in one file, [`Cinematic_Views.lua`](./Cinematic_Views.lua).

## Install

1. Install FlyWithLua NG+ for X-Plane 12 if you don't have it yet.
2. Copy `Cinematic_Views.lua` to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`.
3. Start a flight, or use **Plugins → FlyWithLua → Reload all Lua script files** if X-Plane is already running.

To start filming, choose **Plugins → FlyWithLua → FlyWithLua Macros → Cinematic Views: Director on/off**. Run it again to stop and get your own view back. **Cinematic Views: settings window** opens the controls.

For one-key control, bind the commands in **Settings → Keyboard** (or Joystick) and search for `cinematic`. Good ones to bind are `FlyWithLua/cinematic_views/toggle`, `next_shot` and the hold-to-adjust `orbit_left`/`orbit_right`/`zoom_in`/`zoom_out`, for example on a hat switch.

## The Director

The Director watches the flight phase and picks shots that fit it:

| Phase | Favourite shots |
| --- | --- |
| Taxi | chase, orbit, gear cam, over the shoulder, pilot's eye |
| Runway (takeoff roll and rollout) | spotter, chase, tail and wing cams, pilot's eye |
| Departure | flyby, chase, air-to-air, tail cam |
| En route | air-to-air, orbit, crane sweep, wing/tail/nose cams, side window |
| Approach | spotter at the fence, flyby, chase, gear cam, pilot's eye |

It never shows the same shot twice in a row and avoids shots used just before. It doesn't show air-to-air on the ground or the gear cam at cruise altitude. When the phase changes, for example when the takeoff roll starts, it cuts to something that suits the new phase. Flybys and spotter shots last until the aircraft has passed. Related shots glide into each other; other changes are hard cuts.

**Hold shot** keeps the current shot until you resume. **Next** asks the Director for another shot now.

## Shots

### Exterior

All exterior shots use X-Plane's camera API. They're framed for a 60° lens whatever your FOV, and they scale to the size of the aircraft, from a Cessna to an A380.

| Shot | What it does |
| --- | --- |
| Chase | Follows behind and a little to one side. It swings out lazily in turns, follows climbs and descents, and banks a little with you. |
| Orbit | Circles the aircraft slowly, rising and falling as it goes. |
| Flyby | Sets up ahead of you, off to one side, and tracks you past with a zoom that keeps the aircraft a steady size in frame. |
| Spotter | A handheld camera on the ground, up to 8× telephoto. Best on takeoff and landing. |
| Air-to-air | A photo ship in loose formation. It drifts slowly around its slot and banks with you, the classic air-to-air look. |
| Crane sweep | A slow, eased crane move around the aircraft along one of three paths. |
| Tail, wing, nose, top and gear cams | Fixed to the airframe, rolling and pitching with it, with a little vibration from speed and runway roughness. |

### Cockpit

Cockpit shots move the pilot's head in the 3D cockpit, around the eye point the script captures when it starts.

| Shot | What it does |
| --- | --- |
| Pilot's eye | Your seat, with natural glances out of the windows and down at the panel. |
| Over the shoulder | Behind the pilots, easing slowly forward. |
| Panel sweep | A slow pan across the instrument panel. |
| Side window | Looking out of your side window, slowly scanning. |
| First officer | From the other seat, looking across at you (two-seat cockpits). |
| Cabin window | A passenger window over the wing. It's for airliners with a modelled cabin, so the Director only uses it if you allow it in the settings. |

## Living cockpit

The living cockpit adds head motion while you fly. It's on by default and also runs in the cockpit shots.

- G-forces push your head back on the takeoff roll, down when you pull, and sideways in skids. Turbulence comes through naturally.
- A firm landing bumps your head down with a nod. The harder the landing, the bigger the bump.
- Runway and taxiway rumble grows with speed, and there's a faint engine buzz.
- **Look into turns** turns your head into the turn. **Lean toward the horizon** tilts it slightly against the bank, as real pilots do.

The script removes its own offset from the head every frame, so mouse-look, snap views and presets keep working normally. You can turn the living cockpit off, or change its strength, in the settings window. With a head-tracking plugin such as TrackIR, the head tracking takes priority. Turn off any other head-motion plugin you use, so the two don't add up.

## Settings window

The settings window has the shot buttons and the Director controls, plus these settings:

- **Director**: shot length, exterior and cockpit shots on or off, the share of cockpit shots, cabin window shots, and the glide time between shots (0 for hard cuts only).
- **Exterior camera**: distance, orbit speed, handheld shake, telephoto limit and aircraft size. The size is estimated from the maximum weight; scale it if the mounted cameras sit too close or too far away. There are also buttons to nudge the live shot around, up and down, or in and out.
- **Cockpit**: the living cockpit settings and an optional FOV for cockpit shots. **Use my current head position as the pilot's eye** resets the eye point if you started from a moved head.
- **Look**: letterbox bars (1.85:1, 2:1 or 2.39:1 scope) and shot titles.

Settings are saved to `Cinematic_Views.ini` next to the script.

## Commands

Every command starts with `FlyWithLua/cinematic_views/`.

| Command | Action |
| --- | --- |
| `toggle` | Start the Director, or stop and hand the camera back |
| `director` | Director on/off |
| `stop` | Stop and return to your view |
| `next_shot`, `previous_shot` | Step through shots (with the Director on, `next_shot` asks it for a new one) |
| `hold_shot` | Hold the Director on the current shot, or resume |
| `shot_<name>` | A specific shot: `chase`, `orbit`, `flyby`, `spotter`, `a2a`, `sweep`, `tail`, `wing`, `nose`, `top`, `gear`, `pilot`, `shoulder`, `panel`, `side`, `fo`, `cabin` |
| `orbit_left`, `orbit_right`, `camera_up`, `camera_down`, `zoom_in`, `zoom_out` | Adjust the live shot while held |
| `reset_adjustments` | Undo those adjustments |
| `toggle_living_cockpit`, `toggle_letterbox`, `toggle_window` | Toggles |

## Tips

- For video, fly or load a flight, then use X-Plane's replay with the Director on. The script reads the aircraft's motion directly in replays.
- The camera keeps moving while the sim is paused, so you can pause for screenshots.
- If you change the view yourself (a view key, or the View menu), the script hands the camera straight back to you.
- Cinematic shots and the living cockpit switch themselves off in VR.

## How it works

Exterior shots use the SDK's `XPLMControlCamera` through LuaJIT's FFI. The camera callback reads the aircraft position itself, so the camera never lags the drawn aircraft. Fixed cameras are stored as latitude and longitude, so they stay put when X-Plane moves its local coordinate origin. A terrain probe keeps every camera above the ground. Cockpit shots and the living cockpit write the `sim/graphics/view/pilots_head_*` datarefs. When you stop, or reload scripts, the script releases the camera and puts the pilot's head and FOV back.

If something isn't working, look for lines starting with `Cinematic Views:` in X-Plane's `Log.txt`.

## Tests

`test/run_tests.sh` runs the script under LuaJIT against a small C stand-in for X-Plane's SDK (`test/mock_xplm.c`). It flies simulated taxi, takeoff, cruise, approach and landing segments and checks a range of behaviour:

- Every exterior shot keeps the aircraft in frame and above ground, and the mounted cameras stay rigid.
- Cockpit shots stay near the eye point, and stopping restores the head exactly.
- View changes hand the camera over in both directions.
- The Director varies its shots and keeps them right for the phase of flight.
- The living cockpit settles, and never piles up while you drag the view.
- Pause, replay, the settings window and saved settings work.

The tests need `cc` and `luajit`. Because they run against a mock, they check the script's logic but not X-Plane's own behaviour, so try changes in the sim too.
