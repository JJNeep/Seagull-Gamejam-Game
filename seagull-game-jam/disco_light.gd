extends VisualInstance3D

var curr_node: VisualInstance3D = self

const BAR_COUNT : int = 32

const FREQ_MAX : float = 11050.0

const MIN_DB: int = 60

var spectrum : AudioEffectSpectrumAnalyzerInstance

@export var curve : Curve

var max_energy = 9.053

var beat_memory_len = 16

var past_beats : Array[float] = []

var rainbow = [Color.RED,Color.ORANGE,Color.YELLOW,Color.GREEN,Color.BLUE,Color.INDIGO,Color.VIOLET]

var bass_range_low = 20.0
var bass_range_high = 150.0
var base_light_energy = 0
var base_volume_density = 0
var flash_intensity = 9.053
var volume_flash_intensity = 0.2

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
	
	var magnitude = spectrum.get_magnitude_for_frequency_range(bass_range_low, bass_range_high).length()
	
	# 2. Normalize or scale the magnitude (audio values are non-linear)
	# Clamp it so it doesn't blow out completely
	var beat_force = clamp(magnitude * flash_intensity, 0.0, 5.0)
	
	# 3. Apply it to your light's energy
	# Using lerp helps smooth out the transition so it doesn't look too glitchy
	if curr_node is Light3D:
		curr_node.light_color = rainbow[hue]
		curr_node.light_energy = lerp(curr_node.light_energy, base_light_energy + beat_force, delta * 15.0)
	elif curr_node is FogVolume:
		curr_node.material.albedo = rainbow[hue]
		curr_node.material.density = lerp(curr_node.material.density, base_volume_density + beat_force * volume_flash_intensity, delta * 15.0)

func is_beat() -> bool:
	var l_hz: float = (0 + 1) * FREQ_MAX / BAR_COUNT
	var l_magnitiude: float = spectrum.get_magnitude_for_frequency_range(0.0, l_hz).length()
	var l_energy: float = clampf((MIN_DB + linear_to_db(l_magnitiude)) / MIN_DB, 0, 1)
	#curr_node.light_energy = lerp(curr_node.light_energy,curve.sample(l_energy) * max_energy,0.5)
	past_beats.append(l_energy)
	if len(past_beats) > beat_memory_len:
		past_beats.remove_at(0)
	if len(past_beats) == beat_memory_len:
		return past_beats.max() == past_beats[2] and past_beats.max() != past_beats[0]
	return false
