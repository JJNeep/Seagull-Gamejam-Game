extends CanvasLayer
## Throwaway connect panel for the playtest multiplayer. Built in code so there
## is no .tscn to clean up later. Deleted along with res://mp_test/.

const DEFAULT_PORT := 27015

var _status: Label
var _players: Label
var _name_edit: LineEdit
var _addr_edit: LineEdit
var _port_edit: LineEdit


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(460, 0)
	margin.add_child(box)

	var title := Label.new()
	title.text = "PLAYTEST MULTIPLAYER  (temporary - not in the jam build)"
	box.add_child(title)

	box.add_child(HSeparator.new())

	_name_edit = _add_row(box, "Your name", MPTest.player_name)
	_addr_edit = _add_row(box, "Host address", "127.0.0.1")
	_port_edit = _add_row(box, "Port", str(DEFAULT_PORT))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_add_button(buttons, "Host", _on_host)
	_add_button(buttons, "Join", _on_join)
	_add_button(buttons, "Disconnect", _on_disconnect)
	_add_button(buttons, "Close (F3)", _on_close)

	box.add_child(HSeparator.new())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	_players = Label.new()
	_players.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_players)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.65)
	help.text = "Address takes an IP or a hostname (play.example.com), and an optional :port.\n" \
		+ "Same house / wifi: use the host's local IP, shown below.\n" \
		+ "Over the internet: forward UDP %d to the host, or run everyone through a\n" % DEFAULT_PORT \
		+ "free virtual LAN (ZeroTier, Radmin VPN, Hamachi) and use the IP it gives you.\n" \
		+ "\nThis machine: " + _local_ips()
	box.add_child(help)


func _add_row(box: VBoxContainer, label_text: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	return e


func _add_button(row: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	row.add_child(b)


func _local_ips() -> String:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		# IPv4 only, skip loopback and the 169.254.x junk Windows invents
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return ", ".join(out) if out.size() > 0 else "unknown"


func refresh() -> void:
	if _status == null:
		return
	_status.text = "Status: " + MPTest.status
	_players.text = ("In world: " + ", ".join(MPTest.peer_names())) if MPTest.online else ""


func _on_host() -> void:
	MPTest.set_player_name(_name_edit.text)
	MPTest.host_game(int(_port_edit.text))


func _on_join() -> void:
	MPTest.set_player_name(_name_edit.text)
	MPTest.join_game(_addr_edit.text, int(_port_edit.text))


func _on_disconnect() -> void:
	MPTest.shutdown()


func _on_close() -> void:
	MPTest.close_ui()


func _process(_delta: float) -> void:
	if visible:
		refresh()
