class_name Maquina
extends RefCounted
## Una máquina con identidad estable (p. ej. FUN-01). Entrada por el lado opuesto a `rot`, salida por `rot`.

var id: String
var tipo: String
var def: Dictionary
var celda: Vector2i          # esquina de menor x/z de la huella
var rot: int                 # 0 = salida hacia +X, 1 = +Z, 2 = -X, 3 = -Z
var tam: Vector2i
var entrada := {}            # material -> unidades
var salida := {}
var receta := ""
var progreso := 0.0
var trabajando := false
var estado := "construyendo"
var obra := 0.0              # segundos de construcción pendientes
var turno_diurno := false    # true = se detiene de 22:00 a 06:00
var pausada := false
var averiada := false
var producidos := 0
var salida_cinta := "cobre"  # solo recepción: qué material manda a la cinta
var envio_auto := true       # solo despacho
var dev_tiempo := 1.0        # multiplicador de duración por instancia, solo laboratorio


func _init(p_id: String, p_tipo: String, p_celda: Vector2i, p_rot: int) -> void:
	id = p_id
	tipo = p_tipo
	def = Cfg.MAQUINAS[tipo]
	celda = p_celda
	rot = posmod(p_rot, 4)
	tam = Cfg.tam_rotado(def.tam, rot)
	if def.has("recetas"):
		receta = def.recetas.keys()[0]


func rect() -> Rect2i:
	return Rect2i(celda, tam)


func celdas() -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for z in tam.y:
		for x in tam.x:
			res.append(celda + Vector2i(x, z))
	return res


func centro() -> Vector2:
	return Vector2(celda) + Vector2(tam) * 0.5


func lista() -> bool:
	return obra <= 0.0


## Casilla interior del lado de entrada (una cinta que apunte aquí entrega material).
func celda_entrada() -> Vector2i:
	return _lado(-1, false)


## Casilla exterior del lado de salida (la máquina empuja material a una cinta situada aquí).
func celda_salida() -> Vector2i:
	return _lado(1, true)


func _lado(signo: int, exterior: bool) -> Vector2i:
	var d := Cfg.dir_vec(rot) * signo
	var medio := celda + Vector2i(tam.x / 2, tam.y / 2)
	if d.x != 0:
		var x := celda.x + tam.x - 1 if d.x > 0 else celda.x
		return Vector2i(x + (d.x if exterior else 0), medio.y)
	var z := celda.y + tam.y - 1 if d.y > 0 else celda.y
	return Vector2i(medio.x, z + (d.y if exterior else 0))


func receta_actual() -> Dictionary:
	return def.recetas[receta] if receta != "" else {}


func acepta(material: String) -> bool:
	if def.has("acepta"):
		return material in def.acepta
	var r := receta_actual()
	return not r.is_empty() and r.entra.has(material)


func cap_entrada() -> int:
	return def.get("cap_entrada", 0)


func cap_salida() -> int:
	return def.get("cap_salida", 0)


func espacio_para(material: String) -> int:
	if not acepta(material) or not lista():
		return 0
	return max(0, cap_entrada() - int(entrada.get(material, 0)))


## Devuelve las unidades aceptadas, o -1 si este material no se usa aquí.
func aceptar(material: String, cantidad: int) -> int:
	if not acepta(material):
		return -1
	var n: int = min(cantidad, espacio_para(material))
	if n > 0:
		entrada[material] = int(entrada.get(material, 0)) + n
	return n


func total_salida() -> int:
	var s := 0
	for k in salida:
		s += int(salida[k])
	return s


func total_entrada() -> int:
	var s := 0
	for k in entrada:
		s += int(entrada[k])
	return s


func ruido() -> float:
	return def.get("ruido", 0.0)


func humo() -> float:
	return def.get("humo", 0.0)
