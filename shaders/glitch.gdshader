shader_type canvas_item;

uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.2;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    vec2 uv = UV;
    
    // Slice glitch offset
    float slice_y = floor(uv.y * 20.0);
    float slice_noise = random(vec2(slice_y, floor(TIME * 10.0)));
    
    if (slice_noise < glitch_intensity) {
        uv.x += (random(vec2(TIME, slice_y)) - 0.5) * 0.08;
    }
    
    vec4 col = texture(SCREEN_TEXTURE, uv);
    COLOR = col;
}
