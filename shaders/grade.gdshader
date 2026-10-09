shader_type canvas_item;

// Cinematic colour grade for the 2D world: a touch more contrast and
// saturation, cool shadows / warm highlights (split toning) and a vignette.
// Reads the composited viewport below it, so it grades the tiles, the baked
// lightmap and the glows together. Rendered on a CanvasLayer under the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float brightness : hint_range(-0.5, 0.5) = 0.0;
uniform float contrast : hint_range(0.0, 3.0) = 1.16;
uniform float saturation : hint_range(0.0, 3.0) = 1.24;
uniform float vignette : hint_range(0.0, 1.5) = 0.42;
uniform vec3 lift = vec3(0.0, 0.008, 0.030);
uniform vec3 gain = vec3(1.03, 1.0, 0.95);

void fragment() {
    vec3 c = texture(screen_tex, SCREEN_UV).rgb;

    c += brightness;
    c = (c - 0.5) * contrast + 0.5;

    float l = dot(clamp(c, 0.0, 1.0), vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(l), c, saturation);

    // split tone: cool the darks, warm the brights
    c += lift * (1.0 - smoothstep(0.0, 0.6, l));
    c *= gain;

    float d = length(SCREEN_UV - vec2(0.5));
    float vig = smoothstep(0.86, 0.22, d);
    c *= mix(1.0 - vignette, 1.0, vig);

    COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
