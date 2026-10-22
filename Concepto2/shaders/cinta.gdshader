// Cinta transportadora: franjas que avanzan por el eje X local de cada segmento.
// INSTANCE_CUSTOM.r = 1 mientras está en obra (holograma), .g = atascada (parpadeo ámbar).
shader_type spatial;

uniform float velocidad = 1.6;
uniform float tiempo_sim = 0.0;

varying float obra;
varying float atasco;
varying float lx;

void vertex() {
	obra = INSTANCE_CUSTOM.r;
	atasco = INSTANCE_CUSTOM.g;
	lx = VERTEX.x;
}

void fragment() {
	vec3 col = vec3(0.07, 0.08, 0.09);
	float franja = step(0.55, fract(lx * 3.0 - tiempo_sim * velocidad));
	// Solo la cara superior lleva franjas (normal hacia arriba).
	float arriba = step(0.7, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	col = mix(col, vec3(0.16, 0.18, 0.2), franja * arriba);
	if (arriba < 0.5) col = vec3(0.24, 0.3, 0.38);
	if (atasco > 0.5 && arriba > 0.5) col = mix(col, vec3(1.0, 0.55, 0.1), 0.35 + 0.25 * sin(TIME * 8.0));
	ALBEDO = col;
	ROUGHNESS = 0.6;
	if (obra > 0.5) {
		ALBEDO = vec3(0.2, 0.8, 1.0);
		EMISSION = vec3(0.1, 0.5, 0.7);
	}
}
