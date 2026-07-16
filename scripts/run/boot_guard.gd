extends Node
## Last-resort visible failure if RunManager / create UI never appears.


func _ready() -> void:
	call_deferred("_check_boot")


func _check_boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var run := get_parent().get_node_or_null("RunManager")
	if run == null or run.get_script() == null:
		_fail(
			"RunManager failed to load.\n\n"
			+ "Open the Godot editor Output dock for SCRIPT ERROR lines,\n"
			+ "or run start.bat and read the console."
		)
		return
	## Create UI is added deferred; give it a moment.
	await get_tree().create_timer(0.35).timeout
	var found_ui := false
	for child in get_parent().get_children():
		if child is CanvasLayer and child.has_method("show_create"):
			found_ui = true
			break
	if not found_ui:
		_fail(
			"Create-run UI never appeared.\n\n"
			+ "Boot reached RunManager but create_run.tscn did not show.\n"
			+ "Check the console for SCRIPT ERROR / Boot messages."
		)


func _fail(message: String) -> void:
	const Loud := preload("res://scripts/core/loud_error.gd")
	Loud.report("BootGuard", message)
	## Also paint an on-screen banner so windowed runs without OS.alert still see it.
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_parent().add_child(layer)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	label.text = "BOOT FAILED\n\n%s" % message
	layer.add_child(label)
