// Losa de hormigón de la parcela: «lo fabricado se modela», textura limpia (no pixel art).
// Rejilla de 1 m para construir y franja de seguridad en el borde de la parcela.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 rect = vec4(16.0, 40.0, 56.0, 48.0);   // x, z, ancho, fondo
uniform float rejilla_visible = 0.35;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	vec3 col = vec3(0.2, 0.22, 0.25);
	col *= 0.94 + 0.06 * hash(floor(p * 3.0));
	vec2 f = abs(fract(p) - 0.5);
	float linea = smoothstep(0.47, 0.5, max(f.x, f.y));
	vec2 f2 = abs(fract(p * 0.25) - 0.5);
	float linea4 = smoothstep(0.485, 0.5, max(f2.x, f2.y));
	col = mix(col, vec3(0.06, 0.08, 0.11), linea * rejilla_visible + linea4 * 0.35);
	vec2 rel = p - rect.xy;
	float borde = min(min(rel.x, rect.z - rel.x), min(rel.y, rect.w - rel.y));
	if (borde < 0.45) {
		float raya = step(0.5, fract((p.x + p.y) * 0.9));
		col = mix(vec3(0.02, 0.02, 0.03), vec3(0.85, 0.45, 0.02), raya);
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
