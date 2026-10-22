extends Node
## Prueba de controles por la ruta real de entrada (eventos de ratón/teclado simulados).
## godot --path . -- --guion=res://pruebas/guion_controles.gd

var p: Node
var t := 0.0
var paso := 0
var fallos := 0
var salida := ""


func _ready() -> void:
	salida = ProjectSettings.globalize_path("res://pruebas/capturas/")
	DirAccess.make_dir_recursive_absolute(salida)
	p.hud.ayuda.visible = false


func _captura(nombre: String) -> void:
	get_viewport().get_texture().get_image().save_png(salida + nombre + ".png")
	print("CAPTURA ", nombre)


func _comprobar(cond: bool, que: String) -> void:
	print(("OK   " if cond else "FALLO ") + que)
	if not cond:
		fallos += 1


func _pantalla(x: float, z: float, y: float = 0.3) -> Vector2:
	return p.cam.a_pantalla(Vector3(x, y, z))


func _boton(pos: Vector2, boton: int, presionado: bool, shift := false) -> void:
	Input.warp_mouse(pos)
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = boton
	e.pressed = presionado
	e.shift_pressed = shift
	Input.parse_input_event(e)


func _clic(pos: Vector2, boton := MOUSE_BUTTON_LEFT, shift := false) -> void:
	_boton(pos, boton, true, shift)
	_boton(pos, boton, false, shift)


func _mover(pos: Vector2, rel: Vector2) -> void:
	Input.warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	Input.parse_input_event(e)


func _tecla(k: int) -> void:
	for pres in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pres
		Input.parse_input_event(e)


func _process(delta: float) -> void:
	t += delta
	var c: ControlRTS = p.control
	var sim: Simulacion = p.sim
	match paso:
		0:
			if t > 1.0:
				p.cam.centrar(Vector3(27, 0, 63))
				p.cam.nivel = 5
				paso += 1
		1:
			if t > 2.0:
				var r1 := sim.robots[0]
				_clic(_pantalla(r1.pos.x, r1.pos.y, 0.45))
				paso += 1
		2:
			if t > 2.3:
				_comprobar(c.sel_robots == [1], "clic izquierdo selecciona R1 (sel=%s)" % [c.sel_robots])
				# Clic derecho en la pila de cobre de REC-01 (lado -z del andén) y Shift+clic derecho en FUN-01.
				_clic(_pantalla(19.5, 60.7, 0.5), MOUSE_BUTTON_RIGHT)
				_clic(_pantalla(27.5, 61.5, 0.8), MOUSE_BUTTON_RIGHT, true)
				paso += 1
		3:
			if t > 2.6:
				var r1 := sim.robots[0]
				var tipos := []
				for o in r1.ordenes:
					tipos.append("%s %s %s" % [o.tipo, o.get("objetivo", ""), o.get("material", "")])
				_comprobar(r1.ordenes.size() == 2 and r1.ordenes[0].tipo == "recoger" and r1.ordenes[0].get("material") == "cobre"
					and r1.ordenes[1].tipo == "entregar" and r1.ordenes[1].objetivo == "FUN-01",
					"clic derecho = recoger cobre, Shift+clic derecho encola entregar (órdenes: %s)" % [tipos])
				_captura("10_orden_encolada")
				# Caja de selección alrededor de los dos robots.
				var a := _pantalla(20.5, 63.5)
				var b := _pantalla(25.5, 67.5)
				_boton(a, MOUSE_BUTTON_LEFT, true)
				_mover(a.lerp(b, 0.5), b - a)
				_mover(b, Vector2(2, 2))
				paso += 1
		4:
			if t > 2.8:
				_captura("11_caja_seleccion")
				_boton(_pantalla(25.5, 67.5), MOUSE_BUTTON_LEFT, false)
				paso += 1
		5:
			if t > 3.0:
				_comprobar(c.sel_robots.size() == 2, "arrastrar selecciona con caja (sel=%s)" % [c.sel_robots])
				_tecla(KEY_ESCAPE)
				_tecla(KEY_B)
				paso += 1
		6:
			if t > 3.2:
				_comprobar(c.modo == "menu", "B abre el menú de construcción (modo=%s)" % c.modo)
				_tecla(KEY_W)
				paso += 1
		7:
			if t > 3.4:
				_comprobar(c.modo == "colocar" and c.tipo_colocar == "fundidora", "W elige la fundidora")
				_tecla(KEY_R)
				_mover(_pantalla(29.0, 50.0), Vector2.ZERO)
				paso += 1
		8:
			if t > 3.7:
				_captura("12_fantasma")
				_clic(_pantalla(29.0, 50.0))
				paso += 1
		9:
			if t > 4.0:
				_comprobar(sim.maquinas.has("FUN-02") and sim.maquinas["FUN-02"].rot == 1, "clic coloca FUN-02 girada (R)")
				_tecla(KEY_B)
				_tecla(KEY_Q)
				paso += 1
		10:
			if t > 4.2:
				_comprobar(c.modo == "cinta", "B, Q = trazar cinta")
				var a := _pantalla(30.5, 66.5)
				var b := _pantalla(36.5, 70.5)
				_boton(a, MOUSE_BUTTON_LEFT, true)
				_mover(b, b - a)
				paso += 1
		11:
			if t > 4.5:
				_captura("13_cinta_previa")
				_boton(_pantalla(36.5, 70.5), MOUSE_BUTTON_LEFT, false)
				paso += 1
		12:
			if t > 4.8:
				var ok := sim.cintas.celdas.has(Vector2i(30, 66)) and sim.cintas.celdas.has(Vector2i(36, 66)) and sim.cintas.celdas.has(Vector2i(36, 70))
				_comprobar(ok and sim.cintas.celdas[Vector2i(36, 66)].dir == 1, "arrastre en L crea la cinta con esquina")
				# Rueda pulsada: orbitar y soltar ajusta a 45°.
				var centro := Vector2(800, 400)
				_boton(centro, MOUSE_BUTTON_MIDDLE, true)
				_mover(centro + Vector2(70, 0), Vector2(70, 0))
				paso += 1
		13:
			if t > 5.0:
				_boton(Vector2(870, 400), MOUSE_BUTTON_MIDDLE, false)
				paso += 1
		14:
			if t > 5.6:
				var y: float = p.cam.yaw_obj
				_comprobar(is_equal_approx(fmod(abs(y), PI / 4.0), 0.0) or is_equal_approx(fmod(abs(y), PI / 4.0), PI / 4.0),
					"rueda pulsada orbita y se ajusta a 45° (yaw=%.1f°)" % rad_to_deg(y))
				_captura("14_orbitada")
				p.velocidad = 4.0
				paso += 1
		15:
			if t > 9.0:
				var r1 := sim.robots[0]
				_comprobar(sim.maquinas["FUN-01"].producidos > 2 or r1.pc >= 2, "R1 ejecutó su lista (pc=%d, FUN-01 producidos=%d)" % [r1.pc, sim.maquinas["FUN-01"].producidos])
				print("RESULTADO: %d fallos" % fallos)
				get_tree().quit()
