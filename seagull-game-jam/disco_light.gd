extends OmniLight3D

const BAR_COUNT : int = 32

const FREQ_MAX : float = 11050.0

const MIN_DB: int = 60

var spectrum : AudioEffectSpectrumAnalyzerInstance

@export var curve : Curve

var max_energy = 9.053

var beat_memory_len = 16

var past_beats : Array[float] = []

var rainbow = [Color.RED,Color.ORANGE,Color.YELLOW,Color.GREEN,Color.BLUE,Color.INDIGO,Color.VIOLET]

var hue : int = 0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	spectrum = AudioServer.get_bus_effect_instance(1, 0)
	#hue += delta/10
	#hue = fmod(hue, 1.0)
	#light_color = Color.from_hsv(hue, 1.0, 1.0)
	var beat = is_beat()
	if beat:
		hue = (hue + 1) % len(rainbow)
	light_color = rainbow[hue]

func is_beat() -> bool:
	var l_hz: float = (0 + 1) * FREQ_MAX / BAR_COUNT
	var l_magnitiude: float = spectrum.get_magnitude_for_frequency_range(0.0, l_hz).length()
	var l_energy: float = clampf((MIN_DB + linear_to_db(l_magnitiude)) / MIN_DB, 0, 1)
	light_energy = lerp(light_energy,curve.sample(l_energy) * max_energy,0.5)
	print(light_energy)
	past_beats.append(l_energy)
	if len(past_beats) > beat_memory_len:
		past_beats.remove_at(0)
	if len(past_beats) == beat_memory_len:
		return past_beats.max() == past_beats[2] and past_beats.max() != past_beats[0]
	return false

func prin(e) -> void:
	print(e)
