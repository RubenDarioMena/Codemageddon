class_name BaseDatos
extends RefCounted
## Adaptador de base de datos con dos motores detrás de la misma interfaz:
##   - PostgreSQL (destino): PGlite en el servicio auxiliar de Node (scripts/servicio/servicio.gd).
##   - SQLite (respaldo): godot-sqlite, si no hay Node. El juego funciona igual, sin programas JS.
## Para que cambiar de motor no pierda nada:
##   - Todo el SQL del juego (esquema, ejemplos, auditorías) usa el subconjunto común de los dos.
##   - Las diferencias quedan aquí: el token {ID} del esquema y cómo se escribe y se consulta.
##   - El mundo no se lee de la base. La base es registro y proyección (GDD §10): borrar una fila
##     no crea ni destruye material.

const RUTA_SQLITE := "user://partida.db"
const ID := {
	"sqlite": "INTEGER PRIMARY KEY",
	"postgres": "BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY",
}

var motor := "SQLite"
var es_postgres := false
var pendiente := false          # web: PostgreSQL aún arrancando en el navegador (se acumulan los eventos)
var filas_eventos := 0
var servicio: Servicio = null
var db = null                  # SQLite (godot-sqlite) sin tipo estático: la extensión puede faltar
var _esquema := ""


static func esquema(dialecto: String) -> String:
	return FileAccess.get_file_as_string("res://datos/esquema.sql").replace("{ID}", ID[dialecto])


## Web: la base se decide unos segundos después (cuando PGlite termina de cargar).
func abrir_pendiente() -> void:
	pendiente = true
	motor = "PostgreSQL (arrancando…)"


## Con un servicio conectado (que ya creó el esquema en PostgreSQL) usa PostgreSQL; si no, SQLite.
func abrir(p_servicio: Servicio = null) -> void:
	pendiente = false
	if p_servicio != null and p_servicio.conectado:
		servicio = p_servicio
		es_postgres = true
		motor = p_servicio.motor
		_esquema = esquema("postgres")
		return
	es_postgres = false
	if not ClassDB.class_exists("SQLite"):
		motor = "Sin base de datos"
		return
	var absoluta := ProjectSettings.globalize_path(RUTA_SQLITE)
	if FileAccess.file_exists(RUTA_SQLITE):
		DirAccess.remove_absolute(absoluta)
	db = ClassDB.instantiate("SQLite")
	db.path = RUTA_SQLITE
	db.verbosity_level = 0   # QUIET
	db.open_db()
	_esquema = esquema("sqlite")
	motor = "SQLite " + str(_consulta_sqlite("SELECT sqlite_version() AS v").filas[0].v)
	crear_esquema()


## Texto para la interfaz: dónde está la base y cómo abrirla con otras herramientas.
func descripcion() -> String:
	if pendiente:
		return "PostgreSQL arrancando en el navegador…"
	if es_postgres and servicio.es_web:
		return "%s, dentro de tu navegador (PGlite, en memoria)." % motor
	if es_postgres:
		var conexion := ""
		if servicio.puerto_pg > 0:
			conexion = " · conéctate con psql/DBeaver: host 127.0.0.1, puerto %d, usuario postgres" % servicio.puerto_pg
		return "%s, en memoria%s." % [motor, conexion]
	return "%s · archivo %s (ábrelo con DB Browser o sqlite3). Destino: PostgreSQL (mismo SQL)." % [
		motor, ProjectSettings.globalize_path(RUTA_SQLITE)]


func crear_esquema() -> void:
	if es_postgres:
		servicio.sql_luego(_esquema, func(_r): pass)
		return
	if db == null:
		return
	for sentencia in dividir(_esquema):
		db.query(sentencia)


## Inserta las colas de la simulación. Si el jugador borró una tabla, se recrea y se avisa.
func volcar(sim: Simulacion) -> String:
	if pendiente:
		return ""   # los eventos esperan en la simulación hasta que la base esté lista
	var aviso := ""
	if db == null and not es_postgres:
		sim.registro.clear()
		sim.quejas.clear()
		return ""
	if not sim.registro.is_empty():
		if es_postgres:
			servicio.enviar({"op": "insertar", "tabla": "eventos", "filas": sim.registro})
		elif not db.insert_rows("eventos", sim.registro):
			crear_esquema()
			db.insert_rows("eventos", sim.registro)
			aviso = "La tabla eventos no existía: el juego la volvió a crear."
		filas_eventos += sim.registro.size()
		sim.registro.clear()
	if not sim.quejas.is_empty():
		if es_postgres:
			servicio.enviar({"op": "insertar", "tabla": "quejas", "filas": sim.quejas})
		elif not db.insert_rows("quejas", sim.quejas):
			crear_esquema()
			db.insert_rows("quejas", sim.quejas)
		sim.quejas.clear()
	return aviso


## Reescribe las tablas de estado actual (maquinas, robots).
func proyectar(sim: Simulacion) -> void:
	if pendiente:
		return
	var maq: Array[Dictionary] = []
	for m: Maquina in sim.maquinas.values():
		maq.append({"id": m.id, "tipo": m.tipo, "x": m.celda.x, "z": m.celda.y, "ruido": m.ruido(),
			"estado": m.estado, "turno": "diurno" if m.turno_diurno else "24h", "entrada": m.total_entrada(),
			"salida": m.total_salida(), "producidos": m.producidos})
	var rob: Array[Dictionary] = []
	for r in sim.robots:
		rob.append({"id": r.id, "nivel": r.def.nivel, "modelo": r.def.nombre, "estado": r.estado,
			"carga": r.carga if r.carga != "" else null, "cantidad": r.cant, "x": snappedf(r.pos.x, 0.1),
			"z": snappedf(r.pos.y, 0.1), "distancia": snappedf(r.distancia, 0.1)})
	if es_postgres:
		servicio.enviar({"op": "proyectar", "maquinas": maq, "robots": rob})
		return
	if db == null:
		return
	if not db.query("DELETE FROM maquinas"):
		crear_esquema()
	db.query("DELETE FROM robots")
	db.insert_rows("maquinas", maq)
	db.insert_rows("robots", rob)


## Política de retención: si el registro supera la capacidad, se borran los eventos más antiguos.
func retener(capacidad: int) -> int:
	var r := consultar("SELECT COUNT(*) AS n FROM eventos")
	if not r.ok or r.filas.is_empty():
		return 0
	filas_eventos = int(r.filas[0].n)
	var exceso := filas_eventos - capacidad
	if exceso <= 0:
		return 0
	consultar("DELETE FROM eventos WHERE id IN (SELECT id FROM eventos ORDER BY id LIMIT %d)" % exceso)
	filas_eventos = capacidad
	return exceso


## Versión asíncrona de `retener` (la que usa el juego: en la web nada puede bloquear).
func retener_luego(capacidad: int, al_borrar: Callable) -> void:
	consultar_luego("SELECT COUNT(*) AS n FROM eventos", func(r):
		if not r.ok or r.filas.is_empty():
			return
		filas_eventos = int(r.filas[0].n)
		var exceso := filas_eventos - capacidad
		if exceso > 0:
			consultar_luego("DELETE FROM eventos WHERE id IN (SELECT id FROM eventos ORDER BY id LIMIT %d)" % exceso, func(_r): pass)
			filas_eventos = capacidad
			al_borrar.call(exceso))


## Consulta asíncrona: `listo` recibe el mismo formato que `consultar`. La usan la consola, el HUD,
## los paneles fijados y las auditorías, porque funciona igual en escritorio y en la web.
func consultar_luego(sql: String, listo: Callable) -> void:
	if pendiente:
		listo.call({"ok": false, "columnas": [], "filas": [], "error": "La base de datos aún está arrancando…", "ms": 0.0})
	elif not es_postgres:
		listo.call(_consulta_sqlite(sql))
	else:
		servicio.sql_luego(sql, func(r): listo.call(_convertir(r)))


## Consulta síncrona (escritorio y pruebas). Admite varias sentencias separadas por «;» y devuelve la
## última. Formato común: {ok, columnas: [StringName], filas: [{columna: valor}], error, ms}.
func consultar(sql: String) -> Dictionary:
	if pendiente:
		return {"ok": false, "columnas": [], "filas": [], "error": "La base de datos aún está arrancando…", "ms": 0.0}
	if not es_postgres:
		return _consulta_sqlite(sql)
	return _convertir(servicio.sql(sql))


func _convertir(r: Dictionary) -> Dictionary:
	var columnas: Array = []
	for c in r.get("columnas", []):
		columnas.append(StringName(c))
	var filas: Array = []
	for f in r.get("filas", []):
		var d := {}
		for i in columnas.size():
			var v = f[i]
			# JSON no distingue enteros: 3.0 vuelve a ser 3.
			d[columnas[i]] = int(v) if v is float and v == floor(v) and abs(v) < 1e15 else v
		filas.append(d)
	return {"ok": bool(r.get("ok", false)), "columnas": columnas, "filas": filas, "error": str(r.get("error", "")),
		"ms": float(r.get("ms", 0.0))}


func _consulta_sqlite(sql: String) -> Dictionary:
	var inicio := Time.get_ticks_usec()
	var res := {"ok": true, "columnas": [], "filas": [], "error": "", "ms": 0.0}
	if db == null:
		res.ok = false
		res.error = "No hay base de datos disponible"
		return res
	var sentencias := dividir(sql)
	if sentencias.is_empty():
		res.ok = false
		res.error = "Consulta vacía"
		return res
	for s in sentencias:
		if not db.query(s):
			res.ok = false
			res.error = db.error_message
			break
		res.filas = db.query_result.duplicate()
	res.ms = (Time.get_ticks_usec() - inicio) / 1000.0
	if res.ok and not res.filas.is_empty():
		res.columnas = res.filas[0].keys()
	return res


## Divide un texto en sentencias por «;», respetando comillas simples y comentarios «--».
static func dividir(sql: String) -> PackedStringArray:
	var res: PackedStringArray = []
	var actual := ""
	var en_cadena := false
	var en_comentario := false
	for i in sql.length():
		var ch := sql[i]
		if en_comentario:
			if ch == "\n":
				en_comentario = false
				actual += ch
			continue
		if not en_cadena and ch == "-" and i + 1 < sql.length() and sql[i + 1] == "-":
			en_comentario = true
			continue
		if ch == "'":
			en_cadena = not en_cadena
		if ch == ";" and not en_cadena:
			if actual.strip_edges() != "":
				res.append(actual.strip_edges())
			actual = ""
			continue
		actual += ch
	if actual.strip_edges() != "":
		res.append(actual.strip_edges())
	return res
