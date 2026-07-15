class_name LoudError
extends RefCounted
## Surface failures so they cannot disappear into a non-console window.


static func report(context: String, message: String) -> void:
	var full := "[%s] %s" % [context, message]
	push_error(full)
	printerr(full)
	## Modal alert keeps failures visible in windowed runs. Skip under headless
	## (OS.alert blocks forever with no UI).
	if _can_alert():
		OS.alert(full, "Masher error")


static func _can_alert() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	for arg in OS.get_cmdline_args():
		if arg == "--headless":
			return false
	for arg in OS.get_cmdline_user_args():
		if arg == "--headless":
			return false
	return true
