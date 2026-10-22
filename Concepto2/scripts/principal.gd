extends Node3D
## Arranque y bucle: simulación a reloj fijo (Cfg.HZ) con velocidad variable, presentación
## interpolada, volcado de eventos a la base y auditorías de la ciudad.

const VELOCIDADES := [1.0, 2.0, 4.0, 8.0]

var sim: Simulacion
var db: BaseDatos
var vmundo: VistaMundo
var vfab: VistaFabrica
var vrob: VistaRobots
var cam: CamaraRTS
var hud: Hud
var control: ControlRTS
var velocidad := 1.0
var _vel_previa := 1.0
var _acum := 0.0
var _t_volcado := 0.0
var _t_proyeccion := 0.0
var _t_retencion := 0.0


func _ready() -> void:
	sim = Simulacion.new()
	db = BaseDatos.new()
	db.abrir()
	vmundo = VistaMundo.new()
	add_child(vmundo)
	vmundo.construir(sim)
	vfab = VistaFabrica.new()
	add_child(vfab)
	vfab.construir(sim, vmundo.tex_humo)
	vrob = VistaRobots.new()
	add_child(vrob)
	vrob.construir(sim)
	cam = CamaraRTS.new()
	add_child(cam)
	cam.centrar(Vector3(34, 0, 64))
	hud = Hud.new()
	add_child(hud)
	hud.iniciar(self)
	control = ControlRTS.new()
	add_child(control)
	control.iniciar(self)
	control.seleccion_cambiada.connect(hud.al_cambiar_seleccion)
	hud.al_cambiar_seleccion()
	hud.aviso("Base de datos de la partida: %s" % db.ruta_absoluta(), "info")
	hud.aviso("Pulsa F1 para ver los controles. Selecciona una mula y haz clic derecho en la pila de cobre de REC-01.", "aviso")
	# Pruebas automáticas: godot --path . -- --guion=res://pruebas/guion_capturas.gd
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--guion="):
			var guion: Node = load(arg.trim_prefix("--guion=")).new()
			guion.set("p", self)
			add_child(guion)


func _process(delta: float) -> void:
	var dt := 1.0 / Cfg.HZ
	_acum += min(delta, 0.1) * velocidad
	var pasos := 0
	while _acum >= dt and pasos < 64:
		sim.paso()
		_acum -= dt
		pasos += 1
	var alfa := clampf(_acum / dt, 0.0, 1.0) if velocidad > 0.0 else 1.0
	vmundo.actualizar(delta)
	vfab.actualizar(alfa, velocidad)
	vrob.actualizar(alfa, velocidad)
	_base_de_datos(delta)
	for a in sim.avisos:
		hud.aviso(a.texto, a.tipo)
	sim.avisos.clear()
	hud.actualizar(delta)


func _base_de_datos(delta: float) -> void:
	_t_volcado += delta
	_t_proyeccion += delta
	_t_retencion += delta
	if _t_volcado > 0.25:
		_t_volcado = 0.0
		var a := db.volcar(sim)
		if a != "":
			hud.aviso(a, "aviso")
	if _t_proyeccion > 1.0:
		_t_proyeccion = 0.0
		db.proyectar(sim)
	if _t_retencion > 5.0:
		_t_retencion = 0.0
		var borradas := db.retener(sim.capacidad_registro())
		if borradas > 0:
			hud.aviso("Registro lleno: se borraron %d eventos antiguos. Construye un servidor o decide qué registrar." % borradas, "aviso")
	# La ciudad audita tu tabla de eventos con SQL (el mismo que podrías escribir tú).
	for au in sim.auditorias:
		db.volcar(sim)
		db.proyectar(sim)
		var r := db.consultar(au.sql)
		hud.aviso("El ayuntamiento ejecutó sobre tu base:\n" + au.sql.replace("\n", " "), "aviso")
		sim.resultado_auditoria(r.filas if r.ok else [])
	sim.auditorias.clear()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo) or control.escribiendo():
		return
	match e.keycode:
		KEY_P, KEY_F3, KEY_PAUSE:
			if velocidad == 0.0:
				velocidad = _vel_previa
			else:
				_vel_previa = velocidad
				velocidad = 0.0
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			velocidad = VELOCIDADES[min(VELOCIDADES.find(max(velocidad, 1.0)) + 1, VELOCIDADES.size() - 1)]
		KEY_MINUS, KEY_KP_SUBTRACT:
			velocidad = VELOCIDADES[max(VELOCIDADES.find(max(velocidad, 1.0)) - 1, 0)]
		_:
			return
	get_viewport().set_input_as_handled()
