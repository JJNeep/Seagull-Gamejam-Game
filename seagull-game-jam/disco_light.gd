extends OmniLight3D

var hue = 0.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	hue += delta/10
	hue = fmod(hue, 1.0)
	light_color = Color.from_hsv(hue, 1.0, 1.0)
