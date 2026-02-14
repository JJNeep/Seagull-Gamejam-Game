extends CharacterBody3D

# --- Configuration ---
@export_group("Movement")
@export var walk_speed: float = 8.0
@export var jump_velocity: float = 7.0
@export var mouse_sensitivity: float = 0.003
@export var step_height: float = 1.2 # How high we can step up

@export_group("Elytra Physics")
@export var min_glide_speed: float = 8.0
@export var max_glide_speed: float = 40.0 
@export var dive_acceleration: float = 25.0 
@export var climb_deceleration: float = 20.0 
@export var glide_gravity: float = 8.0 # This ensures you slowly sink if looking forward
@export var base_glide_speed: float = 8.0
@export var roll_amount: float = 30.0

# --- References ---
@onready var stair_scanner: ShapeCast3D = $StairScanner # Make sure path is correct!
@onready var visuals: Node3D = $Visuals
@onready var cam_pivot: Node3D = $CamPivot
@onready var spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var anim_player: AnimationPlayer = $Visuals/AnimationPlayer 

var is_gliding: bool = false
var current_glide_speed: float = 0.0
var default_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	spring_arm.add_excluded_object(self)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var rot = cam_pivot.rotation_degrees
		rot.y -= event.relative.x * mouse_sensitivity * 50.0
		rot.x -= event.relative.y * mouse_sensitivity * 50.0
		rot.x = clamp(rot.x, -80.0, 80.0)
		rot.z = 0.0
		cam_pivot.rotation_degrees = rot

	if event.is_action_pressed("jump") and not is_on_floor():
		toggle_glide()
			
	if event.is_action_pressed("squawk"):
		perform_squawk()

func _physics_process(delta: float) -> void:
	if is_gliding:
		process_glide(delta)
	else:
		process_standard_movement(delta)
		
	move_and_slide()
	handle_stairs(delta)
	update_visuals(delta)
	update_animations() 
	
	if is_gliding and is_on_floor():
		toggle_glide()

func perform_squawk() -> void:
	# Alert Humans in a 20 meter radius
	get_tree().call_group("humans", "get_annoyed", global_position)

func toggle_glide() -> void:
	is_gliding = !is_gliding
	if is_gliding:
		current_glide_speed = max(velocity.length(), base_glide_speed)
		velocity.y = 0 
		var look_dir = -camera.global_transform.basis.z
		look_dir.y = 0
		visuals.look_at(global_position + look_dir, Vector3.UP)

func process_glide(delta: float) -> void:
	var aim_dir = -camera.global_transform.basis.z
	var pitch_factor = aim_dir.y 
	
	# Dive logic
	if pitch_factor > 0:
		current_glide_speed += pitch_factor * dive_acceleration * delta
	else:
		current_glide_speed += pitch_factor * climb_deceleration * delta
		
	current_glide_speed = clamp(current_glide_speed, min_glide_speed, max_glide_speed)
	
	velocity = aim_dir * current_glide_speed
	velocity.y -= glide_gravity * delta

func process_standard_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= default_gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis = cam_pivot.global_transform.basis
	var direction = (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction.y = 0 
	
	if direction:
		velocity.x = direction.x * walk_speed
		velocity.z = direction.z * walk_speed
	else:
		velocity.x = move_toward(velocity.x, 0, walk_speed)
		velocity.z = move_toward(velocity.z, 0, walk_speed)

func update_visuals(delta: float) -> void:
	visuals.global_transform.basis = visuals.global_transform.basis.orthonormalized()
	
	if is_gliding:
		if velocity.length() > 1.0:
			var target_transform = visuals.global_transform.looking_at(global_position + velocity, Vector3.UP)
			var target_basis = target_transform.basis.orthonormalized()
			visuals.global_transform.basis = visuals.global_transform.basis.slerp(target_basis, delta * 5.0)
		
		var turn_input = Input.get_axis("move_left", "move_right")
		var target_roll = -turn_input * deg_to_rad(roll_amount)
		visuals.rotation.z = lerp(visuals.rotation.z, target_roll, delta * 3.0)
		
	else:
		visuals.rotation.z = lerp(visuals.rotation.z, 0.0, delta * 10.0)
		visuals.rotation.x = lerp(visuals.rotation.x, 0.0, delta * 10.0)
		
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if input_dir.length() > 0:
			var cam_basis = cam_pivot.global_transform.basis
			var direction = (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			var target_y = atan2(-direction.x, -direction.z)
			visuals.rotation.y = lerp_angle(visuals.rotation.y, target_y, delta * 10.0) # 10.0 is rotation speed

func update_animations() -> void:
	if is_gliding:
		anim_player.play("Glide")
	elif is_on_floor():
		var h_vel = Vector2(velocity.x, velocity.z)
		if h_vel.length() > 0.1:
			anim_player.play("Run")
		else:
			anim_player.play("Idle")
	else:
		if velocity.y > 0:
			anim_player.play("Jump")
		else:
			anim_player.play("Fall")

func handle_stairs(delta: float) -> void:
	# 1. Only climb if we are on the floor and moving against a wall
	if not is_on_floor() or not is_on_wall():
		return

	# 2. Update the scanner to look in our movement direction
	# We normalize velocity so the scanner always checks exactly 0.6 meters ahead
	var vel_2d = Vector2(velocity.x, velocity.z)
	if vel_2d.length() < 0.1:
		return # Not moving enough to step up
		
	var look_dir = Vector3(vel_2d.x, 0, vel_2d.y).normalized()
	stair_scanner.target_position = look_dir * 0.6
	
	# 3. Force the scanner to check NOW (Physics updates happen later usually)
	stair_scanner.force_shapecast_update()
	
	# 4. The Logic:
	# If the scanner (at height 1.1) hits NOTHING, it means the space above the block is empty.
	# Therefore, the block in front of us is short enough to step on.
	if not stair_scanner.is_colliding():
		# TELEPORT UP!
		# We use global_position for snapping. 
		# We add a tiny bit of forward movement so you don't snap up and fall back down.
		global_position.y += step_height * delta * 5.0 # Smooth step
		global_position += look_dir * 0.2 # Nudge forward onto the step
