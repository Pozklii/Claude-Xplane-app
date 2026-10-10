# Cinematic Camera (FlyWithLua, X-Plane 12)

[`Scripts/cinematic_camera.lua`](./Scripts/cinematic_camera.lua) adds a cinematic camera mode to X-Plane 12. The camera moves slowly and smoothly close to your aircraft, so you can take screenshots or record video while it runs.

- **Outside views:** when an external view is active (chase, free camera and so on), the camera slowly orbits and drifts around the aircraft. There are 9 shots: front quarter, nose close-up, wing and engine, low wing root, tail orbit, low rear chase, overhead, left side flyby, and wingtip to fuselage.
- **Cockpit views:** when an internal view is active, the pilot's head pans slowly around the 3D cockpit. There are 9 shots: captain's scan, instrument panel, pedestal and throttles, overhead panel, left window, right window, over the shoulder, first officer's seat, and sky through the glass. A 2D panel view is switched to the 3D cockpit automatically. When the camera is deactivated, the head goes back to where it was.
- If you switch between an outside view and a cockpit view while the camera is running, it changes to the matching set of shots.

The camera is driven through X-Plane's own camera API, so X-Plane's normal screenshot key (`sim/operation/screenshot`) keeps working while the camera is active.

## Requirements

- X-Plane 12
- [FlyWithLua NG+](https://forums.x-plane.org/index.php?/files/file/82888-flywithlua-ng-next-generation-plus-edition-for-x-plane-12-win-lin-mac/) (needs the imgui floating windows and LuaJIT that it comes with)

## Install

Copy `Scripts/cinematic_camera.lua` into `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`. Then restart X-Plane, or use *Plugins → FlyWithLua → Reload all Lua script files*.

To open the control window, use *Plugins → FlyWithLua → FlyWithLua Macros → Cinematic Camera: show window*, or bind the `window` command below.

## Commands (key / joystick bindings)

To bind these, go to *Settings → Keyboard* (or *Joystick*) and search for "Cinematic".

| Command | Action |
| --- | --- |
| `FlyWithLua/CinematicCamera/toggle` | Turn the camera on or off |
| `FlyWithLua/CinematicCamera/next_view` | Next shot |
| `FlyWithLua/CinematicCamera/prev_view` | Previous shot |
| `FlyWithLua/CinematicCamera/screenshot` | Hide the control window, take an X-Plane screenshot, then show the window again |
| `FlyWithLua/CinematicCamera/window` | Show or hide the control window |

When the camera is off, next and previous choose the shot it will start on.

## Window controls

- **Activate / Deactivate**, **< Prev**, **Next >**, and **Screenshot**
- **Travel speed:** how fast the camera position moves along its path
- **Pan / look speed:** how fast the view pans across its subject
- **Smoothing:** camera inertia, in seconds
- **Handheld shake:** adds subtle handheld motion (0 keeps the camera rock steady)
- **Auto next shot:** moves on to the next shot after this many seconds (set it to 0 to turn this off)
- **Distance** and **Zoom:** for outside views only
- **Glide between shots:** moves smoothly to the next shot instead of cutting to it
- **Follow aircraft pitch & roll:** for outside views; by default the camera follows only the aircraft's heading, which keeps the horizon level
- **Hide this window while active**

Settings are saved to `cinematic_camera_settings.ini` next to the script.

## Notes

- Outside shots are sized from the aircraft's dimensions (`acf_size_x` / `acf_size_z`). If the camera sits too far from or too close to a particular aircraft, adjust **Distance**.
- Near the ground, the camera height is limited so it stays above the ground under the aircraft. This assumes the ground is flat.
- Cockpit shots move the head relative to the aircraft's default eye point. On some aircraft, X-Plane's cockpit head limits may stop the head short of where a shot puts it.
