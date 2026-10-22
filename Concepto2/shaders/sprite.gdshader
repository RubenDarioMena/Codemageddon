// Sprite pixel art en un MultiMesh: mira a la cámara y todo él queda a la profundidad de su base,
// así ordena como en 2D dentro del mundo 3D (Concepto 1, decisión 3).
// INSTANCE_CUSTOM = rectángulo en el atlas (u0, v0, u1, v1). La escala de la instancia = tamaño en m.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D atlas : filter_nearest, source_color;
uniform float luz : hint_range(0.0, 1.5) = 1.0;
uniform vec3 tinte : source_color = vec3(1.0);

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 derecha = INV_VIEW_MATRIX[0].xyz;
	vec3 arriba = INV_VIEW_MATRIX[1].xyz;
	vec3 p = base + derecha * VERTEX.x * sx + arriba * VERTEX.y * sy;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	// Toda la superficie a la profundidad de la base, tomada un poco hacia la cámara para no cortarse con el suelo.
	vec3 hacia_cam = INV_VIEW_MATRIX[2].xyz;
	vec4 pb = PROJECTION_MATRIX * VIEW_MATRIX * vec4(base + hacia_cam * 0.35, 1.0);
	POSITION.z = pb.z / pb.w * POSITION.w;
	UV = mix(INSTANCE_CUSTOM.xy, INSTANCE_CUSTOM.zw, vec2(UV.x, UV.y));
}

void fragment() {
	vec4 c = texture(atlas, UV);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * luz * tinte;
}
