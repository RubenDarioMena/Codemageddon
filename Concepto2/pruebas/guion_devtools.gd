extends Node
## Integración real de F12, pausa, reemplazo del mundo y barrera SQL. Capturas fuera del repo.
var p: Node
var fallos := 0
var comprobaciones := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_comprobar(p.devtools != null, "Las herramientas se cargan en desarrollo")
	if p.devtools == null:
		get_tree().quit(1)
		return
	_tecla(KEY_F12)
	await get_tree().process_frame
	var d: Devtools = p.devtools
	_comprobar(d.panel.abierto and p.velocidad == 0, "F12 abre y pausa")
	_comprobar(not p.control.is_processing_unhandled_input() and not p.cam.is_processing(), "Panel bloquea órdenes y cámara")
	for tab in 5:
		d.panel.tabs.current_tab = tab
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/codemageddon-devtools-%d.png" % tab)
	_comprobar(d.cargar("Primera noche") == "", "Carga preset desde controlador real")
	await _esperar_carga()
	_comprobar(is_equal_approx(p.sim.hora(), 21.5), "Hora de escenario preparada sin avanzar")
	_comprobar(p.control.sim == p.sim and p.hud.sim == p.sim and p.vfab.sim == p.sim, "Todas las vistas usan el mundo nuevo")
	_comprobar(not p.control.is_processing_unhandled_input(), "El reemplazo mantiene bloqueo modal")
	_comprobar(d.avanzar(20) == "" and p.sim.n_paso == 20, "Avance de un segundo")
	var num: int = p.sim.robots.size()
	_comprobar(d.ejecutar({"tipo": "dev_robot", "nivel": 1, "cantidad": 1, "celda": [24, 68]}) == "", "Alta por coordenadas JSON")
	var huella: String = p.sim.huella()
	_comprobar(d.guardar("prueba_integracion_devtools") == "", "Guardar ranura con orden final en pausa")
	_comprobar(d.ejecutar({"tipo": "dev_dinero", "valor": 999}) == "", "Editar mundo después de guardar")
	_comprobar(d.cargar("Guardado: prueba_integracion_devtools") == "", "Restaurar ranura")
	await _esperar_carga()
	_comprobar(p.sim.huella() == huella and p.sim.robots.size() == num + 1, "Restauración exacta del mundo sin duplicar altas")
	var r: Dictionary = p.db.consultar("SELECT COUNT(*) AS n FROM robots")
	if p.db.es_postgres and p.servicio.es_web:
		_comprobar(true, "Proyección web asíncrona")
	else:
		_comprobar(r.ok and int(r.filas[0].n) == p.sim.robots.size(), "La proyección SQL pertenece al mundo restaurado")
	_tecla(KEY_F12)
	await get_tree().process_frame
	_comprobar(not d.panel.abierto and p.control.is_processing_unhandled_input() and p.cam.is_processing(), "Cerrar restaura entrada y cámara")
	# Mismo ID y mismo contador local: la época de la sesión invalida respuestas de workers viejos.
	var robot: Robot = p.sim.robot(3)
	if robot != null:
		_comprobar(p._token_programa(robot) >= 2000000000, "Tokens separan sesiones de JavaScript")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Devtools.CARPETA + "prueba_integracion_devtools.json"))
	print("Guion devtools: %d comprobaciones; fallos=%d" % [comprobaciones, fallos])
	get_tree().quit(1 if fallos else 0)


func _esperar_carga() -> void:
	for _i in 600:
		await get_tree().process_frame
		if not p.devtools.ocupado:
			return
	_comprobar(false, "La barrera de carga SQL respondió")


func _tecla(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	Input.parse_input_event(e)


func _comprobar(ok: bool, mensaje: String) -> void:
	comprobaciones += 1
	if not ok:
		fallos += 1
		push_error(mensaje)
