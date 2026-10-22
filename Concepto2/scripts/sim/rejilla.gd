class_name Rejilla
extends RefCounted
## Mapa lógico a 1 casilla por metro: terreno, obstáculos, menas, flora y búsqueda de rutas.
## Solo datos: la presentación lee de aquí para dibujar, nunca al revés.

enum { PASTO, AGUA, ARENA, LOSA, CARRETERA, CIUDAD, PUENTE }

var ancho: int
var alto: int
var tipo := PackedByteArray()
var humedad := PackedFloat32Array()
var agua := PackedFloat32Array()      # campo continuo para dibujar orillas orgánicas
var fijo := PackedByteArray()         # 1 = bloqueado por el mundo (agua, árbol, mena, ciudad)
var ocupante := {}                    # Vector2i -> id de máquina
var flora: Array[Dictionary] = []     # {pos: Vector2, clase: String, semilla: int, bloquea: bool}
var menas: Array[Dictionary] = []     # {id, celda: Vector2i, cantidad, max}
var astar := AStarGrid2D.new()
var puente_x := Vector2(INF, -INF)     # tramo de la carretera de venta que cruza el agua


func _init(semilla: int = 7) -> void:
	ancho = Cfg.MAPA.x
	alto = Cfg.MAPA.y
	var n := ancho * alto
	tipo.resize(n)
	humedad.resize(n)
	agua.resize(n)
	fijo.resize(n)
	_generar(semilla)
	astar.region = Rect2i(0, 0, ancho, alto)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for z in alto:
		for x in ancho:
			if fijo[z * ancho + x]:
				astar.set_point_solid(Vector2i(x, z), true)


func idx(c: Vector2i) -> int:
	return c.y * ancho + c.x


func dentro(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < ancho and c.y < alto


func tipo_en(c: Vector2i) -> int:
	return tipo[idx(c)] if dentro(c) else AGUA


func libre(c: Vector2i) -> bool:
	return dentro(c) and not fijo[idx(c)] and not ocupante.has(c)


func en_parcela(c: Vector2i) -> bool:
	return Cfg.PARCELA.has_point(c)


func ocupar(celdas: Array, id: String) -> void:
	for c in celdas:
		ocupante[c] = id
		astar.set_point_solid(c, true)


func liberar(celdas: Array) -> void:
	for c in celdas:
		ocupante.erase(c)
		astar.set_point_solid(c, fijo[idx(c)] == 1)


func ruta(desde: Vector2i, hasta: Vector2i) -> PackedVector2Array:
	if not dentro(desde) or not dentro(hasta):
		return PackedVector2Array()
	# Si el robot quedó sobre una casilla bloqueada (p. ej. se construyó encima), sale por la más cercana.
	var origen := desde if not astar.is_point_solid(desde) else casilla_libre_cerca(desde)
	if astar.is_point_solid(hasta):
		return PackedVector2Array()
	return astar.get_point_path(origen, hasta)


func casilla_libre_cerca(c: Vector2i, radio: int = 6) -> Vector2i:
	for r in range(1, radio + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(abs(dx), abs(dz)) != r:
					continue
				var q := c + Vector2i(dx, dz)
				if dentro(q) and not astar.is_point_solid(q):
					return q
	return c


## Casilla libre alrededor de un rectángulo, la más cercana a `cerca`.
func borde_libre(rect: Rect2i, cerca: Vector2) -> Vector2i:
	var mejor := Vector2i(-1, -1)
	var dmin := INF
	for z in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			var c := Vector2i(x, z)
			if rect.has_point(c) or not dentro(c) or astar.is_point_solid(c):
				continue
			var d := Vector2(c).distance_squared_to(cerca)
			if d < dmin:
				dmin = d
				mejor = c
	return mejor


func mena_en(c: Vector2i) -> Dictionary:
	for m in menas:
		if m.celda == c:
			return m
	return {}


# ----------------------------------------------------------------- generación

func _generar(semilla: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var hum := FastNoiseLite.new()
	hum.seed = semilla
	hum.frequency = 0.03
	hum.fractal_octaves = 4
	var meandro := FastNoiseLite.new()
	meandro.seed = semilla + 11
	meandro.frequency = 0.02

	for z in alto:
		var rio_x := 104.0 + 5.0 * sin(z * 0.06) + 6.0 * meandro.get_noise_1d(z)
		for x in ancho:
			var i := z * ancho + x
			var h := hum.get_noise_2d(x, z) * 0.5 + 0.5
			humedad[i] = h
			var d_rio: float = abs(x - rio_x)
			var d_lago := Vector2(x, z).distance_to(Vector2(58, 14)) - (8.0 + 3.0 * hum.get_noise_2d(x * 3.0, z * 3.0))
			var d_agua: float = min(d_rio - 2.4, d_lago)
			agua[i] = clamp(0.5 - d_agua / 3.0, 0.0, 1.0)
			if d_agua < 0.0:
				tipo[i] = AGUA
				fijo[i] = 1
			elif d_agua < 1.6:
				tipo[i] = ARENA
			else:
				tipo[i] = PASTO

	var parcela := Cfg.PARCELA
	_marcar_rect(parcela, LOSA)
	for c in _celdas_polilinea(Cfg.RUTA_PROVEEDOR, 1):
		_marcar(c, CARRETERA)
	for c in _celdas_polilinea(Cfg.RUTA_VENTA, 1):
		var sobre_agua := tipo_en(c) in [AGUA, ARENA]
		_marcar(c, PUENTE if sobre_agua else CARRETERA)
		if sobre_agua:
			puente_x.x = min(puente_x.x, c.x)
			puente_x.y = max(puente_x.y, c.x + 1)
	_marcar_rect(Cfg.CIUDAD, CIUDAD)
	for z in range(Cfg.CIUDAD.position.y, Cfg.CIUDAD.end.y):
		for x in range(Cfg.CIUDAD.position.x, Cfg.CIUDAD.end.x):
			fijo[z * ancho + x] = 1

	_colocar_menas(rng)
	_colocar_flora(rng)


func _marcar(c: Vector2i, t: int) -> void:
	if not dentro(c):
		return
	var i := idx(c)
	tipo[i] = t
	fijo[i] = 0
	agua[i] = 0.0 if t != PUENTE else agua[i]


func _marcar_rect(r: Rect2i, t: int) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_marcar(Vector2i(x, z), t)


func _celdas_polilinea(puntos: Array, medio_ancho: int) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for k in puntos.size() - 1:
		var a: Vector2 = puntos[k]
		var b: Vector2 = puntos[k + 1]
		var pasos := int(ceil(a.distance_to(b) * 2.0))
		for s in pasos + 1:
			var p := a.lerp(b, float(s) / max(pasos, 1))
			for dz in range(-medio_ancho - 1, medio_ancho + 1):
				for dx in range(-medio_ancho - 1, medio_ancho + 1):
					var c := Vector2i(floor(p.x) + dx, floor(p.y) + dz)
					if Vector2(c).distance_to(p - Vector2(0.5, 0.5)) <= medio_ancho + 0.6 and not res.has(c):
						res.append(c)
	return res


func _zona_reservada(c: Vector2i, margen: int) -> bool:
	var t := tipo_en(c)
	if t in [AGUA, LOSA, CARRETERA, CIUDAD, PUENTE]:
		return true
	if Cfg.PARCELA.grow(margen).has_point(c) or Cfg.CIUDAD.grow(margen).has_point(c):
		return true
	for dz in range(-margen, margen + 1):
		for dx in range(-margen, margen + 1):
			if tipo_en(c + Vector2i(dx, dz)) in [CARRETERA, PUENTE]:
				return true
	return false


func _colocar_menas(rng: RandomNumberGenerator) -> void:
	var centros := [Vector2i(84, 50), Vector2i(86, 96), Vector2i(122, 38), Vector2i(126, 90), Vector2i(36, 104), Vector2i(76, 22)]
	var n := 1
	for cen in centros:
		var colocadas := 0
		var intentos := 0
		while colocadas < 6 and intentos < 60:
			intentos += 1
			var c: Vector2i = cen + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
			if _zona_reservada(c, 1) or fijo[idx(c)] or tipo_en(c) == ARENA:
				continue
			var cant := rng.randi_range(10, 16)
			menas.append({"id": "MENA-%02d" % n, "celda": c, "cantidad": cant, "max": cant})
			fijo[idx(c)] = 1
			n += 1
			colocadas += 1


func _colocar_flora(rng: RandomNumberGenerator) -> void:
	for z in alto:
		for x in ancho:
			var c := Vector2i(x, z)
			var i := idx(c)
			if fijo[i] or _zona_reservada(c, 2):
				continue
			var h := humedad[i]
			var tierra_seca := tipo[i] == ARENA
			var p_arbol: float = clamp((h - 0.52) * 0.9, 0.0, 0.3)
			# Cerca de las menas el bosque se abre (claros visibles desde lejos).
			for m in menas:
				if Vector2(m.celda).distance_to(Vector2(c)) < 4.0:
					p_arbol = 0.0
			var r := rng.randf()
			var pos := Vector2(x + 0.5 + rng.randf_range(-0.25, 0.25), z + 0.5 + rng.randf_range(-0.25, 0.25))
			if not tierra_seca and r < p_arbol:
				var clase := "pino" if h > 0.62 or rng.randf() < 0.35 else "arbol"
				flora.append({"pos": pos, "clase": clase, "semilla": rng.randi(), "bloquea": true})
				fijo[i] = 1
			elif r < p_arbol + 0.035:
				flora.append({"pos": pos, "clase": "arbusto", "semilla": rng.randi(), "bloquea": false})
			elif r < p_arbol + 0.035 + 0.08:
				flora.append({"pos": pos, "clase": "flores" if rng.randf() < 0.25 else "pasto", "semilla": rng.randi(), "bloquea": false})
			elif tierra_seca and r < 0.05:
				flora.append({"pos": pos, "clase": "roca", "semilla": rng.randi(), "bloquea": false})
