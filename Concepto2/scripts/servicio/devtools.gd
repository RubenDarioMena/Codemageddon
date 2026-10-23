class_name Devtools
extends Node
## Coordinación de desarrollo: nunca escribe estado físico fuera de aplicar().

const CARPETA := "user://devtools/"
var p: Node
var panel: DevtoolsPanel
var ocupado := false
var escenario := DevEscenarios.plantilla()
var eventos: Array = []
var indice_evento := 0
var condicion := {"evento": "", "pasos": 0}
var pausa_consumida := false
var notas: Array = []
var marcas: Array = []
var metricas: Array = []
var _inicio_registro := 0
var _motivo := ""


func iniciar(principal: Node) -> void:
	p = principal
	panel = DevtoolsPanel.new()
	add_child(panel)
	panel.iniciar(self)


func plantilla() -> Dictionary:
	return DevEscenarios.plantilla()


func ejecutar(cmd: Dictionary) -> String:
	if ocupado:
		return "Espera a que termine la carga."
	if cmd.get("tipo") == "dev_detener_programas":
		for r in p.sim.robots:
			p.detener_programa(r, "Devtools")
		return ""
	if not str(cmd.get("tipo", "")).begins_with("dev_"):
		return "La consola admite comandos dev_*; las órdenes normales se dan en el juego."
	var e: String = p.sim.aplicar(DevEscenarios.normalizar(cmd))
	if e == "":
		_marcar("ajuste", str(cmd))
	return e


func pausa() -> void:
	if not ocupado:
		p.velocidad = 1.0 if p.velocidad == 0.0 else 0.0


func velocidad(valor: float) -> void:
	if not ocupado and valor in [0.0, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0]:
		p.velocidad = valor


func antes_paso() -> bool:
	if ocupado:
		return false
	while indice_evento < eventos.size() and eventos[indice_evento].paso <= p.sim.n_paso:
		var ev: Dictionary = eventos[indice_evento]
		indice_evento += 1
		var e := ejecutar(ev.cmd)
		if e != "":
			_detener("Evento %d: %s" % [indice_evento, e])
			return false
	return true


func despues_paso() -> void:
	observar_registro()
	if p.sim.n_paso % Cfg.HZ == 0:
		var producidos := 0
		for m: Maquina in p.sim.maquinas.values():
			producidos += m.producidos
		metricas.append({"paso": p.sim.n_paso, "dinero": p.sim.dinero, "producidos": producidos})
		if metricas.size() > 3600:
			metricas.pop_front()


## También observa eventos de callbacks SQL entre pasos (p. ej. multas en pausa).
func observar_registro() -> void:
	if _inicio_registro > p.sim.registro.size():
		_inicio_registro = 0
	for i in range(_inicio_registro, p.sim.registro.size()):
		var ev: Dictionary = p.sim.registro[i]
		if ev.tipo in ["venta", "multa", "bloqueo", "ordenanza", "sabotaje", "derrame", "viaje_vacio"]:
			_marcar(ev.tipo, "%s: %s" % [ev.origen, ev.get("detalle", "")])
		if not pausa_consumida and condicion.evento != "" and ev.tipo == condicion.evento:
			pausa_consumida = true
			_detener("Pausa por evento: %s" % ev.tipo)
	_inicio_registro = p.sim.registro.size()
	if not pausa_consumida and int(condicion.pasos) > 0 and p.sim.n_paso >= int(condicion.pasos):
		pausa_consumida = true
		_detener("Límite de %d pasos alcanzado." % int(condicion.pasos))


func avanzar(pasos: int) -> String:
	if ocupado or pasos < 1 or pasos > DevEscenarios.MAX_PASOS:
		return "Avance válido: 1–24000 pasos, sin una carga pendiente."
	for r in p.sim.robots:
		if r.ejecutando:
			return "Detén los programas JS antes del avance sin dibujar; usa velocidad normal para probarlos."
	p.velocidad = 0.0
	_motivo = ""
	for _i in pasos:
		if not antes_paso():
			break
		p.sim.paso()
		despues_paso()
		# No adelantar el mundo a una respuesta SQL que todavía no se ha recibido.
		if not p.sim.auditorias.is_empty():
			_detener("Auditoría pendiente: reanuda cuando la base responda.")
			break
		if _motivo != "":
			break
	p._acum = 0.0
	return ""


func _detener(texto: String) -> void:
	p.velocidad = 0.0
	_motivo = texto
	_marcar("pausa", texto)


func _marcar(tipo: String, texto: String) -> void:
	marcas.append({"paso": p.sim.n_paso, "tipo": tipo, "texto": texto})
	if marcas.size() > 200:
		marcas.pop_front()


func anotar(texto: String) -> String:
	if texto.strip_edges().is_empty():
		return "Escribe una nota."
	notas.append({"paso": p.sim.n_paso, "texto": texto.left(2000)})
	return ""


func reiniciar() -> String:
	return cargar_escenario(escenario)


func cargar_escenario(datos: Dictionary) -> String:
	if ocupado:
		return "Ya hay una carga pendiente."
	if p.db != null and p.db.pendiente:
		return "Espera a que arranque la base de datos."
	var preparado := DevEscenarios.crear(datos)
	if not preparado.ok:
		return preparado.error
	escenario = datos.duplicate(true)
	eventos = preparado.eventos
	indice_evento = 0
	condicion = preparado.pausa
	pausa_consumida = false
	notas.clear()
	marcas.clear()
	metricas.clear()
	return _instalar(preparado.sim)


func _instalar(s: Simulacion) -> String:
	ocupado = true
	p.velocidad = 0.0
	# Replay reconstruye salidas históricas, que no se vuelven a ejecutar contra la DB.
	s.auditorias.clear()
	s.resultados.clear()
	s.avisos.clear()
	_inicio_registro = s.registro.size()
	# Este gancho permite probar el controlador sin renderer ni servicio.
	if p.has_method("dev_reemplazar"):
		p.dev_reemplazar(s)
		p.db.reiniciar_dev(func(r):
			ocupado = false
			if not r.ok:
				_detener("Error al limpiar la base: %s" % r.error)
			else:
				p.db.volcar(p.sim)
				_inicio_registro = 0
				p.db.proyectar(p.sim))
	else:
		p.sim = s
		ocupado = false
	_motivo = "Escenario preparado. Los programas se conservan como código y se ejecutan desde J."
	return ""


func escenarios() -> Array[String]:
	var res := DevEscenarios.nombres()
	var dir := DirAccess.open(CARPETA)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				res.append("Guardado: " + f.trim_suffix(".json"))
	return res


static func _nombre_valido(nombre: String) -> bool:
	return not nombre.is_empty() and nombre.length() <= 64 and nombre == nombre.validate_filename() and nombre not in [".", ".."]


## Ranura de laboratorio: restaura mundo + ajustes + agenda; la DB se regenera, no es guardado comercial.
func guardar(nombre: String) -> String:
	if ocupado or not _nombre_valido(nombre):
		return "Nombre inválido o carga pendiente (máximo 64 caracteres, sin rutas)."
	if p.sim.n_paso > DevEscenarios.MAX_PASOS:
		return "La ranura supera el límite de replay de 24000 pasos. Guarda antes o crea otro escenario."
	if p.db != null and p.db.pendiente:
		return "Espera a que arranque la base."
	var pendientes: Variant = p.get("_auditorias_pendientes")
	if not p.sim.auditorias.is_empty() or (pendientes != null and int(pendientes) > 0):
		return "Espera la respuesta de la auditoría antes de guardar."
	for r in p.sim.robots:
		if r.ejecutando:
			return "Detén los programas JS antes de guardar la ranura de laboratorio."
	var programas := {}
	for r in p.sim.robots:
		if r.codigo != "":
			programas[str(r.id)] = r.codigo
	var datos := {"version": 1, "escenario": escenario, "pasos": p.sim.n_paso,
		"diario": Marshalls.raw_to_base64(var_to_bytes(p.sim.diario)), "huella": p.sim.huella(),
		"eventos": Marshalls.raw_to_base64(var_to_bytes(eventos)), "indice_evento": indice_evento,
		"condicion": condicion, "pausa_consumida": pausa_consumida,
		"notas": notas, "marcas": marcas, "metricas": metricas, "programas": programas}
	datos["integridad_diario"] = str(datos.diario).sha256_text()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA))
	var ruta := CARPETA + nombre + ".json"
	var f := FileAccess.open(ruta + ".tmp", FileAccess.WRITE)
	if f == null:
		return "No se pudo escribir la ranura."
	f.store_string(JSON.stringify(datos, "\t"))
	f.close()
	var e := DirAccess.rename_absolute(ProjectSettings.globalize_path(ruta + ".tmp"), ProjectSettings.globalize_path(ruta))
	return "" if e == OK else "No se pudo reemplazar la ranura: %s" % error_string(e)


func cargar(nombre: String) -> String:
	if ocupado:
		return "Espera a que termine la carga."
	if p.db != null and p.db.pendiente:
		return "Espera a que arranque la base de datos."
	if nombre in DevEscenarios.nombres():
		return cargar_escenario(DevEscenarios.preset(nombre))
	nombre = nombre.trim_prefix("Guardado: ")
	if not _nombre_valido(nombre):
		return "Nombre de ranura inválido."
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARPETA + nombre + ".json"))
	if not datos is Dictionary or datos.get("version") != 1 or not datos.get("escenario") is Dictionary:
		return "Ranura inexistente o incompatible."
	if not DevEscenarios.numero(datos.get("pasos")) or datos.pasos != int(datos.pasos) or datos.pasos < 0 or datos.pasos > DevEscenarios.MAX_PASOS:
		return "La ranura supera el límite de replay de 24000 pasos."
	if not datos.get("diario") is String or datos.diario.sha256_text() != datos.get("integridad_diario", ""):
		return "Integridad del diario inválida."
	var diario: Variant = bytes_to_var(Marshalls.base64_to_raw(str(datos.get("diario", ""))))
	var agenda: Variant = bytes_to_var(Marshalls.base64_to_raw(str(datos.get("eventos", ""))))
	if not diario is Array or not agenda is Array:
		return "Diario o agenda dañados."
	var paso_anterior := 0
	for entrada in diario:
		if not entrada is Dictionary or not DevEscenarios.numero(entrada.get("paso")) or entrada.paso != int(entrada.paso) or entrada.paso < paso_anterior or entrada.paso > datos.pasos or not entrada.get("cmd") is Dictionary or not entrada.cmd.get("tipo") is String:
			return "Entrada de diario inválida."
		paso_anterior = int(entrada.paso)
	if not DevEscenarios.numero(datos.get("indice_evento")) or datos.indice_evento != int(datos.indice_evento) or datos.indice_evento < 0 or datos.indice_evento > agenda.size():
		return "Posición de agenda inválida."
	if not datos.get("condicion") is Dictionary or not datos.get("pausa_consumida") is bool:
		return "Condición de pausa inválida."
	var pa: Dictionary = datos.condicion
	if pa.get("evento") not in DevEscenarios.EVENTOS_PAUSA or not DevEscenarios.numero(pa.get("pasos")) or pa.pasos < 0 or pa.pasos > DevEscenarios.MAX_PASOS or pa.pasos != int(pa.pasos):
		return "Condición de pausa inválida."
	for clave in ["notas", "marcas", "metricas"]:
		if not datos.get(clave) is Array:
			return "Metadatos inválidos: %s" % clave
	if not datos.get("programas") is Dictionary:
		return "Programas de ranura inválidos."
	for ev in agenda:
		if not ev is Dictionary or not DevEscenarios.numero(ev.get("paso")) or not ev.get("cmd") is Dictionary or ev.cmd.get("tipo") not in DevEscenarios.COMANDOS:
			return "Evento de ranura inválido."
	# El serializador binario sin objetos conserva Vector2i, enteros y floats exactamente.
	var s := Simulacion.reproducir(diario, int(datos.pasos), true)
	if s.huella() != str(datos.get("huella", "")):
		return "La huella no coincide: ranura dañada o reglas de otra versión."
	for id in datos.get("programas", {}):
		if s.robot(int(id)) != null:
			s.robot(int(id)).codigo = str(datos.programas[id])
	escenario = datos.escenario
	eventos = agenda
	indice_evento = int(datos.get("indice_evento", 0))
	condicion = datos.get("condicion", {"evento": "", "pasos": 0})
	pausa_consumida = bool(datos.get("pausa_consumida", false))
	notas = datos.get("notas", [])
	marcas = datos.get("marcas", [])
	metricas = datos.get("metricas", [])
	return _instalar(s)


func inspeccionar() -> Dictionary:
	var s: Simulacion = p.sim
	var maquinas := {}
	for m: Maquina in s.maquinas.values():
		var causa := m.estado
		if m.estado == "sin_insumo":
			var faltan := []
			for mat in m.receta_actual().get("entra", {}):
				if m.entrada.get(mat, 0) < m.receta_actual().entra[mat]:
					faltan.append(mat)
			causa = "Falta: " + ", ".join(faltan)
		maquinas[m.id] = {"estado": m.estado, "causa": causa, "entrada": m.entrada, "salida": m.salida,
			"progreso": m.progreso, "producidos": m.producidos}
	var robots := {}
	for r in s.robots:
		robots[r.nombre()] = {"estado": r.estado, "orden": r.pc, "ordenes": r.ordenes.size(),
			"carga": r.carga, "cantidad": r.cant, "capacidad": r.cap(), "velocidad": r.vel(), "resultado": r.resultado}
	return {"escenario": escenario.get("nombre", ""), "paso": s.n_paso, "dia": s.dia(), "hora": s.hora(),
		"dinero": s.dinero, "motivo": _motivo, "cargando": ocupado, "sistemas": s.dev_sistemas,
		"ajustes": s.dev_ajustes, "maquinas": maquinas, "robots": robots,
		"ciudad": {"distritos": s.ciudad.distritos, "precio": s.ciudad.precio,
			"quejas_nocturnas": s.ciudad.quejas_nocturnas, "ordenanza": s.ciudad.ordenanza,
			"bloqueo_horas": s.ciudad.bloqueo_horas},
		"agenda_pendiente": eventos.size() - indice_evento, "notas": notas,
		"ultimas_marcas": marcas.slice(maxi(0, marcas.size() - 20)),
		"metricas": metricas.slice(maxi(0, metricas.size() - 30))}
