extends Control
## Dedicated server scene for the playtest multiplayer. Part of res://mp_test/
## and deleted with it.
##
## This scene deliberately loads NO island: the server is only a relay and a
## referee (it decides who drives which boat). One of the connected players
## simulates the boats nobody is in, and the ocean clock -- see
## MPTest._world_authority.
##
## Run it headless on a Linux box:
##     ./SeagullGameJam.x86_64 --headless --mp-server
##     ./SeagullGameJam.x86_64 --headless --mp-server --mp-port=27015

const DEFAULT_PORT := 27015

var _log: Label
var _started_at := 0


func _ready() -> void:
	# Global grabs the mouse on startup; a server has no business doing that
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	margin.add_child(_log)

	_started_at = Time.get_ticks_msec()

	MPTest.dedicated = true
	MPTest.player_name = "server"
	MPTest.host_game(_port_from_cmdline())

	print("[MP] ", MPTest.status)
	print("[MP] waiting for gulls...")


func _port_from_cmdline() -> int:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--mp-port="):
			return int(a.substr(10))
	return DEFAULT_PORT


func _process(_delta: float) -> void:
	if _log == null:
		return
	var uptime := int((Time.get_ticks_msec() - _started_at) / 1000.0)
	var lines := [
		"SEAGULL PLAYTEST SERVER",
		"",
		MPTest.status,
		"up %d:%02d:%02d" % [uptime / 3600, (uptime / 60) % 60, uptime % 60],
		"",
		"Players (%d):" % MPTest.connected_count(),
	]
	for n in MPTest.remote_names():
		lines.append("  - " + n)
	if MPTest.connected_count() == 0:
		lines.append("  (nobody yet)")
	_log.text = "\n".join(lines)
