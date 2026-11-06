shader_type canvas_item;

uniform float brightness : hint_range(0.5, 3.0) = 1.8;
uniform vec4 tint : source_color = vec4(0.74, 1.0, 0.78, 1.0);
uniform float scanlines : hint_range(0.0, 0.4) = 0.08;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 c = tex.rgb * brightness * tint.rgb;
	c *= 1.0 - scanlines * (0.5 + 0.5 * sin(UV.y * 720.0 * 3.14159));
	COLOR = vec4(c, tex.a);
}
