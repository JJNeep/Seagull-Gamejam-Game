extends Node3D

@onready var main_music : AudioStreamPlayer = get_tree().get_first_node_in_group("main_music")
@onready var og_volume = main_music.volume_db

var stopped = false

var time_at_party : float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

var player_pos : Vector3

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	player_pos = get_tree().get_first_node_in_group("player").position
	if player_pos.x > -28 and player_pos.x < -11 and player_pos.y > 12 and player_pos.y < 41 and player_pos.z > -8 and player_pos.z < 10:
		time_at_party += delta
		stopped = true
		main_music.stream_paused = true
		if !$Speakers/Music.playing:
			$Speakers/Music.play()
		QuestManager.check_quests("world",self)
	elif stopped:
		time_at_party = 0.0
		main_music.stream_paused = false
		stopped = false
	#if player_pos.x > 5 and player_pos.x < 13 and player_pos.y > 13 and player_pos.y < 18.5 and player_pos.z > -29 and player_pos.z < -22:
	#	QuestManager.check_quests("world",self)
	QuestManager.check_quests("building", $NavigationRegion3D/RigidBody3D)
	QuestManager.check_quests("world",self)
