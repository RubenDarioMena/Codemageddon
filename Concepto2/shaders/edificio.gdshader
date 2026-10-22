// Edificios de la ciudad: fachada con ventanas que se encienden de noche.
shader_type spatial;

uniform vec3 color_base : source_color = vec3(0.8, 0.75, 0.68);
uniform float noche = 0.0;
uniform float semilla = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = color_base * 0.7;
	float lateral = 1.0 - step(0.7, abs(wnorm.y));
	vec2 f = abs(wnorm.x) > 0.5 ? wpos.zy : wpos.xy;
	vec2 celda = floor(vec2(f.x / 1.2, (f.y - 0.4) / 1.5));
	vec2 r = fract(vec2(f.x / 1.2, (f.y - 0.4) / 1.5));
	float ventana = step(0.25, r.x) * step(r.x, 0.75) * step(0.3, r.y) * step(r.y, 0.8) * step(0.6, f.y) * lateral;
	float encendida = step(0.45, hash(celda + semilla));
	col = mix(col, vec3(0.16, 0.22, 0.3), ventana);
	if (lateral < 0.5) col = vec3(0.32, 0.33, 0.36);   // azotea
	ALBEDO = col;
	ROUGHNESS = 0.8;
	EMISSION = vec3(1.0, 0.78, 0.4) * ventana * encendida * noche * 1.6;
}
