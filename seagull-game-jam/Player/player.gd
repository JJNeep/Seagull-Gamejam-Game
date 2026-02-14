extends CharacterBody3D

# --- Configuration ---
@export_group("Movement")
@export var walk_speed: float = 8.0
@export var jump_velocity: float = 10.0
@export var mouse_sensitivity: float = 0.003
@export var rotation_speed: float = 10.0

@export_group("Elytra Physics")
@export var min_glide_speed: float = 10.0
@export var max_glide_speed: float = 45.0 # Reduced from 60 for control
@export var dive_acceleration: float = 20.0 # Reduced from 40 (less explosive)
@export var climb_deceleration: float = 25.0 
@export var glide_gravity: float = 8.0 # Increased gravity (feels heavier)
@export var base_glide_speed: float = 25.0
@export var roll_amount: float = 30.0 # Reduced roll for stability

@export_group("Stats")
@export var max_energy: float = 100.0
@export var energy_drain: float = 20.0 # Drains 20 per sec (5 seconds flight)

# --- References ---
@onready var visuals: Node3D = $Visuals
@onready var cam_pivot: Node3D = $CamPivot
@onready var spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var anim_player: AnimationPlayer = $Visuals/AnimationPlayer 

# --- State ---
var is_squawking: bool = false
var is_gliding: bool = false
var current_glide_speed: float = 0.0
var current_energy: float = 100.0
var default_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	spring_arm.add_excluded_object(self)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Improved Camera Logic (No more spinning)
		var rot = cam_pivot.rotation_degrees
		rot.y -= event.relative.x * mouse_sensitivity * 50.0
		rot.x -= event.relative.y * mouse_sensitivity * 50.0
		rot.x = clamp(rot.x, -80.0, 80.0)
		rot.z = 0.0 # Force roll to zero
		cam_pivot.rotation_degrees = rot

	if event.is_action_pressed("jump") and not is_on_floor():
		if current_energy > 10.0: # Can only open wings if you have energy
			toggle_glide()
			
	# SQUAWK MECHANIC (Press F)
	if event.is_action_pressed("squawk"): # Add "squawk" to Project Settings -> Input Map!
		perform_squawk()

func _physics_process(delta: float) -> void:
	if is_gliding:
		process_glide(delta)
	else:
		process_standard_movement(delta)
		# Recover energy slowly when on ground
		if is_on_floor():
			current_energy = move_toward(current_energy, max_energy, delta * 30.0)
		
	move_and_slide()
	update_visuals(delta)
	update_animations() 
	
	if is_gliding and is_on_floor():
		toggle_glide()

func perform_squawk() -> void:
	# 1. Play Animation (Optional)
	is_squawking = true
	anim_player.play("Squawk")
	$Squawk.play()
	
	# 2. Alert Humans
	# This sends a signal to any node in the "humans" group
	get_tree().call_group("humans", "get_annoyed", global_position)
	print("AI text here")
	await get_tree().create_timer(1).timeout
	is_squawking = false

func toggle_glide() -> void:
	is_gliding = !is_gliding
	if is_gliding:
		current_glide_speed = max(velocity.length(), base_glide_speed)
		velocity.y = 0 
		var look_dir = -camera.global_transform.basis.z
		look_dir.y = 0
		visuals.look_at(global_position + look_dir, Vector3.UP)

func process_glide(delta: float) -> void:
	# Energy Management
	current_energy -= energy_drain * delta
	if current_energy <= 0:
		is_gliding = false # Force landing
		return

	var aim_dir = -camera.global_transform.basis.z
	var pitch_factor = aim_dir.y 
	
	# Physics: Dive adds speed, Climbing removes it
	if pitch_factor > 0:
		current_glide_speed += pitch_factor * dive_acceleration * delta
		# Diving slightly recovers energy (Mechanic: Dive to fly longer!)
		current_energy += delta * 5.0 
	else:
		current_glide_speed += pitch_factor * climb_deceleration * delta
		
	current_glide_speed = clamp(current_glide_speed, min_glide_speed, max_glide_speed)
	
	# Apply Velocity
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
			visuals.global_transform.basis = visuals.global_transform.basis.slerp(target_basis, delta * 5.0) # Slower turn for weight
		
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
			visuals.rotation.y = lerp_angle(visuals.rotation.y, target_y, delta * rotation_speed)

func update_animations() -> void:
	if is_squawking:
		pass
	elif is_gliding:
		anim_player.play("Glide", 0.2)
	elif is_on_floor():
		var h_vel = Vector2(velocity.x, velocity.z)
		if h_vel.length() > 0.1:
			anim_player.play("Run", 0.2)
		else:
			anim_player.play("Idle", 0.2)
	else:
		if velocity.y > 0:
			anim_player.play("Jump", 0.2)
		else:
			anim_player.play("Fall", 0.2)
