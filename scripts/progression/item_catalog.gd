class_name ItemCatalog
extends RefCounted
## Books and consumables used by inventory / loot.

const _Abilities := preload("res://scripts/progression/ability_catalog.gd")
const _ItemDef := preload("res://scripts/progression/item_def.gd")
const _Loud := preload("res://scripts/core/loud_error.gd")


static func all() -> Array:
	var out: Array = []
	for ability_id in _Abilities.spell_ids():
		var ab = _Abilities.by_id(ability_id)
		out.append(_book(
			StringName("book_%s" % String(ability_id)),
			"%s Tome" % ab.display_name,
			_ItemDef.Kind.SPELL_BOOK,
			ability_id,
			0,
			"Read to learn or upgrade %s." % ab.display_name
		))
	for ability_id2 in _Abilities.skill_ids():
		var ab2 = _Abilities.by_id(ability_id2)
		out.append(_book(
			StringName("book_%s" % String(ability_id2)),
			"%s Manual" % ab2.display_name,
			_ItemDef.Kind.SKILL_BOOK,
			ability_id2,
			0,
			"Read to learn or upgrade %s." % ab2.display_name
		))
	out.append(_book(
		&"book_vital_codex",
		"Vital Codex",
		_ItemDef.Kind.HEALTH_BOOK,
		&"",
		15,
		"Read to increase maximum health."
	))
	return out


static func by_id(id: StringName):
	for def in all():
		if def.id == id:
			return def
	_Loud.report("ItemCatalog", "Unknown item id: %s" % String(id))
	return null


static func book_ids_for_kind(kind: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for def in all():
		if int(def.kind) == kind:
			out.append(def.id)
	return out


static func _book(
	id: StringName,
	name: String,
	kind: int,
	ability_id: StringName,
	health_bonus: int,
	desc: String
):
	var d = _ItemDef.new()
	d.id = id
	d.display_name = name
	d.kind = kind
	d.ability_id = ability_id
	d.health_bonus = health_bonus
	d.description = desc
	return d
