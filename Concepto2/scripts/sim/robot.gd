class_name Robot
extends RefCounted
## Robot con identidad estable (robots[n]). Las órdenes manuales y las programadas son la misma lista.

var id: int
var nivel: int
var def: Dictionary
var pos: Vector2
var prev: Vector2
var rumbo := 0.0             # radianes; 0 = mirando hacia +Z
var prev_rumbo := 0.0
var carga := ""
var cant := 0
var ordenes: Array[Dictionary] = []
var pc := 0                  # orden en curso (contador de programa)
var repetir := false
var auto := false            # rutina autónoma (solo T2)
var auto_fase := "buscar"
var auto_obj := {}           # mena o máquina elegida por la rutina
var camino := PackedVector2Array()
var paso := 0
var meta := Vector2i(-1, -1)
var timer := 0.0
var estado := "ocioso"
var distancia := 0.0
var atasco := 0.0            # segundos sin avanzar hacia el siguiente punto


func _init(p_id: int, p_nivel: int, p_pos: Vector2) -> void:
	id = p_id
	nivel = p_nivel
	def = Cfg.ROBOTS[nivel]
	pos = p_pos
	prev = p_pos
	auto = def.auto


func nombre() -> String:
	return "R%d" % id


func etiqueta() -> String:
	return "R%d · %s %s" % [id, def.nombre, def.nivel]


func cap() -> int:
	return def.cap


func celda() -> Vector2i:
	return Vector2i(floor(pos.x), floor(pos.y))


func ocioso() -> bool:
	return pc >= ordenes.size() and not auto


func vel() -> float:
	return def.vel


## Programa equivalente a la lista de órdenes, en el JavaScript que usará el jugador.
## Devuelve [líneas, índice de la línea en ejecución o -1].
func programa() -> Array:
	var ref := "robots[%d]" % id
	var lineas: PackedStringArray = []
	var activa := -1
	if auto and pc >= ordenes.size():
		lineas = [
			"// Rutina del explorador (sensores + pala)",
			"while (true) {",
			"  const m = %s.buscarMena();" % ref,
			"  await %s.minar(m);" % ref,
			"  const f = %s.buscarMaquina(\"fundidora\", { conEspacio: true });" % ref,
			"  await %s.entregar(f);" % ref,
			"}",
		]
		activa = {"buscar": 2, "ir_mena": 3, "minar": 3, "ir_fundidora": 4, "esperar": 4, "entregar": 5}.get(auto_fase, -1)
		return [lineas, activa]
	if ordenes.is_empty():
		return [PackedStringArray(["// Sin órdenes. Clic derecho para dar una.", "// Shift + clic derecho las encola."]), -1]
	var sangria := ""
	lineas.append("// %s · %s" % [etiqueta(), "en bucle" if repetir else "una vez"])
	if repetir:
		lineas.append("while (true) {")
		sangria = "  "
	for k in ordenes.size():
		if k == pc:
			activa = lineas.size()
		lineas.append(sangria + _linea(ordenes[k], ref))
	if repetir:
		lineas.append("}")
	elif pc >= ordenes.size():
		lineas.append("// fin: el robot queda ocioso")
		activa = lineas.size() - 1
	return [lineas, activa]


func _linea(o: Dictionary, ref: String) -> String:
	match o.tipo:
		"mover":
			return "await %s.ir(%d, %d);" % [ref, o.celda.x, o.celda.y]
		"recoger":
			if o.objetivo == "suelo":
				return "await %s.recoger(suelo(%d, %d));" % [ref, o.celda.x, o.celda.y]
			if o.get("material", "") != "":
				return "await %s.recoger(\"%s\", \"%s\");" % [ref, o.objetivo, o.material]
			return "await %s.recoger(\"%s\");" % [ref, o.objetivo]
		"entregar":
			return "await %s.entregar(\"%s\");" % [ref, o.objetivo]
		"minar":
			return "await %s.minar(\"%s\");" % [ref, o.objetivo]
		"reparar":
			return "await %s.reparar(\"%s\");" % [ref, o.objetivo]
	return "// ?"
