# Royal Air Maroc E190 livery (X-Plane 12, 8K)

Royal Air Maroc livery (CN-RGO) for an Embraer E190 in X-Plane 12.

**Status:** the 8K fuselage and tail textures are built for the X-Crafts
E-Jets Family E190. They are derived from the X-Crafts paint kit, so they live
in the private `Pozklii/190` repo (branch `royal-air-maroc-livery`), not here.

- `artwork/ram_e190_profile_8k.png`: 8192 px left-side profile of the full design (transparent background)
- `artwork/ram_e190_profile_preview.jpg`: the same profile on a sky background
- `artwork/ram_tail_logo_4k.png`, `ram_title_en.png`, `ram_title_ar.png`, `ram_reg.png`: the livery elements, transparent
- `tools/geometry.py`: band boundaries, outline, windows, doors and title positions traced from the reference photo
- `tools/elements.py`, `tools/profile.py`: render the elements and the profile

Regenerate (needs Pillow, NumPy and SciPy):

```sh
python3 tools/elements.py artwork fonts
python3 tools/profile.py artwork artwork/ram_e190_profile_8k.png
```

### Building the X-Plane textures (`kit-tools/`)

Run from a working folder next to the extracted kit PSDs (needs
`psd-tools[composite]`, SciPy):

```sh
python3 kit-tools/extract.py "E-JETS_PAINTKIT_FUSELAGE 25-02-05.psd" "E-JETS_PAINTKIT_TAIL 22-08-28.psd" "E-JETS_PAINTKIT_BELLY_E19X 22-08-28.psd"
python3 kit-tools/base_fus.py "E-JETS_PAINTKIT_FUSELAGE 25-02-05.psd" layers/fus_base_e190.png
python3 kit-tools/base_generic.py "E-JETS_PAINTKIT_TAIL 22-08-28.psd" layers/tail_base.png "BASE TEXTURE" "TOP LAYER"
python3 kit-tools/base_generic.py "E-JETS_PAINTKIT_BELLY_E19X 22-08-28.psd" layers/belly_base.png "BASE TEXTURE" "TOP LAYER"
python3 kit-tools/kitart.py "E-JETS_PAINTKIT_FUSELAGE 25-02-05.psd" kitart
python3 kit-tools/paint_fus.py tools fonts layers
python3 kit-tools/paint_tail.py tools layers
python3 kit-tools/combine.py layers/fus_base_e190.png layers/fus_paint8.png fuselage.png
python3 kit-tools/combine.py layers/tail_base.png layers/tail_paint8.png TAIL.png
python3 kit-tools/paint_belly.py tools layers/belly_base.png belly.png
python3 kit-tools/paint_registration.py "E-JETS_PAINTKIT_REGISTRATION 23-11-02.psd" fonts REGISTRATION.png
```

`REGISTRATION.png` (the cockpit placard and the registration under the left
wing) goes in `objects/E190/`, with a copy in `objects/`. In the livery folder
the fuselage and belly go in `objects/E190/`, while `TAIL.png` goes
in `objects/` itself: the E-Jets share one tail texture across variants.

The fuselage is mapped from the photo using the cabin windows as anchors: both
sections share one smooth station curve through them, meeting at the same
station where the sections join. On
the tail cone, where the texture is cut into strips by darts, the angle
around the fuselage runs evenly across each strip between its seams, whose
angles are fixed by the dart tips and whose edges are taken from the kit's
wireframe, not its padded paint mask (`stringers.py`). The ventral antenna,
packed beside the lower strip, is painted in the belly's colour, and the
belly fairing takes the same white as the fuselage. Each fin side uses a
smooth thin-plate-spline map through five points (`finmap.py`). The paint is carried a few texels past each
strip into the empty gutter around it, so the sim's texture filtering doesn't
blend white into the seams. `check_slivers.py` (same arguments as `paint_fus.py`
minus the output) lists every colour band under 2.5 px wide in the design: the
pointed tips are meant to be there, anything else is two shapes that should
share an edge but don't. `dump.py` and `tree.py` inspect a PSD's layers.

Fonts: Outfit, Barlow (the registrations) and Aref Ruqaa, all SIL Open Font
License (see `fonts/`).
