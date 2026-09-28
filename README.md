# Heroes of Four Seasons

An abstract, Heroes-of-Might-and-Magic-style strategy game built from a design
document: four factions (Alpha, Beta, Gamma, Delta) with four tiers each, an
action-based "rows and engagements" battle system, and an overworld of 20×20
cards where every card has its own explorable interior.

Made with **Godot 4.3** (GDScript, GL Compatibility renderer).

## Download & play (Windows)

Every push to `main` builds a fresh Windows executable automatically.
Go to **Releases → Latest build** and download `HeroesOfFourSeasons.exe`.
Just run it — nothing to install. Saved games go into a `saves` folder next
to the exe.

## Run from source

1. Install [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) (standard, not .NET).
2. Open Godot → **Import** → pick this folder's `project.godot`.
3. Press **F5** to play.

## Where things live

| Path | What |
|---|---|
| `data/data.json` | **All the rules data** — unit stats, spells, terrain, skills, artifacts, prices, config. Edit this to tune the game. |
| `scripts/rules/` | Pure game rules: `battle.gd` (combat engine), `combat_ai.gd`, `units.gd`, `heroes.gd`, `army.gd`, `world_gen.gd`, `world.gd` |
| `scripts/game.gd` | Game controller: turns, walking, sites, battles, saves |
| `scripts/ui/` | Screens: menu, sandbox, battle, overworld, town, army/hero dialogs, music |
| `music/` | Soundtrack (terrain themes on the map, town theme in towns) |
| `tests/` | Headless tests (`godot --headless --path . -- --test=<name>`) |
| `prototype-js/` | The original browser prototype the port was made from (reference only; Godot ignores it) |

## Tests

```
godot --headless --path . -- --test=worldgen_selfcheck   # quick sanity check (also run in CI)
godot --headless --path . -- --test=playthrough          # autopiloted 35-day hotseat game
```

`tests/parity.gd` + `tests/compare_parity.py` check that the Godot combat engine
produces exactly the same battles as the JS prototype (300/300 identical), and
`tests/worldgen.gd` + `tests/compare_world.py` do the same for map generation.

## Design flags

Anything the design doc left open is listed in-game under **Design flags** on
the main menu (and in `data/data.json` → `FLAGS`).
