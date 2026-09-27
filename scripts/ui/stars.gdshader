// Starry, twinkling unexplored space (a HoMM nod). Rectangles drawn in pure
// white become sky; any other colour (the dim "remembered" veil) passes through.
shader_type canvas_item;

uniform vec2 cam = vec2(0.0);
varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i), b = h21(i + vec2(1.0, 0.0)), c = h21(i + vec2(0.0, 1.0)), d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 sky(vec2 p) {
	vec3 col = vec3(0.020, 0.024, 0.040);
	// faint nebula wisps
	float n = vnoise(p / 170.0) * 0.65 + vnoise(p / 64.0) * 0.35;
	float n2 = vnoise(p / 120.0 + 31.0);
	col += mix(vec3(0.27, 0.24, 0.55), vec3(0.16, 0.31, 0.51), n2) * pow(n, 3.0) * 0.45;
	// static dust
	vec2 dg = floor(p / 3.0);
	float dr = h21(dg + 91.0);
	if (dr > 0.985) col += vec3(0.82, 0.84, 0.92) * (0.15 + 0.35 * h21(dg + 5.0));
	// three twinkling star layers
	for (int L = 0; L < 3; L++) {
		float fl = float(L);
		float sc = 26.0 + fl * 11.0;
		vec2 g = p / sc + fl * 17.3;
		vec2 id = floor(g);
		vec2 f = fract(g);
		float r = h21(id + fl * 3.1);
		if (r < 0.30) {
			vec2 sp = vec2(h21(id + 1.7), h21(id + 8.3)) * 0.7 + 0.15;
			vec2 dv = (f - sp) * sc;
			float d = length(dv);
			float big = step(0.75, h21(id + 7.0));
			float tw = 0.15 + 0.85 * pow(0.5 + 0.5 * sin(TIME * 1.1 + fl * 2.09 + r * 40.0), 2.0);
			float core = smoothstep(1.1 + big * 0.6, 0.15, d);
			float crs = big * 0.35 * (smoothstep(3.5, 0.0, abs(dv.x)) * smoothstep(0.7, 0.0, abs(dv.y)) + smoothstep(3.5, 0.0, abs(dv.y)) * smoothstep(0.7, 0.0, abs(dv.x)));
			vec3 sc3 = r < 0.06 ? vec3(1.0, 0.93, 0.75) : (r < 0.11 ? vec3(0.75, 0.82, 1.0) : vec3(0.96, 0.96, 1.0));
			col += sc3 * (core + crs) * tw;
		}
	}
	return col;
}

void fragment() {
	if (COLOR.a > 0.99 && COLOR.r > 0.99 && COLOR.g > 0.99 && COLOR.b > 0.99) {
		COLOR = vec4(sky(lp + cam * 0.6), 1.0);
	}
}
