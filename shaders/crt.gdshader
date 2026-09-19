shader_type canvas_item;

uniform float scanline_count : hint_range(100.0, 1000.0) = 300.0;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.25;
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.6;
uniform float curvature : hint_range(0.0, 0.2) = 0.05;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

vec2 curve(vec2 uv) {
    uv = (uv - 0.5) * 2.0;
    uv.x *= 1.0 + pow((abs(uv.y) / 5.0), 2.0) * curvature;
    uv.y *= 1.0 + pow((abs(uv.x) / 5.0), 2.0) * curvature;
    uv = (uv / 2.0) + 0.5;
    return uv;
}

void fragment() {
    vec2 uv = curve(UV);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        vec4 col = texture(SCREEN_TEXTURE, uv);
        
        // Scanlines
        float scanline = sin(uv.y * scanline_count * 3.14159) * 0.5 + 0.5;
        col.rgb -= scanline * scanline_opacity * col.rgb;
        
        // Vignette
        float vig = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
        vig = clamp(pow(16.0 * vig, vignette_intensity), 0.0, 1.0);
        col.rgb *= vig;
        
        COLOR = col;
    }
}
