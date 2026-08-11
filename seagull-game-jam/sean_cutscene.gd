extends Node3D

@onready var player = get_tree().get_first_node_in_group("player")

var rise_to = Vector3(6.174,0.0,-7.55)

var curr_position : Vector3

var cutscene_started = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if !cutscene_started:
		player.start_cutscene()
		$Camera3D.current = true
		cutscene_started = true
	if cutscene_started:
		$SeaMonster.position.y = lerpf($SeaMonster.position.y,rise_to.y,delta*100)
		print($SeaMonster.position.y)
	
