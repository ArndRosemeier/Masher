class_name BookPickup
extends Area3D
## World book; E / body enter grants into player inventory.

const GROUP := &"book_pickup"

@export var item_id: StringName = &"book_vital_codex"

var _taken: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_ensure_visual()


func setup(p_item_id: StringName) -> void:
	item_id = p_item_id
	_ensure_visual()


func try_pickup(player: Node) -> bool:
	if _taken:
		return false
	assert(player != null, "BookPickup: null player")
	var inv = player.get_node_or_null("Inventory")
	assert(inv != null and inv.has_method("add_item"), "BookPickup: player inventory")
	_taken = true
	inv.add_item(item_id, 1)
	AudioManager.play_ui()
	queue_free()
	return true


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		try_pickup(body)


func _ensure_visual() -> void:
	if has_node("Mesh"):
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.12, 0.45)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.25, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.45, 0.2)
	mat.emission_energy_multiplier = 1.2
	mesh.material_override = mat
	mesh.position = Vector3(0.0, 0.25, 0.0)
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	shape.shape = sphere
	add_child(shape)
