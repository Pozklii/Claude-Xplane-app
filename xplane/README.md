# Cinematic View for X-Plane 12

A [FlyWithLua NG+](https://forums.x-plane.org/index.php?/files/file/82888-flywithlua-ng-next-generation-plus-edition-for-x-plane-12-win-lin-mac/) script that turns X-Plane's camera into a self-directing cinematic camera, like the attract modes in the Need for Speed and Forza Horizon games. It cuts between shots outside the aircraft and inside the cockpit, with letterbox bars, fades and a caption.

It can be switched on and off whenever you like, and it starts by itself after a while with no input (two minutes by default). Pressing a key, moving the mouse or touching the joystick ends it and puts you back in the view you were in.

## Install

1. Install FlyWithLua NG+ for X-Plane 12 if you don't have it.
2. Copy [`FlyWithLua/Scripts/cinematic_view.lua`](FlyWithLua/Scripts/cinematic_view.lua) to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`.
3. Start X-Plane, or choose **Plugins → FlyWithLua → Reload all Lua script files**.

## Use

- **Start/stop by hand:** bind a key or joystick button to **FlyWithLua/cinematic_view/toggle** (Settings → Keyboard or Joystick, search for "cinematic"), or choose **Plugins → FlyWithLua → FlyWithLua Macros → Cinematic View: start/stop**. A cinematic you start yourself keeps running while you use the controls (the autopilot is a good idea) until you toggle it off or pick another view.
- **When you're away:** after `afk_timeout` seconds (120 by default) with no keyboard, mouse, joystick or head-tracking input, it starts by itself. Any input ends it.
- **Settings window:** **Cinematic View: settings** in the macros menu, or the **FlyWithLua/cinematic_view/settings** command.

Other commands you can bind:

| Command | Does |
| --- | --- |
| `FlyWithLua/cinematic_view/next_shot` | Cut to the next shot now |
| `FlyWithLua/cinematic_view/toggle_afk` | Turn auto-start when away on or off |
| `FlyWithLua/cinematic_view/cycle_mode` | Mixed → outside only → cockpit only |

## Shots

Outside the aircraft:

- **Chase cam** — behind and above, lagging a little through turns, leaning into banks and sitting on the flight path in climbs and descents.
- **Long lens** — far behind and off to one side with a telephoto zoom and a slight hand-held wobble, like a broadcast shot.
- **Tracking** — alongside, sliding from the nose to the tail (or back).
- **Flyby** — a camera waiting beside the flight path ahead; the aircraft passes it, zooming to keep it framed. At ground level when you're on or near the ground. Only while moving.
- **Orbit** — a slow circle around the aircraft, showroom style.
- **Pass-by** — starts ahead looking back at the nose, then swings out to the side as the aircraft overtakes it.
- **Tail mount**, **Wing mount**, **Nose boom** — cameras fixed to the airframe that pitch and roll with it.
- **Drone** — high overhead, slowly turning.

Inside the cockpit:

- **Pilot's eye** — slowly looking around from the pilot's seat.
- **Over the shoulder** — from behind the pilot's seat, looking forward.
- **Side window** — looking out of the pilot's side window.
- **Panel** — leaning in and panning across the instruments.
- **Co-pilot's seat** — from the other seat, looking across (side-by-side cockpits only).

Shots are picked at random, weighted, without repeating the last few, and sized to the aircraft (from its size, or its maximum weight if X-Plane doesn't report one). Cameras never go below the ground.

## Settings

Changed in the settings window, or in `cinematic_view.ini` next to the script (written when you change something):

| Setting | Default | |
| --- | --- | --- |
| `afk_enabled` | `true` | Start by itself when you're away |
| `afk_timeout` | `120` | Seconds without input before it starts |
| `afk_when_paused` | `true` | Also start while the sim is paused |
| `mode` | `mixed` | `mixed`, `outside` or `cockpit` |
| `cockpit_share` | `30` | Percent of shots in the cockpit in mixed mode |
| `shot_min`, `shot_max` | `7`, `14` | Shot length range, seconds |
| `letterbox` | `true` | Cinema bars top and bottom |
| `fades` | `true` | Dip to black when switching between inside and outside, and now and then between other shots |
| `caption` | `true` | Shot name, aircraft, altitude and ground speed in the bars |
| `manual_exit_on_input` | `false` | Any input also ends a cinematic you started yourself |
| `joystick_deadband` | `0.03` | How far an axis must move to count as input (raise it for noisy hardware) |

## How it works

- **Outside shots** take control of X-Plane's camera through the plugin SDK's `XPLMControlCamera`, called from Lua through LuaJIT's FFI, which FlyWithLua NG+ includes. The camera is worked out in X-Plane's camera callback from where the aircraft is that frame, so it keeps up with the aircraft at speed, and terrain probes keep it above the ground. The view underneath is X-Plane's chase view, so you hear the outside sounds.
- **Cockpit shots** switch to the 3D cockpit and move the pilot's head (`sim/graphics/view/pilots_head_*`), so cockpit lighting, sounds and reflections stay right.
- If the SDK library can't be loaded, outside shots fall back to X-Plane's own chase, circle and flyby (still spot/linear spot) views.
- **Ending a cinematic** puts back the view and head position you had. If you pick a view yourself during one, it stops and leaves you in that view.
- **Being a good neighbour:** if another plugin (X-Camera, say) takes the camera, it stops rather than fighting for it, and won't start by itself again until you're back. If FlyWithLua stops running scripts, the camera is handed back to X-Plane within a few seconds. Not available in VR.

## Testing without X-Plane

[`test/run.sh`](test/run.sh) builds a mock of X-Plane's SDK library (`test/xplm_mock.c`), runs the script in a simulated FlyWithLua with and without the SDK, flying a simulated aircraft through cruise, takeoff and parked-and-paused, and checks the camera math against X-Plane's conventions. It needs `luajit` and a C compiler:

```bash
xplane/test/run.sh
```

It can't show what the shots look like in X-Plane, only that they keep the aircraft in frame at sensible distances, never go below the ground, and that starting, stopping, input, view changes and settings behave.
