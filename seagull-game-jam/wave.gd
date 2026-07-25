extends MultiMeshInstance3D

@export var ocean_size: int = 500 # 100x100 grid (10,000 blocks)
@export var voxel_size: float = 1.0

var ocean_noise : NoiseTexture2D = NoiseTexture2D.new()
var ocean_material : ShaderMaterial
var noise_image : Image
var time : float = 0.0

func _ready() -> void:
	ocean_noise.seamless = true
	ocean_noise.noise = FastNoiseLite.new()
	generate_ocean()
	# NoiseTexture2D generates in the background - wait for it, then keep a CPU-side
	# copy so get_wave_height() can sample the exact same texture the shader uses
	await ocean_noise.changed
	noise_image = ocean_noise.get_image()

func _process(delta: float) -> void:
	# Drive the shader's clock from here so physics and visuals stay in sync
	time += delta
	ocean_material.set_shader_parameter("time", time)

func handle_float(body: CharacterBody3D, delta: float) -> void:
	if not $Area3D.overlaps_body(body):
		return
		
	var wave_height = get_wave_height(body.position)
	var depth = wave_height - body.position.y
	
	# Only apply buoyancy if the object is actually submerged
	if depth > 0:
		# 1. BUOYANCY FORCE: Deeper means more upward force
		# At rest the body settles gravity/float_force below the surface,
		# so this needs to be strong or everything floats visibly submerged
		var float_force = 50.0
		var buoyancy = depth * float_force
		
		# 2. WATER RESISTANCE: Damps the velocity to prevent endless overshooting
		# Increase water_damping (e.g., 12.0) to make it settle faster
		var water_damping = 8.0
		var damping = body.velocity.y * water_damping
		
		# 3. APPLY FORCES: Combine buoyancy, damping, and counteract gravity
		# This replaces gravity entirely while floating
		body.velocity.y += (buoyancy - damping - body.default_gravity) * delta
	else:
		# If overlapping the area but above the wave crest, let gravity rule
		body.velocity.y -= body.default_gravity * delta

func get_wave_height(global_pos: Vector3) -> float:
	# Mirrors the vertex shader in ocean_generator.gdshader exactly
	if noise_image == null:
		return global_position.y # Texture still generating on first frames

	# 1. Read the same wave settings the shader is using
	var noise_scale: float = ocean_material.get_shader_parameter("noise_scale")
	var scroll_speed: float = ocean_material.get_shader_parameter("speed")
	var wave_amplitude: float = ocean_material.get_shader_parameter("wave_height")

	# 2. Same UV math as the shader: world XZ scaled + time scroll
	var uv = Vector2(global_pos.x, global_pos.z) * noise_scale \
		+ Vector2(time * scroll_speed, time * scroll_speed * 0.3)

	# 3. Sample the same texture the shader displaces with (wrap = seamless tiling)
	var w = noise_image.get_width()
	var h = noise_image.get_height()
	var noise_val = noise_image.get_pixel(wrapi(int(uv.x * w), 0, w), wrapi(int(uv.y * h), 0, h)).r
	noise_val = pow(noise_val, 2.0) # Shader sharpens the peaks the same way

	# 4. Blocks are centered on the ocean's Y, so the visible surface is half a voxel higher
	return global_position.y + noise_val * wave_amplitude + voxel_size * 0.5

func generate_ocean() -> void:
	ocean_material = multimesh.mesh.surface_get_material(0) as ShaderMaterial
	ocean_material.set_shader_parameter("noise_tex", ocean_noise)
	
	# 1. Setup the MultiMesh container
	multimesh.instance_count = ocean_size * ocean_size
	
	# The mesh is a tall column (not a cube) so waves can't open see-through
	# gaps between neighbours. Sink it so its TOP sits half a voxel above y=0.
	var mesh_height: float = (multimesh.mesh as BoxMesh).size.y
	var origin_y: float = voxel_size * 0.5 - mesh_height * 0.5

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
			transform.origin = Vector3(pos_x, origin_y, pos_z)
			
			# Set the transform for this specific cube
			multimesh.set_instance_transform(index, transform)
			
			index += 1
	
	create_ocean_hitbox()

func create_ocean_hitbox():
	var total_width = ocean_size * voxel_size
	var depth_thickness = 4.0 # Thickness of the floor collider
	$Area3D/CollisionShape3D.shape = BoxShape3D.new()
	$Area3D/CollisionShape3D.shape.size = Vector3(total_width,depth_thickness*4,total_width)
	
