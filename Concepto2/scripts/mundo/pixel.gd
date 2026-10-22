class_name Pixel
extends RefCounted
## Pixel art procedural (portado del Concepto 1): paleta, sprites de naturaleza y caras de robot.
## Densidad común: 16 píxeles por metro. Luz desde arriba a la izquierda.

const PPM := 16

const PAL := {
	"pasto0": Color("2b5f35"), "pasto1": Color("36743d"), "pasto2": Color("4a8c45"), "pasto3": Color("6aa84f"), "pasto4": Color("8fc463"),
	"hoja0": Color("173d29"), "hoja1": Color("245a33"), "hoja2": Color("3a7d3c"), "hoja3": Color("5fa449"), "hoja4": Color("9fd36a"),
	"tronco0": Color("3a281c"), "tronco1": Color("5a3c27"), "tronco2": Color("7a5536"),
	"roca0": Color("3a3e4c"), "roca1": Color("565b6c"), "roca2": Color("7d8396"), "roca3": Color("adb3c4"),
	"cobre0": Color("7c3519"), "cobre1": Color("c25f2a"), "cobre2": Color("ee9550"), "cobre3": Color("ffd7a0"),
	"contorno": Color("10201a"),
	"humo0": Color("7d8896"), "humo1": Color("b3bdc8"), "humo2": Color("e4eaf0"),
	"cian": Color("59f0ff"), "cian_osc": Color("1b6f80"), "ambar": Color("ffb547"), "rojo": Color("ff5a5a"),
}
const HOJAS := ["hoja0", "hoja1", "hoja2", "hoja3", "hoja4"]
const ROCAS := ["roca0", "roca1", "roca2", "roca3"]
const B4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


static func bayer(x: int, y: int) -> float:
	return (B4[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0


static func hash2(ix: int, iy: int, semilla: int = 0) -> float:
	var h := (ix * 374761393 + iy * 668265263 + semilla * 982451653) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	h ^= h >> 16
	return float(h & 0xffffffff) / 4294967296.0


static func ruido(x: float, y: float, semilla: int = 0) -> float:
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - ix
	var fy := y - iy
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := hash2(ix, iy, semilla)
	var b := hash2(ix + 1, iy, semilla)
	var c := hash2(ix, iy + 1, semilla)
	var d := hash2(ix + 1, iy + 1, semilla)
	return lerp(lerp(a, b, sx), lerp(c, d, sx), sy)


static func rampa(nombres: Array, luz: float, x: int, y: int, fuerza: float = 0.7) -> Color:
	var v := luz * nombres.size() + (bayer(x, y) - 0.5) * fuerza
	return PAL[nombres[clampi(int(floor(v)), 0, nombres.size() - 1)]]


class Lienzo:
	var w: int
	var h: int
	var img: Image

	func _init(p_w: int, p_h: int) -> void:
		w = p_w
		h = p_h
		img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))

	func poner(x: int, y: int, c: Color) -> void:
		if x >= 0 and y >= 0 and x < w and y < h:
			img.set_pixel(x, y, c)

	func lleno(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and img.get_pixel(x, y).a > 0.0

	## Contorno exterior de 1 px (vecindad 4), estilo sprite clásico.
	func contorno(c: Color = PAL.contorno) -> Lienzo:
		var marcas: Array[Vector2i] = []
		for y in h:
			for x in w:
				if lleno(x, y):
					continue
				if lleno(x - 1, y) or lleno(x + 1, y) or lleno(x, y - 1) or lleno(x, y + 1):
					marcas.append(Vector2i(x, y))
		for m in marcas:
			img.set_pixel(m.x, m.y, c)
		return self


static func _tronco(L: Lienzo, cx: int, y0: int, y1: int, ancho: int = 3) -> void:
	for y in range(y0, y1 + 1):
		for i in ancho:
			var x := cx - (ancho >> 1) + i
			L.poner(x, y, PAL.tronco2 if i == 0 else (PAL.tronco0 if i == ancho - 1 else PAL.tronco1))
	L.poner(cx - (ancho >> 1) - 1, y1, PAL.tronco1)
	L.poner(cx + (ancho >> 1) + 1, y1, PAL.tronco0)


static func pino(semilla: int) -> Lienzo:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var L := Lienzo.new(24, 48)
	var cx := 12
	_tronco(L, cx, 39, 46, 3)
	for i in 4:
		var y0 := 2 + i * 9
		var y1 := y0 + 13
		var hw_max := 3.0 + i * 2.4 + rng.randf() * 1.2
		for y in range(y0, y1 + 1):
			var t := float(y - y0) / (y1 - y0)
			var hw := int(round(t * hw_max))
			for x in range(cx - hw, cx + hw + 1):
				if y == y1 and (x + i) % 3 == 0:
					continue
				var rx := float(x - cx) / (hw + 1)
				var luz := 0.62 - rx * 0.42 - t * 0.28 + (ruido(x * 0.7, y * 0.7, semilla) - 0.5) * 0.3
				L.poner(x, y, rampa(HOJAS.slice(0, 4), luz, x, y))
	L.poner(cx, 1, PAL.hoja3)
	L.poner(cx, 2, PAL.hoja4)
	return L.contorno()


static func _copa(L: Lienzo, blobs: Array, semilla: int, base: float = 0.55) -> void:
	for y in L.h:
		for x in L.w:
			var mejor := Vector2.INF
			var f := 0.0
			for b in blobs:
				var dx: float = (x + 0.5 - b.x) / b.r
				var dy: float = (y + 0.5 - b.y) / b.r
				var d := dx * dx + dy * dy
				if d < 1.0 and 1.0 - d > f:
					f = 1.0 - d
					mejor = Vector2(dx, dy)
			if mejor == Vector2.INF:
				continue
			var luz := base - mejor.x * 0.32 - mejor.y * 0.4 + f * 0.15 + (ruido(x * 0.9, y * 0.9, semilla) - 0.5) * 0.35
			L.poner(x, y, rampa(HOJAS, luz, x, y))


static func arbol(semilla: int) -> Lienzo:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var L := Lienzo.new(34, 40)
	_tronco(L, 17, 24, 38, 4)
	var blobs := [{"x": 17.0, "y": 14.0, "r": 10.0}]
	for i in 5:
		blobs.append({"x": 9.0 + rng.randf() * 16.0, "y": 8.0 + rng.randf() * 14.0, "r": 5.0 + rng.randf() * 4.0})
	_copa(L, blobs, semilla)
	return L.contorno()


static func arbusto(semilla: int) -> Lienzo:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var L := Lienzo.new(16, 11)
	_copa(L, [{"x": 8.0, "y": 7.0, "r": 5.0}, {"x": 4.0 + rng.randf() * 3.0, "y": 6.5, "r": 3.5},
		{"x": 10.0 + rng.randf() * 2.0, "y": 6.0, "r": 3.8}], semilla, 0.6)
	if rng.randf() < 0.5:
		for i in 3:
			L.poner(3 + rng.randi_range(0, 9), 3 + rng.randi_range(0, 4), Color("e2504c"))
	return L.contorno()


static func pasto(semilla: int) -> Lienzo:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var L := Lienzo.new(9, 7)
	for i in rng.randi_range(3, 5):
		var x0 := rng.randi_range(1, 7)
		var alto := rng.randi_range(3, 6)
		var inclin := -1 if rng.randf() < 0.5 else 1
		for k in alto:
			var x := x0 + (inclin if k > alto * 0.6 else 0)
			L.poner(x, 6 - k, PAL.pasto4 if k > alto - 2 else (PAL.pasto3 if k > 1 else PAL.pasto1))
	return L


static func flores(semilla: int) -> Lienzo:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var L := Lienzo.new(8, 6)
	var col: Color = [Color("e2504c"), Color("f4d35e"), Color("f2efe6"), Color("b48ae0")][rng.randi() % 4]
	for i in 3:
		var x := rng.randi_range(1, 6)
		var y := rng.randi_range(1, 2)
		L.poner(x, y + 1, PAL.pasto2)
		L.poner(x, y + 2, PAL.pasto1)
		L.poner(x, y, col)
	return L


static func _roca_base(L: Lienzo, cx: float, cy: float, rx: float, ry: float, semilla: int) -> void:
	for y in L.h:
		for x in L.w:
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy > 1.0 or y > cy + ry * 0.55:
				continue
			var luz := 0.6 - dx * 0.35 - dy * 0.45 + (ruido(x * 0.8, y * 0.8, semilla) - 0.5) * 0.3
			L.poner(x, y, rampa(ROCAS, luz, x, y))


static func roca(semilla: int) -> Lienzo:
	var L := Lienzo.new(15, 11)
	_roca_base(L, 7.5, 7.0, 7.0, 5.5, semilla)
	return L.contorno()


## Mena de cobre en 4 fases: 3 cristales, 2, 1 y escombro (agotada).
static func cobre(semilla: int) -> Array[Lienzo]:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var cristales := []
	for i in 3:
		cristales.append({"x": 4 + i * 4 + rng.randi_range(0, 1), "y": 6 + rng.randi_range(0, 1), "alto": rng.randi_range(4, 6)})
	var fases: Array[Lienzo] = []
	for f in 4:
		var L := Lienzo.new(19, 15)
		if f < 3:
			_roca_base(L, 9.5, 10.0, 8.0, 5.5, semilla)
		else:
			_roca_base(L, 9.5, 11.5, 5.5, 3.5, semilla)
		for c in cristales.slice(0, 3 - f):
			for k in c.alto:
				var ancho := 1 if k < c.alto - 1 else 0
				for dx in range(-ancho, ancho + 1):
					var col: Color = PAL.cobre3 if dx < 0 else (PAL.cobre1 if dx > 0 else (PAL.cobre3 if k > c.alto - 3 else PAL.cobre2))
					L.poner(c.x + dx, c.y + 2 - k, col)
			L.poner(c.x - 1, c.y + 3, PAL.cobre0)
			L.poner(c.x + 1, c.y + 3, PAL.cobre0)
		fases.append(L.contorno())
	return fases


static func humo(n: int) -> Lienzo:
	var L := Lienzo.new(n * 2 + 2, n * 2 + 2)
	var c := n + 1.0
	for y in L.h:
		for x in L.w:
			var dx := (x + 0.5 - c) / n
			var dy := (y + 0.5 - c) / n
			if dx * dx + dy * dy > 1.0:
				continue
			L.poner(x, y, rampa(["humo0", "humo1", "humo2"], 0.55 - dx * 0.35 - dy * 0.45, x, y, 0.9))
	return L


## Hoja de caras de robot (16x10 cada una). Orden fijo: ver CARAS.
const CARAS := ["reposo", "parpadeo", "mover", "cargado", "minar", "esperando", "error", "dormido"]


static func hoja_caras() -> Image:
	var w := 16
	var h := 10
	var img := Image.create_empty(w * CARAS.size(), h, false, Image.FORMAT_RGBA8)
	img.fill(Color("061015"))
	for i in CARAS.size():
		var ox := i * w
		var nombre: String = CARAS[i]
		var ojo: Color = PAL.cian
		if nombre == "error":
			ojo = PAL.rojo
		elif nombre in ["esperando", "cargado"]:
			ojo = PAL.ambar
		for x in w:  # línea de escaneo
			img.set_pixel(ox + x, 9, PAL.cian_osc)
		match nombre:
			"parpadeo", "dormido":
				for x in [3, 4, 5, 10, 11, 12]:
					img.set_pixel(ox + x, 5, ojo)
				if nombre == "dormido":
					img.set_pixel(ox + 13, 1, PAL.cian_osc)
					img.set_pixel(ox + 14, 1, PAL.cian_osc)
					img.set_pixel(ox + 14, 2, PAL.cian_osc)
					img.set_pixel(ox + 13, 3, PAL.cian_osc)
					img.set_pixel(ox + 14, 3, PAL.cian_osc)
			"error":
				for k in 4:
					for b in [3, 10]:
						img.set_pixel(ox + b + k, 2 + k, ojo)
						img.set_pixel(ox + b + 3 - k, 2 + k, ojo)
			_:
				for b in [3, 10]:
					for y in range(3, 7):
						for x in range(b, b + 3):
							img.set_pixel(ox + x, y, ojo)
					if nombre == "mover":
						img.set_pixel(ox + b + 2, 3, Color.WHITE)
					elif nombre == "minar":
						for x in range(b, b + 3):
							img.set_pixel(ox + x, 3, Color("061015"))
				if nombre in ["cargado", "reposo", "mover"]:
					for x in range(6, 10):
						img.set_pixel(ox + x, 8, ojo)
	return img


## Empaqueta lienzos en un atlas por estantes. Devuelve {imagen, rects: nombre -> Rect2i}.
static func atlas(entradas: Dictionary, tam: int = 512) -> Dictionary:
	var img := Image.create_empty(tam, tam, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var nombres := entradas.keys()
	nombres.sort_custom(func(a, b): return entradas[a].h > entradas[b].h)
	var x := 1
	var y := 1
	var alto_fila := 0
	var rects := {}
	for n in nombres:
		var L: Lienzo = entradas[n]
		if x + L.w + 2 > tam:
			x = 1
			y += alto_fila + 2
			alto_fila = 0
		assert(y + L.h + 1 <= tam, "Atlas lleno")
		img.blit_rect(L.img, Rect2i(0, 0, L.w, L.h), Vector2i(x, y))
		rects[n] = Rect2i(x, y, L.w, L.h)
		x += L.w + 2
		alto_fila = max(alto_fila, L.h)
	return {"imagen": img, "rects": rects}
