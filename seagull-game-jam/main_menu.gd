extends Node3D

var play = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_button_pressed() -> void:
	play = true
	$Camera3D.position = $Camera3D.to_global(Vector3.BACK)
	$"CanvasLayer/Main Menu/Control".hide()
	await get_tree().create_timer(1).timeout
	get_tree().change_scene_to_file("res://level_01.tscn")

func _process(delta: float) -> void:
	if play:
		$"CanvasLayer/Main Menu/ColorRect".color.a = lerp($"CanvasLayer/Main Menu/ColorRect".color.a,1.0,delta*5)
		$Camera3D.position = lerp($Camera3D.position,$Camera3D.to_global(Vector3.BACK*30),delta*10)
		$Path3D/PathFollow3D.progress_ratio = lerpf($Path3D/PathFollow3D.progress_ratio,1,delta)
