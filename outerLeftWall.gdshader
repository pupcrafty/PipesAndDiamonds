shader_type spatial;

uniform sampler2D tile_tex : source_color;
uniform vec2 tile_count = vec2(8.0, 8.0);

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

void fragment() {
	vec2 uv = UV * tile_count;

	vec2 tid = floor(uv);
	vec2 tuv = fract(uv);

	float r = hash12(tid);
	int rot = int(floor(r * 4.0)) % 4;

	float r2 = hash12(tid + 17.0);
	bool flip_x = r2 < 0.5;
	bool flip_y = r2 > 0.75;

	if (flip_x) tuv.x = 1.0 - tuv.x;
	if (flip_y) tuv.y = 1.0 - tuv.y;

	tuv = rotate90(tuv, rot);

	vec4 col = texture(tile_tex, tuv);
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
