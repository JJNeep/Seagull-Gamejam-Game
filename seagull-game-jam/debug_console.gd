extends CanvasLayer

# Add as Autoload named "DebugConsole" in Project Settings → Autoload

const TOGGLE_KEY := KEY_QUOTELEFT  # The ` key (backtick, top-left of keyboard)

var commands := {}
var history: Array[String] = []
var history_index := -1
var is_open := false

var panel: Panel
var output: RichTextLabel
var input: LineEdit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	_build_ui()
	_register_default_commands()
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEY:
			toggle()
			get_viewport().set_input_as_handled()
		elif is_open and event.keycode == KEY_UP:
			_history_prev()
			get_viewport().set_input_as_handled()
		elif is_open and event.keycode == KEY_DOWN:
			_history_next()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	is_open = not is_open
	visible = is_open
	get_tree().paused = is_open
	if is_open:
		input.grab_focus()
		input.text = ""
	else:
		input.release_focus()


func register(name: String, callable: Callable, help: String = "") -> void:
	commands[name.to_lower()] = {"call": callable, "help": help}


func log_line(text: String, color: String = "white") -> void:
	output.append_text("[color=%s]%s[/color]\n" % [color, text])


func _on_input_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	input.text = ""
	if trimmed.is_empty(): return
	
	history.append(trimmed)
	history_index = history.size()
	log_line("> " + trimmed, "#88ddff")
	_execute(trimmed)


func _execute(line: String) -> void:
	var parts := line.split(" ", false)
	if parts.is_empty(): return
	
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	
	if not commands.has(cmd):
		log_line("Unknown command: '%s'. Type 'help' for a list." % cmd, "#ff8888")
		return
	
	var result = commands[cmd]["call"].callv([args])
	if result != null:
		log_line(str(result))


func _history_prev() -> void:
	if history.is_empty(): return
	history_index = max(0, history_index - 1)
	input.text = history[history_index]
	input.caret_column = input.text.length()


func _history_next() -> void:
	if history.is_empty(): return
	history_index += 1
	if history_index >= history.size():
		history_index = history.size()
		input.text = ""
	else:
		input.text = history[history_index]
		input.caret_column = input.text.length()


# ============================================================
# UI
# ============================================================

func _build_ui() -> void:
	panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.modulate.a = 0.92
	add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	# Add some padding from the edges
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.offset_right = -16
	vbox.offset_bottom = -16
	panel.add_child(vbox)
	
	output = RichTextLabel.new()
	output.bbcode_enabled = true
	output.scroll_following = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(output)
	
	input = LineEdit.new()
	input.placeholder_text = "Type a command (try 'help')"
	input.add_theme_font_size_override("font_size", 14)
	input.text_submitted.connect(_on_input_submitted)
	vbox.add_child(input)


# ============================================================
# DEFAULT COMMANDS
# ============================================================

func _register_default_commands() -> void:
	register("help", _cmd_help, "List all commands. Usage: help [command]")
	register("clear", _cmd_clear, "Clear the console.")
	register("quit", _cmd_quit, "Quit the game.")
	
	# === Your game-specific commands go below ===
	register("chips", _cmd_chips, "Set chip count. Usage: chips <amount>")
	register("addchips", _cmd_addchips, "Add chips. Usage: addchips <amount>")
	register("megapoo", _cmd_megapoo, "Force-trigger a mega poo at the player.")
	register("tp", _cmd_tp, "Teleport player. Usage: tp <x> <y> <z>")
	register("timescale", _cmd_timescale, "Set engine time scale. Usage: timescale <float>")
	register("god", _cmd_god, "Toggle infinite chips.")


func _cmd_help(args: Array) -> String:
	if args.size() > 0:
		var name := str(args[0]).to_lower()
		if commands.has(name):
			return "%s — %s" % [name, commands[name]["help"]]
		return "No such command: %s" % name
	
	var keys := commands.keys()
	keys.sort()
	var out := "Available commands:\n"
	for k in keys:
		out += "  %s — %s\n" % [k, commands[k]["help"]]
	return out


func _cmd_clear(_args: Array) -> void:
	output.clear()


func _cmd_quit(_args: Array) -> void:
	get_tree().quit()


# ============================================================
# GAME-SPECIFIC COMMANDS — edit these to fit your project
# ============================================================

func _cmd_chips(args: Array) -> String:
	if args.is_empty():
		return "Current chips: %d" % Global.chips
	Global.chips = int(args[0])
	return "Chips set to %d" % Global.chips


func _cmd_addchips(args: Array) -> String:
	if args.is_empty():
		return "Usage: addchips <amount>"
	var amount := int(args[0])
	Global.chips += amount
	return "Added %d chips. Total: %d" % [amount, Global.chips]


func _cmd_megapoo(_args: Array) -> String:
	# Find the seagull and force-drop a large package
	var seagull := get_tree().get_first_node_in_group("player")
	if seagull == null:
		return "No seagull found (add it to the 'seagull' group)."
	if seagull.has_method("drop_package"):
		seagull.drop_package(true)
		return "Mega poo deployed."
	return "Seagull doesn't have drop_package()."


func _cmd_tp(args: Array) -> String:
	if args.size() < 3:
		return "Usage: tp <x> <y> <z>"
	var seagull := get_tree().get_first_node_in_group("player")
	if seagull == null:
		return "No seagull found."
	seagull.global_position = Vector3(float(args[0]), float(args[1]), float(args[2]))
	return "Teleported to %s" % seagull.global_position


func _cmd_timescale(args: Array) -> String:
	if args.is_empty():
		return "Current timescale: %f" % Engine.time_scale
	Engine.time_scale = float(args[0])
	return "Timescale set to %f" % Engine.time_scale


func _cmd_god(_args: Array) -> String:
	# Simple example — you'd track this somewhere in Global
	if not Global.has_meta("god_mode"):
		Global.set_meta("god_mode", false)
	var current: bool = Global.get_meta("god_mode")
	Global.set_meta("god_mode", not current)
	if not current:
		Global.chips = 999999
		return "God mode ON. Chips topped up."
	return "God mode OFF."
