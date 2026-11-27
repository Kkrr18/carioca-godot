shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Terreno do CARIOCA.
// A cor vem de altura e inclinação calculadas no próprio shader — sem textura
// externa, sem atlas, sem download. É o que permite cobrir centenas de km² com
// um único material e um único draw call por setor.

uniform vec3 low_color : source_color = vec3(0.192, 0.263, 0.137);
uniform vec3 mid_color : source_color = vec3(0.302, 0.353, 0.184);
uniform vec3 high_color : source_color = vec3(0.400, 0.380, 0.310);
uniform vec3 rock_color : source_color = vec3(0.341, 0.318, 0.298);
uniform vec3 sand_color : source_color = vec3(0.639, 0.596, 0.463);
uniform float height_scale = 900.0;
uniform float grain_scale = 0.08;

varying float v_height;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_height = VERTEX.y;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = clamp(v_height / height_scale, 0.0, 1.0);
	float slope = 1.0 - clamp(dot(v_world_normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);

	vec3 c = mix(low_color, mid_color, smoothstep(0.02, 0.35, h));
	c = mix(c, high_color, smoothstep(0.35, 0.80, h));
	c = mix(c, rock_color, smoothstep(0.30, 0.65, slope));
	c = mix(sand_color, c, smoothstep(0.0, 0.015, h));

	float grain = fract(sin(dot(floor(v_world_pos.xz * grain_scale), vec2(12.9898, 78.233))) * 43758.5453);
	c *= 0.94 + grain * 0.12;

	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.08;
}
