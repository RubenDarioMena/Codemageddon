class_name Servicio
extends Node
## Conexión con el «servicio» que aporta PostgreSQL (PGlite) y el runtime JavaScript de los robots.
## Dos transportes con el mismo protocolo (mensajes JSON):
##   - Escritorio: proceso Node (servicio/main.mjs) por TCP local, un mensaje por línea.
##   - Web: módulo de la página (web/servicio_web.js) vía JavaScriptBridge; PGlite y un Web Worker
##     por robot corren en el propio navegador.
## Si ninguno está disponible, el juego sigue con SQLite y sin programas (BaseDatos elige el motor).

enum { SIN_SERVICIO, INICIANDO, CONECTADO }

var estado := SIN_SERVICIO
var conectado: bool:
	get: return estado == CONECTADO
var motor := ""
var puerto_pg := 0
var error := ""
var pid := -1
var es_web := OS.has_feature("web")
var _tcp := StreamPeerTCP.new()
var _bytes := PackedByteArray()
var _recibidos: Array[Dictionary] = []
var _respuestas := {}          # id de consulta -> Callable
var _sig_id := 0
var _esquema := ""
var _limite_web := 0
var _enviado_iniciar := false


## Escritorio: arranca Node y espera a que PostgreSQL esté listo (síncrono, ~1-2 s).
## Web: empieza a cargar el módulo; `actualizar()` completa la conexión unos segundos después.
func iniciar(esquema: String) -> bool:
	_esquema = esquema
	if es_web:
		return _iniciar_web()
	return _iniciar_node()


func actualizar() -> void:
	if es_web and estado == INICIANDO:
		_avanzar_web()


func enviar(m: Dictionary) -> void:
	if es_web:
		if estado != SIN_SERVICIO:
			JavaScriptBridge.eval("window.cmg && window.cmg.enviar(%s)" % JSON.stringify(JSON.stringify(m)))
	elif _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_tcp.put_data((JSON.stringify(m) + "\n").to_utf8_buffer())


## Consulta asíncrona: `listo` recibe {ok, columnas, filas (arrays), error, ms}.
func sql_luego(texto: String, listo: Callable) -> void:
	_sig_id += 1
	_respuestas[_sig_id] = listo
	enviar({"op": "sql", "id": _sig_id, "sql": texto})


## Consulta síncrona (solo escritorio: en la web el hilo principal no puede esperar).
func sql(texto: String, espera_ms: int = 3000) -> Dictionary:
	if es_web:
		return {"ok": false, "columnas": [], "filas": [], "error": "En la web las consultas son asíncronas", "ms": 0.0}
	_sig_id += 1
	var id := _sig_id
	enviar({"op": "sql", "id": id, "sql": texto})
	var r := _esperar(func(m): return m.op == "res" and int(m.id) == id, espera_ms)
	if r.is_empty():
		return {"ok": false, "columnas": [], "filas": [], "error": "El servicio no respondió a tiempo", "ms": float(espera_ms)}
	return r


## Mensajes pendientes (acciones, logs, errores de los programas, avisos de la base).
## Las respuestas a consultas asíncronas se entregan aquí mismo a su callback.
func recibir() -> Array[Dictionary]:
	_leer()
	var res: Array[Dictionary] = []
	for m in _recibidos:
		if m.get("op") == "res" and _respuestas.has(int(m.get("id", -1))):
			var cb: Callable = _respuestas[int(m.id)]
			_respuestas.erase(int(m.id))
			cb.call(m)
		else:
			res.append(m)
	_recibidos = []
	return res


func cerrar() -> void:
	if conectado and not es_web:
		enviar({"op": "salir"})
		_tcp.poll()
	if pid > 0:
		OS.kill(pid)
	estado = SIN_SERVICIO
	pid = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		cerrar()


# ---------------------------------------------------------------- web

func _iniciar_web() -> bool:
	# El módulo carga PGlite (Postgres en WASM) desde la misma web; Godot lo sondea cada fotograma.
	JavaScriptBridge.eval("""(function () {
		if (window.cmgCargando) return;
		window.cmgCargando = true;
		const s = document.createElement('script');
		s.type = 'module';
		s.src = 'servicio_web/servicio_web.js';
		s.onerror = () => { window.cmgError = 'No se pudo cargar servicio_web.js'; };
		document.head.appendChild(s);
	})()""", true)
	estado = INICIANDO
	_limite_web = Time.get_ticks_msec() + 45000
	return false


func _avanzar_web() -> void:
	if Time.get_ticks_msec() > _limite_web:
		error = "PostgreSQL (PGlite) no arrancó en el navegador."
		estado = SIN_SERVICIO
		return
	var fallo = JavaScriptBridge.eval("window.cmgError || ''", true)
	if fallo is String and fallo != "":
		error = fallo
		estado = SIN_SERVICIO
		return
	if not _enviado_iniciar:
		if JavaScriptBridge.eval("window.cmg && window.cmg.listo ? 1 : 0", true) == 1:
			# Aún INICIANDO: enviar() ya funciona porque el estado no es SIN_SERVICIO.
			enviar({"op": "iniciar", "esquema": _esquema})
			_enviado_iniciar = true
		return
	_leer()
	for k in _recibidos.size():
		var m: Dictionary = _recibidos[k]
		if m.get("op") == "listo":
			_recibidos.remove_at(k)
			if m.has("error"):
				error = "Error de esquema en PostgreSQL: " + str(m.error)
				estado = SIN_SERVICIO
			else:
				motor = str(m.motor)
				estado = CONECTADO
			return


# ---------------------------------------------------------------- escritorio (Node)

func _iniciar_node() -> bool:
	var node := _buscar_node()
	if node == "":
		error = "No se encontró Node.js (instálalo o define CODEMAGEDDON_NODE)."
		return false
	var dir := ProjectSettings.globalize_path("res://servicio")
	if not DirAccess.dir_exists_absolute(dir + "/node_modules/@electric-sql/pglite"):
		error = "Faltan dependencias: ejecuta «npm install» en %s." % dir
		return false
	var r := OS.execute_with_pipe(node, [dir + "/main.mjs", "--puerto", "0", "--pg", "5433",
		"--log", ProjectSettings.globalize_path("user://servicio.log")])
	if r.is_empty():
		error = "No se pudo lanzar Node (%s)." % node
		return false
	pid = r.pid
	# La primera (y única) línea de stdout es «PUERTO <n>», escrita cuando Postgres ya arrancó.
	var linea: String = (r.stdio as FileAccess).get_line()
	if not linea.begins_with("PUERTO "):
		error = "El servicio no arrancó (ver user://servicio.log)."
		return false
	var puerto := int(linea.split(" ")[1])
	_tcp.connect_to_host("127.0.0.1", puerto)
	var limite := Time.get_ticks_msec() + 4000
	while _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < limite:
		_tcp.poll()
		OS.delay_msec(5)
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		error = "No se pudo conectar con el servicio en el puerto %d." % puerto
		return false
	_tcp.set_no_delay(true)
	enviar({"op": "iniciar", "esquema": _esquema})
	var listo := _esperar(func(m): return m.op == "listo", 15000)
	if listo.is_empty():
		error = "El servicio no respondió al crear el esquema."
		return false
	if listo.has("error"):
		error = "Error de esquema en PostgreSQL: " + str(listo.error)
		return false
	motor = str(listo.motor)
	puerto_pg = int(listo.get("pg", 0))
	estado = CONECTADO
	return true


func _leer() -> void:
	if es_web:
		if estado == SIN_SERVICIO:
			return
		var s = JavaScriptBridge.eval("window.cmg ? window.cmg.recibir() : ''", true)
		if s is String and s != "":
			var lista = JSON.parse_string(s)
			if lista is Array:
				for m in lista:
					if m is Dictionary:
						_recibidos.append(m)
		return
	_tcp.poll()
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if conectado:
			estado = SIN_SERVICIO
			error = "Se perdió la conexión con el servicio."
		return
	var n := _tcp.get_available_bytes()
	if n <= 0:
		return
	var datos: Array = _tcp.get_data(n)
	if datos[0] != OK:
		return
	_bytes.append_array(datos[1])
	while true:
		var i := _bytes.find(10)
		if i < 0:
			break
		var linea := _bytes.slice(0, i).get_string_from_utf8()
		_bytes = _bytes.slice(i + 1)
		var m = JSON.parse_string(linea)
		if m is Dictionary:
			_recibidos.append(m)


func _esperar(criterio: Callable, espera_ms: int) -> Dictionary:
	var limite := Time.get_ticks_msec() + espera_ms
	while Time.get_ticks_msec() < limite:
		_leer()
		for k in _recibidos.size():
			if criterio.call(_recibidos[k]):
				var m: Dictionary = _recibidos[k]
				_recibidos.remove_at(k)
				return m
		OS.delay_usec(250)
	return {}


func _buscar_node() -> String:
	var candidatos: Array[String] = []
	if OS.has_environment("CODEMAGEDDON_NODE"):
		candidatos.append(OS.get_environment("CODEMAGEDDON_NODE"))
	var salida := []
	if OS.get_name() != "Windows":
		OS.execute("/bin/zsh", ["-lc", "command -v node"], salida)
		for s in salida:
			candidatos.append(str(s).strip_edges().get_slice("\n", 0))
		# nvm no se carga en shells de login: buscar la versión más reciente instalada.
		var nvm := OS.get_environment("HOME") + "/.nvm/versions/node"
		var versiones := DirAccess.get_directories_at(nvm)
		if versiones.size() > 0:
			var lista := Array(versiones)
			lista.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) > 0)
			candidatos.append(nvm + "/" + lista[0] + "/bin/node")
		candidatos.append_array(["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"])
	else:
		OS.execute("where", ["node"], salida)
		for s in salida:
			candidatos.append(str(s).strip_edges().get_slice("\n", 0))
	for c in candidatos:
		if c != "" and FileAccess.file_exists(c):
			return c
	return ""
