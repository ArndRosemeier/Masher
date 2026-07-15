extends Node
## Kenney (and ambient) SFX playback.

var _players: Dictionary = {}
var _ambient: AudioStreamPlayer


func _ready() -> void:
	_register("footstep", "res://assets/audio/game/footstep.ogg", -8.0)
	_register("hit", "res://assets/audio/game/hit.ogg", -4.0)
	_register("hurt", "res://assets/audio/game/hurt.ogg", -6.0)
	_register("swing", "res://assets/audio/game/swing.ogg", -10.0)
	_register("ui", "res://assets/audio/game/ui_click.ogg", -12.0)
	_register("death", "res://assets/audio/game/death.ogg", -4.0)
	_register("exit", "res://assets/audio/game/exit.ogg", -6.0)

	_ambient = AudioStreamPlayer.new()
	_ambient.name = "Ambient"
	_ambient.volume_db = -18.0
	_ambient.bus = &"Master"
	var ambient_stream := load("res://assets/audio/game/ambient.wav")
	if ambient_stream is AudioStream:
		var stream := ambient_stream as AudioStream
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		_ambient.stream = stream
	add_child(_ambient)


func start_ambient() -> void:
	if _ambient and _ambient.stream and not _ambient.playing:
		_ambient.play()


func stop_ambient() -> void:
	if _ambient and _ambient.playing:
		_ambient.stop()


func play_footstep() -> void:
	var player: AudioStreamPlayer = _players.get("footstep")
	if player and player.stream:
		player.pitch_scale = randf_range(0.92, 1.08)
		player.play()


func play_hit() -> void:
	_play("hit")


func play_hurt() -> void:
	_play("hurt")


func play_swing() -> void:
	_play("swing")


func play_ui() -> void:
	_play("ui")


func play_death() -> void:
	_play("death")


func play_exit() -> void:
	_play("exit")


func _register(id: String, path: String, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.name = id.capitalize()
	player.volume_db = volume_db
	var stream := load(path)
	if stream:
		player.stream = stream
	add_child(player)
	_players[id] = player


func _play(id: String) -> void:
	var player: AudioStreamPlayer = _players.get(id)
	if player and player.stream:
		player.play()
