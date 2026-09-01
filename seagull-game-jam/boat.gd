extends CharacterBody3D


@export var SPEED : float = 50.0
const JUMP_VELOCITY = 4.5
const default_area_shape_size = Vector3(3.0,2.94,4.2)
# what boat.tscn's CollisionShape3D is authored at (goodBoat)
const base_size := 1.94
const base_collision_offset_y := 0.15

var in_boat : bool = false
var was_in_boat : bool = false

var player_offset : Vector3

var default_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var motor : int = 0

var boat_cam_distance = 10

var init_transform = null

@onready var boats = {
	0:{
		"mesh": preload("res://goodBoat.vox"),
		"cam_distance": 10,
		"size": 1.94,
	},
	1:{
		"mesh": preload("res://Gullboat.vox"),
		"cam_distance": 5,
		"size": 1,
	}
}

enum boat_types {GOODBOAT, GULLBOAT}

@export var boat_type : boat_types = boat_types.GULLBOAT

func _ready() -> void:
	init_transform = transform
	var size : float = boats[boat_type].size
	$Mesh.mesh = boats[boat_type].mesh
	boat_cam_distance = boats[boat_type].cam_distance
	$Mesh.scale = Vector3(size,size,size)

	# the shapes come from boat.tscn as shared sub-resources, so every boat
	# instance would otherwise resize the same resource and the last one wins
	$CollisionShape3D.shape = $CollisionShape3D.shape.duplicate()
	$Area3D/CollisionShape3D.shape = $Area3D/CollisionShape3D.shape.duplicate()

	# solid hitbox scales with the mesh (base scale in the scene is goodBoat's 1.94)
	$CollisionShape3D.scale = Vector3(size,size,size)
	$CollisionShape3D.position.y = base_collision_offset_y / base_size * size

	$Area3D/CollisionShape3D.shape.size = Vector3(size * default_area_shape_size.x,default_area_shape_size.y,size * default_area_shape_size.z)

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
	if direction:
		velocity.x += direction.x * delta * SPEED * motor
		velocity.z += direction.z * delta * SPEED * motor
	velocity.x *= pow(0.2, delta)
	velocity.z *= pow(0.2, delta)
	
	was_in_boat = in_boat
	
	if in_boat:
		
		if not was_in_boat:
			player.cam_distance = boat_cam_distance
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
	if was_in_boat:
		# only the boat we just left restores the player's camera/input
		player.cam_distance = player.base_cam_distance
		player.handle_input = true

	if position.x > 150 or position.x < -150 or position.z > 150 or position.z < -150:
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
