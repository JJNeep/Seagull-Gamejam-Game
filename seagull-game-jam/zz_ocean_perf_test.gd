extends Node3D

# Throwaway probe: verifies the ocean builds its LOD rings and that the CPU-side
# wave height still tracks the shader's wave. Safe to delete.

func _ready() -> void:
	var ocean := $Ocean
	await get_tree().process_frame
	await get_tree().process_frame
	# Give the noise texture time to finish generating in the background
	for i in 60:
		await get_tree().process_frame
		if ocean.noise_image != null:
			break
	print("--- OCEAN PROBE ---")
	print("instance_count = ", ocean.multimesh.instance_count)
	print("buffer floats  = ", ocean.multimesh.buffer.size(),
		" (expected ", ocean.multimesh.instance_count * 12, ")")
	print("coarsest_cell  = ", ocean.coarsest_cell)
	print("custom_aabb    = ", ocean.custom_aabb)
	print("noise_image    = ", ocean.noise_image)
	print("area size      = ", ocean.get_node("Area3D/CollisionShape3D").shape.size)
	var buf: PackedFloat32Array = ocean.multimesh.buffer
	print("buf[0..12]     = ", buf.slice(0, 12))
	print("buf[mid]       = ", buf.slice(16000 * 12, 16000 * 12 + 12))
	print("buf[last]      = ", buf.slice(buf.size() - 12, buf.size()))
	# Every instance must be a scale-only basis with y scale exactly 1
	var bad := 0
	var scales := {}
	for i in ocean.multimesh.instance_count:
		var o := i * 12
		if not is_equal_approx(buf[o + 5], 1.0):
			bad += 1
		scales[snappedf(buf[o], 0.001)] = scales.get(snappedf(buf[o], 0.001), 0) + 1
	print("bad y-scale    = ", bad)
	print("x-scale histogram = ", scales)
	for p in [Vector3.ZERO, Vector3(13.7, 0, -42.2), Vector3(-80.5, 0, 95.1)]:
		print("wave height at ", p, " = ", ocean.get_wave_height(p))
	print("ocean pos after camera follow = ", ocean.global_position)
	print("--- END PROBE ---")
	get_tree().quit()
