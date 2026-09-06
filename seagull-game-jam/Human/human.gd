extends CharacterBody3D

# --- State Machine Setup ---
enum HumanTypes { STANDARD, WHITE }
enum State { IDLE, STARTLE, INVESTIGATE, CHASE, PACKAGE, CONFUSED }
enum Idle_State { WORK, BEACH, HOME }
var current_state: State = State.IDLE
var after_startle: State
var current_idle: Idle_State = Idle_State.WORK
var is_at_location = false
var suspicious = false
var state_timer : SceneTreeTimer
var suspicion_timer : SceneTreeTimer
var is_eating_chip = false
@export var human_type : HumanTypes

# Frame-based countdowns (replace the old await-based timers so the state
# machine never spawns overlapping coroutines).
var startle_time: float = 0.0
var confused_time: float = 0.0
var location_wait: float = 0.0

var last_squawk_time: float = 0.0
var squawk_cooldown: float = 2.5

var view_distance: float = 1000.0
var fov_angle: float = 90.0

var curr_chip_object : RigidBody3D
var frozen : bool = false

@export var absolute_cinema : bool = false

@export var investigate_time : float = 4.0
@export var chase_time : float = 4.0
@export var suspicious_for_investigate_timer : float = 20.0
@export var suspicious_for_chase_timer : float = 20.0
@export var hearing_range : float = 1000.0

@export_group("Pathfind")
@export var job_position = Node3D
@export var job_time : float
@export var home_position = Node3D
@export var home_time : float
@export var beach_position_point_1 = Node3D
@export var beach_position_point_2 = Node3D
@export var beach_time : float
@export var starting_idle : Idle_State

var beach_point : Vector3

@export_group("Movement")
@export var walk_speed: float = 2.5
@export var run_speed: float = 7.0
@export var flee_duration: float = 4.0

@export var player : Player

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var move_dir: Vector3 = Vector3.ZERO

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_player: AnimationPlayer = $Visuals/AnimationPlayer
@onready var state_player: AnimationPlayer = $Visuals/StatePlayer
@onready var chip = preload("res://chip.tscn")
@onready var ray = $Vision

func _ready() -> void:
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 1.0
	ray.target_position.z = -view_distance
	get_model("Shorts","Visuals/Shorts")
	current_idle = starting_idle
	# Starting straight in BEACH skips the HOME->BEACH transition that normally
	# picks a spot, so choose one now instead of walking to an unset (0,0,0).
	if current_idle == Idle_State.BEACH:
		beach_point = _find_beach_position()

func get_model(model_name:String,part_path:NodePath):
	var model = "res://Human/" + "%02d" % (human_type+1) + "_" + model_name + ".vox"
	get_node(part_path).mesh = load(model)

func set_movement_target(target:Vector3):
	nav_agent.target_position = target

func _physics_process(delta: float) -> void:
	if position.y < -100:
		QuestManager.check_quests("human", self)
		queue_free()
	
	if absolute_cinema:
		return
	
	# Handle Gravity cleanly
	if not is_on_floor() and not is_on_wall() and not frozen:
		velocity.y -= gravity * delta
	else:
		# Process State Machine
		if current_state == State.IDLE:
			idle(delta)
		else:
			non_idle(delta)
	
	if is_instance_valid(suspicion_timer) and suspicion_timer.time_left > 0:
		suspicious = true
	else:
		suspicious = false
		suspicion_timer = null # Clean up reference
	
	# Only transition to startle if we aren't already startling/chasing
	if current_state == State.IDLE and suspicious and can_see_player():
		after_startle = State.CHASE
		current_state = State.STARTLE
		startle_time = 0.0
	
	# Check if chip stolen while eating
	if current_state == State.IDLE and is_eating_chip:
		if not is_instance_valid(curr_chip_object) or curr_chip_object.get_parent() != $Chip:
			is_eating_chip = false
			curr_chip_object = null
			after_startle = State.INVESTIGATE
			current_state = State.STARTLE
			startle_time = 0.0
	
	# Billboard reaction icon to camera
	if is_instance_valid(player) and is_instance_valid(player.camera):
		$Visuals/Reaction.look_at(Vector3(player.camera.global_position.x, $Visuals/Reaction.position.y, player.camera.global_position.z))
		$Visuals/Reaction.rotation_degrees.y -= 180
	
	move_and_slide()


func non_idle(delta):
	is_at_location = false
	
	if current_state == State.STARTLE:
		show_player()
		stop_pathfinding()
		if is_eating_chip:
			drop_chip()
		state_player.play("Startle")
		
		# Frame-based wait instead of an await coroutine.
		startle_time += delta
		if startle_time >= 2.0:
			startle_time = 0.0
			current_state = after_startle
			if after_startle == State.INVESTIGATE:
				state_timer = get_tree().create_timer(investigate_time)
			elif after_startle == State.CHASE:
				state_timer = get_tree().create_timer(chase_time)
			elif after_startle == State.CONFUSED:
				confused_time = 0.0

	elif current_state == State.INVESTIGATE:
		state_player.play("Confused")
		if can_see_player():
			after_startle = State.CHASE
			current_state = State.STARTLE
			startle_time = 0.0
		else:
			rotation.y += 1.0 * delta
			# Only count down / return to idle while we still can't see the player.
			if not is_instance_valid(state_timer) or state_timer.time_left <= 0:
				suspicion_timer = get_tree().create_timer(suspicious_for_investigate_timer)
				current_state = State.IDLE
				is_at_location = false
				location_wait = 0.0

	elif current_state == State.CHASE:
		state_player.play("Angry")
		if can_see_player(true) and chase_time > 0:
			set_movement_target(player.position)
			navigation_frame(delta, true)
		else:
			confused_time = 0.0
			current_state = State.CONFUSED
			suspicion_timer = get_tree().create_timer(suspicious_for_chase_timer)

	elif current_state == State.CONFUSED:
		state_player.play("Confused")
		if can_see_player(true):
			confused_time = 0.0
			current_state = State.CHASE
			return
		stop_pathfinding()
		# Frame-based wait so he stays responsive (keeps checking for the player).
		confused_time += delta
		if confused_time >= 10.0:
			confused_time = 0.0
			current_state = State.IDLE
			is_at_location = false
			location_wait = 0.0

func idle(delta):
	if current_idle == Idle_State.WORK:
		state_player.play("Normal")
		if not is_at_location:
			set_movement_target(job_position.position)
			navigation_frame(delta)
		else:
			stop_pathfinding()
			hide_player()
			location_wait += delta
			if location_wait >= job_time:
				location_wait = 0.0
				current_idle = Idle_State.HOME
				show_player()
				is_at_location = false

	elif current_idle == Idle_State.HOME:
		state_player.play("Normal")
		if not is_at_location:
			set_movement_target(home_position.position)
			navigation_frame(delta)
		else:
			stop_pathfinding()
			hide_player()
			location_wait += delta
			if location_wait >= home_time:
				location_wait = 0.0
				current_idle = Idle_State.BEACH
				beach_point = _find_beach_position()
				show_player()
				is_at_location = false

	elif current_idle == Idle_State.BEACH:
		if not is_at_location:
			state_player.play("Normal")
			set_movement_target(beach_point)
			navigation_frame(delta)
		else:
			stop_pathfinding()
			if not is_eating_chip and curr_chip_object == null:
				curr_chip_object = chip.instantiate()
				$Chip.add_child(curr_chip_object)
				is_eating_chip = true
			
			location_wait += delta
			if location_wait >= beach_time:
				location_wait = 0.0
				current_idle = Idle_State.WORK
				
				if is_eating_chip and is_instance_valid(curr_chip_object):
					curr_chip_object.queue_free()
				is_eating_chip = false
				curr_chip_object = null
				is_at_location = false

func drop_chip():
	if is_instance_valid(curr_chip_object):
		curr_chip_object.reparent(get_parent())
		curr_chip_object.freeze = false
	curr_chip_object = null
	is_eating_chip = false

func navigation_frame(delta, running:bool=false):
	if nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		anim_player.play("Idle")
		is_at_location = true
	
	if not nav_agent.is_target_reachable():
		nav_agent.target_position = NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), nav_agent.target_position)
	
	var current_agent_position: Vector3 = global_position
	var next_path_position: Vector3 = nav_agent.get_next_path_position()
	var new_velocity: Vector3 = next_path_position - current_agent_position
	new_velocity = new_velocity.normalized()
	if running:
		anim_player.play("Run")
		new_velocity = new_velocity * run_speed
	else:
		anim_player.play("Walk")
		new_velocity = new_velocity * walk_speed
	
	if new_velocity.length() > 0.1:
		var target_angle = atan2(-new_velocity.x, -new_velocity.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)
	
	velocity = new_velocity

func stop_pathfinding():
	velocity = Vector3.ZERO
	if is_eating_chip:
		anim_player.play("EatChip")
	else:
		anim_player.play("Idle")

func hide_player():
	$Visuals.hide()
	frozen = true
	$CollisionShape3D.disabled = true

func show_player():
	$Visuals.show()
	frozen = false
	$CollisionShape3D.disabled = false

func can_see_player(ignore_fov = false) -> bool:
	var dist = global_position.distance_to(player.global_position)
	if dist > view_distance:
		return false
	
	var direction_to_player = (player.global_position - global_position).normalized()
	var forward_vector = -global_transform.basis.z
	
	var dot_product = forward_vector.dot(direction_to_player)
	var angle_to_player = rad_to_deg(acos(dot_product))
	
	if angle_to_player > fov_angle / 2 and not ignore_fov:
		return false
	
	ray.look_at(player.global_position)
	ray.force_raycast_update()
	
	if ray.is_colliding():
		var collider = ray.get_collider()
		if collider == player:
			return true
			
	return false

func hear_squawk(bird_pos: Vector3) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Respect the cooldown so rapid squawks can't spam the trigger.
	if current_time - last_squawk_time < squawk_cooldown:
		return
	# Only react when unaware. If he's already startled / investigating / chasing /
	# confused, ignore the squawk so it can't restart the reaction or reset timers.
	if current_state != State.IDLE:
		return
	
	if bird_pos.distance_to(position) < hearing_range:
		last_squawk_time = current_time
		after_startle = State.INVESTIGATE
		current_state = State.STARTLE
		startle_time = 0.0

func collide_package() -> void:
	after_startle = State.CONFUSED
	current_state = State.STARTLE
	startle_time = 0.0

func _find_beach_position() -> Vector3:
	# Get the marker positions
	var min_pos = beach_position_point_1.global_position
	var max_pos = beach_position_point_2.global_position
	
	# Get random X and Z coordinates within the boundary
	var random_x = randf_range(min_pos.x, max_pos.x)
	var random_z = randf_range(min_pos.z, max_pos.z)
	
	# Keep the Y level exactly where the agent currently is
	var target_y = global_position.y 
	
	# Combine into the final target position
	var target_position = Vector3(random_x, target_y, random_z)
	return target_position
