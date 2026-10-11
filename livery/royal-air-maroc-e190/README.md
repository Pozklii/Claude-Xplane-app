# Royal Air Maroc E190 livery (X-Plane 12, 8K)

Royal Air Maroc livery (CN-RGO) for an Embraer E190 in X-Plane 12.

**Status:** the design is done; the textures are not built yet. The fuselage
and tail textures have to follow the exact UV layout of the E190 model, so
they need that model's paint kit (or one of its stock liveries) before they
can be built.

- `artwork/ram_e190_profile_8k.png`: 8192 px left-side profile of the full design (transparent background)
- `artwork/ram_e190_profile_preview.jpg`: the same profile on a sky background
- `artwork/ram_tail_logo_4k.png`, `ram_title_en.png`, `ram_title_ar.png`, `ram_reg.png`: the livery elements, transparent
- `tools/geometry.py`: band boundaries, outline, windows, doors and title positions traced from the reference photo
- `tools/elements.py`, `tools/profile.py`: render the elements and the profile

Regenerate (needs Pillow and NumPy):

```sh
python3 tools/elements.py artwork fonts
python3 tools/profile.py artwork artwork/ram_e190_profile_8k.png
```

Fonts: Outfit and Aref Ruqaa, both SIL Open Font License (see `fonts/`).
