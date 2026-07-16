class_name PlayerProgression
extends Node
## Learned ability ranks + hotbar for the current dive.

const _Items := preload("res://scripts/progression/item_catalog.gd")
const _ItemDef := preload("res://scripts/progression/item_def.gd")
const _Abilities := preload("res://scripts/progression/ability_catalog.gd")
const _Loud := preload("res://scripts/core/loud_error.gd")

signal ranks_changed
signal hotbar_changed
signal toast(message: String)

const HOTBAR_SIZE := 4
const HEALTH_BOOK_BONUS := 15

## StringName -> int rank
var ranks: Dictionary = {}
## Fixed hotbar slots (ability ids or empty).
var hotbar: Array[StringName] = [&"", &"", &"", &""]


func clear() -> void:
	ranks.clear()
	hotbar = [&"", &"", &"", &""]
	ranks_changed.emit()
	hotbar_changed.emit()


func rank_of(ability_id: StringName) -> int:
	return int(ranks.get(ability_id, 0))


func read_book(item_id: StringName, health: Health) -> String:
	var item = _Items.by_id(item_id)
	assert(item != null, "PlayerProgression.read_book: bad item")
	match item.kind as int:
		_ItemDef.Kind.HEALTH_BOOK:
			var bonus: int = item.health_bonus if item.health_bonus > 0 else HEALTH_BOOK_BONUS
			health.set_max_health(health.max_health + bonus, true)
			var msg := "Max HP +%d (%d)" % [bonus, health.max_health]
			toast.emit(msg)
			return msg
		_ItemDef.Kind.SPELL_BOOK, _ItemDef.Kind.SKILL_BOOK:
			assert(item.ability_id != &"", "Book missing ability_id")
			var def = _Abilities.by_id(item.ability_id)
			assert(def != null, "Book ability missing")
			var prev := rank_of(item.ability_id)
			if prev >= def.max_rank:
				var capped := "%s already at max rank %d" % [def.display_name, def.max_rank]
				toast.emit(capped)
				return capped
			var next := prev + 1
			ranks[item.ability_id] = next
			_auto_equip(item.ability_id)
			ranks_changed.emit()
			var msg2 := "%s %s" % [def.display_name, _roman(next)]
			toast.emit(msg2)
			return msg2
	_Loud.report("PlayerProgression", "Unhandled item kind for %s" % String(item_id))
	return ""


func _auto_equip(ability_id: StringName) -> void:
	for slot in hotbar:
		if slot == ability_id:
			return
	for i in hotbar.size():
		if hotbar[i] == &"":
			hotbar[i] = ability_id
			hotbar_changed.emit()
			return


func set_hotbar_slot(index: int, ability_id: StringName) -> void:
	assert(index >= 0 and index < HOTBAR_SIZE, "hotbar index")
	if ability_id != &"" and rank_of(ability_id) <= 0:
		_Loud.report("PlayerProgression", "Cannot equip unlearned %s" % String(ability_id))
		return
	hotbar[index] = ability_id
	hotbar_changed.emit()


func _roman(n: int) -> String:
	match n:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV"
		5:
			return "V"
	return str(n)
