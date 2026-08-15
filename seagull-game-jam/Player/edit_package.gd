extends CharacterBody3D

# === Tweakables ===
const SLOWMO_SCALE := 0.2
const FOV_PUNCH := 25.0
const HITSTOP_DURATION := 0.15
const SHAKE_AMOUNT := 0.3
const SHAKE_DECAY := 0.6
const HYPE_PHRASES := ["MEGA POO", "효모", "헛소리", "도플갱어", "💀💀💀", "전형적인", "스푸너주의", "하찮은 사람", "벽옥", "사과", "당신의", "감자 스튜", "공생"]
const EMOJIS := ["💀", "🔥", "💯", "🗿", "💩", "👑", "🫃🏻", "🕚", "🎅🏿", "🐿️", "🤯"]

const SPLAT_TEXTURE := preload("res://Player/Impact.png")
const SPLAT_SIZE_NORMAL := 1.5
const SPLAT_SIZE_LARGE := 4.0
const SPLAT_LIFETIME := 30.0
const EDIT_MAX_DURATION := 16.0  # seconds (real time) before edit force-ends
const STANDARD_FOV = 75.0

# === State ===
var on_floor := false
var large := false
var _edit_started := false
var _impact_triggered := false

# Edit state
var _shake_cam: Camera3D
var _shake_amount := 0.0
var _emoji_spawning := false
var _emoji_timer := 0.0

# Mute main music
var _main_music: AudioStreamPlayer
var _main_music_was_playing := false
var _main_music_position := 0.0

# Node refs (created at runtime for large packages)
var _overlay: CanvasLayer
var _vignette: ColorRect
var _chromatic: ColorRect
var _hype_text: Label
var _emoji_layer: Control
var _phonk_player: AudioStreamPlayer
var _impact_player: AudioStreamPlayer


func _ready() -> void:
	if large:
		scale = Vector3(2, 2, 2)
		_build_edit_overlay()
		_start_edit()


func _physics_process(delta: float) -> void:
	if is_on_floor():
		if not on_floor:
			QuestManager.check_quests("poo",self)
			if position.y < 0:
				var sean = load("res://sean_cutscene.tscn")
				var inst = sean.instantiate()
				inst.position = get_tree().get_first_node_in_group("player").position
				get_parent().add_child(inst)
			SoundManager.play_sound_3d("splat.mp3", position, 0.0, randf_range(0.5, 1.5))
			if large and _edit_started and not _impact_triggered:
				_spawn_splat()
				_impact_triggered = true
				_trigger_impact()
		$Package.mesh = preload("res://Player/package.vox")
		on_floor = true
	else:
		if large:
			var nuke_pos = get_tree().get_first_node_in_group("Nuke_centre").global_position
			if (nuke_pos*Vector3(1, 0, 1)).distance_squared_to(position*Vector3(1, 0, 1)) < 64 and position.y < nuke_pos.y + 13:
				get_tree().get_first_node_in_group("Nuke_centre").get_node("../GPUParticles3D2").emitting = true
				QuestManager.check_quests("poo",self)
				if large and _edit_started and not _impact_triggered:
					_spawn_splat()
					_impact_triggered = true
					_trigger_impact()
		velocity += get_gravity() * delta
	move_and_slide()


func _process(delta: float) -> void:
	# Camera shake during edit
	if _shake_cam and _shake_amount > 0.0:
		_shake_cam.h_offset = randf_range(-_shake_amount, _shake_amount)
		_shake_cam.v_offset = randf_range(-_shake_amount, _shake_amount)
		_shake_amount = max(0.0, _shake_amount - SHAKE_DECAY * delta)
		if _shake_amount == 0.0:
			_shake_cam.h_offset = 0.0
			_shake_cam.v_offset = 0.0
	
	# Emoji rain
	if _emoji_spawning:
		_emoji_timer -= delta
		if _emoji_timer <= 0.0:
			_emoji_timer = 0.05
			_spawn_emoji()


func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.has_method("collide_package"):
		body.call("collide_package")


# ============================================================
# EDIT SYSTEM — self-contained, builds itself at runtime
# ============================================================

func _build_edit_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	
	# Vignette
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	var vig_shader := Shader.new()
	vig_shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	float v = smoothstep(0.3, 0.8, dist);
	COLOR = vec4(0.8, 0.0, 0.0, v);
}
"""
	var vig_mat := ShaderMaterial.new()
	vig_mat.shader = vig_shader
	_vignette.material = vig_mat
	_overlay.add_child(_vignette)
	
	# Chromatic aberration
	_chromatic = ColorRect.new()
	_chromatic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chromatic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrom_shader := Shader.new()
	chrom_shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 0.05) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = (uv - 0.5);
	float r = texture(screen_tex, uv + dir * strength).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - dir * strength).b;
	COLOR = vec4(r, g, b, 1.0);
}
"""
	var chrom_mat := ShaderMaterial.new()
	chrom_mat.shader = chrom_shader
	chrom_mat.set_shader_parameter("strength", 0.0)
	_chromatic.material = chrom_mat
	_overlay.add_child(_chromatic)
	
	# Emoji layer (above shaders)
	_emoji_layer = Control.new()
	_emoji_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_emoji_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_emoji_layer)
	
	# Hype text
	_hype_text = Label.new()
	_hype_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hype_text.add_theme_font_size_override("font_size", 96)
	_hype_text.add_theme_color_override("font_color", Color.WHITE)
	_hype_text.add_theme_color_override("font_outline_color", Color.BLACK)
	_hype_text.add_theme_constant_override("outline_size", 12)
	_hype_text.modulate.a = 0.0
	_overlay.add_child(_hype_text)
	
	# Audio
	_phonk_player = AudioStreamPlayer.new()
	_phonk_player.process_mode = Node.PROCESS_MODE_ALWAYS
	# Optional: load a phonk track if you have one
	_phonk_player.stream = preload("res://Player/phonk.mp3")
	_overlay.add_child(_phonk_player)
	
	_impact_player = AudioStreamPlayer.new()
	_impact_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_impact_player.stream = preload("res://Player/impact.mp3")
	_overlay.add_child(_impact_player)
	
	# Make the package process during pause for hit-stop
	process_mode = Node.PROCESS_MODE_ALWAYS


func _start_edit() -> void:
	_edit_started = true
	Engine.time_scale = SLOWMO_SCALE
	
	_main_music = get_tree().get_first_node_in_group("main_music")
	if _main_music and _main_music.playing:
		_main_music_was_playing = true
		_main_music_position = _main_music.get_playback_position()
		_main_music.stop()
	
	var cam := get_viewport().get_camera_3d()
	if cam:
		var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(cam, "fov", STANDARD_FOV - FOV_PUNCH, 0.4)
	
	if _phonk_player.stream:
		_phonk_player.play()
	
	var vt := create_tween()
	vt.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	vt.tween_property(_vignette, "modulate:a", 0.7, 0.3)
	
	var ct := create_tween()
	ct.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	ct.tween_method(_set_chromatic, 0.0, 0.015, 0.3)
	
	_flash_hype_text()
	_emoji_spawning = true
	
	# Safety: force-end the edit if the package never lands
	_start_timeout()

func _start_timeout() -> void:
	# Use a SceneTreeTimer with process_always=true so slow-mo doesn't affect it
	# (we want REAL seconds, not in-game seconds)
	var timer := get_tree().create_timer(EDIT_MAX_DURATION, true, false, true)
	await timer.timeout
	if _edit_started and not _impact_triggered:
		print("Mega poo edit timed out — force-ending.")
		_trigger_impact()

func _flash_hype_text() -> void:
	_hype_text.text = HYPE_PHRASES.pick_random()
	_hype_text.modulate.a = 1.0
	_hype_text.scale = Vector2(0.1, 0.1)
	_hype_text.rotation = randf_range(-0.15, 0.15)
	_hype_text.pivot_offset = _hype_text.size / 2.0
	
	var t := create_tween().set_parallel(true)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_hype_text, "scale", Vector2(1.2, 1.2), 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_hype_text, "rotation", 0.0, 0.15)


func _set_chromatic(v: float) -> void:
	if _chromatic and _chromatic.material:
		_chromatic.material.set_shader_parameter("strength", v)


func _trigger_impact() -> void:
	Engine.time_scale = 1.0
	
	# Hit-stop
	get_tree().paused = true
	await get_tree().create_timer(HITSTOP_DURATION, true, false, true).timeout
	get_tree().paused = false
	
	# Shake
	_shake_cam = get_viewport().get_camera_3d()
	_shake_amount = SHAKE_AMOUNT
	
	if _impact_player.stream:
		_impact_player.play()
	
	_hype_text.text = "💥 OBLITERATED 💥"
	_flash_hype_text()
	
	await get_tree().create_timer(1.2).timeout
	_end_edit()


func _end_edit() -> void:
	if _main_music and _main_music_was_playing and is_instance_valid(_main_music):
		_main_music.play(_main_music_position)
	var cam := get_viewport().get_camera_3d()
	var t := create_tween().set_parallel(true)
	t.tween_property(_vignette, "modulate:a", 0.0, 0.4)
	t.tween_method(_set_chromatic, 0.015, 0.0, 0.4)
	t.tween_property(_hype_text, "modulate:a", 0.0, 0.4)
	if cam:
		t.tween_property(cam, "fov", STANDARD_FOV, 0.4)
	if _phonk_player.playing:
		t.tween_property(_phonk_player, "volume_db", -40.0, 0.4)
	
	await t.finished
	if _phonk_player:
		_phonk_player.stop()
	_emoji_spawning = false


func _spawn_emoji() -> void:
	if not _emoji_layer: return
	var label := Label.new()
	label.text = EMOJIS.pick_random()
	label.add_theme_font_size_override("font_size", randi_range(40, 80))
	var vp := get_viewport().get_visible_rect().size
	label.position = Vector2(randf() * vp.x, vp.y + 50)
	_emoji_layer.add_child(label)
	
	var t := create_tween().set_parallel(true)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(label, "position:y", -100.0, randf_range(0.8, 1.5))
	t.tween_property(label, "rotation", randf_range(-PI, PI), 1.2)
	t.tween_property(label, "modulate:a", 0.0, 1.2).set_delay(0.3)
	await t.finished
	if is_instance_valid(label):
		label.queue_free()

func _spawn_splat() -> void:
	# Raycast down to find exactly where to place the decal
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.1
	var to := global_position + Vector3.DOWN * 5.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result := space.intersect_ray(query)
	
	var splat_pos: Vector3
	var splat_normal: Vector3 = Vector3.UP
	if result.is_empty():
		# Fallback: just use the package's current position
		splat_pos = global_position
	else:
		splat_pos = result.position
		splat_normal = result.normal
	
	# Build the decal
	var decal := Decal.new()
	decal.texture_albedo = SPLAT_TEXTURE
	decal.albedo_mix = 1.0
	decal.cull_mask = 2
	decal.modulate = Color(0.35, 0.2, 0.08)
	
	var splat_size: float = SPLAT_SIZE_LARGE if large else SPLAT_SIZE_NORMAL
	# Add randomness so they don't all look identical
	splat_size *= randf_range(0.85, 1.15)
	# Decal size: x/z = footprint, y = how deep down it projects
	decal.size = Vector3(splat_size, 2.0, splat_size)
	
	# Figure out what to parent the decal to
	var parent_node: Node = get_tree().current_scene
	if not result.is_empty():
		var hit_collider = result.collider
		if hit_collider != null:
			# Walk up to find a Node3D parent (decals need a 3D parent)
			parent_node = _find_node3d_parent(hit_collider)
	
	parent_node.add_child(decal)
	decal.global_position = splat_pos + splat_normal * 0.05
	
	# Orient the decal to point along the surface normal (handles slopes)
	if splat_normal.is_equal_approx(Vector3.UP):
		decal.rotation.y = randf() * TAU  # random rotation for variety
	else:
		decal.look_at(decal.global_position - splat_normal, Vector3.UP)
		decal.rotate_object_local(Vector3.RIGHT, PI / 2)
	
	# Optional fade-out
	if SPLAT_LIFETIME > 0.0:
		var tween := decal.create_tween()
		tween.tween_interval(SPLAT_LIFETIME - 2.0)
		tween.tween_property(decal, "modulate:a", 0.0, 2.0)
		tween.tween_callback(decal.queue_free)

func _find_node3d_parent(node: Node) -> Node3D:
	# Walk up the tree until we find a Node3D, fall back to current scene
	var current := node
	while current != null:
		if current is Node3D:
			return current
		current = current.get_parent()
	return get_tree().current_scene

func _exit_tree() -> void:
	# Safety: if package gets freed mid-edit, restore the world
	if _edit_started:
		Engine.time_scale = 1.0
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.fov = STANDARD_FOV
			cam.h_offset = 0.0
			cam.v_offset = 0.0
		if get_tree().paused:
			get_tree().paused = false
