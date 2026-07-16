class_name LootTable
extends RefCounted
## Weighted item rolls for chests and enemy drops.

const _Items := preload("res://scripts/progression/item_catalog.gd")
const _ItemDef := preload("res://scripts/progression/item_def.gd")


static func roll_chest(rng: RandomNumberGenerator) -> Array[StringName]:
	## 1–2 books, bias toward combat books.
	var count := 1 if rng.randf() < 0.55 else 2
	var out: Array[StringName] = []
	for _i in count:
		out.append(_roll_book(rng, 0.45, 0.4, 0.15))
	return out


static func roll_enemy_drop(rng: RandomNumberGenerator, drop_chance: float) -> Array[StringName]:
	if rng.randf() > drop_chance:
		return []
	return [_roll_book(rng, 0.4, 0.4, 0.2)]


static func _roll_book(
	rng: RandomNumberGenerator,
	spell_w: float,
	skill_w: float,
	health_w: float
) -> StringName:
	var t := spell_w + skill_w + health_w
	var r := rng.randf() * t
	var kind: int = _ItemDef.Kind.SPELL_BOOK
	if r < spell_w:
		kind = _ItemDef.Kind.SPELL_BOOK
	elif r < spell_w + skill_w:
		kind = _ItemDef.Kind.SKILL_BOOK
	else:
		kind = _ItemDef.Kind.HEALTH_BOOK
	var ids: Array[StringName] = _Items.book_ids_for_kind(kind)
	assert(not ids.is_empty(), "LootTable: empty book list")
	return ids[rng.randi_range(0, ids.size() - 1)]
