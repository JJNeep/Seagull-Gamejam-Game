extends CharacterBody3D


const SPEED = 50.0
const JUMP_VELOCITY = 4.5

var in_boat : bool = false

var player_offset : Vector3

var default_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var motor : int = 0

var init_transform = null

enum boat_types {GOODBOAT, GULLBOAT}

@onready var boats = [preload("res://goodBoat.vox"),preload("res://Gullboat.vox")]

@export var boat_type : boat_types = boat_types.GULLBOAT

func _ready() -> void:
	init_transform = transform
	$Mesh.mesh = boats[boat_type]

func _physics_process(delta: float) -> void:
	get_tree().get_first_node_in_group("ocean").handle_float(self,delta)
	
	var player : Player = get_tree().get_first_node_in_group("player")
	
	if $Area3D.has_overlapping_bodies():
		if Input.is_action_just_pressed("select"):  # just_pressed so it fires once
			in_boat = !in_boat
			if in_boat:
				player_offset = to_local(player.position)
		$Label3D.transparency = lerpf($Label3D.transparency, 1.0, delta * 10)
	else:
		$Label3D.transparency = lerpf($Label3D.transparency, 0.0, delta * 10)
	
	var direction = (global_transform.basis * Vector3.FORWARD).normalized()
	print(direction)
	if direction:
		velocity.x += direction.x * delta * SPEED * motor
		velocity.z += direction.z * delta * SPEED * motor
	velocity.x *= pow(0.2, delta)
	velocity.z *= pow(0.2, delta)
	
	if in_boat:
		player.handle_input = false
		player.position = to_global(player_offset)
		rotation.y = get_viewport().get_camera_3d().global_rotation.y
		if Input.is_action_just_pressed("move_forward"):
			motor += 1
		elif Input.is_action_just_pressed("move_backward"):
			motor -= 1
		motor = clamp(motor,-1,1)
		if not $Area3D.has_overlapping_bodies():
			in_boat = !in_boat
	else:
		player.handle_input = true
	
	if position.x > 100 or position.x < -100 or position.z > 100 or position.z < -100:
		respawn(player)
	
	move_and_slide()

func respawn(player:Player):
	if in_boat:
		in_boat = false
	motor = 0
	transform = init_transform
	velocity = Vector3.ZERO
	if $Area3D.has_overlapping_bodies():
		await get_tree().create_timer(0.1).timeout
		player.velocity = Vector3.ZERO
		player.position = to_global(player_offset)
