extends CharacterBody3D

class_name Player

# --- Configuration ---
@export_group("Movement")
@export var walk_speed: float = 8.0
@export var jump_velocity: float = 7.0
@export var mouse_sensitivity: float = 0.003

@export_group("Flight Physics")
@export var min_glide_speed: float = 8.0
@export var max_glide_speed: float = 30.0 
@export var dive_acceleration: float = 25.0 
@export var climb_deceleration: float = 40.0 
@export var glide_gravity: float = 8.0 # This ensures you slowly sink if looking forward
@export var base_glide_speed: float = 8.0
@export var roll_amount: float = 30.0
@export var flap_force: float = 20.0

# --- References ---
@onready var visuals: Node3D = $Visuals
@onready var cam_pivot: Node3D = $CamPivot
@onready var spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var anim_player: AnimationPlayer = $Visuals/AnimationPlayer 

var pov = 1
var is_flapping: bool = false
var is_squawking: bool = false
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
	
	if event.is_action_pressed("toggle_pov"):
		if pov == 1:
			pov = -1
		else:
			pov = 1

func _physics_process(delta: float) -> void:
	if is_gliding:
		process_glide(delta)
	else:
		process_standard_movement(delta)
		if not $RayCast3D.is_colliding() and is_on_wall():
			velocity.y += 0.3
	
	move_and_slide()
	update_visuals(delta)
	update_animations() 
	
	if is_gliding and is_on_floor():
		toggle_glide()
	
	spring_arm.rotation_degrees.y = 180 * abs(clamp(pov,-1,0))

func perform_squawk() -> void:
	is_squawking = true
	# Alert Humans in a 20 meter radius
	get_tree().call_group("humans", "get_annoyed", global_position)
	await get_tree().create_timer(1).timeout
	is_squawking = false

func toggle_glide() -> void:
	is_gliding = !is_gliding
	if is_gliding:
		current_glide_speed = max(velocity.length(), base_glide_speed)
		velocity.y = 0 
		var look_dir = -camera.global_transform.basis.z * pov
		look_dir.y = 0
		visuals.look_at(global_position + look_dir, Vector3.UP)

func process_glide(delta: float) -> void:
	var aim_dir = -camera.global_transform.basis.z * pov
	# Invert the pitch factor: Looking down (-Y) should now dive
	var pitch_factor = -aim_dir.y 
	
	# Dive logic
	if pitch_factor > 0:
		# Positive pitch_factor now represents diving (nose down)
		current_glide_speed += pitch_factor * dive_acceleration * delta
	else:
		# Negative pitch_factor now represents climbing (nose up)
		current_glide_speed += pitch_factor * climb_deceleration * delta
		
	current_glide_speed = clamp(current_glide_speed, min_glide_speed, max_glide_speed)
	
	velocity = aim_dir * current_glide_speed
	velocity.y -= glide_gravity * delta
	
	#if Input.is_action_just_pressed("flap"):
	#	is_flapping = true
	
	if Input.is_action_pressed("flap"):
		velocity.y += flap_force * delta * 10
		is_flapping = true
	else:
		is_flapping = false
	
	#if is_flapping:
	#	velocity.y += flap_force * delta * 10
	#	await get_tree().create_timer(0.5).timeout
	#	is_flapping = false

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
	if is_squawking:
		anim_player.play("Squawk")
	elif is_gliding:
		if is_flapping:
			anim_player.play("Flap")
		else:
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
