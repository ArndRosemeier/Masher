extends SceneTree
func _initialize():
	call_deferred("go")
func go():
	var p = load("res://scenes/player/player.tscn")
	var e = load("res://scenes/enemies/enemy.tscn")
	var m = load("res://scenes/main.tscn")
	assert(p and e and m)
	var pi = p.instantiate()
	var ei = e.instantiate()
	root.add_child(pi)
	root.add_child(ei)
	await process_frame
	print("SCENES_OK")
	quit(0)
