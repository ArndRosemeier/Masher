class_name Inventory
extends Node
## Run-scoped item stacks.

const _Items := preload("res://scripts/progression/item_catalog.gd")
const _Loud := preload("res://scripts/core/loud_error.gd")

signal changed
signal toast(message: String)

var _stacks: Array[Dictionary] = [] ## {id: StringName, count: int}
var selected_index: int = 0


func clear() -> void:
	_stacks.clear()
	selected_index = 0
	changed.emit()


func stacks() -> Array[Dictionary]:
	return _stacks.duplicate(true)


func is_empty() -> bool:
	return _stacks.is_empty()


func add_item(item_id: StringName, count: int = 1) -> void:
	assert(count > 0, "Inventory.add_item: count")
	assert(_Items.by_id(item_id) != null, "Inventory.add_item: unknown %s" % String(item_id))
	for stack in _stacks:
		if stack["id"] == item_id:
			stack["count"] = int(stack["count"]) + count
			changed.emit()
			toast.emit("Got %s x%d" % [_Items.by_id(item_id).display_name, count])
			return
	_stacks.append({"id": item_id, "count": count})
	if _stacks.size() == 1:
		selected_index = 0
	changed.emit()
	toast.emit("Got %s x%d" % [_Items.by_id(item_id).display_name, count])


func remove_one(item_id: StringName) -> void:
	for i in _stacks.size():
		var stack: Dictionary = _stacks[i]
		if stack["id"] != item_id:
			continue
		var n := int(stack["count"]) - 1
		if n <= 0:
			_stacks.remove_at(i)
			selected_index = clampi(selected_index, 0, maxi(0, _stacks.size() - 1))
		else:
			stack["count"] = n
		changed.emit()
		return
	_Loud.report("Inventory", "remove_one missing item %s" % String(item_id))


func selected_item_id() -> StringName:
	if _stacks.is_empty():
		return &""
	selected_index = clampi(selected_index, 0, _stacks.size() - 1)
	return _stacks[selected_index]["id"] as StringName


func select_next(delta: int) -> void:
	if _stacks.is_empty():
		return
	selected_index = posmod(selected_index + delta, _stacks.size())
	changed.emit()
