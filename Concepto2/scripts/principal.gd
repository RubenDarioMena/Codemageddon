extends Node3D
## Arranque y bucle: simulación a reloj fijo (Cfg.HZ) con velocidad variable, presentación
## interpolada, volcado de eventos a la base, auditorías de la ciudad y programas JS de los robots.

const VELOCIDADES := [1.0, 2.0, 4.0, 8.0]

var sim: Simulacion
var db: BaseDatos
var servicio: Servicio
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
var _t_foto := 0.0


func _ready() -> void:
	ThemeDB.fallback_font = Estilo.fuente()   # también para los Label3D del mundo
	sim = Simulacion.new()
	# PostgreSQL y JavaScript viven en el servicio auxiliar (Node). Sin él: SQLite y sin programas.
	servicio = Servicio.new()
	add_child(servicio)
	var con_servicio := servicio.iniciar(BaseDatos.esquema("postgres"))
	db = BaseDatos.new()
	if servicio.estado == Servicio.INICIANDO:
		db.abrir_pendiente()   # web: PGlite tarda unos segundos en cargar en el navegador
	else:
		db.abrir(servicio if con_servicio else null)
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
	if not db.pendiente:
		_anunciar_base()
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
	_programas(delta)
	for a in sim.avisos:
		hud.aviso(a.texto, a.tipo)
	sim.avisos.clear()
	hud.actualizar(delta)


func _anunciar_base() -> void:
	hud.aviso("Base de datos: " + db.descripcion(), "info")
	if servicio.conectado:
		hud.aviso("Programas JavaScript activos: selecciona un robot T1 o T2 y pulsa J.", "info")
	else:
		hud.aviso("Sin servicio de programas: %s Se usa %s y no hay programas JS." % [servicio.error, db.motor], "aviso")


func _base_de_datos(delta: float) -> void:
	if db.pendiente:
		servicio.actualizar()
		if servicio.estado != Servicio.INICIANDO:
			db.abrir(servicio if servicio.conectado else null)
			_anunciar_base()
		return
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
		db.retener_luego(sim.capacidad_registro(), func(borradas):
			hud.aviso("Registro lleno: se borraron %d eventos antiguos. Construye un servidor o decide qué registrar." % borradas, "aviso"))
	# La ciudad audita tu tabla de eventos con SQL (el mismo que podrías escribir tú).
	for au in sim.auditorias:
		db.volcar(sim)
		db.proyectar(sim)
		hud.aviso("El ayuntamiento ejecutó sobre tu base:\n" + au.sql.replace("\n", " "), "aviso")
		db.consultar_luego(au.sql, func(r): sim.resultado_auditoria(r.filas if r.ok else []))
	sim.auditorias.clear()


# ---------------------------------------------------------------- programas JS

func _programas(delta: float) -> void:
	if not servicio.conectado:
		sim.resultados.clear()
		var perdidos: Array[int] = []
		for r in sim.robots:
			if r.ejecutando:
				perdidos.append(r.id)
		if not perdidos.is_empty():
			sim.aplicar({"tipo": "perdida_servicio"})
			for id in perdidos:
				var r := sim.robot(id)
				r.consola.append("[color=#ff6b6b]✖ Se perdió la conexión con el servicio.[/color]")
		return
	for m in servicio.recibir():
		var r: Robot = sim.robot(int(m.get("robot", -1))) if m.has("robot") else null
		if r != null and int(m.get("ejecucion", -1)) != r.ejecucion:
			continue   # mensaje tardío de un programa ya detenido o sustituido
		match str(m.op):
			"accion":
				if r != null and r.ejecutando:
					r.linea = int(m.linea)
					sim.aplicar({"tipo": "orden_programa", "robot": r.id, "datos": m.orden, "ticket": int(m.ticket)})
			"log":
				if r != null:
					var texto := str(m.texto)
					r.consola.append("[color=#6a8394]%3d[/color]  %s" % [int(m.linea), Estilo.escapar(texto)])
					sim.log_evento(r.nombre(), "log", "", 0, texto.left(240))
			"error":
				if r != null:
					var linea := int(m.linea)
					r.linea_error = linea
					r.consola.append("[color=#ff6b6b]✖ %s%s[/color]" % ["línea %d: " % linea if linea > 0 else "", Estilo.escapar(str(m.mensaje))])
					hud.aviso("%s: %s" % [r.nombre(), str(m.mensaje)], "error")
					sim.log_evento(r.nombre(), "error_programa", "", linea, str(m.mensaje).left(240))
			"fin":
				if r != null and r.ejecutando:
					sim.aplicar({"tipo": "fin_programa", "robot": r.id})
					r.consola.append("[color=#7f95a3]— fin del programa —[/color]")
			"aviso_db":
				hud.aviso("PostgreSQL (%s): %s" % [str(m.tabla), str(m.error)], "error")
				if "does not exist" in str(m.error):
					db.crear_esquema()
					hud.aviso("Faltaba una tabla: el juego volvió a crear el esquema.", "aviso")
	# Cada orden terminada despierta su `await` con el resultado y una foto fresca del mundo.
	if not sim.resultados.is_empty():
		var foto := sim.instantanea()
		for res in sim.resultados:
			var rr := sim.robot(res.robot)
			servicio.enviar({"op": "resultado", "robot": res.robot, "ticket": res.ticket, "resultado": res.resultado,
				"ejecucion": rr.ejecucion if rr else 0, "estado": foto})
		sim.resultados.clear()
	_t_foto += delta
	if _t_foto > 0.25:
		_t_foto = 0.0
		for r in sim.robots:
			if r.ejecutando:
				servicio.enviar({"op": "estado", "estado": sim.instantanea()})
				break


func ejecutar_programa(r: Robot) -> void:
	if not servicio.conectado:
		hud.aviso("Los programas necesitan el servicio Node (%s)." % servicio.error, "error")
		return
	if r.nivel < 1:
		hud.aviso("%s no tiene chip: fabrica un Operario (T1)." % r.etiqueta(), "error")
		return
	if r.ejecutando:
		servicio.enviar({"op": "detener", "robot": r.id})
	sim.aplicar({"tipo": "iniciar_programa", "robot": r.id})
	r.consola.clear()
	r.consola.append("[color=#3fe08a]▶ ejecutando (%s)[/color]" % ("pausa: el programa espera a que reanudes" if velocidad == 0.0 else "×%d" % int(velocidad)))
	r.linea = 0
	r.linea_error = 0
	servicio.enviar({"op": "estado", "estado": sim.instantanea()})
	servicio.enviar({"op": "ejecutar", "robot": r.id, "nivel": r.nivel, "codigo": r.codigo, "ejecucion": r.ejecucion})
	log_programa(r, "inicio")


func detener_programa(r: Robot, motivo: String = "") -> void:
	if not r.ejecutando:
		return
	servicio.enviar({"op": "detener", "robot": r.id})
	sim.aplicar({"tipo": "detener_programa", "robot": r.id})
	r.consola.append("[color=#7f95a3]■ detenido%s[/color]" % (": " + motivo if motivo != "" else ""))
	if motivo != "":
		hud.aviso("%s: %s" % [r.nombre(), motivo], "aviso")
	log_programa(r, "detenido")


func log_programa(r: Robot, que: String) -> void:
	sim.log_evento(r.nombre(), "programa", "", r.codigo.count("\n") + 1, que)


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
