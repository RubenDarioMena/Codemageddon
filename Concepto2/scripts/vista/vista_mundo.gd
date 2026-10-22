class_name VistaMundo
extends Node3D
## Naturaleza (pixel art), losa, carreteras, puente, ciudad 3D, luz del día y suelo que reacciona.

var sim: Simulacion
var sol: DirectionalLight3D
var entorno: WorldEnvironment
var mat_sprites: ShaderMaterial
var mat_terreno: ShaderMaterial
var mats_edificios: Array[ShaderMaterial] = []
var img_estado: Image
var tex_estado: ImageTexture
var atlas_rects := {}
var atlas_tam := 1024
var mm_menas: MultiMeshInstance3D
var fases_mena := {}            # id -> [rects por fase]
var tex_humo: ImageTexture
var _t_estado := 0.0
var _contam := PackedFloat32Array()
var _desgaste := PackedFloat32Array()


func construir(p_sim: Simulacion) -> void:
	sim = p_sim
	_luz()
	_terreno()
	_sprites()
	_losa()
	_carreteras()
	_ciudad()


# ---------------------------------------------------------------- luz y ambiente

func _luz() -> void:
	sol = DirectionalLight3D.new()
	sol.shadow_enabled = true
	sol.directional_shadow_max_distance = 140.0
	sol.light_energy = 1.0
	add_child(sol)
	# Luz «desde arriba a la izquierda» como el sombreado dibujado de los sprites.
	sol.look_at_from_position(Vector3.ZERO, Vector3(0.9, -1.6, 0.55), Vector3.UP)
	entorno = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0c1420")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9fb4d8")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.2
	entorno.environment = env
	add_child(entorno)


## 0 = pleno día, 1 = noche cerrada.
func noche_factor(h: float) -> float:
	if h >= 7.0 and h <= 19.0:
		return 0.0
	if h > 19.0 and h < 22.0:
		return (h - 19.0) / 3.0
	if h >= 4.0 and h < 7.0:
		return 1.0 - (h - 4.0) / 3.0
	return 1.0


func actualizar(delta: float) -> void:
	var nf := noche_factor(sim.hora())
	sol.light_energy = lerp(1.0, 0.15, nf)
	sol.light_color = Color("fff1d6").lerp(Color("8fa6ff"), nf)
	entorno.environment.ambient_light_color = Color("9fb4d8").lerp(Color("3a4a8a"), nf)
	entorno.environment.ambient_light_energy = lerp(0.4, 0.3, nf)
	mat_sprites.set_shader_parameter("luz", lerp(1.0, 0.42, nf))
	mat_sprites.set_shader_parameter("tinte", Color.WHITE.lerp(Color("8ea2ff"), nf))
	for m in mats_edificios:
		m.set_shader_parameter("noche", nf)
	_t_estado += delta
	if _t_estado > 0.5:
		_actualizar_estado(_t_estado)
		_actualizar_menas()
		_t_estado = 0.0


# ---------------------------------------------------------------- terreno

func _terreno() -> void:
	var rj := sim.rejilla
	var img := Image.create_empty(rj.ancho, rj.alto, false, Image.FORMAT_RGBA8)
	var bosque := PackedFloat32Array()
	bosque.resize(rj.ancho * rj.alto)
	for f in rj.flora:
		if f.bloquea:
			var c := Vector2i(floor(f.pos.x), floor(f.pos.y))
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var q := c + Vector2i(dx, dz)
					if rj.dentro(q):
						bosque[rj.idx(q)] += 0.34 if dx == 0 and dz == 0 else 0.12
	for z in rj.alto:
		for x in rj.ancho:
			var i := z * rj.ancho + x
			img.set_pixel(x, z, Color(rj.agua[i], rj.humedad[i], 0.0, clamp(bosque[i], 0.0, 1.0)))
	img_estado = Image.create_empty(rj.ancho, rj.alto, false, Image.FORMAT_RGBA8)
	img_estado.fill(Color(0, 0, 0, 1))
	tex_estado = ImageTexture.create_from_image(img_estado)
	_contam.resize(rj.ancho * rj.alto)
	_desgaste.resize(rj.ancho * rj.alto)
	mat_terreno = ShaderMaterial.new()
	mat_terreno.shader = load("res://shaders/terreno.gdshader")
	mat_terreno.set_shader_parameter("mapa", ImageTexture.create_from_image(img))
	mat_terreno.set_shader_parameter("estado", tex_estado)
	mat_terreno.set_shader_parameter("tam_mapa", Vector2(rj.ancho, rj.alto))
	var plano := PlaneMesh.new()
	plano.size = Vector2(rj.ancho + 120, rj.alto + 120)
	var mi := MeshInstance3D.new()
	mi.mesh = plano
	mi.material_override = mat_terreno
	mi.position = Vector3(rj.ancho * 0.5, 0.0, rj.alto * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _actualizar_estado(dt: float) -> void:
	var rj := sim.rejilla
	for r in sim.robots:
		var c := r.celda()
		if rj.dentro(c) and r.estado == "yendo":
			_desgaste[rj.idx(c)] = min(1.0, _desgaste[rj.idx(c)] + 0.02)
	for m: Maquina in sim.maquinas.values():
		if m.estado != "trabajando" or m.humo() <= 0.0:
			continue
		var cen := m.centro()
		var radio := 9
		for dz in range(-radio, radio + 1):
			for dx in range(-radio, radio + 1):
				var q := Vector2i(floor(cen.x) + dx, floor(cen.y) + dz)
				if not rj.dentro(q):
					continue
				var d := Vector2(dx, dz).length() / radio
				if d < 1.0:
					var i := rj.idx(q)
					_contam[i] = min(1.0, _contam[i] + dt * 0.004 * m.humo() * (1.0 - d))
	for z in rj.alto:
		for x in rj.ancho:
			var i := z * rj.ancho + x
			if _desgaste[i] > 0.0 or _contam[i] > 0.0:
				img_estado.set_pixel(x, z, Color(_desgaste[i], _contam[i], 0.0, 1.0))
	tex_estado.update(img_estado)


# ---------------------------------------------------------------- sprites

func _sprites() -> void:
	var entradas := {}
	for i in 6:
		entradas["pino%d" % i] = Pixel.pino(100 + i)
		entradas["arbol%d" % i] = Pixel.arbol(200 + i)
		entradas["arbusto%d" % i] = Pixel.arbusto(300 + i)
		entradas["pasto%d" % i] = Pixel.pasto(400 + i)
	for i in 4:
		entradas["flores%d" % i] = Pixel.flores(500 + i)
		entradas["roca%d" % i] = Pixel.roca(600 + i)
	for i in 6:
		var fases := Pixel.cobre(700 + i)
		for f in 4:
			entradas["cobre%d_%d" % [i, f]] = fases[f]
	var at := Pixel.atlas(entradas, atlas_tam)
	atlas_rects = at.rects
	var tex := ImageTexture.create_from_image(at.imagen)
	mat_sprites = ShaderMaterial.new()
	mat_sprites.shader = load("res://shaders/sprite.gdshader")
	mat_sprites.set_shader_parameter("atlas", tex)

	var flora := sim.rejilla.flora
	var mm := _multimesh(flora.size())
	for k in flora.size():
		var f: Dictionary = flora[k]
		var n: String = f.clase + str(f.semilla % (4 if f.clase in ["flores", "roca"] else 6))
		_poner_sprite(mm, k, n, Vector3(f.pos.x, 0.0, f.pos.y))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat_sprites
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var menas := sim.rejilla.menas
	var mm2 := _multimesh(menas.size())
	for k in menas.size():
		var m: Dictionary = menas[k]
		fases_mena[m.id] = k % 6
	mm_menas = MultiMeshInstance3D.new()
	mm_menas.multimesh = mm2
	mm_menas.material_override = mat_sprites
	add_child(mm_menas)
	_actualizar_menas()

	var humo := Pixel.humo(4)
	tex_humo = ImageTexture.create_from_image(humo.img)


func _multimesh(n: int) -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.center_offset = Vector3(0, 0.5, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = n
	return mm


func _poner_sprite(mm: MultiMesh, k: int, nombre: String, pos: Vector3) -> void:
	var r: Rect2i = atlas_rects[nombre]
	var b := Basis.from_scale(Vector3(r.size.x / 16.0, r.size.y / 16.0, 1.0))
	mm.set_instance_transform(k, Transform3D(b, pos))
	var t := float(atlas_tam)
	mm.set_instance_custom_data(k, Color(r.position.x / t, r.position.y / t, r.end.x / t, r.end.y / t))


func _actualizar_menas() -> void:
	var menas := sim.rejilla.menas
	for k in menas.size():
		var m: Dictionary = menas[k]
		var frac: float = float(m.cantidad) / m.max
		var fase := 3 if m.cantidad <= 0 else (0 if frac > 0.66 else (1 if frac > 0.33 else 2))
		_poner_sprite(mm_menas.multimesh, k, "cobre%d_%d" % [fases_mena[m.id], fase],
			Vector3(m.celda.x + 0.5, 0.0, m.celda.y + 0.5))


# ---------------------------------------------------------------- losa, carreteras y puente

func _losa() -> void:
	var p := Cfg.PARCELA
	var caja := BoxMesh.new()
	caja.size = Vector3(p.size.x, 0.1, p.size.y)
	var mi := MeshInstance3D.new()
	mi.mesh = caja
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/losa.gdshader")
	mat.set_shader_parameter("rect", Vector4(p.position.x, p.position.y, p.size.x, p.size.y))
	mi.material_override = mat
	mi.position = Vector3(p.position.x + p.size.x * 0.5, 0.05, p.position.y + p.size.y * 0.5)
	mi.name = "Losa"
	add_child(mi)
	var cartel := Label3D.new()
	cartel.text = "CODEMAGEDDON S.A. · PARCELA 1"
	cartel.font_size = 96
	cartel.pixel_size = 0.01
	cartel.modulate = Color(1, 1, 1, 0.55)
	cartel.rotation_degrees = Vector3(-90, 0, 0)
	cartel.position = Vector3(p.position.x + p.size.x * 0.5, 0.11, p.end.y - 2.0)
	add_child(cartel)


func _tira(puntos: Array, ancho: float, y: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in puntos.size() - 1:
		var a: Vector2 = puntos[k]
		var b: Vector2 = puntos[k + 1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * ancho * 0.5
		var ext := d * ancho * 0.5 if k < puntos.size() - 2 else Vector2.ZERO
		var v := [a - n, a + n, b + ext + n, b + ext - n]
		st.set_normal(Vector3.UP)
		for idx in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(Vector3(v[idx].x, y, v[idx].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	return mi


func _carreteras() -> void:
	var asfalto := StandardMaterial3D.new()
	asfalto.albedo_color = Color("2a2d33")
	asfalto.roughness = 0.9
	var linea := StandardMaterial3D.new()
	linea.albedo_color = Color("e8c34a")
	_tira(Cfg.RUTA_PROVEEDOR, 3.2, 0.04, asfalto)
	_tira(Cfg.RUTA_VENTA, 3.2, 0.04, asfalto)
	for ruta in [Cfg.RUTA_PROVEEDOR, Cfg.RUTA_VENTA]:
		for k in ruta.size() - 1:
			var a: Vector2 = ruta[k]
			var b: Vector2 = ruta[k + 1]
			var l := a.distance_to(b)
			var s := 1.0
			while s < l - 1.0:
				var p := a.lerp(b, s / l)
				var q := a.lerp(b, min(s + 1.2, l) / l)
				_tira([p, q], 0.14, 0.06, linea)
				s += 3.0
	# Puente sobre el río: tablero, barandillas y pilares.
	var px := sim.rejilla.puente_x
	if px.x < px.y:
		var acero := StandardMaterial3D.new()
		acero.albedo_color = Color("55657d")
		acero.metallic = 0.5
		var x0 := px.x - 1.0
		var x1 := px.y + 1.0
		var z := 61.5
		_caja(Vector3((x0 + x1) * 0.5, 0.18, z), Vector3(x1 - x0, 0.2, 3.6), asfalto)
		for lado in [-1.0, 1.0]:
			_caja(Vector3((x0 + x1) * 0.5, 0.6, z + lado * 1.85), Vector3(x1 - x0, 0.08, 0.1), acero)
			var x := x0
			while x <= x1:
				_caja(Vector3(x, 0.4, z + lado * 1.85), Vector3(0.1, 0.5, 0.1), acero)
				x += 1.5
		var x2 := x0 + 2.0
		while x2 < x1 - 1.0:
			_caja(Vector3(x2, -0.2, z), Vector3(0.5, 0.6, 3.0), acero)
			x2 += 4.0


func _caja(pos: Vector3, tam: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = tam
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


# ---------------------------------------------------------------- ciudad

func _ciudad() -> void:
	var c := Cfg.CIUDAD
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var acera := StandardMaterial3D.new()
	acera.albedo_color = Color("6c7178")
	acera.roughness = 0.9
	var calle := StandardMaterial3D.new()
	calle.albedo_color = Color("34373d")
	_caja(Vector3(c.position.x + c.size.x * 0.5, 0.03, c.position.y + c.size.y * 0.5), Vector3(c.size.x, 0.06, c.size.y), acera)
	var colores := [Color("d9cbb4"), Color("c9a98a"), Color("b8c4cc"), Color("e0d6c2"), Color("a7b59a"), Color("cfb0a8")]
	for i in colores.size():
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/edificio.gdshader")
		m.set_shader_parameter("color_base", colores[i])
		m.set_shader_parameter("semilla", float(i) * 7.3)
		mats_edificios.append(m)
	var verde := StandardMaterial3D.new()
	verde.albedo_color = Color("4f8a46")
	var copa := StandardMaterial3D.new()
	copa.albedo_color = Color("2f6b3a")
	var tronco := StandardMaterial3D.new()
	tronco.albedo_color = Color("6b4a32")
	var paso := 13
	var z := c.position.y + 1
	while z < c.end.y - 4:
		var x := c.position.x + 4
		while x < c.end.x - 4:
			var bloque := Rect2(x, z, paso - 3, paso - 3)
			# Calle principal (la carretera de venta entra por aquí).
			if bloque.position.y < 64.5 and bloque.end.y > 58.5:
				x += paso
				continue
			_caja(Vector3(bloque.get_center().x, 0.0, bloque.get_center().y), Vector3(paso, 0.08, 0.6), calle)
			var centro_d: float = abs(bloque.get_center().y - 64.0) / 50.0
			if rng.randf() < 0.14:
				_caja(Vector3(bloque.get_center().x, 0.07, bloque.get_center().y), Vector3(bloque.size.x, 0.04, bloque.size.y), verde)
				for k in 5:
					var p := bloque.position + Vector2(rng.randf_range(1, bloque.size.x - 1), rng.randf_range(1, bloque.size.y - 1))
					_arbol_3d(Vector3(p.x, 0.0, p.y), rng.randf_range(0.8, 1.3), copa, tronco)
			else:
				var n := rng.randi_range(2, 4)
				for k in n:
					var w := bloque.size.x / 2.0 - 0.4 if n > 1 else bloque.size.x
					var d := bloque.size.y / 2.0 - 0.4
					var p := bloque.position + Vector2((k % 2) * (w + 0.8) + w * 0.5, (k / 2) * (d + 0.8) + d * 0.5)
					var alto := rng.randf_range(3.0, 7.0) + (1.0 - centro_d) * rng.randf_range(2.0, 11.0)
					var e := _caja(Vector3(p.x, alto * 0.5, p.y), Vector3(w, alto, d), mats_edificios[rng.randi() % mats_edificios.size()])
					e.name = "edificio"
			x += paso
		z += paso
	# Mercado a la entrada de la ciudad, donde venden los camiones.
	var toldo := StandardMaterial3D.new()
	toldo.albedo_color = Color("d9503f")
	for k in 3:
		_caja(Vector3(144.5 + k * 2.2, 1.6, 57.2), Vector3(1.9, 0.12, 1.8), toldo)
		_caja(Vector3(144.5 + k * 2.2, 0.5, 57.2), Vector3(1.6, 1.0, 1.2), mats_edificios[0])
	var cartel := Label3D.new()
	cartel.text = "MERCADO"
	cartel.font_size = 64
	cartel.pixel_size = 0.012
	cartel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cartel.position = Vector3(146.7, 2.6, 57.2)
	cartel.modulate = Color("ffd27a")
	add_child(cartel)


func _arbol_3d(pos: Vector3, escala: float, copa: Material, tronco: Material) -> void:
	var t := CylinderMesh.new()
	t.top_radius = 0.08 * escala
	t.bottom_radius = 0.1 * escala
	t.height = 0.8 * escala
	var mt := MeshInstance3D.new()
	mt.mesh = t
	mt.material_override = tronco
	mt.position = pos + Vector3(0, 0.4 * escala, 0)
	add_child(mt)
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.55 * escala
	c.height = 1.6 * escala
	var mc := MeshInstance3D.new()
	mc.mesh = c
	mc.material_override = copa
	mc.position = pos + Vector3(0, 1.4 * escala, 0)
	add_child(mc)
