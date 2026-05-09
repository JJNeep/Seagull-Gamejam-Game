extends Node

enum point_types {
	Points, Chips
}

var points = 0

var chips = 0

var mouse_locked = true

@onready var popup_display = preload("res://popup_display.tscn")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if mouse_locked:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_locked = !mouse_locked

func create_popup_display(pos:Vector3,amount:int,life_length:float,points_type:point_types=0):
	get_tree().get_first_node_in_group("hud").create_points_popup(amount,points_type)
	var inst : Node3D = popup_display.instantiate()
	inst.life_length = life_length
	inst.position = pos
	inst.amount = amount
	inst.point_type = points_type
	get_parent().get_child(0).add_child(inst)
