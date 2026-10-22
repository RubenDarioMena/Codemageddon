extends Node
## Prueba de punta a punta de PostgreSQL (PGlite) y los programas JavaScript, en ventana.
## godot --path . -- --guion=res://pruebas/guion_programas.gd

var p: Node
var t := 0.0
var paso := 0
var fallos := 0
var marca := 0.0
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


func _n(sql: String) -> int:
	var r: Dictionary = p.db.consultar(sql)
	return int(r.filas[0].n) if r.ok and not r.filas.is_empty() else -1


func _process(delta: float) -> void:
	t += delta
	var sim: Simulacion = p.sim
	var r3: Robot = sim.robot(3)
	match paso:
		0:
			if t > 1.0:
				_comprobar(p.db.es_postgres, "la base es PostgreSQL (%s)" % p.db.motor)
				var v: Dictionary = p.db.consultar("SELECT version() AS v")
				_comprobar(v.ok and str(v.filas[0].v).begins_with("PostgreSQL"), "SELECT version() → %s" % str(v.filas[0].v).left(40) if v.ok else v.error)
				_comprobar(r3 != null and r3.nivel == 1, "R3 es un Operario T1")
				p.cam.centrar(Vector3(26, 0, 64))
				p.cam.nivel = 5
				p.control._seleccionar_robots([3], false)
				p.hud.alternar_editor()
				r3.codigo = EditorPrograma.PLANTILLAS[1][1]
				p.hud.editor.editor.text = r3.codigo
				p.ejecutar_programa(r3)
				p.velocidad = 4.0
				marca = t
				paso += 1
		1:
			if t > marca + 6.0:
				_captura("20_programa_ejecutando")
				var entregas := _n("SELECT COUNT(*) AS n FROM eventos WHERE origen = 'R3' AND tipo = 'entrega'")
				_comprobar(r3.ejecutando and entregas >= 1, "el programa JS entrega cobre (entregas de R3 en Postgres: %d, línea %d)" % [entregas, r3.linea])
				var logs := _n("SELECT COUNT(*) AS n FROM eventos WHERE origen = 'R3' AND tipo = 'programa'")
				_comprobar(logs >= 1, "el inicio del programa quedó en eventos (%d)" % logs)
				# Pausa: el await no debe avanzar.
				p.velocidad = 0.0
				marca = t
				paso += 1
		2:
			if t > marca + 0.3:
				set_meta("pos", r3.pos)
				set_meta("linea", r3.linea)
				marca = t
				paso += 1
		3:
			if t > marca + 1.5:
				_comprobar(r3.pos == get_meta("pos") and r3.ejecutando, "en pausa el robot y su programa esperan")
				p.velocidad = 4.0
				# Programa con SQL dentro: decide el destino consultando el registro.
				p.detener_programa(r3)
				r3.codigo = EditorPrograma.PLANTILLAS[2][1]
				p.hud.editor.mostrar(null)
				p.hud.editor.mostrar(r3)
				p.ejecutar_programa(r3)
				marca = t
				paso += 1
		4:
			if t > marca + 4.0:
				var con_sql := false
				for l in r3.consola:
					if "Alimento a" in l:
						con_sql = true
				_comprobar(con_sql, "db.query() dentro del programa funciona (consola: %s)" % [r3.consola.slice(-2)])
				_captura("21_programa_sql")
				# Error de sintaxis con número de línea.
				p.detener_programa(r3)
				r3.codigo = "log(\"inicio\");\nawait yo.recoger(\"REC-01\", \"cobre\")\nconst x = ;\n"
				p.hud.editor.mostrar(null)
				p.hud.editor.mostrar(r3)
				p.ejecutar_programa(r3)
				marca = t
				paso += 1
		5:
			if t > marca + 1.0:
				_comprobar(not r3.ejecutando and r3.linea_error == 3, "error de sintaxis señalado en la línea 3 (línea_error=%d)" % r3.linea_error)
				_captura("22_error_sintaxis")
				# Bucle sin await: el vigilante lo detiene.
				r3.codigo = "await yo.esperar(0.2);\nlet i = 0;\nwhile (true) { i++; }\n"
				p.hud.editor.mostrar(null)
				p.hud.editor.mostrar(r3)
				p.ejecutar_programa(r3)
				marca = t
				paso += 1
		6:
			if t > marca + 4.5:
				var vigilante := false
				for l in r3.consola:
					if "sin ceder el control" in l:
						vigilante = true
				_comprobar(vigilante and not r3.ejecutando, "un bucle sin await se detiene a los 3 s")
				# Control manual sobre un robot con programa: lo suspende.
				r3.codigo = EditorPrograma.PLANTILLAS[0][1]
				p.ejecutar_programa(r3)
				p.hud.editor.visible = false   # que el clic llegue al mundo y no al panel
				marca = t
				paso += 1
		7:
			if t > marca + 1.0:
				var pos: Vector2 = p.cam.a_pantalla(Vector3(30.5, 0.1, 70.5))
				var e := InputEventMouseButton.new()
				e.position = pos
				e.button_index = MOUSE_BUTTON_RIGHT
				e.pressed = true
				Input.warp_mouse(pos)
				Input.parse_input_event(e)
				marca = t
				paso += 1
		8:
			if t > marca + 0.5:
				_comprobar(not r3.ejecutando and r3.ordenes.size() == 1 and r3.ordenes[0].tipo == "mover", "un clic derecho detiene el programa y toma el control manual")
				p.hud.editor.visible = false
				p.hud.consola.abrir_con("SELECT origen, tipo, detalle\nFROM eventos\nWHERE origen = 'R3' AND tipo IN ('programa', 'log', 'error_programa')\nORDER BY id DESC\nLIMIT 12;")
				marca = t
				paso += 1
		9:
			if t > marca + 1.0:
				_captura("23_consola_postgres")
				print("RESULTADO: %d fallos" % fallos)
				get_tree().quit()
