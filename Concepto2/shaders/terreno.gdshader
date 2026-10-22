// Terreno pixel art a 16 px/m calculado por píxel a partir de un mapa lógico de 1 texel/m.
// El mapa (lineal) da agua y humedad; el ruido por píxel y el tramado Bayer dan bordes orgánicos.
// `estado` (desgaste, contaminación) lo actualiza la presentación: los robots abren caminos y
// la fundidora seca el pasto. Es solo visual: no toca la simulación.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D mapa : filter_linear, repeat_disable;
uniform sampler2D estado : filter_linear, repeat_disable;
uniform vec2 tam_mapa = vec2(192.0, 128.0);
uniform float ppm = 16.0;

varying vec3 wpos;

const float B4[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	return (B4[i.y * 4 + i.x] + 0.5) / 16.0;
}
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
vec3 srgb(vec3 c) { return pow(c, vec3(2.2)); }
vec3 hex(int h) { return srgb(vec3(float((h >> 16) & 255), float((h >> 8) & 255), float(h & 255)) / 255.0); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 px = floor(wpos.xz * ppm);           // coordenada de píxel del mundo
	vec2 uv = (px + 0.5) / ppm / tam_mapa;
	vec4 d = texture(mapa, uv);
	vec4 e = texture(estado, uv);
	float b = bayer(px);
	float n = vnoise(px * 0.09) * 0.6 + vnoise(px * 0.31) * 0.4;
	float agua = d.r + (n - 0.5) * 0.16;
	vec3 col;
	if (agua > 0.5) {
		float prof = clamp((agua - 0.5) * 2.4 + (b - 0.5) * 0.25, 0.0, 1.0);
		col = prof > 0.55 ? hex(0x24477e) : (prof > 0.22 ? hex(0x34679f) : hex(0x4f8fc4));
		// Reflejos que corren en pasos de píxel.
		float ola = step(0.94, vnoise(vec2(px.x * 0.15 + floor(TIME * 6.0) * 0.5, px.y * 0.9)));
		if (ola > 0.5 && prof > 0.2) col = hex(0x4f8fc4);
		if (agua < 0.53) col = hex(0xa9dcf2);
	} else if (agua > 0.4) {
		col = (n + (b - 0.5) * 0.3) > 0.5 ? hex(0xd9c38a) : hex(0xbfa56c);
	} else {
		float h = d.g + (n - 0.5) * 0.35 + (b - 0.5) * 0.18;
		int k = int(clamp(h * 4.6 - 0.6, 0.0, 4.0));
		vec3 pastos[5] = vec3[](hex(0x8fc463), hex(0x6aa84f), hex(0x4a8c45), hex(0x36743d), hex(0x2b5f35));
		col = pastos[k];
		// Sombra del bosque: más oscuro bajo los árboles.
		if (d.a + (b - 0.5) * 0.4 > 0.55) col = mix(col, hex(0x1f4a2c), 0.45);
		// Desgaste por orugas.
		float des = e.r + (n - 0.5) * 0.3 + (b - 0.5) * 0.25;
		if (des > 0.75) col = (n > 0.5) ? hex(0x7a573a) : hex(0x5c4130);
		else if (des > 0.45) col = (b > 0.5) ? hex(0x73784a) : hex(0x5d6b3b);
		// Contaminación alrededor de la fundición.
		float con = e.g + (n - 0.5) * 0.3 + (b - 0.5) * 0.3;
		if (con > 0.8) col = hex(0x585852);
		else if (con > 0.55) col = (b > 0.5) ? hex(0x858160) : hex(0x6b6a4e);
		else if (con > 0.35) col = mix(col, hex(0x9c9672), 0.35);
	}
	// El terreno recibe sol y ambiente; se oscurece para casar con los sprites (sin iluminar).
	ALBEDO = col * 0.62;
	ROUGHNESS = 1.0;
}
