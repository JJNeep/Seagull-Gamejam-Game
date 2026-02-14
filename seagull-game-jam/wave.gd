extends MultiMeshInstance3D

@export var ocean_size: int = 100 # 100x100 grid (10,000 blocks)
@export var voxel_size: float = 1.0

func _ready() -> void:
	generate_ocean()

func generate_ocean() -> void:
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
