class_name AbilityDef
extends RefCounted
## One castable combat ability (spell or skill).

enum Kind { SPELL, SKILL }

var id: StringName = &""
var display_name: String = ""
var kind: Kind = Kind.SPELL
var max_rank: int = 5
var base_cost: float = 20.0
var base_cooldown: float = 1.0
var base_damage: int = 20
var base_radius: float = 0.0
var description: String = ""


func cost_at(rank: int) -> float:
	var r := maxi(1, rank)
	## Slightly cheaper at higher ranks.
	return maxf(5.0, base_cost - float(r - 1) * 1.5)


func cooldown_at(rank: int) -> float:
	var r := maxi(1, rank)
	return maxf(0.35, base_cooldown - float(r - 1) * 0.08)


func damage_at(rank: int) -> int:
	var r := maxi(1, rank)
	return base_damage + (r - 1) * 8


func radius_at(rank: int) -> float:
	var r := maxi(1, rank)
	return base_radius + float(r - 1) * 0.35
