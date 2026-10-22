class_name BaseDatos
extends RefCounted
## Adaptador de base de datos. Hoy usa SQLite (godot-sqlite); el destino es PostgreSQL.
## Para que la migración no pierda nada:
##   - Todo el SQL del juego (esquema, ejemplos, auditorías) usa el subconjunto común de los dos.
##   - Las diferencias quedan aquí: el token {ID} del esquema y la escritura por lotes.
##   - El mundo no se lee de la base. La base es registro y proyección (GDD §10): borrar una fila
##     no crea ni destruye material.

const RUTA := "user://partida.db"

var db: SQLite
var filas_eventos := 0
var _esquema := ""


func abrir() -> void:
	var absoluta := ProjectSettings.globalize_path(RUTA)
	if FileAccess.file_exists(RUTA):
		DirAccess.remove_absolute(absoluta)
	db = SQLite.new()
	db.path = RUTA
	db.verbosity_level = SQLite.QUIET
	db.open_db()
	_esquema = FileAccess.get_file_as_string("res://datos/esquema.sql").replace("{ID}", "INTEGER PRIMARY KEY")
	crear_esquema()


func ruta_absoluta() -> String:
	return ProjectSettings.globalize_path(RUTA)


func crear_esquema() -> void:
	for sentencia in dividir(_esquema):
		db.query(sentencia)


## Inserta las colas de la simulación. Si el jugador borró una tabla, se recrea y se avisa.
func volcar(sim: Simulacion) -> String:
	var aviso := ""
	if not sim.registro.is_empty():
		if not db.insert_rows("eventos", sim.registro):
			crear_esquema()
			db.insert_rows("eventos", sim.registro)
			aviso = "La tabla eventos no existía: el juego la volvió a crear."
		filas_eventos += sim.registro.size()
		sim.registro.clear()
	if not sim.quejas.is_empty():
		if not db.insert_rows("quejas", sim.quejas):
			crear_esquema()
			db.insert_rows("quejas", sim.quejas)
		sim.quejas.clear()
	return aviso


## Reescribe las tablas de estado actual (maquinas, robots).
func proyectar(sim: Simulacion) -> void:
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

	if not db.query("DELETE FROM maquinas"):
		crear_esquema()
	db.query("DELETE FROM robots")
	db.insert_rows("maquinas", maq)
	db.insert_rows("robots", rob)



## Política de retención: si el registro supera la capacidad, se borran los eventos más antiguos.
func retener(capacidad: int) -> int:
	if not db.query("SELECT COUNT(*) AS n FROM eventos") or db.query_result.is_empty():
		return 0
	filas_eventos = int(db.query_result[0].n)
	var exceso := filas_eventos - capacidad
	if exceso <= 0:
		return 0
	db.query("DELETE FROM eventos WHERE id IN (SELECT id FROM eventos ORDER BY id LIMIT %d)" % exceso)
	filas_eventos = capacidad
	return exceso


## Consulta del jugador. Admite varias sentencias separadas por «;»; devuelve el resultado de la última.
func consultar(sql: String) -> Dictionary:
	var inicio := Time.get_ticks_usec()
	var res := {"ok": true, "columnas": [], "filas": [], "error": "", "ms": 0.0, "afectadas": 0}
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
