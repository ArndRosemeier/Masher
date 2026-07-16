class_name AbilityCatalog
extends RefCounted
## Static registry of v1 fighting abilities.

const _AbilityDef := preload("res://scripts/progression/ability_def.gd")
const _Loud := preload("res://scripts/core/loud_error.gd")


static func all() -> Array:
	var out: Array = []
	out.append(_spell(&"firebolt", "Firebolt", 18.0, 0.55, 28, 0.0, "Hitscan fire bolt."))
	out.append(_spell(&"frost_nova", "Frost Nova", 32.0, 2.2, 18, 3.2, "Cold burst around you."))
	out.append(_spell(&"arc_shield", "Arc Shield", 28.0, 6.0, 0, 0.0, "Absorb the next hits briefly."))
	out.append(_skill(&"power_strike", "Power Strike", 22.0, 1.1, 45, 2.8, "Heavy melee smash."))
	out.append(_skill(&"whirlwind", "Whirlwind", 30.0, 2.5, 22, 2.6, "Spin and hit nearby foes."))
	out.append(_skill(&"bash", "Bash", 18.0, 1.4, 20, 2.4, "Knock foes back hard."))
	return out


static func by_id(id: StringName):
	for def in all():
		if def.id == id:
			return def
	_Loud.report("AbilityCatalog", "Unknown ability id: %s" % String(id))
	return null


static func spell_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def in all():
		if def.kind == _AbilityDef.Kind.SPELL:
			out.append(def.id)
	return out


static func skill_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def in all():
		if def.kind == _AbilityDef.Kind.SKILL:
			out.append(def.id)
	return out


static func _spell(
	id: StringName,
	name: String,
	cost: float,
	cd: float,
	dmg: int,
	radius: float,
	desc: String
):
	var d = _AbilityDef.new()
	d.id = id
	d.display_name = name
	d.kind = _AbilityDef.Kind.SPELL
	d.base_cost = cost
	d.base_cooldown = cd
	d.base_damage = dmg
	d.base_radius = radius
	d.description = desc
	return d


static func _skill(
	id: StringName,
	name: String,
	cost: float,
	cd: float,
	dmg: int,
	radius: float,
	desc: String
):
	var d = _AbilityDef.new()
	d.id = id
	d.display_name = name
	d.kind = _AbilityDef.Kind.SKILL
	d.base_cost = cost
	d.base_cooldown = cd
	d.base_damage = dmg
	d.base_radius = radius
	d.description = desc
	return d
