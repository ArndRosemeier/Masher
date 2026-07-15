# Masher

First-person real-time dungeon crawler POC (Godot 4.6).

## Stack

- **Engine:** Godot 4.6 (Forward+)
- **Art:** KayKit Dungeon Remastered + Skeletons (CC0)
- **Audio:** Kenney impact / RPG / UI packs (CC0), plus a short generated ambient loop
- **Layout:** Fixed modular dungeon for the POC; room-graph procgen ready (`LevelMode.GENERATED`)

## Run

Open `C:\Projekte\Masher` in Godot 4.6, or:

```powershell
& "C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64.exe" --path "C:\Projekte\Masher"
```

### Controls

- **WASD** move
- **Mouse** look
- **LMB** melee attack
- **Esc** free / capture mouse
- **R** restart after death or clearing the exit

## POC loop

Start room → corridors → combat room (skeletons) → exit (green orb). Die or reach the exit, then press **R**.

## Procgen switch

On `Main` → `RunManager`, set `level_mode`:

- `Fixed` (default POC layout)
- `Generated` (seedable `RoomGraphGenerator` using the same modules)

## Module contract

See `scripts/dungeon/module_contract.gd` and `scripts/procgen/README.md`.
Gameplay finds `player_spawn`, `enemy_spawn`, and `exit` groups — never hardcodes world positions.
