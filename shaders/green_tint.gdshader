shader_type canvas_item;

uniform float scanline_density : hint_range(100.0, 800.0) = 400.0;
uniform float green_boost : hint_range(1.0, 2.5) = 1.5;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    vec4 col = texture(SCREEN_TEXTURE, UV);
    float luminance = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    
    // Convert to dark green terminal/CRT palette
    vec3 green_monochrome = vec3(luminance * 0.15, luminance * green_boost, luminance * 0.25);
    
    // Scanline grid effect
    float scanline = sin(UV.y * scanline_density * 3.14159) * 0.5 + 0.5;
    green_monochrome *= (0.85 + scanline * 0.15);
    
    COLOR = vec4(green_monochrome, col.a);
}
