class_name Ciudad
extends RefCounted
## Ciudad humana con decisiones por elección discreta (logit anidado, familia GEV).
## Cada hora simulada, una muestra de vecinos de cada distrito elige entre:
##   comprar · ignorar · { quejarse · protestar }   (las dos últimas comparten el nido «política»)
## La utilidad depende del precio, la opinión sobre la empresa y la exposición a humo, ruido y tráfico.
## El jugador no ve las utilidades: ve las quejas en la base de datos y tiene que deducir la causa.

const LAMBDA := 0.6          # disimilitud del nido político (1 = logit multinomial)
const MUESTRA := 24          # vecinos encuestados por distrito y hora

var distritos := {}          # nombre -> {opinion, p: {comprar, ignorar, quejarse, protestar}, humo, ruido}
var precio := Cfg.PRECIO_BASE_CIRCUITO
var bloqueo_horas := 0.0     # horas restantes de bloqueo de carretera
var enfriamiento_bloqueo := 0.0
var ordenanza := false       # silencio nocturno en vigor
var quejas_nocturnas := 0
var rng := RandomNumberGenerator.new()
var ruido_nocturno := 2.5
var umbral_ordenanza := 12


func _init(semilla: int = 3) -> void:
	rng.seed = semilla
	for nombre in Cfg.DISTRITOS:
		distritos[nombre] = {"opinion": 0.6, "p": {"comprar": 0.5, "ignorar": 0.5, "quejarse": 0.0, "protestar": 0.0},
			"humo": 0.0, "ruido": 0.0}


## Exposición de la última hora: humo y ruido medios de la fábrica, segundos de camión en carretera.
## Devuelve una lista de filas de queja {distrito, motivo, intensidad} y eventos {tipo, ...}.
func hora(humo_h: float, ruido_h: float, trafico_h: float, noche: bool) -> Dictionary:
	var quejas: Array[Dictionary] = []
	var eventos: Array[Dictionary] = []
	var suma_comprar := 0.0
	var suma_pob := 0.0
	for nombre in distritos:
		var d: Dictionary = distritos[nombre]
		var cfg: Dictionary = Cfg.DISTRITOS[nombre]
		var e_humo: float = humo_h * cfg.humo * 0.35
		var e_ruido: float = ruido_h * cfg.ruido * 0.12 * (ruido_nocturno if noche else 1.0)
		var e_trafico: float = trafico_h * cfg.trafico * 0.3
		var molestia := e_humo + e_ruido + e_trafico
		d.humo = e_humo
		d.ruido = e_ruido + e_trafico
		var v_comprar: float = 0.6 + 1.2 * d.opinion - 0.04 * (precio - Cfg.PRECIO_BASE_CIRCUITO)
		var v_ignorar := 0.0
		var v_quejarse := -1.6 + 3.0 * molestia
		var v_protestar: float = -3.2 + 3.5 * molestia - 1.5 * (d.opinion - 0.5)
		d.p = probabilidades(v_comprar, v_ignorar, v_quejarse, v_protestar)
		# Muestra de decisiones individuales: cada queja o protesta se registra con su motivo.
		for _k in MUESTRA:
			var r := rng.randf()
			var p: Dictionary = d.p
			if r < p.comprar + p.ignorar:
				continue
			var motivo := _motivo(e_humo, e_ruido, e_trafico, noche)
			var protesta: bool = r >= p.comprar + p.ignorar + p.quejarse
			quejas.append({"distrito": nombre, "motivo": motivo, "intensidad": 2.0 if protesta else 1.0})
			if motivo == "ruido_nocturno":
				quejas_nocturnas += 1
		d.opinion = clamp(d.opinion + 0.05 * (d.p.comprar - 0.45) - 0.08 * d.p.protestar, 0.0, 1.0)
		suma_comprar += d.p.comprar * cfg.poblacion
		suma_pob += cfg.poblacion
	precio = Cfg.PRECIO_BASE_CIRCUITO * (0.7 + 0.6 * suma_comprar / suma_pob)

	bloqueo_horas = max(0.0, bloqueo_horas - 1.0)
	enfriamiento_bloqueo = max(0.0, enfriamiento_bloqueo - 1.0)
	if distritos.Centro.p.protestar > 0.2 and bloqueo_horas <= 0.0 and enfriamiento_bloqueo <= 0.0:
		bloqueo_horas = 2.0
		enfriamiento_bloqueo = 8.0
		eventos.append({"tipo": "bloqueo", "distrito": "Centro"})
	if distritos.Norte.p.protestar > 0.25 and rng.randf() < 0.5:
		eventos.append({"tipo": "sabotaje", "distrito": "Norte"})
	if not ordenanza and quejas_nocturnas >= umbral_ordenanza:
		ordenanza = true
		eventos.append({"tipo": "ordenanza"})
	return {"quejas": quejas, "eventos": eventos}


static func probabilidades(vc: float, vi: float, vq: float, vp: float) -> Dictionary:
	var eq := exp(vq / LAMBDA)
	var ep := exp(vp / LAMBDA)
	var iv := log(eq + ep)                       # valor inclusivo del nido político
	var en := exp(LAMBDA * iv)
	var ec := exp(vc)
	var ei := exp(vi)
	var total := ec + ei + en
	var p_nido := en / total
	return {
		"comprar": ec / total,
		"ignorar": ei / total,
		"quejarse": p_nido * eq / (eq + ep),
		"protestar": p_nido * ep / (eq + ep),
	}


func _motivo(e_humo: float, e_ruido: float, e_trafico: float, noche: bool) -> String:
	var r := rng.randf() * (e_humo + e_ruido + e_trafico + 0.001)
	if r < e_humo:
		return "humo"
	if r < e_humo + e_ruido:
		return "ruido_nocturno" if noche else "ruido"
	return "trafico"


func bloqueada() -> bool:
	return bloqueo_horas > 0.0
