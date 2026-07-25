extends MultiMeshInstance3D

# The water is built as concentric LOD rings instead of one uniform grid: the
# centre ring uses full-size voxels and every ring outwards doubles the cell
# size. Same coverage as before for ~1/8th of the instances, and the extra size
# is only noticeable at a distance where a voxel is a couple of pixels wide.
@export var voxel_size: float = 1.0 # Cell size of the innermost (full detail) ring
@export var ocean_extent: float = 204.8 # Total width/depth of drawn water, world units
@export var detail_extent: float = 40.0 # Width of the full detail centre ring
@export var lod_rings: int = 3 # Ring count. Each ring out doubles the cell size
# Waves come from world XZ in the shader, so re-centring the grid on the camera
# keeps the water visually still while letting us draw a much smaller patch.
@export var follow_camera: bool = true
@export var float_area_size: float = 500.0 # Buoyancy volume width, kept independent of what's drawn

var ocean_noise : NoiseTexture2D = NoiseTexture2D.new()
var ocean_material : ShaderMaterial
var noise_image : Image
var time : float = 0.0

# Cached so get_wave_height() doesn't re-read shader parameters every physics
# frame for every floating body. Call cache_wave_params() if you change them.
var noise_scale : float = 0.05
var wave_speed : float = 0.1
var wave_amplitude : float = 2.0
var noise_width : int = 0
var noise_height : int = 0

var coarsest_cell : float = 1.0 # Grid snap step for camera following
var float_area : Area3D

func _ready() -> void:
	float_area = $Area3D
	ocean_noise.seamless = true
	ocean_noise.noise = FastNoiseLite.new()
	generate_ocean()
	# NoiseTexture2D generates in the background - wait for it, then keep a CPU-side
	# copy so get_wave_height() can sample the exact same texture the shader uses.
	# Checking first matters: if generation already finished, awaiting "changed"
	# would never return and nothing would ever float.
	if ocean_noise.get_image() == null:
		await ocean_noise.changed
	noise_image = ocean_noise.get_image()
	noise_width = noise_image.get_width()
	noise_height = noise_image.get_height()

func _process(delta: float) -> void:
	# Drive the shader's clock from here so physics and visuals stay in sync
	time += delta
	# Wrap it so the noise UV never drifts into float32 precision loss on a long
	# session. The texture is seamless and this shifts the UV by whole tiles
	# (10 across, 3 down), so the wrap is invisible.
	if wave_speed > 0.0:
		time = fmod(time, 10.0 / wave_speed)
	ocean_material.set_shader_parameter("time", time)

	if follow_camera:
		var cam := get_viewport().get_camera_3d()
		if cam:
			# Snap to the coarsest cell size so every ring stays aligned to the
			# same world lattice - otherwise the voxels shimmer as you move.
			global_position = Vector3(
				snappedf(cam.global_position.x, coarsest_cell),
				global_position.y,
				snappedf(cam.global_position.z, coarsest_cell))

func handle_float(body: CharacterBody3D, delta: float) -> void:
	if not float_area.overlaps_body(body):
		return

	var wave_height = get_wave_height(body.global_position)
	var depth = wave_height - body.global_position.y

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

	# 1. Same UV math as the shader: world XZ scaled + time scroll
	var uv = Vector2(global_pos.x, global_pos.z) * noise_scale \
		+ Vector2(time * wave_speed, time * wave_speed * 0.3)

	# 2. Sample the same texture the shader displaces with (wrap = seamless tiling).
	# floori, not int(): int() truncates toward zero, which mirrors the GPU's
	# wrap incorrectly on the negative half of the ocean.
	var noise_val = noise_image.get_pixel(
		wrapi(floori(uv.x * noise_width), 0, noise_width),
		wrapi(floori(uv.y * noise_height), 0, noise_height)).r
	noise_val *= noise_val # Shader sharpens the peaks the same way

	# 3. Blocks are centered on the ocean's Y, so the visible surface is half a voxel higher
	return global_position.y + noise_val * wave_amplitude + voxel_size * 0.5

func cache_wave_params() -> void:
	noise_scale = ocean_material.get_shader_parameter("noise_scale")
	wave_speed = ocean_material.get_shader_parameter("speed")
	wave_amplitude = ocean_material.get_shader_parameter("wave_height")

func generate_ocean() -> void:
	ocean_material = multimesh.mesh.surface_get_material(0) as ShaderMaterial
	ocean_material.set_shader_parameter("noise_tex", ocean_noise)
	cache_wave_params()

	var rings: int = maxi(lod_rings, 1)
	coarsest_cell = voxel_size * float(1 << (rings - 1))

	# The mesh is a tall column (not a cube) so waves can't open see-through
	# gaps between neighbours. Sink it so its TOP sits half a voxel above y=0.
	var mesh_size: Vector3 = (multimesh.mesh as BoxMesh).size
	var origin_y: float = voxel_size * 0.5 - mesh_size.y * 0.5

	# Outer half-extent of each ring, spaced geometrically from the detail ring
	# out to the full ocean. Snapped to the coarsest cell so ring boundaries land
	# on a shared cell edge and the rings tile with no gap or overlap.
	var half_extents := PackedFloat32Array()
	var inner_half: float = detail_extent * 0.5
	var outer_half: float = maxf(ocean_extent * 0.5, inner_half)
	for ring in rings:
		var t: float = float(ring) / float(maxi(rings - 1, 1))
		var half: float = inner_half * pow(outer_half / inner_half, t) if rings > 1 else outer_half
		half_extents.append(maxf(snappedf(half, coarsest_cell), coarsest_cell))

	# Build every transform into one PackedFloat32Array (12 floats per instance,
	# three rows of a 3x4 matrix) and hand it over in a single assignment. A
	# quarter of a million set_instance_transform() calls is a slow startup.
	var upper_bound: int = 0
	for ring in rings:
		var ring_cells: int = int(round(half_extents[ring] * 2.0 / (voxel_size * float(1 << ring))))
		upper_bound += ring_cells * ring_cells
	var transforms := PackedFloat32Array()
	transforms.resize(upper_bound * 12) # Trimmed to the real count once the holes are cut

	var w: int = 0 # Write head into the buffer
	var count: int = 0
	var covered: float = 0.0 # Half-extent already filled by the finer rings
	for ring in rings:
		var cell: float = voxel_size * float(1 << ring)
		var half: float = half_extents[ring]
		if half <= covered:
			continue
		# Only X/Z are scaled up for the coarser rings. Y stays at 1 so the
		# shader's VERTEX.y displacement means the same thing in every ring.
		var scale_x: float = cell / mesh_size.x
		var scale_z: float = cell / mesh_size.z
		var cells: int = int(round(half * 2.0 / cell))
		for x in range(cells):
			var pos_x: float = (float(x) + 0.5) * cell - half
			var inside_x: bool = absf(pos_x) < covered
			for z in range(cells):
				var pos_z: float = (float(z) + 0.5) * cell - half
				# Leave a square hole where the finer ring already has voxels
				if inside_x and absf(pos_z) < covered:
					continue
				transforms[w] = scale_x
				transforms[w + 3] = pos_x
				transforms[w + 5] = 1.0
				transforms[w + 7] = origin_y
				transforms[w + 10] = scale_z
				transforms[w + 11] = pos_z
				w += 12
				count += 1
		covered = half

	transforms.resize(w)
	multimesh.instance_count = count
	multimesh.buffer = transforms

	# Vertex displacement happens after culling, so spell the bounds out or the
	# whole ocean can pop out of view when the camera looks along it.
	custom_aabb = AABB(
		Vector3(-outer_half, origin_y - mesh_size.y * 0.5, -outer_half),
		Vector3(outer_half * 2.0, mesh_size.y + wave_amplitude, outer_half * 2.0))

	create_ocean_hitbox()

func create_ocean_hitbox():
	var depth_thickness = 4.0 # Thickness of the floor collider
	# Sized off float_area_size, not the drawn grid: the grid follows the camera
	# and got smaller, but anything anywhere on the map still needs to float.
	$Area3D/CollisionShape3D.shape = BoxShape3D.new()
	$Area3D/CollisionShape3D.shape.size = Vector3(float_area_size, depth_thickness * 4, float_area_size)
