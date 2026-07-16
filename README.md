# Masher

First-person real-time dungeon crawler POC (Godot 4.6).

## Stack

- **Engine:** Godot 4.6 (Forward+)
- **Art:** KayKit Dungeon Remastered + Skeletons (CC0)
- **Audio:** Kenney impact / RPG / UI packs (CC0), plus a short generated ambient loop
- **Layout:** Multilayer hybrid procgen inside a 3D harness (creation UI on boot)

## Run

Open `C:\Projekte\Masher` in Godot 4.6, or use `start.bat`.

### Controls

- **WASD** move
- **Mouse** look
- **LMB** melee attack
- **Esc** free / capture mouse
- **F1** dungeon ASCII map
- **R** return to create screen after death or clearing the exit

## Loop

Create screen (harness meters / presets / seed) → **Generate** → explore multilayer dungeon → exit orb or death → **R** back to create.
Dev button **Fixed POC** still loads the hand-placed atrium layout.

## Module contract

See `scripts/dungeon/module_contract.gd` and `scripts/procgen/README.md`.
Gameplay finds `player_spawn`, `enemy_spawn`, and `exit` groups — never hardcodes world positions.

## ASCII room specs

Rooms are authored as layered ASCII in `rooms/*.room.txt` (one map per floor).
Pipeline: parse → validate → bake (`scripts/dungeon/spec/`).

```text
# id: example
# cell: 2.0
# layer_height: 4.0
# open: E

layer 0
####
#P. 
#.S 
####

layer 1
####
#..#
#. #
####
```

Legend: `#` wall · `.` floor · space void · `S` stair · `P` spawn · `E` exit · `M` enemy

Validate all rooms headless:

```powershell
godot --path . --headless -s res://scripts/dev/validate_rooms.gd
```
