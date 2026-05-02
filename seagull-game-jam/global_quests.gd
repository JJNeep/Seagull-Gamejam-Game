extends Node3D

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	QuestManager.check_quests("building", $NavigationRegion3D/RigidBody3D)
