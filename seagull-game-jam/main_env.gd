extends Node3D

@onready var main_music : AudioStreamPlayer = get_tree().get_first_node_in_group("main_music")
@onready var og_volume = main_music.volume_db

var stopped = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var player_pos : Vector3 = get_tree().get_first_node_in_group("player").position
	if player_pos.x > -26 and player_pos.x < -3.5 and player_pos.y > 12 and player_pos.y < 41 and player_pos.z > -13 and player_pos.z < 10:
		stopped = true
		main_music.playing = false
	elif stopped:
		main_music.playing = true
		stopped = false
