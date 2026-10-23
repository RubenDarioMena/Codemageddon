extends SceneTree
## Escenarios reproducibles: datos JSON, preparación aislada y replay con ajustes.

var fallos := 0
var comprobaciones := 0


class PartidaPrueba:
	extends Node
	var sim := Simulacion.new(true)
	var velocidad := 1.0
	var _acum := 0.0
	var db: Variant = null


func _init() -> void:
	_plantilla()
	_presets()
	_granularidad()
	_rechazos()
	_controlador()
	print("Dev escenarios: %d comprobaciones; fallos=%d" % [comprobaciones, fallos])
	quit(1 if fallos > 0 else 0)


func _comprobar(condicion: bool, mensaje: String) -> void:
	comprobaciones += 1
	if not condicion:
		fallos += 1
		push_error(mensaje)


func _plantilla() -> void:
	var datos := DevEscenarios.plantilla()
	var antes := var_to_str(datos)
	var a := DevEscenarios.crear(datos)
	_comprobar(bool(a.ok), "La plantilla debe producir un escenario válido: %s" % a.get("error", ""))
	_comprobar(antes == var_to_str(datos), "Crear un escenario no debe mutar sus datos fuente")
	if not bool(a.ok):
		return
	var sim: Simulacion = a.sim
	_comprobar(sim.desarrollo, "El escenario debe habilitar explícitamente los comandos de desarrollo")
	var vuelta: Dictionary = JSON.parse_string(JSON.stringify(datos))
	var b := DevEscenarios.crear(vuelta)
	_comprobar(bool(b.ok), "La plantilla debe soportar ida y vuelta JSON")
	if bool(b.ok):
		_comprobar(sim.huella() == b.sim.huella(), "El JSON no debe cambiar el estado inicial")
	var copia := DevEscenarios.plantilla()
	copia.inicio.dinero = 4321.0
	_comprobar(float(DevEscenarios.plantilla().inicio.dinero) != 4321.0,
		"Las plantillas deben ser independientes entre sí")
	var configurado := DevEscenarios.crear(copia)
	_comprobar(bool(configurado.ok), "El presupuesto inicial debe ser configurable")
	if bool(configurado.ok):
		_comprobar(is_equal_approx(configurado.sim.dinero, 4321.0), "Se debe aplicar el presupuesto solicitado")


func _presets() -> void:
	var nombres := DevEscenarios.nombres()
	_comprobar(not nombres.is_empty(), "Debe existir al menos un escenario de ejemplo")
	for nombre in nombres:
		var datos := DevEscenarios.preset(nombre)
		var a := DevEscenarios.crear(datos)
		var b := DevEscenarios.crear(datos)
		_comprobar(bool(a.ok) and bool(b.ok), "Preset inválido: %s (%s)" % [nombre, a.get("error", "")])
		if not bool(a.ok) or not bool(b.ok):
			continue
		var sa: Simulacion = a.sim
		var sb: Simulacion = b.sim
		var inicial := sa.huella()
		_comprobar(sa.huella() == sb.huella(), "El preset %s no prepara dos estados idénticos" % nombre)
		for paso in 220:
			sa.paso()
			sb.paso()
		_comprobar(sa.huella() == sb.huella(), "El preset %s diverge tras avanzar" % nombre)
		var replay := Simulacion.reproducir(sa.diario, sa.n_paso, true)
		_comprobar(replay.huella() == sa.huella(), "El diario del preset %s debe reconstruir el estado" % nombre)
		var json: Dictionary = JSON.parse_string(JSON.stringify(datos))
		var desde_json := DevEscenarios.crear(json)
		_comprobar(bool(desde_json.ok), "Preset %s inválido después de JSON" % nombre)
		if bool(desde_json.ok):
			_comprobar(desde_json.sim.huella() == inicial,
				"El JSON debe conservar el estado inicial del preset %s" % nombre)


func _granularidad() -> void:
	var capacidad_original: int = Cfg.ROBOTS[1].cap
	var datos := DevEscenarios.plantilla()
	datos.base = "vacio"
	datos.inicio = {"dia": 2, "hora": 23.0, "dinero": 300.0, "semilla_ciudad": 456}
	datos.sistemas = {"ciudad": false, "produccion": false, "robots": false, "logistica": false}
	datos.ajustes = {"robots.1.cap": 5.0}
	datos.comandos = [
		{"tipo": "dev_robot", "nivel": 1, "cantidad": 1, "celda": [23, 66]},
		{"tipo": "dev_robot_estado", "id": 1, "carga": "cobre", "cantidad": 4},
		{"tipo": "dev_maquina", "maquina": "fundidora", "celda": [26, 60], "rot": 1},
		{"tipo": "dev_maquina_estado", "id": "FUN-01", "entrada": {"cobre": 6}, "progreso": 0.5},
		{"tipo": "dev_material", "material": "cobre", "cantidad": 3, "celda": [24, 66]}]
	datos.eventos = [
		{"paso": 20, "cmd": {"tipo": "dev_dinero", "valor": 42}},
		{"paso": 0, "cmd": {"tipo": "dev_material", "material": "silicio", "cantidad": 1, "celda": [25, 66]}},
		{"paso": 20, "cmd": {"tipo": "dev_dinero", "valor": 57}}]
	datos.pausa = {"evento": "derrame", "pasos": 200}
	datos.programas = {"1": "await yo.esperar(1);"}
	var r := DevEscenarios.crear(datos)
	_comprobar(bool(r.ok), "El escenario granular debe ser válido: %s" % r.get("error", ""))
	if not bool(r.ok):
		return
	var sim: Simulacion = r.sim
	_comprobar(sim.dia() == 2 and is_equal_approx(sim.hora(), 23.0), "El reloj inicial debe aplicar día y hora")
	_comprobar(sim.n_paso == 0, "Preparar una hora inicial no debe simular el pasado")
	_comprobar(sim.robots.size() == 1 and sim.robots[0].nivel == 1, "Base vacía permite escenarios sin mulas")
	_comprobar(sim.robot(1).cap() == 5 and sim.robot(1).cant == 4, "Ajuste de tipo debe aplicarse al robot creado después")
	_comprobar(Cfg.ROBOTS[1].cap == capacidad_original, "El escenario no debe mutar las constantes de balance")
	_comprobar(sim.maquinas.size() == 1 and sim.maquinas["FUN-01"].rot == 1, "Se debe preparar una máquina y su orientación")
	_comprobar(sim.maquinas["FUN-01"].trabajando and is_equal_approx(sim.maquinas["FUN-01"].progreso, 0.5),
		"Se debe poder preparar una producción en curso")
	_comprobar(sim.suelo[Vector2i(24, 66)].cant == 3, "Coordenadas JSON deben convertirse a celdas del mundo")
	_comprobar(sim.robot(1).codigo == datos.programas["1"] and not sim.robot(1).ejecutando,
		"Asignar código no debe iniciar un worker")
	_comprobar(r.eventos.size() == 3 and r.eventos[0].paso == 0 and r.eventos[1].cmd.valor == 42 and r.eventos[2].cmd.valor == 57,
		"Los eventos se ordenan por paso y conservan orden de autoría en empates")
	_comprobar(r.pausa.evento == "derrame" and r.pausa.pasos == 200, "El escenario debe conservar las dos condiciones de pausa")
	for paso in 30:
		sim.paso()
	_comprobar(is_equal_approx(sim.maquinas["FUN-01"].progreso, 0.5), "Congelar producción debe conservar el avance")
	_comprobar(sim.robot(1).cant == 4, "Congelar robots debe conservar la carga")
	_comprobar(sim.ciudad.quejas_nocturnas == 0, "Congelar ciudad no debe generar quejas de noche")
	_comprobar(Simulacion.reproducir(sim.diario, sim.n_paso, true).huella() == sim.huella(),
		"El escenario granular debe reconstruirse desde su diario")
	var normalizado := DevEscenarios.normalizar({"celda": [23, 66], "orden": {"celda": [24, 67]}})
	_comprobar(normalizado.celda == Vector2i(23, 66) and normalizado.orden.celda == Vector2i(24, 67),
		"Normalizar debe convertir también coordenadas anidadas")
	_comprobar(DevEscenarios.normalizar({"celda": [23.5, 66]}).celda is Array,
		"Normalizar debe conservar coordenadas fraccionarias para rechazarlas sin truncamiento")


func _rechazos() -> void:
	var partida := Simulacion.new(true)
	partida.paso()
	var antes := partida.huella()
	var casos: Array[Dictionary] = []
	var version := DevEscenarios.plantilla()
	version.version = 999
	casos.append(version)
	var base := DevEscenarios.plantilla()
	base.base = "desconocida"
	casos.append(base)
	var comando := DevEscenarios.plantilla()
	comando.comandos = [{"tipo": "dev_no_existe"}]
	casos.append(comando)
	var fraccionario := DevEscenarios.plantilla()
	fraccionario.comandos = [{"tipo": "dev_robot", "nivel": 1, "celda": [23.5, 66]}]
	casos.append(fraccionario)
	var programa := DevEscenarios.plantilla()
	programa.programas = {"999": "await yo.esperar(1);"}
	casos.append(programa)
	var reloj_diferido := DevEscenarios.plantilla()
	reloj_diferido.eventos = [{"paso": 20, "cmd": {"tipo": "dev_reloj", "dia": 1, "hora": 12.0}}]
	casos.append(reloj_diferido)
	var ajuste := DevEscenarios.plantilla()
	ajuste.ajustes = {"robots.1.cap": 1.5}
	casos.append(ajuste)
	for datos in casos:
		var resultado := DevEscenarios.crear(datos)
		_comprobar(not bool(resultado.ok), "Los datos inválidos deben devolver un error")
		_comprobar(str(resultado.get("error", "")) != "", "Un rechazo debe explicar el motivo")
		_comprobar(partida.huella() == antes, "Validar otro escenario debe preservar la partida activa")


func _controlador() -> void:
	var p := PartidaPrueba.new()
	var d := Devtools.new()
	d.p = p
	var datos := DevEscenarios.plantilla()
	datos.sistemas = {"ciudad": false, "produccion": false, "robots": false, "logistica": false}
	datos.eventos = [
		{"paso": 2, "cmd": {"tipo": "dev_dinero", "valor": 111}},
		{"paso": 2, "cmd": {"tipo": "dev_dinero", "valor": 222}},
		{"paso": 5, "cmd": {"tipo": "dev_dinero", "valor": 333}},
		{"paso": 10, "cmd": {"tipo": "dev_dinero", "valor": 444}}]
	datos.pausa = {"evento": "", "pasos": 3}
	_comprobar(d.cargar_escenario(datos) == "", "El controlador debe instalar un escenario válido")
	_comprobar(p.velocidad == 0.0 and not d.ocupado, "Instalar debe dejar la partida pausada y disponible")
	_comprobar(d.avanzar(20) == "", "El avance manual debe aceptar pasos válidos")
	_comprobar(p.sim.n_paso == 3 and d.pausa_consumida, "El límite debe interrumpir el avance exactamente en su paso")
	_comprobar(p.sim.dinero == 222 and d.indice_evento == 2, "Los eventos del mismo paso deben aplicarse en orden una vez")
	_comprobar(d.avanzar(4) == "" and p.sim.n_paso == 7, "Una pausa consumida debe permitir continuar el experimento")
	_comprobar(p.sim.dinero == 333 and d.indice_evento == 3, "Los eventos posteriores deben respetar su paso")
	var antes := p.sim.huella()
	var escenario_antes := var_to_str(d.escenario)
	var invalido := DevEscenarios.plantilla()
	invalido.version = 999
	_comprobar(d.cargar_escenario(invalido) != "", "El controlador debe rechazar escenarios inválidos")
	_comprobar(p.sim.huella() == antes and var_to_str(d.escenario) == escenario_antes,
		"Un escenario inválido debe conservar mundo y escenario actual")
	_comprobar(d.ejecutar({"tipo": "dev_robot", "nivel": 1, "cantidad": 1, "celda": [40, 70]}) == "",
		"Se debe poder crear un robot con la partida pausada en el paso final")
	_comprobar(d.anotar("Capacidad suficiente, falta transporte") == "", "El controlador debe aceptar notas")
	p.sim.robot(3).codigo = "await yo.esperar(2);"
	var guardada := p.sim.huella()
	var n_robots := p.sim.robots.size()
	var nombre := "_prueba_devtools_%d" % OS.get_process_id()
	_comprobar(d.guardar("../fuera") != "", "Una ranura no puede escribir fuera de su carpeta")
	_comprobar(d.guardar(nombre) == "", "El controlador debe guardar la ranura de prueba")
	_comprobar(("Guardado: " + nombre) in d.escenarios(), "La ranura debe aparecer en el catálogo")
	_comprobar(d.ejecutar({"tipo": "dev_dinero", "valor": 999}) == "", "Se puede modificar la partida tras guardarla")
	var restaurar := d.cargar("Guardado: " + nombre)
	_comprobar(restaurar == "", "La ranura debe poder restaurarse: %s" % restaurar)
	if restaurar == "":
		_comprobar(p.sim.huella() == guardada and p.sim.robots.size() == n_robots,
			"El replay debe aplicar una sola vez las órdenes del último paso en pausa")
		_comprobar(d.indice_evento == 3 and d.pausa_consumida and d.notas.size() == 1,
			"Restaurar debe conservar agenda consumida, pausa y notas")
		_comprobar(p.sim.robot(3).codigo == "await yo.esperar(2);" and not p.sim.robot(3).ejecutando,
			"La ranura debe conservar código sin iniciar su ejecución")
		_comprobar(d.avanzar(4) == "" and p.sim.n_paso == 11 and p.sim.dinero == 444,
			"Restaurar debe continuar la agenda pendiente sin repetir eventos anteriores")
	var ruta := Devtools.CARPETA + nombre + ".json"
	var original := FileAccess.get_file_as_string(ruta)
	var alterada: Dictionary = JSON.parse_string(original)
	alterada.huella = "incorrecta"
	var archivo := FileAccess.open(ruta, FileAccess.WRITE)
	archivo.store_string(JSON.stringify(alterada))
	archivo.close()
	var antes_danada := p.sim.huella()
	var agenda_antes_danada := d.indice_evento
	_comprobar(d.cargar(nombre) != "", "Una huella corrupta debe impedir restaurar la ranura")
	_comprobar(p.sim.huella() == antes_danada and d.indice_evento == agenda_antes_danada,
		"Una ranura corrupta debe preservar el mundo y la agenda activos")
	var metadatos_invalidos: Array[Dictionary] = [
		{"condicion": "invalida"}, {"indice_evento": -1}, {"indice_evento": 999},
		{"notas": {}}, {"marcas": {}}, {"metricas": {}}, {"pasos": 7.5}]
	for metadatos in metadatos_invalidos:
		var corrupta: Dictionary = JSON.parse_string(original)
		corrupta.merge(metadatos, true)
		archivo = FileAccess.open(ruta, FileAccess.WRITE)
		archivo.store_string(JSON.stringify(corrupta))
		archivo.close()
		_comprobar(d.cargar(nombre) != "", "Metadatos inválidos deben rechazar la ranura: %s" % metadatos)
		_comprobar(p.sim.huella() == antes_danada and d.indice_evento == agenda_antes_danada,
			"Metadatos inválidos deben preservar la partida y agenda: %s" % metadatos)
	_comprobar(d.reiniciar() == "" and p.sim.n_paso == 0 and d.indice_evento == 0 and d.notas.is_empty(),
		"Reiniciar debe devolver el escenario original y limpiar notas y agenda consumida")
	# Una pausa por evento debe reaccionar al registro físico generado durante el paso.
	var produccion := DevEscenarios.plantilla()
	produccion.sistemas.ciudad = false
	produccion.comandos = [{"tipo": "dev_maquina_estado", "id": "FUN-01", "entrada": {"cobre": 1}}]
	produccion.pausa = {"evento": "salida", "pasos": 0}
	_comprobar(d.cargar_escenario(produccion) == "", "Debe poder prepararse una pausa por producción")
	_comprobar(d.avanzar(200) == "" and p.sim.n_paso < 200 and d.pausa_consumida,
		"El primer evento salida debe interrumpir el avance manual")
	_comprobar(int(p.sim.maquinas["FUN-01"].producidos) == 1, "La pausa por producción debe ocurrir tras la primera salida")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ruta))
	d.free()
	p.free()
