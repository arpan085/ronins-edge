# Ronin's Edge

A samurai open-world action game made with **Godot 4.3**: posture-and-deflect
sword combat, stealth, a horse, weather, day and night, and a story across a
hand-built valley.

## Play it

The playable build is **`RoninsEdge_v23_play.zip`** (about 143 MB), attached
to the project's Notion page (*Ronin's Edge — Samurai Game*). In Godot 4.3:
Project Manager, **Import**, pick the zip and choose an empty folder (or unzip
it and import `RoninsEdge/project.godot`). `README.txt` inside has the
controls; `WHATS_NEW.md` has the notes for every version.

## What is in this repository

- `game/` is the Godot project's source: every script, scene, shader and
  document (`WHATS_NEW.md`, `CREDITS.md`, `README.txt`).
- `tools/` holds the asset and packaging scripts (`pack.py` builds the zips).
- `v3/` is the old Blender animation pipeline (v0.3 era), kept for history.

Binary assets (models, textures, audio, about 130 MB) and the 1.3 MB
`world.json` terrain file are **not** in git. To get a working project, unzip
the play build and copy this repository's `game/` over its `RoninsEdge/`
folder (or simply use the zip as it is).

## Tests

Run headless from the project folder:

```
godot --headless --path . res://tests/TestRunner.tscn   # unit checks
godot --headless --path . res://tests/AdvQA.tscn        # stealth and combat
godot --headless --path . res://tests/PlayerQA.tscn     # player moves
godot --headless --path . res://tests/HorseQA.tscn      # the horse's tail, dust, breath (v0.23)
godot --headless --path . res://tests/PrologueQA.tscn -- log   # the opening cinematic (v0.23)
godot --headless --path . -s tools/check_scripts.gd     # every script compiles
```

v0.23: unit tests 75 / 0, stealth and combat 86 / 0, player 129 / 0, horse 14 / 0,
v0.23 checks 21 / 0, the full prologue run 8 / 0, and all 109 scripts compile. Every build so
far has been checked with software rendering and headless runs only, not
played on a GPU.

## Licences

Third-party tracks, sounds, textures, models and fonts are listed with their
sources and licences in `game/CREDITS.md` (CC0, except the fonts, SIL OFL, and
the wolf model, CC-BY 4.0 by CoinCoin).
