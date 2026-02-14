shader_type spatial;

// --- COLORS ---
uniform vec3 deep_color : source_color = vec3(0.0, 0.2, 0.6);
uniform vec3 shallow_color : source_color = vec3(0.2, 0.6, 1.0);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);

// --- WAVES ---
uniform float wave_height = 2.0;
uniform float speed = 0.1;
uniform float wave_foam_level = 0.65; // High peaks turn white

// --- NOISE TEXTURE ---
uniform sampler2D noise_tex;
uniform float noise_scale = 0.05;

// --- SHORELINE FOAM (NEW!) ---
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float shoreline_foam_width = 1.5; // How far from shore foam appears
uniform bool voxel_style_foam = true; // True = Hard edges, False = Smooth fade

varying float wave_h; 

void vertex() {
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	vec2 uv = (world_pos.xz * noise_scale) + vec2(TIME * speed, TIME * speed * 0.3);
	
	float noise = texture(noise_tex, uv).r;
	noise = pow(noise, 2.0); // Sharpen the peaks
	
	VERTEX.y += noise * wave_height;
	
	wave_h = noise;
}

void fragment() {
	// 1. CALCULATE DEPTH (Distance to the ground behind the water)
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
	// 2. CALCULATE DISTANCE (Difference between water and ground)
	// VERTEX.z in fragment shader is the distance from camera to the water surface
	float depth_diff = linear_depth - (-VERTEX.z);
	
	// 3. DETERMINE COLOR
	vec3 final_color;
	
	// Check A: Is it a high wave peak?
	bool is_wave_foam = wave_h > wave_foam_level;
	
	// Check B: Is it touching the ground? (Shoreline)
	// If voxel_style_foam is true, we use a hard 'step' for a blocky look
	// If false, we use 'smoothstep' for a soft fade
	bool is_shore_foam = false;
	
	if (voxel_style_foam) {
		if (depth_diff < shoreline_foam_width) {
			is_shore_foam = true;
		}
	} else {
		// Optional smooth fade if you ever want it
		if (depth_diff < shoreline_foam_width) {
			// You could blend here, but let's stick to the boolean logic for now
			is_shore_foam = true;
		}
	}

	// 4. MIX COLORS
	if (is_wave_foam || is_shore_foam) {
		final_color = foam_color;
		// Make foam glow slightly
		EMISSION = foam_color * 0.3; 
	} 
	else if (wave_h > wave_foam_level - 0.2) {
		final_color = shallow_color;
	} 
	else {
		final_color = deep_color;
	}
	
	ALBEDO = final_color;
	ROUGHNESS = 0.1;
	SPECULAR = 0.5;
}