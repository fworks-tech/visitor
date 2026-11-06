shader_type canvas_item;
render_mode unshaded;

// One-pass aperture composite: fisheye, green grade, grain, scanlines and a
// soft mask for peephole / window / door crack / hatch. The 3D stage renders
// behind this ColorRect; screen_texture is that viewport.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// 0 = circle, 1 = rectangle, 2 = vertical slit
uniform int mask_shape = 0;
uniform vec2 mask_center = vec2(0.5, 0.5);
uniform vec2 mask_size = vec2(0.92, 0.92);
uniform float mask_softness : hint_range(0.0, 0.2) = 0.02;
uniform float aspect = 1.7777778;

uniform float fisheye : hint_range(-0.8, 0.8) = 0.32;
uniform float zoom : hint_range(0.8, 1.4) = 1.05;

uniform vec4 tint : source_color = vec4(0.72, 0.86, 0.72, 1.0);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.55;
uniform float grain : hint_range(0.0, 0.2) = 0.05;
uniform float scanlines : hint_range(0.0, 0.4) = 0.06;
uniform float vignette : hint_range(0.0, 1.0) = 0.75;
uniform float aberration : hint_range(0.0, 0.01) = 0.002;
uniform float tracking : hint_range(0.0, 0.02) = 0.002;
uniform float exposure : hint_range(0.5, 1.5) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float mask_value(vec2 uv) {
	float soft = max(mask_softness, 0.001);
	if (mask_shape == 0) {
		vec2 mp = (uv - mask_center) * vec2(aspect, 1.0);
		float unit = min(aspect, 1.0);
		float r = length(mp) / max(mask_size.x * 0.5 * unit, 0.001);
		return 1.0 - smoothstep(1.0 - soft, 1.0, r);
	}
	vec2 q = abs(uv - mask_center) - mask_size * 0.5;
	float d = max(q.x, q.y);
	return 1.0 - smoothstep(-soft, 0.0, d);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Barrel distortion. Strong for the peephole, almost none for a window.
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	float r2 = dot(p, p);
	p *= (1.0 + fisheye * r2) * zoom;
	vec2 suv = p / vec2(aspect, 1.0) + 0.5;

	// Sparse tracking band, not a constant wobble.
	float band = smoothstep(0.015, 0.0, abs(fract(uv.y * 2.0 + TIME * 0.07) - 0.5));
	suv.x += band * tracking * (hash(vec2(floor(uv.y * 140.0), floor(TIME))) - 0.5);

	vec3 col = vec3(0.0);
	bool inside = suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0;
	if (inside) {
		vec2 d = suv - 0.5;
		col.r = texture(screen_texture, suv + d * aberration).r;
		col.g = texture(screen_texture, suv).g;
		col.b = texture(screen_texture, suv - d * aberration).b;

		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(lum) * tint.rgb, tint_mix);
		col *= exposure;

		float n = hash(uv * vec2(1280.0, 720.0) + fract(TIME));
		col += (n - 0.5) * grain;

		float scan = 0.5 + 0.5 * sin(uv.y * 720.0 * 3.14159);
		col *= 1.0 - scan * scanlines;

		vec2 vd = (suv - 0.5) * vec2(aspect, 1.0);
		float vig = smoothstep(0.95, 0.30, length(vd));
		col *= mix(1.0, vig, vignette);
	}

	COLOR = vec4(clamp(col, 0.0, 1.0) * mask_value(uv), 1.0);
}
