# Cinematic View for X-Plane 12

A [FlyWithLua NG+](https://forums.x-plane.org/index.php?/files/file/82888-flywithlua-ng-next-generation-plus-edition-for-x-plane-12-win-lin-mac/) script that turns X-Plane's camera into a self-directing cinematic camera, like the attract modes in the Need for Speed and Forza Horizon games. It cuts between shots outside the aircraft and inside the cockpit, with letterbox bars and fades.

It can be switched on and off whenever you like, and it starts by itself after a while with no input (two minutes by default). Pressing a key, moving the mouse or touching the joystick ends it and puts you back in the view you were in. X-Plane's zoom keys (+ and -) zoom the cinematic camera without ending it.

## Install

1. Install FlyWithLua NG+ for X-Plane 12 if you don't have it.
2. Copy [`FlyWithLua/Scripts/cinematic_view.lua`](FlyWithLua/Scripts/cinematic_view.lua) to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`.
3. Start X-Plane, or choose **Plugins → FlyWithLua → Reload all Lua script files**.

## Use

Everything is in one window: **Plugins → FlyWithLua → FlyWithLua Macros → Cinematic View**. It has **Start now / Stop** and **Next shot** buttons, all the settings, and a key for each action.

- **Start/stop by hand:** with the button, or a key you set in the window. A cinematic you start yourself keeps running while you use the controls (the autopilot is a good idea) until you stop it or pick another view.
- **When you're away:** after the away time (2 minutes by default) with no keyboard, mouse, joystick or head-tracking input, it starts by itself. Any input ends it, except the zoom keys and the keys you've set for the cinematic.
- **Zoom:** hold **=** / **+** to zoom in and **-** to zoom out (main keyboard or keypad). In outside shots this zooms the cinematic camera, and the zoom carries on into the next outside shots until the cinematic ends. In the cockpit the keys go to X-Plane's own zoom.

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

**Camera speed** sets how fast the cameras move: orbits, drone turns, pans across the panel and look-arounds turn faster or slower, and tracking and pass-by shots cover more or less ground in the same time. It takes effect from the next shot. The flyby is the exception: there the aircraft does the moving.

## Settings

Changed in the window, or in `cinematic_view.ini` next to the script (written when you change something):

| Setting | Default | |
| --- | --- | --- |
| `afk_enabled` | `true` | Start by itself when you're away |
| `afk_timeout` | `120` | Seconds without input before it starts |
| `afk_when_paused` | `true` | Also start while the sim is paused |
| `mode` | `mixed` | `mixed`, `outside` or `cockpit` |
| `cockpit_share` | `30` | Percent of shots in the cockpit in mixed mode |
| `shot_min`, `shot_max` | `7`, `14` | Shot length range, seconds |
| `camera_speed` | `1.0` | How fast cameras move, pan and orbit, from `0.25` to `2.5` |
| `letterbox` | `true` | Cinema bars top and bottom |
| `fades` | `true` | Dip to black when switching between inside and outside, and now and then between other shots |
| `manual_exit_on_input` | `false` | Any input also ends a cinematic you started yourself |
| `joystick_deadband` | `0.03` | How far an axis must move to count as input (raise it for noisy hardware) |
| `bind_toggle`, `bind_next_shot`, `bind_toggle_afk`, `bind_cycle_mode`, `bind_zoom_in`, `bind_zoom_out`, `bind_settings` | empty | The keys set in the window, as `<virtual key code> <modifiers> <name>` (modifiers: 1 Shift, 2 Ctrl, 4 Alt); easiest set from the window |

## How it works

- **Outside shots** take control of X-Plane's camera through the plugin SDK's `XPLMControlCamera`, called from Lua through LuaJIT's FFI, which FlyWithLua NG+ includes. The camera is worked out in X-Plane's camera callback from where the aircraft is that frame, so it keeps up with the aircraft at speed, and terrain probes keep it above the ground. The view underneath is X-Plane's chase view, so you hear the outside sounds.
- **Cockpit shots** switch to the 3D cockpit and move the pilot's head (`sim/graphics/view/pilots_head_*`), so cockpit lighting, sounds and reflections stay right.
- **Zoom:** X-Plane's own zoom can't act on a camera a plugin controls, so in outside shots the script catches + and - and zooms its camera itself. In the cockpit the keys go through to X-Plane, and a key or joystick button set for zoom holds X-Plane's `sim/general/zoom_in`/`zoom_out` commands.
- **Keys** set in the window are caught with FlyWithLua's keyboard sniffer, which runs before X-Plane's own key bindings.
- If the SDK library can't be loaded, outside shots fall back to X-Plane's own chase, circle and flyby (still spot/linear spot) views.
- **Ending a cinematic** puts back the view and head position you had. If you pick a view yourself during one, it stops and leaves you in that view.
- **Being a good neighbour:** if another plugin (X-Camera, say) takes the camera, it stops rather than fighting for it, and won't start by itself again until you're back. If FlyWithLua stops running scripts, the camera is handed back to X-Plane within a few seconds. Not available in VR.

## Testing without X-Plane

[`test/run.sh`](test/run.sh) builds a mock of X-Plane's SDK library (`test/xplm_mock.c`), runs the script in a simulated FlyWithLua with and without the SDK, flying a simulated aircraft through cruise, takeoff and parked-and-paused, and checks the camera math against X-Plane's conventions. It needs `luajit` and a C compiler:

```bash
xplane/test/run.sh
```

It can't show what the shots look like in X-Plane, only that they keep the aircraft in frame at sensible distances, never go below the ground, and that starting, stopping, input, view changes, zoom, keys and settings behave.
