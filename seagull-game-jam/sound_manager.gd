extends Node3D

@export var library : Dictionary[String,AudioStream] = {}

func play_sound(sound:String,volume_db:float=0.0,pitch_scale:float=1.0):
	if not library.has(sound):
		push_error("SoundManager: '%s' not found. Keys present: %s" % [sound, library.keys()])
		return
	var sfx = AudioStreamPlayer.new()
	sfx.stream = library[sound]
	sfx.volume_db = volume_db
	sfx.pitch_scale = pitch_scale
	add_child(sfx)
	sfx.play()
	await sfx.finished
	sfx.queue_free()

func play_sound_3d(sound:String,position:Vector3,volume_db:float=0.0,pitch_scale:float=1.0):
	if not library.has(sound):
		push_error("SoundManager: '%s' not found. Keys present: %s" % [sound, library.keys()])
		return
	var sfx = AudioStreamPlayer3D.new()
	sfx.stream = library[sound]
	sfx.volume_db = volume_db
	sfx.pitch_scale = pitch_scale
	add_child(sfx)
	sfx.global_position = position
	sfx.play()
	await sfx.finished
	sfx.queue_free()
