extends CanvasLayer

@onready var health_bar: ProgressBar = $Root/HealthBar
@onready var health_label: Label = $Root/HealthLabel
@onready var banner: Label = $Root/Banner
@onready var hint: Label = $Root/Hint
@onready var interact_hint: Label = $Root/InteractHint


func _ready() -> void:
	show_playing()
	interact_hint.visible = false


func set_health(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "HP %d / %d" % [current, maximum]


func set_interact_hint(text: String) -> void:
	if text.is_empty():
		interact_hint.visible = false
		interact_hint.text = ""
	else:
		interact_hint.text = text
		interact_hint.visible = true


func show_playing() -> void:
	banner.visible = false
	hint.text = "Mouse look · LMB attack · E doors · Esc free cursor"
	hint.visible = true
	set_interact_hint("")


func show_dead() -> void:
	banner.text = "You died"
	banner.visible = true
	hint.text = "Press R to restart the run"
	hint.visible = true
	set_interact_hint("")


func show_won() -> void:
	banner.text = "Dungeon cleared"
	banner.visible = true
	hint.text = "Press R to restart the run"
	hint.visible = true
	set_interact_hint("")
