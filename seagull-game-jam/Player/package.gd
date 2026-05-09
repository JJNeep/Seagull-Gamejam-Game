extends CharacterBody3D

var on_floor
var large = false

func _physics_process(delta: float) -> void:
	if large:
		scale = Vector3(2,2,2)
	if is_on_floor():
		if !on_floor:
			SoundManager.play_sound_3d("splat.mp3", position, 0.0, randf_range(0.5,1.5))
		$Package.mesh = preload("res://Player/package.vox")
		on_floor = true
	
	# Add the gravity.
	elif not is_on_floor():
		velocity += get_gravity() * delta
	
	move_and_slide()


func _on_area_3d_body_entered(body: Node3D) -> void:
	body.call("collide_package")
