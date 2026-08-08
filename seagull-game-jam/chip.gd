# Shoot email to 
# joseph@codekids.com.au
# Pew Pew
extends RigidBody3D

class_name Chip

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is Player:
		Global.create_popup_display(position,1,2,Global.point_types.Chips)
		Global.chips += 1
		Global.points += 30
		QuestManager.check_quests("chip", self)
		queue_free()
