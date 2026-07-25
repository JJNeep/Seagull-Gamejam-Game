shader_type spatial;
// Reading hint_depth_texture forces this material into the transparent pass,
// where depth writing is off by default - that made the water blocks draw
// in the wrong order (the "layering" artifact). This turns depth write back on.
// diffuse_lambert is cheaper than the default Burley, and the water doesn't need
// to receive shadows - drop shadows_disabled if you ever want them back.
render_mode depth_draw_always, diffuse_lambert, shadows_disabled;

// --- COLORS ---
uniform vec3 deep_color : source_color = vec3(0.0, 0.2, 0.6);
uniform vec3 shallow_color : source_color = vec3(0.2, 0.6, 1.0);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);

// --- WAVES ---
uniform float wave_height = 2.0;
uniform float speed = 0.1;
uniform float time = 0.0; // Driven from wave.gd so physics and visuals share one clock
uniform float wave_foam_level = 0.65; // High peaks turn white

// --- NOISE TEXTURE ---
uniform sampler2D noise_tex;
uniform float noise_scale = 0.05;

// --- SHORELINE FOAM ---
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float shoreline_foam_width = 1.5; // How far from shore foam appears
uniform bool voxel_style_foam = true; // Kept for the scene; the hard-edged look is the only one implemented
// Water past this distance skips the depth-texture lookup entirely. Most of the
// screen is distant water, so this is where the fragment cost goes.
uniform float shoreline_foam_distance = 90.0;

varying float wave_h;

void vertex() {
	// One noise fetch per vertex, driven by the instance origin so all 8 corners
	// of a block move together and it stays a rigid column.
	vec2 uv = (MODEL_MATRIX[3].xz * noise_scale) + vec2(time * speed, time * speed * 0.3);

	float noise = texture(noise_tex, uv).r;
	noise *= noise; // Sharpen the peaks (cheaper than pow(noise, 2.0))

	VERTEX.y += noise * wave_height;

	wave_h = noise;
}

void fragment() {
	// Is this a high wave peak? Checked first because it's free, and it lets the
	// foam pixels skip the depth-texture work below.
	bool is_foam = wave_h > wave_foam_level;

	if (!is_foam && -VERTEX.z < shoreline_foam_distance) {
		// Shoreline foam: how close is the ground behind this water pixel?
		float depth = texture(depth_texture, SCREEN_UV).x;
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float linear_depth = -view.z / view.w;
		// VERTEX.z here is the view-space distance to the water surface
		is_foam = (linear_depth + VERTEX.z) < shoreline_foam_width;
	}

	if (is_foam) {
		ALBEDO = foam_color;
		EMISSION = foam_color * 0.3; // Make foam glow slightly
	} else if (wave_h > wave_foam_level - 0.2) {
		ALBEDO = shallow_color;
	} else {
		ALBEDO = deep_color;
	}

	ROUGHNESS = 0.1;
	SPECULAR = 0.5;
}
