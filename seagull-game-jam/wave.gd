extends MultiMeshInstance3D

@export var ocean_size: int = 500 # 100x100 grid (10,000 blocks)
@export var voxel_size: float = 1.0

var ocean_noise : NoiseTexture2D = NoiseTexture2D.new()

func _ready() -> void:
	ocean_noise.seamless = true
	ocean_noise.noise = FastNoiseLite.new()
	generate_ocean()

func handle_float(body: CharacterBody3D, delta: float) -> void:
	if not $Area3D.overlaps_body(body):
		return
		
	var wave_height = get_wave_height(body.position)
	var depth = wave_height - body.position.y
	
	# Only apply buoyancy if the object is actually submerged
	if depth > 0:
		# 1. BUOYANCY FORCE: Deeper means more upward force
		# Increase float_force (e.g., 15.0) for a higher bounce
		var float_force = 10.0 
		var buoyancy = depth * float_force
		
		# 2. WATER RESISTANCE: Damps the velocity to prevent endless overshooting
		# Increase water_damping (e.g., 4.0) to make it settle faster
		var water_damping = 3.0
		var damping = body.velocity.y * water_damping
		
		# 3. APPLY FORCES: Combine buoyancy, damping, and counteract gravity
		# This replaces gravity entirely while floating
		body.velocity.y += (buoyancy - damping - body.default_gravity) * delta
	else:
		# If overlapping the area but above the wave crest, let gravity rule
		body.velocity.y -= body.default_gravity * delta

func get_wave_height(global_pos: Vector3) -> float:
	# 1. Get the noise configuration from your texture
	var noise: FastNoiseLite = ocean_noise.noise
	
	# 2. Sample the noise using X and Z (match any scaling used in your shader)
	var noise_val = noise.get_noise_2d(global_pos.x, global_pos.z)
	
	# 3. Multiply by your shader's wave height amplitude factor
	var wave_amplitude = 5.0
	return noise_val * wave_amplitude

func generate_ocean() -> void:
	(multimesh.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("noise_tex", ocean_noise)
	
	# 1. Setup the MultiMesh container
	multimesh.instance_count = ocean_size * ocean_size
	
	# 2. Loop through and place cubes
	var index = 0
	for x in range(ocean_size):
		for z in range(ocean_size):
			# Calculate position
			# We center it so (0,0) is in the middle of the ocean
			var pos_x = (x - ocean_size / 2) * voxel_size
			var pos_z = (z - ocean_size / 2) * voxel_size
			
			# Create a Transform (Position/Rotation/Scale)
			var transform = Transform3D()
			transform.origin = Vector3(pos_x, 0, pos_z)
			
			# Set the transform for this specific cube
			multimesh.set_instance_transform(index, transform)
			
			index += 1
	
	create_ocean_hitbox()

func create_ocean_hitbox():
	var total_width = ocean_size * voxel_size
	var depth_thickness = 4.0 # Thickness of the floor collider
	$Area3D/CollisionShape3D.shape = BoxShape3D.new()
	$Area3D/CollisionShape3D.shape.size = Vector3(total_width,depth_thickness*4,total_width)
	
