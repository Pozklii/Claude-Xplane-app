# Cinematic View for X-Plane 12

A [FlyWithLua NG+](https://forums.x-plane.org/index.php?/files/file/82888-flywithlua-ng-next-generation-plus-edition-for-x-plane-12-win-lin-mac/) script that turns X-Plane's camera into a self-directing cinematic camera, like the attract modes in the Need for Speed and Forza Horizon games. It cuts between shots outside the aircraft and inside the cockpit, with letterbox bars and fades. The shots aren't picked from a fixed list: each one is generated as it starts.

It can be switched on and off whenever you like, and it starts by itself after a while with no input (two minutes by default). Pressing a key, moving the mouse or touching the joystick ends it and puts you back in the view you were in. X-Plane's zoom keys (+ and -) zoom the cinematic camera without ending it.

## Install

1. Install FlyWithLua NG+ for X-Plane 12 if you don't have it.
2. Copy [`FlyWithLua/Scripts/cinematic_view.lua`](FlyWithLua/Scripts/cinematic_view.lua) to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`.
3. Start X-Plane, or choose **Plugins → FlyWithLua → Reload all Lua script files**.

## Use

Everything is in one window: **Plugins → FlyWithLua → FlyWithLua Macros → Cinematic View**. It has **Start now / Stop** and **Next shot** buttons, all the settings, and a key for each action.

- **Start/stop by hand:** with the button, or a key you set in the window. A cinematic you start yourself keeps running while you use the controls (the autopilot is a good idea) until you stop it or pick another view.
- **When you're away:** after the away time (2 minutes by default) with no keyboard, mouse, joystick or head-tracking input, it starts by itself, but never while the sim is paused. Any input ends it, except the zoom keys and the keys you've set for the cinematic.
- **Zoom:** hold **=** / **+** to zoom in and **-** to zoom out (main keyboard or keypad). In outside shots this zooms the cinematic camera smoothly: it speeds up gently when you press, eases to a stop when you let go, and a tap makes a small step. The zoom carries on into the next outside shots until the cinematic ends. In the cockpit the keys go to X-Plane's own zoom.

### Keys

In the window's **Keys** section, press **Set** next to an action, then the key you want (with Ctrl, Alt or Shift if you like; Esc cancels). **Clear** removes it. A key set here takes priority over whatever X-Plane does with it, and setting a key on one action takes it off any other.

| Action | Does |
| --- | --- |
| Start / stop | Start or stop the cinematic |
| Next shot | Cut to the next shot now |
| Auto-start on/off | Turn starting when you're away on or off |
| Cycle shot types | Mixed → outside only → cockpit only |
| Zoom in / Zoom out | Zoom while held (as well as + and -) |
| This window | Show or hide the window |

For joystick buttons, each action is also an X-Plane command, under **Settings → Joystick** (search for "cinematic"): `FlyWithLua/cinematic_view/toggle`, `next_shot`, `toggle_afk`, `cycle_mode`, `zoom_in`, `zoom_out` and `settings`. Pressing one of these buttons doesn't count as the input that ends a cinematic.

## Shots

There's no fixed list of shots. Each one is generated as it starts, from random choices within limits that suit what the aircraft is doing, so the same shot rarely comes round twice. Outside the aircraft there are three kinds, and each covers a whole family:

- **Orbiting** — a camera moving around the aircraft, in a frame that turns with its heading. The script picks where it starts (from any direction round the aircraft, from low or high, near or far), how it moves over the shot (round the aircraft, up or down, in or out, or a mix), the lens (wide, or a long lens from further away), how much it lags the aircraft's turns and leans with its bank, and where the aircraft sits in the picture. Chase, tracking, orbit, crane, pass-by, drone and long-lens shots all come out of this.
- **Trackside** — a camera standing still by the flight path, on the ground when you're low or in the air when you're high, that the aircraft passes, comes towards or leaves behind, zooming to keep it a similar size. Only while moving.
- **Mounted** — a camera fixed just off the airframe (above and behind the tail, off a wingtip, ahead of the nose looking back, or below to one side), rolling and pitching with it.

Moments that cut in as they happen, the way racing games cut to a jump or a finish:

- **Touchdown** — on short final (below about 130 ft, descending), a camera by the runway a little past where you'll touch down.
- **Liftoff** — as the wheels leave the runway, a camera low by the runway as the aircraft lifts off and climbs away.

Inside the cockpit, the pilot's head is placed somewhere (the pilot's seat, over the shoulder, leaning towards the panel, or the other seat in a side-by-side cockpit), looks somewhere (forward, out of the side window, at the panel, across the cockpit) and pans slowly. It holds still otherwise: no bobbing.

### How shots are generated

- **By what you're doing.** Parked, it's mostly orbiting shots from low to fairly high. Taxiing and on the takeoff or landing roll, cameras stay low and trackside cameras stand on the ground. Flying low, trackside shots from the ground are as likely as orbiting ones. In cruise there are more long lenses, shots from below and high above, and trackside cameras in the air.
- **Variety.** Each orbiting shot starts from a different direction from the last, and the same kind of shot never comes three times running.
- **Faster cutting when it's busy.** On the takeoff or landing roll and flying low, shots come from the short half of your shot-length range; parked and in cruise, from the long half.
- **A reveal to open with.** A cinematic starts with an orbiting shot from ahead, swinging round (unless it's cockpit-only).
- **Tilted horizons** now and then.
- **Cameras never go below the ground.**

### Camera speed and panning speed

Two sliders limit how fast the picture moves, each from 0.1 to 2 (default 0.5):

- **Camera speed** is how fast cameras travel: an orbiting camera going round the aircraft, up or down, in or out (about 2.5° a second at the default, 0.5° at the slowest). A zoomed-in camera moves less, since zoom magnifies motion.
- **Panning speed** is how fast cameras turn:
  - Trackside cameras stand far enough from the flight path that they never have to turn faster than the limit to follow the aircraft (about 20° a second at the default, 4° at the slowest), and zoom out as it passes so the picture doesn't sweep faster than that. The touchdown and liftoff cameras do the same, so with fast aircraft and slow panning they stand well back from the runway.
  - Mounted cameras' slow drift across the aircraft, and the pilot's head panning in cockpit shots (about 3.75° a second at the default), keep to it too.

Both take effect from the next shot.

### Aircraft size

Shots are framed and kept clear of the aircraft using its size: its span, or a guess from its maximum weight if X-Plane doesn't report one. Cameras stay outside a sphere round the aircraft sized from it. If cameras clip an aircraft (a long fuselage, say), raise **Aircraft size** in the window; it's kept for that aircraft (by its file), and **Auto** goes back to the worked-out size.

## Settings

Changed in the window, or in `cinematic_view.ini` next to the script (written when you change something):

| Setting | Default | |
| --- | --- | --- |
| `afk_enabled` | `true` | Start by itself when you're away |
| `afk_timeout` | `120` | Seconds without input before it starts |
| `mode` | `mixed` | `mixed`, `outside` or `cockpit` |
| `cockpit_share` | `30` | Percent of shots in the cockpit in mixed mode |
| `shot_min`, `shot_max` | `7`, `14` | Shot length range, seconds |
| `camera_pace` | `0.5` | Camera speed: how fast cameras travel, from `0.1` to `2` (replaces the old `camera_speed`, so earlier settings start at the new slower default) |
| `pan_pace` | `0.5` | Panning speed: how fast cameras turn, from `0.1` to `2` |
| `letterbox` | `true` | Cinema bars top and bottom |
| `fades` | `true` | Dip to black when switching between inside and outside, and now and then between other shots |
| `manual_exit_on_input` | `false` | Any input also ends a cinematic you started yourself |
| `joystick_deadband` | `0.03` | How far an axis must move to count as input (raise it for noisy hardware) |
| `bind_toggle`, `bind_next_shot`, `bind_toggle_afk`, `bind_cycle_mode`, `bind_zoom_in`, `bind_zoom_out`, `bind_settings` | empty | The keys set in the window, as `<virtual key code> <modifiers> <name>` (modifiers: 1 Shift, 2 Ctrl, 4 Alt); easiest set from the window |
| `chase_view` | `0` | Not a setting: X-Plane's number for its chase view, learned the first time it's needed (see below) |
| `size:<aircraft file>` | none | An aircraft size set in the window, in metres, one line per aircraft |

## How it works

- **Outside shots** take control of X-Plane's camera through the plugin SDK's `XPLMControlCamera`, called from Lua through LuaJIT's FFI, which FlyWithLua NG+ includes. The camera is worked out in X-Plane's camera callback from where the aircraft is that frame, so it keeps up with the aircraft at speed, and terrain probes keep it above the ground. The view underneath is X-Plane's chase view, so you hear the outside sounds.
- **Cockpit shots** switch to the 3D cockpit and move the pilot's head (`sim/graphics/view/pilots_head_*`), so cockpit lighting, sounds and reflections stay right.
- **Zoom:** X-Plane's own zoom can't act on a camera a plugin controls, so in outside shots the script catches + and - and zooms its camera itself. FlyWithLua reports X-Plane's key repeats (while a key is held) as releases, so the script treats a key as held until it's let go quickly after the press (a tap) or its events stop coming, which also copes with slow key-repeat settings. The zoom ramps up over a quarter of a second and the camera eases after it. In the cockpit the keys go through to X-Plane, and a key or joystick button set for zoom holds X-Plane's `sim/general/zoom_in`/`zoom_out` commands.
- **Switching views quietly:** X-Plane announces a view change on screen when its view commands are used, so the script switches views by setting X-Plane's view number (`sim/graphics/view/view_type`) directly. The 3D cockpit's number is fixed; the chase view's (used under the outside shots) is learned the first time with X-Plane's chase command, so you may see its name that once, and kept in `cinematic_view.ini` as `chase_view`. If a direct switch doesn't take, the script falls back to the command.
- **Keys** set in the window are caught with FlyWithLua's keyboard sniffer, which runs before X-Plane's own key bindings.
- If the SDK library can't be loaded, outside shots fall back to X-Plane's own chase, circle and flyby (still spot/linear spot) views.
- **Ending a cinematic** puts back the view and head position you had. If you pick a view yourself during one, it stops and leaves you in that view.
- **Being a good neighbour:** if another plugin (X-Camera, say) takes the camera, it stops rather than fighting for it, and won't start by itself again until you're back. If FlyWithLua stops running scripts, the camera is handed back to X-Plane within a few seconds. Not available in VR.

## Testing without X-Plane

[`test/run.sh`](test/run.sh) builds a mock of X-Plane's SDK library (`test/xplm_mock.c`), runs the script in a simulated FlyWithLua with and without the SDK, flying a simulated aircraft through cruise, a landing, a takeoff, low flying and parked-and-paused, and checks the camera math against X-Plane's conventions. It needs `luajit` and a C compiler:

```bash
xplane/test/run.sh
```

It also flies a simulated landing and takeoff to check that the touchdown and liftoff shots cut in, with their cameras by the runway, and flies low until trackside cameras on the ground come up. It checks that generated shots come from all round the aircraft with a mix of lenses and heights, that cameras stay outside the aircraft's clearance sphere, that orbiting and trackside cameras move within the camera speed limit, and that cockpit shots hold the head steady. It can't show what the shots look like in X-Plane, only that they keep the aircraft in frame, never go below the ground, and that starting, stopping, input, view changes, zoom, keys and settings behave.
