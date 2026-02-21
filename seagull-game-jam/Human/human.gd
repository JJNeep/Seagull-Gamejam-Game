extends CharacterBody3D

# --- State Machine Setup ---
enum State { IDLE, STARTLE, INVESTIGATE, CHASE }
enum Idle_State { WORK, HOME, BEACH }
var current_state: State = State.IDLE
var current_idle: Idle_State = Idle_State.WORK
var is_at_location = false

@export_group("Pathfind")
@export var job_position = Node3D
@export var job_time : float
@export var home_position = Node3D
@export var home_time : float
@export var beach_position = Node3D
@export var beach_time : float

# --- Configuration ---
@export_group("Movement")
@export var walk_speed: float = 2.5
@export var run_speed: float = 7.0
@export var flee_duration: float = 4.0

@export var movement_target: Node3D
@export var player : Player

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var move_dir: Vector3 = Vector3.ZERO
var state_timer: float = 0.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var ray_front: RayCast3D = $RayFront
@onready var anim_player: AnimationPlayer = $AnimationPlayer # Optional: If you have animations

func _ready() -> void:
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = 4.0

func set_movement_target(target:Vector3):
	nav_agent.target_position = target

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif current_state == State.IDLE:
		idle(delta)
	
	$Reaction.look_at(Vector3(player.camera.global_position.x,$Reaction.position.y,player.camera.global_position.z))
	$Reaction.rotation_degrees.y -= 180
	
	move_and_slide()

func idle(delta):
	if current_idle == Idle_State.WORK:
		if !is_at_location:
			set_movement_target(job_position.position)
			navigation_frame(delta)
		else:
			pass

func navigation_frame(delta):
	if nav_agent.is_navigation_finished():
		is_at_location = true
	
	var current_agent_position: Vector3 = global_position
	var next_path_position: Vector3 = nav_agent.get_next_path_position()
	var new_velocity: Vector3 = next_path_position - current_agent_position
	new_velocity = new_velocity.normalized()
	new_velocity = new_velocity * walk_speed
	
	# Place this after calculating new_velocity but before move_and_slide()
	if new_velocity.length() > 0.1:
		var target_angle = atan2(-new_velocity.x, -new_velocity.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)
	
	velocity = new_velocity

# --- EXTERNAL SIGNALS ---

# This exact function name was called by your Player's perform_squawk()
func get_annoyed(bird_pos: Vector3) -> void:
	pass
