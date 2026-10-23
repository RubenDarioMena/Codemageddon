class_name VistaFabrica
extends Node3D
## Traduce el estado de la simulación a nodos: máquinas GLB animadas, cintas, objetos en tránsito,
## material en el suelo, camiones y el piquete de la ciudad.

const COLOR_ESTADO := {
	"trabajando": Color("3fe08a"), "inactiva": Color("8a96a8"), "sin_insumo": Color("ffb547"),
	"salida_llena": Color("ff5a5a"), "pausada": Color("6a7383"), "turno": Color("7a8cff"),
	"construyendo": Color("59f0ff"), "averiada": Color("ff3b3b"),
}
const ICONO_ESTADO := {
	"sin_insumo": "⚠ sin insumo", "salida_llena": "■ salida llena", "pausada": "❚❚ pausada",
	"turno": "☾ turno diurno", "averiada": "✖ averiada",
}
## Flechas de puertos: por dónde entra (verde, apunta a la máquina) y sale (roja, apunta hacia fuera)
## el material de las cintas. Parpadean hasta que una cinta las conecta.
const COLOR_ENTRADA := Color("3fe08a")
const COLOR_SALIDA := Color("ff5a5a")
const ALTURA_FLECHA := 0.7
const ESCALA_FLECHA := 1.2

var sim: Simulacion
var escenas := {}
var nodos_maq := {}        # id -> {raiz, anim, luz: StandardMaterial3D, etiqueta, humo, mallas}
var nodos_cam := {}        # id -> Node3D
var mm_cintas: MultiMeshInstance3D
var mm_items: MultiMeshInstance3D
var mm_suelo: MultiMeshInstance3D
var mm_pilas: MultiMeshInstance3D
var mm_puertos: MultiMeshInstance3D
var mm_puertos_fantasma: MultiMeshInstance3D
var fantasma: Maquina      # máquina en colocación (la pone ControlRTS); null = ninguna
var mat_cinta: ShaderMaterial
var mat_obra: StandardMaterial3D
var piquete: Node3D
var tex_humo: Texture2D


func construir(p_sim: Simulacion, p_tex_humo: Texture2D) -> void:
	sim = p_sim
	tex_humo = p_tex_humo
	for n in ["fundidora", "ensambladora", "fabrica_robots", "recepcion", "despacho", "servidor", "camion"]:
		escenas[n] = load("res://assets/modelos/%s.glb" % n)
	mat_obra = StandardMaterial3D.new()
	mat_obra.albedo_color = Color(0.35, 0.85, 1.0, 0.35)
	mat_obra.emission_enabled = true
	mat_obra.emission = Color(0.1, 0.55, 0.8)
	mat_obra.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_obra.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mat_cinta = ShaderMaterial.new()
	mat_cinta.shader = load("res://shaders/cinta.gdshader")
	var caja := BoxMesh.new()
	caja.size = Vector3(1.0, 0.16, 0.78)
	mm_cintas = _mmi(caja, mat_cinta, true, false)

	var item := BoxMesh.new()
	item.size = Vector3(0.24, 0.16, 0.24)
	var mat_item := StandardMaterial3D.new()
	mat_item.vertex_color_use_as_albedo = true
	mat_item.metallic = 0.4
	mat_item.roughness = 0.4
	mm_items = _mmi(item, mat_item, false, true)
	var pila := BoxMesh.new()
	pila.size = Vector3(0.34, 0.28, 0.34)
	mm_suelo = _mmi(pila, mat_item, false, true)
	mm_pilas = _mmi(pila, mat_item, false, true)

	# Las flechas son interfaz sobre el mundo: sin luz y siempre visibles, como las etiquetas.
	var mat_flecha := StandardMaterial3D.new()
	mat_flecha.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_flecha.vertex_color_use_as_albedo = true
	mat_flecha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_flecha.no_depth_test = true
	mat_flecha.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flecha := malla_flecha()
	mm_puertos = _mmi(flecha, mat_flecha, false, true)
	mm_puertos_fantasma = _mmi(flecha, mat_flecha, false, true)
	_crear_piquete()


func _mmi(malla: Mesh, mat: Material, custom: bool, colores: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.use_colors = colores
	mm.mesh = malla
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
	return mi


static func transform_maquina(m: Maquina) -> Transform3D:
	var c := m.centro()
	return Transform3D(Basis(Vector3.UP, -m.rot * PI / 2.0), Vector3(c.x, 0.1, c.y))


## Instancia un modelo de máquina (también lo usa el fantasma de construcción).
func instanciar_modelo(tipo: String) -> Node3D:
	return escenas[Cfg.MAQUINAS[tipo].modelo].instantiate()


func actualizar(alfa: float, velocidad: float) -> void:
	_sincronizar_maquinas(velocidad)
	_actualizar_cintas()
	_actualizar_items(alfa)
	_actualizar_suelo()
	_actualizar_camiones(alfa)
	_actualizar_puertos()
	piquete.visible = sim.ciudad.bloqueada()
	if piquete.visible:
		for k in piquete.get_child_count():
			var p := piquete.get_child(k) as Node3D
			p.position.y = abs(sin(Time.get_ticks_msec() / 220.0 + k)) * 0.12


# ---------------------------------------------------------------- máquinas

func _sincronizar_maquinas(velocidad: float) -> void:
	for id in nodos_maq.keys():
		if not sim.maquinas.has(id):
			nodos_maq[id].raiz.queue_free()
			nodos_maq.erase(id)
	for m: Maquina in sim.maquinas.values():
		if not nodos_maq.has(m.id):
			_crear_maquina(m)
		var n: Dictionary = nodos_maq[m.id]
		var en_obra := not m.lista()
		if en_obra != n.en_obra:
			n.en_obra = en_obra
			for mi in n.mallas:
				(mi as MeshInstance3D).material_override = mat_obra if en_obra else null
		if en_obra:
			var avance := 1.0 - m.obra / Cfg.T_CONSTRUIR
			n.modelo.scale = Vector3(1.0, max(0.05, avance), 1.0)
		else:
			n.modelo.scale = Vector3.ONE
		var col: Color = COLOR_ESTADO.get(m.estado, Color.WHITE)
		if n.luz:
			n.luz.albedo_color = col
			n.luz.emission = col
		if n.anim:
			var debe := m.estado == "trabajando" and velocidad > 0.0
			if debe and not n.anim.is_playing():
				n.anim.play(n.anim_nombre)
			elif not debe and n.anim.is_playing():
				n.anim.pause()
			n.anim.speed_scale = max(velocidad, 0.01)
		if n.humo:
			n.humo.emitting = m.estado == "trabajando"
		var aviso: String = ICONO_ESTADO.get(m.estado, "")
		n.etiqueta.text = m.id + ("\n" + aviso if aviso != "" else "")
		n.etiqueta.modulate = col if aviso != "" else Color(1, 1, 1, 0.8)
		if m.tipo == "recepcion":
			_pilas_recepcion(m)


func _crear_maquina(m: Maquina) -> void:
	var raiz := Node3D.new()
	raiz.transform = transform_maquina(m)
	add_child(raiz)
	var modelo := instanciar_modelo(m.tipo)
	raiz.add_child(modelo)
	var n := {"raiz": raiz, "modelo": modelo, "anim": null, "anim_nombre": "", "luz": null, "humo": null,
		"mallas": [], "en_obra": false}
	for c in modelo.find_children("*", "", true, false):
		if c is AnimationPlayer:
			var lista: PackedStringArray = c.get_animation_list()
			if not lista.is_empty():
				n.anim = c
				n.anim_nombre = lista[0]
				c.get_animation(lista[0]).loop_mode = Animation.LOOP_LINEAR
		elif c is MeshInstance3D:
			n.mallas.append(c)
			if c.name == "luz_estado":
				var mat := StandardMaterial3D.new()
				mat.emission_enabled = true
				mat.emission_energy_multiplier = 2.5
				c.set_surface_override_material(0, mat)
				n.luz = mat
	if m.tipo == "fundidora":
		n.humo = _humo(Vector3(0.55, 3.0, -0.55))
		raiz.add_child(n.humo)
	var et := Label3D.new()
	et.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	et.font_size = 40
	et.pixel_size = 0.012
	et.outline_size = 10
	et.position = Vector3(0, 3.4, 0)
	et.no_depth_test = true
	et.fixed_size = false
	raiz.add_child(et)
	n.etiqueta = et
	nodos_maq[m.id] = n


func _humo(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex_humo
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	q.material = mat
	p.mesh = q
	p.position = pos
	p.amount = 14
	p.lifetime = 3.5
	p.direction = Vector3(0.3, 1, 0.2)
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.15, 0.05, 0.1)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.6))
	curva.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curva
	p.emitting = false
	return p


## Flecha plana que apunta a +X, con borde oscuro: el color de la instancia tiñe el relleno
## (vértices blancos) y el borde (vértices negros) sigue negro. Sin prueba de profundidad, los
## triángulos se pintan en orden: primero el borde, encima el relleno.
static func malla_flecha() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# [color, cola, cuello, medio grosor del asta, media ala de la punta, punta]
	for capa in [[Color.BLACK, -0.42, -0.02, 0.15, 0.36, 0.52], [Color.WHITE, -0.36, 0.05, 0.09, 0.27, 0.42]]:
		var cola: float = capa[1]
		var cuello: float = capa[2]
		var g: float = capa[3]
		var ala: float = capa[4]
		st.set_color(capa[0])
		for v in [Vector3(cola, 0, -g), Vector3(cuello, 0, -g), Vector3(cuello, 0, g),
				Vector3(cola, 0, -g), Vector3(cuello, 0, g), Vector3(cola, 0, g),
				Vector3(cuello, 0, -ala), Vector3(capa[5], 0, 0), Vector3(cuello, 0, ala)]:
			st.add_vertex(v)
	return st.commit()


## Puertos de cinta de una máquina: [casilla donde va la flecha, dirección del flujo, es_entrada].
## La flecha de entrada va en la casilla exterior donde termina la cinta que la alimenta (justo antes
## de `celda_entrada()`); la de salida, en `celda_salida()`. Solo tiene entrada quien acepta material
## y solo tiene salida quien lo empuja a una cinta (la fábrica de robots saca robots, no material).
static func puertos(m: Maquina) -> Array:
	var d := Cfg.dir_vec(m.rot)
	var res := []
	if m.def.has("cap_entrada"):
		res.append([m.celda_entrada() - d, d, true])
	if m.def.has("cap_salida"):
		res.append([m.celda_salida(), d, false])
	return res


func _actualizar_puertos() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var lista := []
	for m: Maquina in sim.maquinas.values():
		for pu in puertos(m):
			lista.append([pu, _conectado(m, pu)])
	_escribir_flechas(mm_puertos.multimesh, lista, t)
	var fl := []
	if fantasma != null:
		for pu in puertos(fantasma):
			fl.append([pu, false])
	_escribir_flechas(mm_puertos_fantasma.multimesh, fl, t)


## Un puerto está conectado si hay una cinta en su casilla que lleva el material en su sentido.
func _conectado(m: Maquina, pu: Array) -> bool:
	var b = sim.cintas.celdas.get(pu[0])
	if b == null:
		return false
	return b.dir == m.rot if pu[2] else b.dir != posmod(m.rot + 2, 4)


## Las flechas sin conectar flotan hacia el sentido del flujo y parpadean; las conectadas se
## quedan quietas y tenues, para que una fábrica montada no se llene de avisos.
func _escribir_flechas(mm: MultiMesh, lista: Array, t: float) -> void:
	if mm.instance_count < lista.size():
		mm.instance_count = lista.size() + 8
	mm.visible_instance_count = lista.size()
	var vaiven := sin(t * 5.0) * 0.12
	var pulso := 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 6.0))
	for k in lista.size():
		var pu: Array = lista[k][0]
		var conectado: bool = lista[k][1]
		var c: Vector2i = pu[0]
		var d: Vector2i = pu[1]
		var dir := Vector3(d.x, 0, d.y)
		var base := Basis(Vector3.UP, atan2(-float(d.y), float(d.x))).scaled(Vector3.ONE * ESCALA_FLECHA)
		var pos := Vector3(c.x + 0.5, ALTURA_FLECHA, c.y + 0.5) + dir * (0.0 if conectado else vaiven)
		mm.set_instance_transform(k, Transform3D(base, pos))
		var col: Color = COLOR_ENTRADA if pu[2] else COLOR_SALIDA
		col.a = 0.45 if conectado else pulso
		mm.set_instance_color(k, col)


func _pilas_recepcion(m: Maquina) -> void:
	# Cajas apiladas en el andén: cobre a un lado, silicio al otro. Se cuentan a simple vista.
	var mm := mm_pilas.multimesh
	var cobre := int(ceil(int(m.salida.get("cobre", 0)) / 2.0))
	var silicio := int(ceil(int(m.salida.get("silicio", 0)) / 2.0))
	var n: int = min(cobre, 30) + min(silicio, 30)
	if mm.instance_count < 60:
		mm.instance_count = 60
	mm.visible_instance_count = n
	var k := 0
	var base := transform_maquina(m)
	for pila in [["cobre", cobre, -0.75], ["silicio", silicio, 0.75]]:
		for i in min(pila[1], 30):
			var local := Vector3(0.35 + (i % 3) * 0.4, 0.32 + (i / 9) * 0.3, pila[2] + ((i / 3) % 3 - 1) * 0.4)
			mm.set_instance_transform(k, Transform3D(Basis(), base * local))
			mm.set_instance_color(k, Cfg.MATERIALES[pila[0]].color)
			k += 1


# ---------------------------------------------------------------- cintas y objetos

func _actualizar_cintas() -> void:
	var mm := mm_cintas.multimesh
	var celdas := sim.cintas.celdas
	if mm.instance_count != celdas.size():
		mm.instance_count = celdas.size()
	var k := 0
	for c in celdas:
		var b: Dictionary = celdas[c]
		var t := Transform3D(Basis(Vector3.UP, -b.dir * PI / 2.0), Vector3(c.x + 0.5, 0.18, c.y + 0.5))
		mm.set_instance_transform(k, t)
		mm.set_instance_custom_data(k, Color(1.0 if b.obra > 0.0 else 0.0, 1.0 if b.atasco else 0.0, 0, 0))
		k += 1
	mat_cinta.set_shader_parameter("tiempo_sim", sim.t)


func _actualizar_items(alfa: float) -> void:
	var mm := mm_items.multimesh
	var n := 0
	for c in sim.cintas.celdas:
		n += sim.cintas.celdas[c].items.size()
	if mm.instance_count < n:
		mm.instance_count = n + 32
	mm.visible_instance_count = n
	var k := 0
	for c in sim.cintas.celdas:
		var b: Dictionary = sim.cintas.celdas[c]
		for it in b.items:
			var s: float = lerp(float(it.ps), float(it.s), alfa)
			var p := Cintas.posicion(c, b.dir, s)
			mm.set_instance_transform(k, Transform3D(Basis(), Vector3(p.x, 0.34, p.y)))
			mm.set_instance_color(k, Cfg.MATERIALES[it.mat].color)
			k += 1


func _actualizar_suelo() -> void:
	var mm := mm_suelo.multimesh
	var total := 0
	for c in sim.suelo:
		total += min(int(sim.suelo[c].cant), 6)
	if mm.instance_count < total:
		mm.instance_count = total + 16
	mm.visible_instance_count = total
	var k := 0
	for c in sim.suelo:
		var p: Dictionary = sim.suelo[c]
		for i in min(int(p.cant), 6):
			var off := Vector3((i % 2) * 0.36 - 0.18, 0.14 + (i / 4) * 0.28, ((i / 2) % 2) * 0.36 - 0.18)
			var b := Basis(Vector3.UP, 0.3 * i)
			mm.set_instance_transform(k, Transform3D(b, Vector3(c.x + 0.5, 0.1, c.y + 0.5) + off))
			mm.set_instance_color(k, Cfg.MATERIALES[p.mat].color.darkened(0.15))
			k += 1


# ---------------------------------------------------------------- camiones y piquete

func _actualizar_camiones(alfa: float) -> void:
	var vivos := {}
	for c in sim.camiones:
		vivos[c.id] = true
		if not nodos_cam.has(c.id):
			var n: Node3D = escenas.camion.instantiate()
			add_child(n)
			nodos_cam[c.id] = n
		var nodo: Node3D = nodos_cam[c.id]
		var s: float = lerp(float(c.ps), float(c.s), alfa)
		var pr := Simulacion.punto_ruta(c.ruta, s)
		var dir: Vector2 = pr[1] if c.estado != "vuelta" else -pr[1]
		# Circula por la derecha.
		var lado := Vector2(-dir.y, dir.x) * 0.75
		var pos: Vector2 = pr[0] + lado
		var y := 0.3 if _en_puente(pos) else 0.05
		nodo.position = Vector3(pos.x, y, pos.y)
		nodo.rotation.y = atan2(-dir.x, -dir.y)
	for id in nodos_cam.keys():
		if not vivos.has(id):
			nodos_cam[id].queue_free()
			nodos_cam.erase(id)


func _en_puente(p: Vector2) -> bool:
	var px := sim.rejilla.puente_x
	return p.x > px.x - 1.0 and p.x < px.y + 1.0 and abs(p.y - 61.5) < 2.0


func _crear_piquete() -> void:
	piquete = Node3D.new()
	add_child(piquete)
	var pr := Simulacion.punto_ruta(Cfg.RUTA_VENTA, sim.s_bloqueo())
	var centro: Vector2 = pr[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ropa := [Color("c8553d"), Color("3d6fc8"), Color("e0b84a"), Color("5aa06a"), Color("8a5ac8")]
	for k in 16:
		var persona := Node3D.new()
		var cuerpo := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.16
		cap.height = 0.8
		cuerpo.mesh = cap
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ropa[k % ropa.size()]
		cuerpo.material_override = mat
		cuerpo.position.y = 0.45
		persona.add_child(cuerpo)
		if k % 3 == 0:
			var cartel := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.6, 0.4, 0.04)
			cartel.mesh = b
			var mc := StandardMaterial3D.new()
			mc.albedo_color = Color("f4efe2")
			cartel.material_override = mc
			cartel.position = Vector3(0, 1.25, 0)
			persona.add_child(cartel)
		var p := centro + Vector2(rng.randf_range(-1.8, 1.8), rng.randf_range(-1.6, 1.6))
		var raiz := Node3D.new()
		raiz.position = Vector3(p.x, 0.05, p.y)
		raiz.add_child(persona)
		piquete.add_child(raiz)
	var et := Label3D.new()
	et.text = "¡FUERA HUMO!"
	et.font_size = 56
	et.pixel_size = 0.012
	et.outline_size = 12
	et.modulate = Color("ff8a6a")
	et.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	et.position = Vector3(centro.x, 2.4, centro.y)
	piquete.add_child(et)
	piquete.visible = false
