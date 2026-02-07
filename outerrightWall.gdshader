shader_type spatial;

uniform sampler2D tile_tex : source_color;
uniform float tiles_per_meter = 2.0; // bigger = smaller tiles
uniform float seed = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_nrm;

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 rotate90(vec2 uv, int r) {
	if (r == 0) return uv;
	if (r == 1) return vec2(uv.y, 1.0 - uv.x);
	if (r == 2) return vec2(1.0 - uv.x, 1.0 - uv.y);
	return vec2(1.0 - uv.y, uv.x);
}

vec4 sample_random_tiled(vec2 uv01, vec2 tile_id) {
	float r = hash12(tile_id + seed);
	int rot = int(floor(r * 4.0)) % 4;

	float r2 = hash12(tile_id + seed + 17.0);
	bool flip_x = r2 < 0.5;
	bool flip_y = r2 > 0.75;

	vec2 tuv = uv01;
	if (flip_x) tuv.x = 1.0 - tuv.x;
	if (flip_y) tuv.y = 1.0 - tuv.y;

	tuv = rotate90(tuv, rot);

	return texture(tile_tex, tuv);
}

vec4 tiled_triplanar(vec3 wp, vec3 wn) {
	vec3 n = abs(normalize(wn));

	// Blend sharpness: higher = crisper transitions
	vec3 w = pow(n, vec3(8.0));
	w /= (w.x + w.y + w.z);

	vec2 uv_x = wp.zy * tiles_per_meter; // for X-facing surfaces
	vec2 uv_y = wp.xz * tiles_per_meter; // for Y-facing
	vec2 uv_z = wp.xy * tiles_per_meter; // for Z-facing

	vec2 id_x = floor(uv_x);
	vec2 id_y = floor(uv_y);
	vec2 id_z = floor(uv_z);

	vec2 in_x = fract(uv_x);
	vec2 in_y = fract(uv_y);
	vec2 in_z = fract(uv_z);

	// Offsets help avoid repeating the exact same random pattern across projections
	vec4 cx = sample_random_tiled(in_x, id_x + vec2(100.0, 0.0));
	vec4 cy = sample_random_tiled(in_y, id_y + vec2(200.0, 0.0));
	vec4 cz = sample_random_tiled(in_z, id_z + vec2(300.0, 0.0));

	return cx * w.x + cy * w.y + cz * w.z;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec4 col = tiled_triplanar(v_world_pos, v_world_nrm);
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
