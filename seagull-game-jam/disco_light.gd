extends OmniLight3D

const BAR_COUNT : int = 32

var spectrum : AudioEffectSpectrumAnalyzerInstance

var hue = 0.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	spectrum = AudioServer.get_bus_effect_instance(1, 0)
	hue += delta/10
	hue = fmod(hue, 1.0)
	light_color = Color.from_hsv(hue, 1.0, 1.0)
