shader_type canvas_item;

uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.0015;
uniform float tape_noise : hint_range(0.0, 1.0) = 0.06;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.15;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    vec2 uv = UV;
    
    // Chromatic Aberration (scales up with glitch spikes)
    float aberration = chromatic_aberration * (1.0 + glitch_intensity * 3.0);
    float r = texture(SCREEN_TEXTURE, vec2(uv.x + aberration, uv.y)).r;
    float g = texture(SCREEN_TEXTURE, uv).g;
    float b = texture(SCREEN_TEXTURE, vec2(uv.x - aberration, uv.y)).b;
    
    vec3 color = vec3(r, g, b);
    
    // Tape Noise (scales up with glitch spikes)
    float noise = random(uv + vec2(TIME * 0.1, TIME * 0.2));
    color += (noise - 0.5) * tape_noise * (1.0 + glitch_intensity * 2.0);
    
    COLOR = vec4(color, 1.0);
}
