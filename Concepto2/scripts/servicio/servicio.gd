class_name Servicio
extends Node
## Conexión con el proceso auxiliar (servicio/main.mjs, Node.js):
##   - PostgreSQL real (PGlite) para el registro y la consola SQL.
##   - Runtime JavaScript de los programas de los robots.
## Protocolo: TCP local, un mensaje JSON por línea. Si Node no está, el juego sigue con SQLite y sin
## programas (BaseDatos elige el motor). En la web, el plan es el mismo protocolo sobre
## JavaScriptBridge con PGlite y un Web Worker en el navegador.

var conectado := false
var motor := ""
var puerto_pg := 0
var error := ""
var pid := -1
var _tcp := StreamPeerTCP.new()
var _bytes := PackedByteArray()
var _recibidos: Array[Dictionary] = []
var _sig_id := 0


func iniciar(esquema: String) -> bool:
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
	enviar({"op": "iniciar", "esquema": esquema})
	var listo := _esperar(func(m): return m.op == "listo", 15000)
	if listo.is_empty():
		error = "El servicio no respondió al crear el esquema."
		return false
	if listo.has("error"):
		error = "Error de esquema en PostgreSQL: " + str(listo.error)
		return false
	motor = str(listo.motor)
	puerto_pg = int(listo.get("pg", 0))
	conectado = true
	return true


func enviar(m: Dictionary) -> void:
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_tcp.put_data((JSON.stringify(m) + "\n").to_utf8_buffer())


## Consulta síncrona (la consola y el HUD esperan el resultado; en local tarda ~1 ms).
func sql(texto: String, espera_ms: int = 3000) -> Dictionary:
	_sig_id += 1
	var id := _sig_id
	enviar({"op": "sql", "id": id, "sql": texto})
	var r := _esperar(func(m): return m.op == "res" and int(m.id) == id, espera_ms)
	if r.is_empty():
		return {"ok": false, "columnas": [], "filas": [], "error": "El servicio no respondió a tiempo", "ms": float(espera_ms)}
	return r


## Mensajes pendientes (acciones, logs, errores de los programas, avisos de la base).
func recibir() -> Array[Dictionary]:
	_leer()
	var res := _recibidos
	_recibidos = []
	return res


func cerrar() -> void:
	if conectado:
		enviar({"op": "salir"})
		_tcp.poll()
	if pid > 0:
		OS.kill(pid)
	conectado = false
	pid = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		cerrar()


func _leer() -> void:
	_tcp.poll()
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if conectado:
			conectado = false
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
