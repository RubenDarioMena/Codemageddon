class_name ControlRTS
extends Node3D
## Entrada estilo Age of Empires II:
##   clic izquierdo = seleccionar (arrastrar = caja, doble clic = todos los del mismo nivel en pantalla,
##   Shift = añadir). Clic derecho = orden según el objetivo (mover, recoger, entregar, minar, reparar);
##   Shift + clic derecho = encolar. Ctrl+número = grupo; número = seleccionarlo (dos veces = centrar).
##   «.» = siguiente robot ocioso, H = la fábrica, Espacio = centrar en la selección.
##   B = menú de construcción (rejilla Q W E / A S D), R = girar, Shift = colocar varias, clic derecho/Esc = cancelar.
##   Supr = demoler, Ctrl+Z = deshacer la última obra. La rueda pulsada orbita la cámara.

signal seleccion_cambiada

var p: Node                       # principal: sim, cam, vfab, vrob, hud
var sim: Simulacion
var cam: CamaraRTS
var sel_robots: Array[int] = []
var sel_maquina := ""
var sel_otro := {}                # {tipo: "mena"/"camion", id}
var grupos := {}
var modo := "normal"              # normal · menu · colocar · cinta
var tipo_colocar := ""
var rot_colocar := 0
var fantasma: Node3D
var fantasma_mats: Array[StandardMaterial3D] = []
var fantasma_puertos: Node3D
var mm_previa: MultiMeshInstance3D
var marcador: MeshInstance3D
var capa: Control                 # dibuja la caja de selección
var _presion := Vector2.INF
var _arrastrando := false
var _cinta_inicio := Vector2i(-1, -1)
var _ultimo_grupo := -1
var _t_grupo := 0.0
var _t_marcador := 0.0
var _idx_ocioso := 0


func iniciar(principal: Node) -> void:
	p = principal
	sim = p.sim
	cam = p.cam
	capa = Control.new()
	capa.set_anchors_preset(Control.PRESET_FULL_RECT)
	capa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.draw.connect(_dibujar_capa)
	p.hud.capa_mundo.add_child(capa)
	var q := BoxMesh.new()
	q.size = Vector3(0.96, 0.05, 0.96)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm_previa = MultiMeshInstance3D.new()
	mm_previa.multimesh = mm
	mm_previa.material_override = mat
	add_child(mm_previa)
	marcador = MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = 0.3
	toro.outer_radius = 0.42
	marcador.mesh = toro
	var mm2 := StandardMaterial3D.new()
	mm2.albedo_color = Color("3fe08a")
	mm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm2.no_depth_test = true
	marcador.material_override = mm2
	marcador.scale = Vector3(1, 0.2, 1)
	marcador.visible = false
	add_child(marcador)


func escribiendo() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _process(delta: float) -> void:
	# En el menú de construcción, W/A/S/D/Q/E son atajos de edificios, no de cámara.
	cam.teclas_activas = not escribiendo() and modo != "menu"
	cam.rotacion_con_qe = modo == "normal"
	_t_grupo += delta
	if marcador.visible:
		_t_marcador += delta
		var s := 1.0 + _t_marcador * 2.0
		marcador.scale = Vector3(s, 0.2, s)
		if _t_marcador > 0.6:
			marcador.visible = false
	# Limpia la selección de cosas que ya no existen.
	if sel_maquina != "" and not sim.maquinas.has(sel_maquina):
		sel_maquina = ""
		seleccion_cambiada.emit()
	var raton := get_viewport().get_mouse_position()
	if modo == "colocar":
		_actualizar_fantasma(raton)
	elif modo == "cinta":
		_actualizar_previa_cinta(raton)
	p.vrob.seleccion = sel_robots
	capa.queue_redraw()


# ================================================================ entrada

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		_boton(e as InputEventMouseButton)
	elif e is InputEventMouseMotion:
		if _presion != Vector2.INF and e.position.distance_to(_presion) > 6.0 and modo == "normal":
			_arrastrando = true
	elif e is InputEventKey and e.pressed and not e.echo and not escribiendo():
		if _tecla(e as InputEventKey):
			get_viewport().set_input_as_handled()


func _boton(b: InputEventMouseButton) -> void:
	if b.button_index == MOUSE_BUTTON_LEFT:
		if b.pressed:
			_presion = b.position
			_arrastrando = false
			if modo == "cinta":
				_cinta_inicio = _celda_bajo(b.position)
			elif modo == "colocar":
				_colocar(b.shift_pressed)
				_presion = Vector2.INF
			elif b.double_click:
				_doble_clic(b.position)
				_presion = Vector2.INF
		else:
			if modo == "cinta" and _cinta_inicio.x >= 0:
				_poner_cinta(b.position, b.shift_pressed)
			elif _presion != Vector2.INF:
				if _arrastrando:
					_seleccion_caja(Rect2(_presion, b.position - _presion).abs(), b.shift_pressed)
				else:
					_clic(b.position, b.shift_pressed)
			_presion = Vector2.INF
			_arrastrando = false
		get_viewport().set_input_as_handled()
	elif b.button_index == MOUSE_BUTTON_RIGHT and b.pressed:
		if modo in ["colocar", "cinta", "menu"]:
			cancelar_modo()
		else:
			_orden(b.position, b.shift_pressed)
		get_viewport().set_input_as_handled()


func _tecla(k: InputEventKey) -> bool:
	var tecla := k.keycode
	if modo == "menu":
		for tipo in Cfg.ORDEN_CONSTRUCCION:
			var t: int = Cfg.TECLA_CINTA if tipo == "cinta" else Cfg.MAQUINAS[tipo].tecla
			if tecla == t:
				empezar_construccion(tipo)
				return true
	if tecla == KEY_ESCAPE:
		if modo != "normal":
			cancelar_modo()
		else:
			limpiar_seleccion()
		return true
	if tecla == KEY_B:
		if modo == "menu":
			cancelar_modo()
		else:
			cancelar_modo()
			modo = "menu"
			p.hud.mostrar_menu_construccion(true)
		return true
	if tecla == KEY_R and modo == "colocar":
		rot_colocar = (rot_colocar + 1) % 4
		return true
	if tecla == KEY_Z and k.ctrl_pressed or tecla == KEY_Z and k.meta_pressed:
		var err := sim.deshacer()
		p.hud.aviso(err if err != "" else "Obra deshecha: presupuesto devuelto.", "error" if err != "" else "info")
		return true
	if tecla in [KEY_DELETE, KEY_BACKSPACE] and sel_maquina != "":
		demoler_seleccion()
		return true
	if tecla >= KEY_0 and tecla <= KEY_9:
		var g := tecla - KEY_0
		if k.ctrl_pressed or k.meta_pressed:
			grupos[g] = sel_robots.duplicate()
			p.hud.aviso("Grupo %d: %d robots." % [g, sel_robots.size()], "info")
		elif grupos.has(g):
			var ids: Array[int] = []
			for id in grupos[g]:
				if sim.robot(id) != null:
					ids.append(id)
			_seleccionar_robots(ids, false)
			if _ultimo_grupo == g and _t_grupo < 0.4:
				centrar_seleccion()
			_ultimo_grupo = g
			_t_grupo = 0.0
		return true
	if tecla == KEY_PERIOD:
		_siguiente_ocioso()
		return true
	if tecla == KEY_H:
		cam.centrar(Vector3(30, 0, 64))
		return true
	if tecla == KEY_SPACE:
		centrar_seleccion()
		return true
	# Atajos de la selección (como el panel de comandos de AoE2).
	if not sel_robots.is_empty():
		var rs := robots_sel()
		match tecla:
			KEY_L:
				var activar := not rs[0].repetir
				for r in rs:
					var err := sim.set_repetir(r, activar)
					if err != "":
						p.hud.aviso(err, "error")
				seleccion_cambiada.emit()
				return true
			KEY_X:
				for r in rs:
					sim.limpiar_ordenes(r)
				seleccion_cambiada.emit()
				return true
			KEY_U:
				for r in rs:
					sim.set_auto(r, not r.auto)
				seleccion_cambiada.emit()
				return true
	if sel_maquina != "":
		var m: Maquina = sim.maquinas[sel_maquina]
		match tecla:
			KEY_Z:
				m.pausada = not m.pausada
				seleccion_cambiada.emit()
				return true
			KEY_T:
				m.turno_diurno = not m.turno_diurno
				seleccion_cambiada.emit()
				return true
			KEY_V:
				var err := sim.enviar_camion()
				p.hud.aviso(err if err != "" else "Camión de venta en camino a la ciudad.", "error" if err != "" else "info")
				return true
	return false


# ================================================================ selección

func robots_sel() -> Array[Robot]:
	var res: Array[Robot] = []
	for id in sel_robots:
		var r := sim.robot(id)
		if r != null:
			res.append(r)
	return res


func limpiar_seleccion() -> void:
	sel_robots.clear()
	sel_maquina = ""
	sel_otro = {}
	seleccion_cambiada.emit()


func _seleccionar_robots(ids: Array, sumar: bool) -> void:
	if not sumar:
		sel_robots.clear()
	for id in ids:
		if sumar and id in sel_robots and ids.size() == 1:
			sel_robots.erase(id)
		elif not id in sel_robots:
			sel_robots.append(id)
	sel_maquina = ""
	sel_otro = {}
	seleccion_cambiada.emit()


func _clic(pos: Vector2, sumar: bool) -> void:
	var r := _robot_bajo(pos)
	if r != null:
		_seleccionar_robots([r.id], sumar)
		return
	if sumar:
		return
	var c := _celda_bajo(pos)
	var m := sim.maquina_en(c)
	sel_robots.clear()
	sel_otro = {}
	sel_maquina = ""
	if m != null:
		sel_maquina = m.id
	else:
		var cam_id := _camion_bajo(pos)
		var mena := _mena_bajo(pos)
		if cam_id != "":
			sel_otro = {"tipo": "camion", "id": cam_id}
		elif not mena.is_empty():
			sel_otro = {"tipo": "mena", "id": mena.id}
	seleccion_cambiada.emit()


func _doble_clic(pos: Vector2) -> void:
	var r := _robot_bajo(pos)
	if r == null:
		_clic(pos, false)
		return
	var tam := get_viewport().get_visible_rect().size
	var ids: Array[int] = []
	for o in sim.robots:
		if o.nivel == r.nivel and Rect2(Vector2.ZERO, tam).has_point(cam.a_pantalla(_pos3(o))):
			ids.append(o.id)
	_seleccionar_robots(ids, false)


func _seleccion_caja(rect: Rect2, sumar: bool) -> void:
	var ids: Array[int] = []
	for r in sim.robots:
		if rect.has_point(cam.a_pantalla(_pos3(r))):
			ids.append(r.id)
	if not sumar:
		sel_robots.clear()
	for id in ids:
		if not id in sel_robots:
			sel_robots.append(id)
	sel_maquina = ""
	sel_otro = {}
	seleccion_cambiada.emit()


func centrar_seleccion() -> void:
	var rs := robots_sel()
	if not rs.is_empty():
		var c := Vector2.ZERO
		for r in rs:
			c += r.pos
		c /= rs.size()
		cam.centrar(Vector3(c.x, 0, c.y))
	elif sel_maquina != "":
		var m: Maquina = sim.maquinas[sel_maquina]
		cam.centrar(Vector3(m.centro().x, 0, m.centro().y))


func _siguiente_ocioso() -> void:
	var ociosos: Array[Robot] = []
	for r in sim.robots:
		if r.ocioso():
			ociosos.append(r)
	if ociosos.is_empty():
		p.hud.aviso("No hay robots ociosos.", "info")
		return
	_idx_ocioso = (_idx_ocioso + 1) % ociosos.size()
	var r := ociosos[_idx_ocioso]
	_seleccionar_robots([r.id], false)
	cam.centrar(Vector3(r.pos.x, 0, r.pos.y))


func _pos3(r: Robot) -> Vector3:
	return Vector3(r.pos.x, 0.45, r.pos.y)


func _robot_bajo(pos: Vector2) -> Robot:
	var mejor: Robot = null
	var dmin := 24.0 * cam.ppm() / 16.0 + 8.0
	for r in sim.robots:
		var d := cam.a_pantalla(_pos3(r)).distance_to(pos)
		if d < dmin:
			dmin = d
			mejor = r
	return mejor


func _mena_bajo(pos: Vector2) -> Dictionary:
	var mejor := {}
	var dmin := 0.7 * cam.ppm() + 6.0
	for m in sim.rejilla.menas:
		var d := cam.a_pantalla(Vector3(m.celda.x + 0.5, 0.35, m.celda.y + 0.5)).distance_to(pos)
		if d < dmin:
			dmin = d
			mejor = m
	return mejor


func _camion_bajo(pos: Vector2) -> String:
	for id in p.vfab.nodos_cam:
		var n: Node3D = p.vfab.nodos_cam[id]
		if cam.a_pantalla(n.position + Vector3(0, 0.8, 0)).distance_to(pos) < 1.4 * cam.ppm():
			return id
	return ""


func _celda_bajo(pos: Vector2) -> Vector2i:
	var h := cam.rayo_suelo(pos, 0.1)
	return Vector2i(floor(h.x), floor(h.z)) if h != Vector3.INF else Vector2i(-1, -1)


# ================================================================ órdenes

## ¿Llevará carga el robot cuando llegue a esta orden? Con Shift se mira la última orden encolada.
func _llevara_carga(r: Robot, encolar: bool) -> bool:
	if encolar and r.pc < r.ordenes.size():
		for k in range(r.ordenes.size() - 1, r.pc - 1, -1):
			var t: String = r.ordenes[k].tipo
			if t in ["recoger", "minar"]:
				return true
			if t == "entregar":
				return false
	return r.cant > 0


func _orden(pos: Vector2, encolar: bool) -> void:
	var rs := robots_sel()
	if rs.is_empty():
		return
	var c := _celda_bajo(pos)
	var punto := cam.rayo_suelo(pos, 0.1)
	var destino := Vector3(c.x + 0.5, 0.12, c.y + 0.5)
	var mena := _mena_bajo(pos)
	var m := sim.maquina_en(c)
	if not mena.is_empty() and m == null:
		sim.ordenar(rs, {"tipo": "minar", "objetivo": mena.id}, encolar)
		destino = Vector3(mena.celda.x + 0.5, 0.12, mena.celda.y + 0.5)
	elif m != null:
		for r in rs:
			var o := {}
			if m.averiada:
				o = {"tipo": "reparar", "objetivo": m.id}
			elif _llevara_carga(r, encolar):
				o = {"tipo": "entregar", "objetivo": m.id}
			else:
				o = {"tipo": "recoger", "objetivo": m.id, "punto": Vector2(punto.x, punto.z)}
				if m.tipo == "recepcion":
					o.material = _pila_recepcion(m, Vector2(punto.x, punto.z))
			sim.ordenar([r], o, encolar)
		destino = Vector3(m.centro().x, 0.12, m.centro().y)
	elif sim.suelo.has(c):
		sim.ordenar(rs, {"tipo": "recoger", "objetivo": "suelo", "celda": c}, encolar)
	elif sim.rejilla.dentro(c):
		# Varios robots: se reparten alrededor del punto en vez de pelearse por la misma casilla.
		var k := 0
		for r in rs:
			var off := Vector2i(k % 3 - 1, k / 3) if rs.size() > 1 else Vector2i.ZERO
			var meta := c + off
			if not sim.rejilla.libre(meta):
				meta = sim.rejilla.casilla_libre_cerca(meta)
			sim.ordenar([r], {"tipo": "mover", "celda": meta}, encolar)
			k += 1
	else:
		return
	marcador.position = destino
	marcador.visible = true
	_t_marcador = 0.0
	seleccion_cambiada.emit()


## En recepción, el lado del andén donde haces clic elige la pila: cobre o silicio.
func _pila_recepcion(m: Maquina, punto: Vector2) -> String:
	var local := VistaFabrica.transform_maquina(m).affine_inverse() * Vector3(punto.x, 0, punto.y)
	return "cobre" if local.z < 0.0 else "silicio"


# ================================================================ construcción

func empezar_construccion(tipo: String) -> void:
	cancelar_modo()
	if tipo == "cinta":
		modo = "cinta"
		p.hud.aviso("Cinta: arrastra con clic izquierdo. El primer eje del arrastre decide la esquina. Shift = seguir.", "info")
		return
	if sim.dinero < Cfg.MAQUINAS[tipo].costo:
		p.hud.aviso("Falta presupuesto para %s (₵ %d)." % [Cfg.MAQUINAS[tipo].nombre, Cfg.MAQUINAS[tipo].costo], "error")
		return
	modo = "colocar"
	tipo_colocar = tipo
	fantasma = p.vfab.instanciar_modelo(tipo)
	add_child(fantasma)
	fantasma_mats.clear()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fantasma_mats.append(mat)
	for c in fantasma.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = mat
	# Flechas de puertos: entrada (cian) y salida (ámbar).
	fantasma_puertos = Node3D.new()
	for lado in [[-1, Color("59f0ff")], [1, Color("ffb547")]]:
		var flecha := MeshInstance3D.new()
		var cono := CylinderMesh.new()
		cono.top_radius = 0.0
		cono.bottom_radius = 0.28
		cono.height = 0.6
		flecha.mesh = cono
		var mf := StandardMaterial3D.new()
		mf.albedo_color = lado[1]
		mf.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mf.no_depth_test = true
		flecha.material_override = mf
		flecha.rotation_degrees = Vector3(0, 0, -90)
		var tam: Vector2i = Cfg.MAQUINAS[tipo].tam
		flecha.position = Vector3(lado[0] * (tam.x * 0.5 + (0.7 if lado[0] < 0 else 0.4)), 0.5, 0)
		fantasma_puertos.add_child(flecha)
	if tipo in ["recepcion", "servidor"]:
		fantasma_puertos.visible = false
	fantasma.add_child(fantasma_puertos)
	p.hud.mostrar_menu_construccion(false)


func cancelar_modo() -> void:
	if fantasma:
		fantasma.queue_free()
		fantasma = null
	modo = "normal"
	tipo_colocar = ""
	_cinta_inicio = Vector2i(-1, -1)
	mm_previa.multimesh.instance_count = 0
	p.hud.mostrar_menu_construccion(false)


func _celda_colocar(raton: Vector2) -> Vector2i:
	var tam := Cfg.tam_rotado(Cfg.MAQUINAS[tipo_colocar].tam, rot_colocar)
	var h := cam.rayo_suelo(raton, 0.1)
	if h == Vector3.INF:
		return Vector2i(-1, -1)
	return Vector2i(round(h.x - tam.x * 0.5), round(h.z - tam.y * 0.5))


func _actualizar_fantasma(raton: Vector2) -> void:
	if fantasma == null:
		return
	var celda := _celda_colocar(raton)
	var m := Maquina.new("?", tipo_colocar, celda, rot_colocar)
	fantasma.transform = VistaFabrica.transform_maquina(m)
	var err := sim.validar(tipo_colocar, celda, rot_colocar)
	fantasma_mats[0].albedo_color = Color(0.3, 1.0, 0.5, 0.5) if err == "" else Color(1.0, 0.3, 0.3, 0.5)
	p.hud.pista("%s · ₵ %d%s   [R girar · Shift varias · clic derecho cancelar]" % [
		Cfg.MAQUINAS[tipo_colocar].nombre, Cfg.MAQUINAS[tipo_colocar].costo, "" if err == "" else " · " + err])


func _colocar(seguir: bool) -> void:
	var celda := _celda_colocar(get_viewport().get_mouse_position())
	var err := sim.construir(tipo_colocar, celda, rot_colocar)
	if err != "":
		p.hud.aviso(err, "error")
		return
	if not seguir or sim.dinero < Cfg.MAQUINAS[tipo_colocar].costo:
		cancelar_modo()


## Tramo en L desde el inicio del arrastre: primero el eje con más recorrido.
func _tramo(desde: Vector2i, hasta: Vector2i) -> Array:
	var res := []
	var d := hasta - desde
	var primero_x: bool = abs(d.x) >= abs(d.y)
	var esquina := Vector2i(hasta.x, desde.y) if primero_x else Vector2i(desde.x, hasta.y)
	var puntos: Array[Vector2i] = []
	for seg in [[desde, esquina], [esquina, hasta]]:
		var a: Vector2i = seg[0]
		var b: Vector2i = seg[1]
		var paso := (b - a).sign()
		var c := a
		while true:
			if puntos.is_empty() or puntos.back() != c:
				puntos.append(c)
			if c == b:
				break
			c += paso
	for k in puntos.size():
		var dir := 0
		var sig := puntos[k + 1] - puntos[k] if k + 1 < puntos.size() else (puntos[k] - puntos[k - 1] if k > 0 else Vector2i(1, 0))
		for i in 4:
			if Cfg.dir_vec(i) == sig:
				dir = i
		res.append([puntos[k], dir])
	return res


func _actualizar_previa_cinta(raton: Vector2) -> void:
	var c := _celda_bajo(raton)
	var tramo := _tramo(_cinta_inicio, c) if _cinta_inicio.x >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else [[c, 0]]
	var mm := mm_previa.multimesh
	mm.instance_count = tramo.size()
	var nuevas := 0
	for k in tramo.size():
		var celda: Vector2i = tramo[k][0]
		var ok := sim.validar_cinta(celda) == ""
		if not sim.cintas.celdas.has(celda):
			nuevas += 1
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, -tramo[k][1] * PI / 2.0), Vector3(celda.x + 0.5, 0.3, celda.y + 0.5)))
		mm.set_instance_color(k, Color(0.3, 1, 0.5, 0.5) if ok else Color(1, 0.3, 0.3, 0.5))
	p.hud.pista("Cinta · %d casillas · ₵ %d   [arrastra · clic derecho cancelar]" % [nuevas, nuevas * Cfg.CINTA_COSTO])


func _poner_cinta(raton: Vector2, seguir: bool) -> void:
	var tramo := _tramo(_cinta_inicio, _celda_bajo(raton))
	var err := sim.construir_cintas(tramo)
	if err != "":
		p.hud.aviso(err, "error")
	_cinta_inicio = Vector2i(-1, -1)
	if not seguir:
		cancelar_modo()


func demoler_seleccion() -> void:
	if sel_maquina == "":
		return
	var m: Maquina = sim.maquinas[sel_maquina]
	if m.tipo == "recepcion":
		p.hud.aviso("La recepción del proveedor no se puede demoler.", "error")
		return
	sim.demoler(sel_maquina)
	sel_maquina = ""
	seleccion_cambiada.emit()


# ================================================================ capa 2D

func _dibujar_capa() -> void:
	if _arrastrando and _presion != Vector2.INF:
		var r := Rect2(_presion, get_viewport().get_mouse_position() - _presion).abs()
		capa.draw_rect(r, Color(0.25, 0.95, 0.55, 0.12), true)
		capa.draw_rect(r, Color(0.25, 0.95, 0.55, 0.9), false, 1.5)
	# Marco de la máquina seleccionada (en pantalla, sobre su huella).
	if sel_maquina != "" and sim.maquinas.has(sel_maquina):
		var m: Maquina = sim.maquinas[sel_maquina]
		var e := m.rect()
		var esquinas := [Vector3(e.position.x, 0.12, e.position.y), Vector3(e.end.x, 0.12, e.position.y),
			Vector3(e.end.x, 0.12, e.end.y), Vector3(e.position.x, 0.12, e.end.y)]
		var pts := PackedVector2Array()
		for q in esquinas:
			pts.append(cam.a_pantalla(q))
		pts.append(pts[0])
		capa.draw_polyline(pts, Color("3fe08a"), 2.0)
