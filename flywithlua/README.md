# Cinematic Views for X-Plane 12

A [FlyWithLua NG+](https://github.com/X-Friese/FlyWithLua) script for screenshots and videos. It's an automatic cinematic camera that works outside and inside the aircraft, and every view is always slowly moving:

- **Outside:** a wide shot of the whole aircraft, or a close-up of one part of it.
- **Inside:** a pilot's head looking around the cockpit, as a real pilot would.

Step through 19 shots or generate endless random ones. Nothing is ever drawn over the picture.

Everything is in one file, [`Cinematic_Views.lua`](./Cinematic_Views.lua).

## Install

1. Install FlyWithLua NG+ for X-Plane 12 if you don't have it yet.
2. Copy `Cinematic_Views.lua` to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`, replacing any older copy.
3. Start a flight, or use **Plugins → FlyWithLua → Reload all Lua script files** if X-Plane is already running.

Open **Plugins → FlyWithLua → FlyWithLua Macros → Cinematic Views**. That's the script's only menu entry, and it opens and closes the window. Once your keys or joystick buttons are assigned, you don't need the window to film.

Only run one camera script at a time. If you also have other cinematic camera scripts installed (for example `CineCam.lua` or `cinematic_camera.lua`), they'll fight over the camera.

## The window

The window is small and holds the basics:

- **A row of buttons:**
  - **Camera ON/OFF**
  - **< Previous** and **Next >**
  - **Random**, for a new random view
  - **Save**, which keeps the random view on screen. On a saved shot it becomes **Delete**.
- **Your controls:** a key or joystick button for **Camera on/off**, **Next view**, **Previous view** and **New random view**.
  - Press **Assign**, then the key or button you want. **Esc** cancels.
  - Assigned keys only control the camera, so X-Plane won't also act on them.
  - X-Plane still sees joystick buttons, so pick ones that have no X-Plane assignment.
  - + and − can't be assigned, because they're kept for zoom.
- **Sliders:**
  - **Camera distance**
  - **Camera shake**
  - **Shot transition:** the glide between related shots, 0 for a hard cut
  - **Cockpit head movement**
  - **Aircraft size:** a correction for the aircraft you're flying, remembered for it

Everything saves automatically to `Cinematic_Views.ini` next to the script.

## Shots

### Exterior

Every exterior shot is either a **wide shot** of the whole aircraft or a **close-up** of one part, and the camera never stops moving.

- **Movement:** the camera drifts slowly round a small ellipse, around the subject and up and down at the same time, while easing in and out a little. In a turn it follows smoothly.
- **Framing:** the zoom keeps the whole aircraft, or the part, filling a steady share of the frame.

| Shot | What it shows |
| --- | --- |
| Wide: rear quarter | The whole aircraft from behind and to one side |
| Wide: front quarter | The whole aircraft from ahead and to one side |
| Wide: side profile | The whole aircraft side-on |
| Wide: high | The whole aircraft from above |
| Wide: low front | The whole aircraft from low and ahead, looking up |
| Close-up: cockpit | The cockpit windows, from ahead |
| Close-up: nose | The nose |
| Close-up: engine | An engine (under the wing on twins and four-engine aircraft, in the nose on light singles) |
| Close-up: wing | A wing, from above and behind or from ahead |
| Close-up: wingtip | A wingtip |
| Close-up: tail | The tail fin |
| Close-up: main gear, nose gear | The landing gear, only while it's down |

Each shot picks a side, left or right, and varies its movement a little every time it starts, so it never looks quite the same twice.

- **Fitting the aircraft:** the script reads the aircraft's span and length from X-Plane, checks them against its weight, and works out whether they're in metres or feet. If X-Plane doesn't provide usable dimensions, it estimates the size from the weight instead. Each part's position comes from those dimensions.
- **Close-ups never clip:** the camera sits just outside a box around the airframe, as close to the part as it can get, and the zoom does the rest.
- **Adjusting:** if close-ups miss their part on an aircraft, adjust **Aircraft size**. The correction is remembered for that aircraft.
- **Limits:** X-Plane doesn't tell scripts where the engines are, so the engine close-up assumes under-wing engines on twins and four-engine aircraft. On aircraft with tail-mounted engines (most business jets, the CRJ), it shows the wing instead. Three-engine aircraft don't get an engine close-up.

### Cockpit

Cockpit shots move the pilot's head the way a real pilot looks around. Each one focuses on a part of the cockpit:

| Shot | Where it looks |
| --- | --- |
| Pilot's scan | Outside, then the flight display, the nav display and back. It's a pilot's normal scan, with the odd look at the glareshield, the centre panel or out of the side window. |
| Instrument panel | Your flight and nav displays and the centre panel |
| Overhead panel | The overhead panel (airliners and larger aircraft only) |
| Throttle and pedestal | The throttle quadrant and the FMC |
| Side window | Out of your side window |
| Autopilot and FMC | The autopilot panel on the glareshield and the FMC |

How the head moves:

- It fixes on a spot and reads it with small movements, sometimes moving to another spot on the same panel.
- It turns to the next spot smoothly, with a slight overshoot that settles. Big turns take a little longer, and it never turns faster than a real head.
- It leans a few centimetres toward what it's reading: forward to the pedestal, back for the overhead, toward the window to look out.
- It breathes, and responds a little to G-forces, turbulence, a firm touchdown and runway rumble.

Where things are comes from typical cockpit layouts, adjusted for the side of the cockpit you sit on. **Cockpit head movement** sets how lively the head is; at 0 it only turns.

Cockpit shots can't clip through the aircraft. The head never moves more than 8 cm sideways, 5 cm up, 4 cm down, 8 cm forward or 6 cm back from the seat. That keeps the view inside the cockpit, clear of the panel, the seat and the walls.

The eye point is your head position when filming starts in the cockpit, so start from your normal seat view. When you stop, your head goes back exactly where it was.

## Random shots

**Random** (or your assigned key or button) makes a new view every time, built from the same pieces:

- **Outside:** a wide shot from any angle, or a close-up of any part the aircraft has right now. Each has its own slow movement, framing and camera style, from drone-smooth to a gentle handheld feel.
- **In the cockpit:** a new mix of places to look at and how long to look at them.

Like every shot, random views can't clip through the aircraft: exterior cameras stay outside the box around the airframe and above the ground, and cockpit views stay in the safe space around the seat.

If you like a random view, press **Save**. It joins **Next / Previous** after the built-in shots and is kept between sessions. **Next** from a random view carries on through the list from the last listed shot you watched.

Shots saved with version 3 are dropped, because views now work differently.

## Zoom

- **Exterior shots:** + (or =) and − zoom the camera, top row or keypad. The zoom is smooth like X-Plane's own: it glides rather than jumping. Holding zooms at a steady rate and eases to a stop when you let go, and Shift zooms faster. The mouse wheel and X-Plane's zoom commands (for example on a joystick) zoom it the same way. Your zoom is on top of the shot's own framing and is remembered for each shot. Switching shots goes straight to the new shot's zoom.
- **Cockpit shots:** +, − and the mouse wheel are X-Plane's own zoom, exactly as normal.
- **When you're not filming,** the script doesn't touch +, − or the mouse wheel at all.

## Commands

You can also bind commands in X-Plane's **Settings → Keyboard** or **Joystick**: search for `cinematic`. Every command starts with `FlyWithLua/cinematic_views/`.

| Command | Action |
| --- | --- |
| `toggle` | Camera on (with your last shot) or off |
| `stop` | Stop and return to your view |
| `next_shot`, `previous_shot` | Next or previous view, including your saved shots; with the camera off they start it with your last shot |
| `random_view`, `random_exterior`, `random_cockpit` | A new random view (exterior or cockpit, or either) |
| `save_shot` | Save the random view on screen |
| `shot_<name>` | A specific shot: `wide_rear`, `wide_front`, `wide_side`, `wide_high`, `wide_low`, `close_cockpit`, `close_nose`, `close_engine`, `close_wing`, `close_wingtip`, `close_tail`, `close_gear`, `close_nosegear`, `scan`, `panel`, `overhead`, `throttle`, `window`, `autopilot` |
| `orbit_left`, `orbit_right`, `camera_up`, `camera_down`, `zoom_in`, `zoom_out` | Adjust the live shot while held |
| `reset_adjustments` | Undo those adjustments for the current shot |
| `toggle_window` | Show or hide the window |

## Tips

- For video, fly or load a flight, then film X-Plane's replay. The script reads the aircraft's motion directly in replays.
- The camera keeps moving while the sim is paused, so you can pause for screenshots.
- If you start from the cockpit, stopping takes you back to it. If you change the view yourself (a view key, or the View menu), the script hands the camera straight back to you.
- It switches itself off in VR.

## How it works

Exterior shots use the SDK's `XPLMControlCamera` through LuaJIT's FFI. The camera callback reads the aircraft position itself, so the camera never lags the drawn aircraft. A terrain probe keeps every camera above the ground. Engine close-ups use `sim/aircraft/engine/acf_num_engines`. Gear close-ups use `sim/flightmodel2/gear/deploy_ratio`; without it, they assume the gear is down on the ground and below 300 m.

Cockpit shots write the `sim/graphics/view/pilots_head_*` datarefs, clamped to the safe space around the seat.

Keys, the mouse wheel and joystick buttons use FlyWithLua's own key and wheel hooks and X-Plane's joystick button values. The script only holds back a key or the wheel when it uses them. X-Plane's zoom commands are taken over only during exterior shots. The script draws nothing on screen.

When you stop, or reload scripts, the script releases the camera and the zoom commands and puts your head back. If FlyWithLua stops running the script for any reason, it releases them on its own.

If something isn't working, look for lines starting with `Cinematic Views:` in X-Plane's `Log.txt`.

## Tests

`test/run_tests.sh` runs the script under LuaJIT against a small C stand-in for X-Plane's SDK (`test/mock_xplm.c`). Keys and the wheel are delivered the way FlyWithLua 2.8 delivers them. The tests fly simulated taxi, takeoff, cruise, approach and landing segments and check a range of behaviour:

- Every exterior shot keeps its subject in frame, with the whole aircraft in a wide shot. Its camera keeps moving, stays outside the aircraft and above the ground, and close-ups fill the frame with their part. This holds for taxiing, a takeoff roll, a banked turn and an approach.
- Cockpit shots, listed and random, stay in the safe space around the seat through takeoff rolls, turbulence and firm landings. They turn smoothly at head-like speeds, never freeze, and look where they should, for example the overhead panel most of the time in the overhead shot.
- Hundreds of random shots, across many random seeds, pass the same checks. Saved shots survive the settings file.
- Key and joystick assignments work, and + and − and the mouse wheel do the right thing inside, outside and when not filming. Zoom glides with no jumps from frame to frame, and it's remembered per shot.
- Shots fit both an airliner and a glider, transitions go round the aircraft, view changes hand the camera over correctly, and your head is restored.
- Pause, replay, the window and saved settings work, and nothing is drawn over the picture.

The tests need `cc` and `luajit`. Because they run against a mock, they check the script's logic but not X-Plane's own behaviour, so try changes in the sim too.
