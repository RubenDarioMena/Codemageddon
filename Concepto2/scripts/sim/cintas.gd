class_name Cintas
extends RefCounted
## Cintas transportadoras en rejilla. Cada casilla tiene una dirección y una cola de objetos
## ordenada del más avanzado (s cercano a 1) al menos avanzado (s cercano a 0).

var celdas := {}   # Vector2i -> {dir: int, items: Array[Dictionary], obra: float, atasco: bool}
var velocidad := Cfg.CINTA_VEL  # instancia: las devtools no modifican Cfg


func poner(c: Vector2i, dir: int, obra: float) -> void:
	celdas[c] = {"dir": posmod(dir, 4), "items": [], "obra": obra, "atasco": false}


func quitar(c: Vector2i) -> Array:
	var items: Array = celdas[c].items if celdas.has(c) else []
	celdas.erase(c)
	return items


func lista(c: Vector2i) -> bool:
	return celdas.has(c) and celdas[c].obra <= 0.0


## ¿Puede entrar un objeto nuevo por el inicio de la casilla?
func admite(c: Vector2i) -> bool:
	if not lista(c):
		return false
	var items: Array = celdas[c].items
	return items.is_empty() or items.back().s >= Cfg.CINTA_HUECO


func meter(c: Vector2i, material: String, s: float = 0.0) -> void:
	celdas[c].items.append({"mat": material, "s": s, "ps": s})


## Avanza los objetos. `entregar(celda_destino, material) -> int` decide si una máquina lo recibe:
## 1 = recibido, 0 = lleno (espera), -1 = no lo acepta (espera, atasco).
func paso(dt: float, entregar: Callable) -> void:
	var avance := velocidad * dt
	for c in celdas:
		var b: Dictionary = celdas[c]
		if b.obra > 0.0:
			b.obra -= dt
			continue
		var items: Array = b.items
		for k in items.size():
			var it: Dictionary = items[k]
			it.ps = it.s
			var limite: float = 1.0 if k == 0 else items[k - 1].s - Cfg.CINTA_HUECO
			it.s = max(it.s, min(it.s + avance, limite))
		b.atasco = false
		if items.is_empty() or items[0].s < 1.0:
			continue
		var frente: Dictionary = items[0]
		var destino: Vector2i = c + Cfg.dir_vec(b.dir)
		if celdas.has(destino):
			var nb: Dictionary = celdas[destino]
			# No se entrega a una cinta que apunta de vuelta (evita ciclos de dos casillas).
			if nb.dir != posmod(b.dir + 2, 4) and admite(destino):
				items.pop_front()
				nb.items.append({"mat": frente.mat, "s": 0.0, "ps": -0.05})
			else:
				b.atasco = true
			continue
		var r: int = entregar.call(destino, frente.mat)
		if r == 1:
			items.pop_front()
		else:
			b.atasco = true


## Posición en el mundo (x, z) de un objeto, interpolada entre pasos.
static func posicion(c: Vector2i, dir: int, s: float) -> Vector2:
	var d := Vector2(Cfg.dir_vec(dir))
	return Vector2(c) + Vector2(0.5, 0.5) + d * (s - 0.5)
