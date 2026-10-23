class_name Simulacion
extends RefCounted
## Simulación a reloj fijo (Cfg.HZ). Solo datos: no conoce nodos ni cómo se dibuja nada.
## Publica tres colas que la presentación y la base de datos vacían:
##   registro  — eventos para la tabla `eventos` (origen, tipo, material, cantidad, detalle, monto)
##   quejas    — filas para la tabla `quejas`
##   avisos    — mensajes para el jugador
## Las órdenes del jugador y las rutinas usan las mismas reglas físicas (GDD §5).

var t := 0.0
var n_paso := 0
var diario: Array[Dictionary] = []
var dinero := float(Cfg.PRESUPUESTO)
var rejilla: Rejilla
var maquinas := {}                  # id -> Maquina
var robots: Array[Robot] = []
var cintas := Cintas.new()
var suelo := {}                     # Vector2i -> {mat, cant}
var camiones: Array[Dictionary] = []
var pedidos: Array[Dictionary] = [] # {material, unidades, espera}
var ciudad := Ciudad.new()
var registro: Array[Dictionary] = []
var quejas: Array[Dictionary] = []
var avisos: Array[Dictionary] = []
var auditorias: Array[Dictionary] = []   # consultas SQL que la ciudad quiere ejecutar sobre tu registro
var resultados: Array[Dictionary] = []   # órdenes de programas JS terminadas: {robot, ticket, resultado}
var hitos := {}                     # logros de la partida para los objetivos guiados
var contadores := {}                # prefijo -> último número usado
var sig_robot := 1
var sig_camion := 1
var historial: Array[Dictionary] = []    # construcciones deshacibles
var _acum := {"humo": 0.0, "ruido": 0.0, "trafico": 0.0}
var _hora_previa := -1
var _estado_previo := {}
var _ultimo_aviso := {}


func _init() -> void:
	rejilla = Rejilla.new(7)
	_instalacion_inicial()


func aplicar(cmd: Dictionary) -> String:
	diario.append({"paso": n_paso, "cmd": cmd.duplicate(true)})
	var r: Robot
	match str(cmd.get("tipo", "")):
		"comprar":
			return _comprar(str(cmd.material))
		"construir":
			return _construir(str(cmd.maquina), cmd.celda, int(cmd.rot))
		"construir_cintas":
			return _construir_cintas(cmd.tramo)
		"demoler":
			_demoler(str(cmd.id))
		"quitar_cinta":
			_quitar_cinta(cmd.celda)
		"deshacer":
			return _deshacer()
		"enviar_camion":
			return _enviar_camion()
		"ordenar":
			var rs := []
			for id in cmd.robots:
				r = robot(int(id))
				if r != null:
					rs.append(r)
			_ordenar(rs, cmd.orden, bool(cmd.encolar))
		"limpiar_ordenes":
			r = robot(int(cmd.robot))
			if r != null:
				_limpiar_ordenes(r)
		"set_repetir":
			r = robot(int(cmd.robot))
			if r == null:
				return "Robot inexistente"
			return _set_repetir(r, bool(cmd.valor))
		"set_auto":
			r = robot(int(cmd.robot))
			if r != null:
				_set_auto(r, bool(cmd.valor))
		"orden_programa":
			r = robot(int(cmd.robot))
			if r != null:
				_orden_programa(r, cmd.datos, int(cmd.ticket))
		"resultado_auditoria":
			_resultado_auditoria(cmd.filas)
		"set_maquina":
			var m: Maquina = maquinas.get(str(cmd.id))
			if m == null:
				return "Máquina inexistente"
			match str(cmd.campo):
				"pausada":
					m.pausada = bool(cmd.valor)
				"turno_diurno":
					m.turno_diurno = bool(cmd.valor)
				"receta":
					m.receta = str(cmd.valor)
				"salida_cinta":
					m.salida_cinta = str(cmd.valor)
				"envio_auto":
					m.envio_auto = bool(cmd.valor)
				_:
					return "Campo de máquina no permitido"
		"iniciar_programa", "detener_programa", "fin_programa":
			r = robot(int(cmd.robot))
			if r == null:
				return "Robot inexistente"
			match str(cmd.tipo):
				"iniciar_programa":
					r.ejecucion += 1
					r.ejecutando = true
					r.linea = 0
					r.linea_error = 0
					r.auto = false
					r.repetir = false
					r.ordenes.clear()
					r.pc = 0
				"detener_programa":
					r.ejecutando = false
					r.ejecucion += 1
					r.ordenes.clear()
					r.pc = 0
				"fin_programa":
					r.ejecutando = false
					r.ordenes.clear()
					r.pc = 0
		"perdida_servicio":
			for x in robots:
				if x.ejecutando:
					x.ejecutando = false
		_:
			return "Comando desconocido: %s" % str(cmd.get("tipo", ""))
	return ""


static func reproducir(entradas: Array, pasos: int) -> Simulacion:
	var s := Simulacion.new()
	var indice := 0
	for k in pasos:
		while indice < entradas.size() and int(entradas[indice].paso) == k:
			s.aplicar(entradas[indice].cmd)
			indice += 1
		s.paso()
	return s


func huella() -> String:
	return var_to_str(huella_detalle()).md5_text()


func huella_detalle() -> Dictionary:
	var ms := {}
	for id in maquinas:
		var m: Maquina = maquinas[id]
		ms[id] = {"id": m.id, "tipo": m.tipo, "celda": m.celda, "rot": m.rot,
			"entrada": m.entrada.duplicate(true), "salida": m.salida.duplicate(true), "receta": m.receta,
			"progreso": m.progreso, "trabajando": m.trabajando, "estado": m.estado, "obra": m.obra,
			"turno_diurno": m.turno_diurno, "pausada": m.pausada, "averiada": m.averiada,
			"producidos": m.producidos, "salida_cinta": m.salida_cinta, "envio_auto": m.envio_auto}
	var rs := []
	for r in robots:
		rs.append({"id": r.id, "nivel": r.nivel, "pos": r.pos, "rumbo": r.rumbo, "carga": r.carga,
			"cant": r.cant, "ordenes": r.ordenes.duplicate(true), "pc": r.pc, "repetir": r.repetir,
			"auto": r.auto, "auto_fase": r.auto_fase, "auto_obj": r.auto_obj.duplicate(true),
			"estado": r.estado, "camino": r.camino, "paso": r.paso, "meta": r.meta,
			"timer": r.timer, "atasco": r.atasco, "distancia": r.distancia,
			"ejecutando": r.ejecutando, "ejecucion": r.ejecucion, "resultado": r.resultado})
	var mn := []
	for mena_dato in rejilla.menas:
		mn.append({"id": mena_dato.id, "celda": mena_dato.celda, "cantidad": mena_dato.cantidad, "max": mena_dato.max})
	return {"t": t, "n_paso": n_paso, "dinero": dinero, "maquinas": ms, "robots": rs,
		"cintas": cintas.celdas.duplicate(true), "suelo": suelo.duplicate(true), "camiones": camiones.duplicate(true),
		"pedidos": pedidos.duplicate(true), "menas": mn, "ciudad": ciudad.distritos.duplicate(true),
		"precio": ciudad.precio, "ordenanza": ciudad.ordenanza, "bloqueo_horas": ciudad.bloqueo_horas,
		"enfriamiento_bloqueo": ciudad.enfriamiento_bloqueo, "quejas_nocturnas": ciudad.quejas_nocturnas,
		"rng": ciudad.rng.state, "historial": historial.duplicate(true), "contadores": contadores.duplicate(true),
		"sig_robot": sig_robot, "sig_camion": sig_camion, "acum": _acum.duplicate(true)}


# ================================================================ preparación

func _instalacion_inicial() -> void:
	var rec := _crear_maquina("recepcion", Vector2i(17, 60), 0, true)
	rec.salida = {"cobre": 10, "silicio": 6}
	_crear_maquina("fundidora", Vector2i(26, 60), 0, true)
	_crear_maquina("ensambladora", Vector2i(34, 60), 0, true)
	_crear_maquina("despacho", Vector2i(66, 60), 0, true)
	for x in range(29, 34):
		cintas.poner(Vector2i(x, 61), 0, 0.0)
	_nuevo_robot(0, Vector2(22.5, 65.5))
	_nuevo_robot(0, Vector2(23.5, 65.5))
	_nuevo_robot(1, Vector2(22.5, 67.5))   # un Operario con chip para empezar a programar
	log_evento("EMPRESA", "inicio", "", 0, "Instalación inicial", dinero)


func _crear_maquina(tipo: String, celda: Vector2i, rot: int, instantanea := false) -> Maquina:
	var pref: String = Cfg.MAQUINAS[tipo].prefijo
	contadores[pref] = int(contadores.get(pref, 0)) + 1
	var m := Maquina.new("%s-%02d" % [pref, contadores[pref]], tipo, celda, rot)
	m.obra = 0.0 if instantanea else Cfg.T_CONSTRUIR
	m.estado = "inactiva" if instantanea else "construyendo"
	maquinas[m.id] = m
	rejilla.ocupar(m.celdas(), m.id)
	return m


func _nuevo_robot(nivel: int, pos: Vector2) -> Robot:
	var r := Robot.new(sig_robot, nivel, pos)
	sig_robot += 1
	robots.append(r)
	log_evento(r.nombre(), "alta", "", 0, r.def.nombre)
	return r


# ================================================================ consultas para la interfaz

func hora() -> float:
	return Cfg.hora_de(t)


func dia() -> int:
	return Cfg.dia_de(t)


func maquina_en(c: Vector2i) -> Maquina:
	var id: String = rejilla.ocupante.get(c, "")
	return maquinas.get(id) if id != "" else null


func robot(id: int) -> Robot:
	for r in robots:
		if r.id == id:
			return r
	return null


func capacidad_registro() -> int:
	var n := Cfg.FILAS_BASE
	for m in maquinas.values():
		if m.tipo == "servidor" and m.lista():
			n += Cfg.MAQUINAS.servidor.filas
	return n


func camion_venta_libre() -> bool:
	for c in camiones:
		if c.tipo == "venta":
			return false
	return true


# ================================================================ acciones del jugador

func comprar(material: String) -> String:
	return aplicar({"tipo": "comprar", "material": material})

func _comprar(material: String) -> String:
	var p: Dictionary = Cfg.PEDIDOS[material]
	if dinero < p.precio:
		return "No alcanza el presupuesto (₵ %d)." % p.precio
	dinero -= p.precio
	pedidos.append({"material": material, "unidades": p.unidades, "espera": Cfg.PLAZO_PEDIDO})
	log_evento("PROVEEDOR", "compra", material, p.unidades, "pedido", -p.precio)
	return ""


func validar(tipo: String, celda: Vector2i, rot: int) -> String:
	var def: Dictionary = Cfg.MAQUINAS[tipo]
	if dinero < def.costo:
		return "Falta presupuesto"
	var tam := Cfg.tam_rotado(def.tam, rot)
	for z in tam.y:
		for x in tam.x:
			var c := celda + Vector2i(x, z)
			if not rejilla.en_parcela(c):
				return "Fuera de tu terreno"
			if not rejilla.libre(c) or cintas.celdas.has(c):
				return "Ocupado"
	return ""


func construir(tipo: String, celda: Vector2i, rot: int) -> String:
	return aplicar({"tipo": "construir", "maquina": tipo, "celda": celda, "rot": rot})

func _construir(tipo: String, celda: Vector2i, rot: int) -> String:
	var err := validar(tipo, celda, rot)
	if err != "":
		return err
	var def: Dictionary = Cfg.MAQUINAS[tipo]
	dinero -= def.costo
	var m := _crear_maquina(tipo, celda, rot)
	historial.append({"tipo": "maquina", "id": m.id, "costo": def.costo})
	log_evento(m.id, "construccion", "", 0, def.nombre, -def.costo)
	_desatascar_robots(m.celdas())
	return ""


func validar_cinta(c: Vector2i) -> String:
	if not rejilla.en_parcela(c):
		return "Fuera de tu terreno"
	if not rejilla.libre(c):
		return "Ocupado"
	return ""


## tramo: Array de [Vector2i, dir]. Las casillas que ya son cinta cambian de dirección gratis.
func construir_cintas(tramo: Array) -> String:
	return aplicar({"tipo": "construir_cintas", "tramo": tramo})

func _construir_cintas(tramo: Array) -> String:
	var nuevas := 0
	for p in tramo:
		if validar_cinta(p[0]) != "":
			return validar_cinta(p[0])
		if not cintas.celdas.has(p[0]):
			nuevas += 1
	var costo := nuevas * Cfg.CINTA_COSTO
	if dinero < costo:
		return "Falta presupuesto (₵ %d)" % costo
	dinero -= costo
	var celdas: Array = []
	for k in tramo.size():
		var c: Vector2i = tramo[k][0]
		if cintas.celdas.has(c):
			cintas.celdas[c].dir = tramo[k][1]
		else:
			cintas.poner(c, tramo[k][1], Cfg.T_CONSTRUIR_CINTA * (k + 1))
			celdas.append(c)
	if nuevas > 0:
		historial.append({"tipo": "cintas", "celdas": celdas, "costo": costo})
		log_evento("CINTAS", "construccion", "", nuevas, "%d casillas" % nuevas, -costo)
	return ""


func demoler(id: String) -> void:
	aplicar({"tipo": "demoler", "id": id})

func _demoler(id: String) -> void:
	var m: Maquina = maquinas.get(id)
	if m == null or m.tipo == "recepcion":
		return
	var reembolso := int(m.def.costo * (1.0 if not m.lista() else 0.5))
	dinero += reembolso
	rejilla.liberar(m.celdas())
	maquinas.erase(id)
	for mat in m.entrada:
		_derramar(m.centro(), mat, m.entrada[mat], id)
	for mat in m.salida:
		_derramar(m.centro(), mat, m.salida[mat], id)
	log_evento(id, "demolicion", "", 0, "", reembolso)


func quitar_cinta(c: Vector2i) -> void:
	aplicar({"tipo": "quitar_cinta", "celda": c})

func _quitar_cinta(c: Vector2i) -> void:
	if not cintas.celdas.has(c):
		return
	for it in cintas.quitar(c):
		_derramar(Vector2(c) + Vector2(0.5, 0.5), it.mat, 1, "CINTAS")
	dinero += Cfg.CINTA_COSTO * 0.5


## Ctrl+Z: deshace la última obra mientras siga en construcción (reembolso completo).
func deshacer() -> String:
	return aplicar({"tipo": "deshacer"})

func _deshacer() -> String:
	if historial.is_empty():
		return "Nada que deshacer"
	var h: Dictionary = historial.back()
	if h.tipo == "maquina":
		var m: Maquina = maquinas.get(h.id)
		if m == null or m.lista():
			historial.pop_back()
			return "La obra ya terminó: usa Supr para demoler"
		rejilla.liberar(m.celdas())
		maquinas.erase(h.id)
	else:
		for c in h.celdas:
			cintas.quitar(c)
	historial.pop_back()
	dinero += h.costo
	log_evento("EMPRESA", "deshacer", "", 0, h.get("id", "cintas"), h.costo)
	return ""


func enviar_camion() -> String:
	return aplicar({"tipo": "enviar_camion"})

func _enviar_camion() -> String:
	var des: Maquina = _primera("despacho")
	if des == null:
		return "No hay despacho"
	if not camion_venta_libre():
		return "El camión de venta está en ruta"
	if des.total_entrada() == 0:
		return "El despacho está vacío"
	var carga := {}
	var cupo := 20
	for mat in ["circuito", "lingote"]:
		var n: int = min(cupo, int(des.entrada.get(mat, 0)))
		if n > 0:
			carga[mat] = n
			des.entrada[mat] -= n
			cupo -= n
	var cam := _nuevo_camion("venta", Cfg.RUTA_VENTA)
	cam.carga = carga
	log_evento(cam.id, "carga", "", 20 - cupo, des.id)
	return ""


## Da una orden a varios robots. `encolar` = Shift (AoE2: añade al final de la lista).
func ordenar(lista: Array, orden: Dictionary, encolar: bool) -> void:
	var ids := []
	for r in lista: ids.append(r.id)
	aplicar({"tipo": "ordenar", "robots": ids, "orden": orden, "encolar": encolar})

func _ordenar(lista: Array, orden: Dictionary, encolar: bool) -> void:
	for r: Robot in lista:
		if orden.tipo == "minar" and not r.def.minar:
			aviso("%s no tiene pala: solo un explorador T2 puede minar." % r.etiqueta(), "error")
			continue
		var o := orden.duplicate()
		o.fase = ""
		if not encolar or r.pc >= r.ordenes.size():
			if not encolar:
				r.ordenes.clear()
			r.pc = r.ordenes.size()
			if r.auto:
				r.auto = false
		r.ordenes.append(o)
		r.camino = PackedVector2Array()


func limpiar_ordenes(r: Robot) -> void:
	aplicar({"tipo": "limpiar_ordenes", "robot": r.id})

func _limpiar_ordenes(r: Robot) -> void:
	r.ordenes.clear()
	r.pc = 0
	r.camino = PackedVector2Array()
	r.estado = "ocioso"


func set_repetir(r: Robot, v: bool) -> String:
	return aplicar({"tipo": "set_repetir", "robot": r.id, "valor": v})

func _set_repetir(r: Robot, v: bool) -> String:
	if v and not r.def.bucle:
		return "La %s no tiene chip: no puede repetir. Fabrica un Operario T1." % r.def.nombre
	r.repetir = v
	if v and r.pc >= r.ordenes.size():
		r.pc = 0
	return ""


func set_auto(r: Robot, v: bool) -> void:
	aplicar({"tipo": "set_auto", "robot": r.id, "valor": v})

func _set_auto(r: Robot, v: bool) -> void:
	if not r.def.auto:
		return
	r.auto = v
	r.auto_fase = "buscar"
	if v:
		r.ordenes.clear()
		r.pc = 0


# ================================================================ programas JS

## Una orden que viene de un programa: sustituye la lista del robot y lleva un ticket que se
## devuelve con su resultado cuando la acción termina (así `await` espera el tiempo simulado).
func orden_programa(r: Robot, datos: Dictionary, ticket: int) -> void:
	aplicar({"tipo": "orden_programa", "robot": r.id, "datos": datos, "ticket": ticket})

func _orden_programa(r: Robot, datos: Dictionary, ticket: int) -> void:
	var o := {"tipo": str(datos.get("tipo", "")), "fase": "", "ticket": ticket}
	match o.tipo:
		"mover":
			var c := Vector2i(int(datos.get("x", 0)), int(datos.get("z", 0)))
			o.celda = c if rejilla.libre(c) else rejilla.casilla_libre_cerca(c)
		"recoger", "entregar", "reparar", "minar":
			o.objetivo = str(datos.get("objetivo", ""))
			if datos.get("material", "") != "":
				o.material = str(datos.material)
		"esperar":
			o.seg = float(datos.get("seg", 1.0))
		_:
			resultados.append({"robot": r.id, "ticket": ticket, "resultado": "orden_desconocida"})
			return
	if o.tipo == "minar" and not r.def.minar:
		resultados.append({"robot": r.id, "ticket": ticket, "resultado": "sin_pala"})
		return
	r.ordenes = [o]
	r.pc = 0
	r.repetir = false
	r.auto = false
	r.resultado = "ok"
	hitos.programa = true
	r.camino = PackedVector2Array()


## Foto del mundo para los programas (sensores y red de planta). Solo datos simples.
func instantanea() -> Dictionary:
	var rs := {}
	for r in robots:
		rs[str(r.id)] = {"nivel": r.nivel, "x": snappedf(r.pos.x, 0.01), "z": snappedf(r.pos.y, 0.01),
			"carga": r.carga if r.cant > 0 else null, "cantidad": r.cant, "capacidad": r.cap(), "estado": r.estado}
	var ms := {}
	for m: Maquina in maquinas.values():
		var acepta: Array = m.def.get("acepta", [])
		if acepta.is_empty() and m.def.has("recetas"):
			acepta = m.receta_actual().entra.keys()
		ms[m.id] = {"tipo": m.tipo, "estado": m.estado, "x": m.centro().x, "z": m.centro().y,
			"entrada": m.entrada.duplicate(), "salida": m.salida.duplicate(), "cap_entrada": m.cap_entrada(), "acepta": acepta}
	var mn := []
	for m in rejilla.menas:
		mn.append({"id": m.id, "x": m.celda.x + 0.5, "z": m.celda.y + 0.5, "cantidad": m.cantidad})
	return {"t": snappedf(t, 0.01), "hora": snappedf(hora(), 0.01), "dia": dia(), "robots": rs, "maquinas": ms, "menas": mn}


# ================================================================ paso

func paso() -> void:
	n_paso += 1
	var dt := 1.0 / Cfg.HZ
	t += dt
	for m: Maquina in maquinas.values():
		_paso_maquina(m, dt)
	cintas.paso(dt, _entregar_desde_cinta)
	for r in robots:
		_paso_robot(r, dt)
	_separar()
	_paso_pedidos(dt)
	for c in camiones.duplicate():
		_paso_camion(c, dt)
	var h := int(hora())
	if h != _hora_previa:
		if _hora_previa != -1:
			_paso_ciudad()
		_hora_previa = h


func _paso_maquina(m: Maquina, dt: float) -> void:
	if m.obra > 0.0:
		m.obra -= dt
		if m.obra <= 0.0:
			m.estado = "inactiva"
			log_evento(m.id, "lista", "", 0, m.def.nombre)
			aviso("%s terminada." % m.id, "info")
		return
	var nuevo := m.estado
	if m.averiada:
		nuevo = "averiada"
	elif m.pausada:
		nuevo = "pausada"
	elif m.turno_diurno and Cfg.es_noche(t):
		nuevo = "turno"
	elif m.def.has("recetas"):
		nuevo = _producir(m, dt)
	else:
		nuevo = "inactiva"
		if m.tipo == "despacho" and m.envio_auto and m.total_entrada() >= 10 and camion_venta_libre() and _primera("despacho") == m:
			_enviar_camion()
	if nuevo == "trabajando":
		_acum.humo += m.humo() * dt
		_acum.ruido += m.ruido() * dt
	if nuevo != m.estado:
		m.estado = nuevo
		if nuevo in ["sin_insumo", "salida_llena", "pausada", "turno", "averiada", "trabajando"]:
			log_evento(m.id, "estado", "", 0, nuevo)
	_empujar_a_cinta(m)


func _producir(m: Maquina, dt: float) -> String:
	var rec := m.receta_actual()
	if not m.trabajando:
		for mat in rec.entra:
			if int(m.entrada.get(mat, 0)) < rec.entra[mat]:
				return "sin_insumo"
		if rec.has("sale"):
			for mat in rec.sale:
				if int(m.salida.get(mat, 0)) + rec.sale[mat] > m.cap_salida():
					return "salida_llena"
		for mat in rec.entra:
			m.entrada[mat] -= rec.entra[mat]
		m.trabajando = true
		m.progreso = 0.0
	m.progreso += dt / rec.t
	if m.progreso < 1.0:
		return "trabajando"
	if rec.has("robot"):
		var sale := rejilla.casilla_libre_cerca(m.celda_salida(), 4)
		var r := _nuevo_robot(rec.robot, Vector2(sale) + Vector2(0.5, 0.5))
		hitos.robot = true
		log_evento(m.id, "salida", "robot", 1, r.nombre())
		aviso("%s fabricó %s." % [m.id, r.etiqueta()], "info")
	else:
		for mat in rec.sale:
			m.salida[mat] = int(m.salida.get(mat, 0)) + rec.sale[mat]
			log_evento(m.id, "salida", mat, rec.sale[mat])
	m.trabajando = false
	m.producidos += 1
	return "trabajando"


func _empujar_a_cinta(m: Maquina) -> void:
	if not m.lista() or m.salida.is_empty():
		return
	var c := m.celda_salida()
	if not cintas.admite(c) or cintas.celdas[c].dir == posmod(m.rot + 2, 4):
		return
	var mat := ""
	if m.tipo == "recepcion":
		mat = m.salida_cinta if int(m.salida.get(m.salida_cinta, 0)) > 0 else ""
	else:
		for k in m.salida:
			if int(m.salida[k]) > 0:
				mat = k
				break
	if mat == "":
		return
	m.salida[mat] -= 1
	cintas.meter(c, mat)
	log_evento(m.id, "a_cinta", mat, 1)


func _entregar_desde_cinta(destino: Vector2i, material: String) -> int:
	var m := maquina_en(destino)
	if m == null or not m.lista() or destino != m.celda_entrada():
		return -1
	var n := m.aceptar(material, 1)
	if n == 1:
		log_evento(m.id, "entrada", material, 1, "cinta")
		if m.tipo == "despacho":
			hitos.cinta_despacho = true
	elif n == -1 and not _estado_previo.get(m.id + material, false):
		log_evento(m.id, "rechazo", material, 1, "cinta")
	_estado_previo[m.id + material] = n == -1
	return n


# ---------------------------------------------------------------- robots

func _paso_robot(r: Robot, dt: float) -> void:
	r.prev = r.pos
	r.prev_rumbo = r.rumbo
	if r.pc < r.ordenes.size():
		_ejecutar_orden(r, r.ordenes[r.pc], dt)
	elif r.auto:
		_rutina_explorador(r, dt)
	else:
		r.estado = "ocioso"


func _terminar(r: Robot) -> void:
	if r.pc < r.ordenes.size():
		var o: Dictionary = r.ordenes[r.pc]
		o.fase = ""
		if o.has("ticket"):
			resultados.append({"robot": r.id, "ticket": o.ticket, "resultado": r.resultado})
	r.resultado = "ok"
	r.pc += 1
	r.camino = PackedVector2Array()
	if r.pc >= r.ordenes.size() and r.repetir and r.def.bucle and not r.ordenes.is_empty():
		r.pc = 0


## Casilla desde la que el robot actúa sobre el objetivo de una orden.
func _acercamiento(r: Robot, o: Dictionary) -> Vector2i:
	match o.tipo:
		"mover":
			return o.celda
		"minar":
			var m := _mena(o.objetivo)
			return rejilla.borde_libre(Rect2i(m.celda, Vector2i.ONE), r.pos) if not m.is_empty() else Vector2i(-1, -1)
		_:
			if o.objetivo == "suelo":
				return o.celda if rejilla.libre(o.celda) else rejilla.borde_libre(Rect2i(o.celda, Vector2i.ONE), r.pos)
			var maq: Maquina = maquinas.get(o.objetivo)
			if maq == null:
				return Vector2i(-1, -1)
			var cerca := r.pos
			if o.has("punto"):
				cerca = o.punto
			return rejilla.borde_libre(maq.rect(), cerca)


func _ejecutar_orden(r: Robot, o: Dictionary, dt: float) -> void:
	if o.fase == "" and o.tipo == "esperar":
		o.fase = "accion"
		r.timer = 0.0
	if o.fase == "":
		var meta := _acercamiento(r, o)
		if meta.x < 0:
			log_evento(r.nombre(), "sin_objetivo", "", 0, str(o.get("objetivo", "")))
			r.estado = "sin_ruta"
			r.resultado = "sin_objetivo"
			_terminar(r)
			return
		if not _planificar(r, meta):
			log_evento(r.nombre(), "sin_ruta", "", 0, str(o.get("objetivo", "")))
			aviso("%s no encuentra camino." % r.nombre(), "error", "ruta" + r.nombre())
			r.estado = "sin_ruta"
			r.resultado = "sin_ruta"
			_terminar(r)
			return
		o.fase = "ruta"
	if o.fase == "ruta":
		r.estado = "yendo"
		if not _mover(r, dt):
			return
		if o.tipo == "mover":
			_terminar(r)
			return
		o.fase = "accion"
		r.timer = 0.0
	# fase acción
	r.timer += dt
	if o.tipo == "esperar":
		r.estado = "esperando"
		if r.timer >= float(o.seg):
			_terminar(r)
		return
	_mirar(r, _foco(o), dt)
	match o.tipo:
		"recoger":
			r.estado = "recogiendo"
			if r.timer >= Cfg.T_RECOGER:
				_recoger(r, o)
				_terminar(r)
		"entregar":
			r.estado = "entregando"
			if r.timer >= Cfg.T_ENTREGAR:
				_entregar(r, o.objetivo)
				_terminar(r)
		"minar":
			r.estado = "minando"
			if r.timer >= Cfg.T_MINAR:
				r.timer = 0.0
				if not _minar_una(r, _mena(o.objetivo)):
					_terminar(r)
		"reparar":
			r.estado = "reparando"
			if r.timer >= 3.0:
				var m: Maquina = maquinas.get(o.objetivo)
				if m != null and m.averiada:
					m.averiada = false
					log_evento(m.id, "reparada", "", 0, r.nombre())
				_terminar(r)


func _foco(o: Dictionary) -> Vector2:
	if o.tipo == "minar":
		var m := _mena(o.objetivo)
		return Vector2(m.celda) + Vector2(0.5, 0.5) if not m.is_empty() else Vector2.ZERO
	if o.get("objetivo", "") == "suelo" or o.tipo == "mover":
		return Vector2(o.celda) + Vector2(0.5, 0.5)
	var maq: Maquina = maquinas.get(o.objetivo)
	return maq.centro() if maq else Vector2.ZERO


func _recoger(r: Robot, o: Dictionary) -> void:
	var hueco := r.cap() - r.cant
	if o.objetivo == "suelo":
		var pila: Dictionary = suelo.get(o.celda, {})
		if pila.is_empty() or (r.carga != "" and r.carga != pila.mat) or hueco <= 0:
			log_evento(r.nombre(), "viaje_vacio", "", 0, "suelo")
			r.resultado = "viaje_vacio"
			return
		var n: int = min(hueco, pila.cant)
		pila.cant -= n
		if pila.cant <= 0:
			suelo.erase(o.celda)
		_cargar(r, pila.mat, n, "suelo")
		return
	var m: Maquina = maquinas.get(o.objetivo)
	if m == null:
		r.resultado = "sin_objetivo"
		return
	var mat: String = o.get("material", "")
	if mat == "":
		for k in m.salida:
			if int(m.salida[k]) > 0 and (r.carga == "" or r.carga == k):
				mat = k
				break
	var hay: int = int(m.salida.get(mat, 0)) if mat != "" else 0
	if r.carga != "" and r.carga != mat and mat != "":
		log_evento(r.nombre(), "manos_ocupadas", r.carga, r.cant, m.id)
		aviso("%s ya lleva %s." % [r.nombre(), r.carga], "error")
		r.resultado = "manos_ocupadas"
		return
	var n: int = min(hueco, hay)
	if n <= 0:
		# Recoger en un punto vacío es una acción del mundo, no un error de programa (GDD §5).
		log_evento(r.nombre(), "viaje_vacio", mat, 0, m.id)
		r.resultado = "viaje_vacio"
		return
	m.salida[mat] -= n
	_cargar(r, mat, n, m.id)


func _cargar(r: Robot, mat: String, n: int, desde: String) -> void:
	r.carga = mat
	r.cant += n
	log_evento(r.nombre(), "recoge", mat, n, desde)


func _entregar(r: Robot, id: String) -> void:
	var m: Maquina = maquinas.get(id)
	if m == null:
		r.resultado = "sin_objetivo"
		return
	if r.cant <= 0:
		log_evento(r.nombre(), "entrega_vacia", "", 0, id)
		r.resultado = "entrega_vacia"
		return
	var n := m.aceptar(r.carga, r.cant)
	if n < 0:
		log_evento(m.id, "rechazo", r.carga, r.cant, r.nombre())
		aviso("%s no usa %s: %s se lo queda." % [m.id, r.carga, r.nombre()], "error", "rechazo" + m.id + r.nombre())
		r.resultado = "rechazo"
		return
	if n > 0:
		log_evento(m.id, "entrada", r.carga, n, r.nombre())
		log_evento(r.nombre(), "entrega", r.carga, n, m.id)
		hitos.entrega = true
	var resto := r.cant - n
	if resto > 0:
		# Entrada llena: el material cae al suelo y se puede recuperar (GDD §5).
		_derramar(r.pos, r.carga, resto, r.nombre())
		r.resultado = "derrame"
		aviso("%s estaba llena: %s derramó %d %s. Consulta los derrames en la base." % [m.id, r.nombre(), resto, r.carga], "aviso", "derrame" + m.id)
	r.carga = ""
	r.cant = 0


func _minar_una(r: Robot, mena: Dictionary) -> bool:
	if mena.is_empty() or mena.cantidad <= 0:
		log_evento(r.nombre(), "viaje_vacio", "cobre", 0, mena.get("id", "?"))
		if r.cant == 0:
			r.resultado = "agotada"
		return false
	if r.carga != "" and r.carga != "cobre":
		return false
	if r.cant >= r.cap():
		return false
	mena.cantidad -= 1
	r.carga = "cobre"
	r.cant += 1
	log_evento(r.nombre(), "mina", "cobre", 1, mena.id)
	if mena.cantidad == 0:
		log_evento(mena.id, "agotada")
	return r.cant < r.cap() and mena.cantidad > 0


func _rutina_explorador(r: Robot, dt: float) -> void:
	match r.auto_fase:
		"buscar":
			r.estado = "buscando"
			if r.cant >= r.cap() or (r.cant > 0 and _mena_cercana(r).is_empty()):
				r.auto_fase = "ir_fundidora"
				return
			var m := _mena_cercana(r)
			if m.is_empty():
				r.estado = "sin_menas"
				return
			r.auto_obj = m
			if _planificar(r, rejilla.borde_libre(Rect2i(m.celda, Vector2i.ONE), r.pos)):
				r.auto_fase = "ir_mena"
		"ir_mena":
			r.estado = "yendo"
			if _mover(r, dt):
				r.auto_fase = "minar"
				r.timer = 0.0
		"minar":
			r.estado = "minando"
			_mirar(r, Vector2(r.auto_obj.celda) + Vector2(0.5, 0.5), dt)
			r.timer += dt
			if r.timer >= Cfg.T_MINAR:
				r.timer = 0.0
				if not _minar_una(r, r.auto_obj):
					r.auto_fase = "ir_fundidora" if r.cant >= r.cap() else "buscar"
		"ir_fundidora":
			var f := _fundidora_para(r)
			if f == null:
				r.estado = "sin_fundidora"
				return
			r.auto_obj = {"id": f.id}
			if _planificar(r, rejilla.borde_libre(f.rect(), r.pos)):
				r.auto_fase = "esperar"
		"esperar":
			r.estado = "yendo"
			if _mover(r, dt):
				r.auto_fase = "entregar"
				r.timer = 0.0
		"entregar":
			var f: Maquina = maquinas.get(r.auto_obj.get("id", ""))
			if f == null:
				r.auto_fase = "ir_fundidora"
				return
			_mirar(r, f.centro(), dt)
			# El sensor de espacio evita derrames: espera en vez de tirar material.
			var hueco := f.espacio_para("cobre")
			if hueco <= 0:
				r.estado = "esperando"
				return
			r.estado = "entregando"
			r.timer += dt
			if r.timer >= Cfg.T_ENTREGAR:
				var n: int = min(hueco, r.cant)
				f.aceptar("cobre", n)
				log_evento(f.id, "entrada", "cobre", n, r.nombre())
				log_evento(r.nombre(), "entrega", "cobre", n, f.id)
				r.cant -= n
				if r.cant <= 0:
					r.carga = ""
					r.auto_fase = "buscar"


func mena(id: String) -> Dictionary:
	return _mena(id)


func _mena(id: String) -> Dictionary:
	for m in rejilla.menas:
		if m.id == id:
			return m
	return {}


func _mena_cercana(r: Robot) -> Dictionary:
	var mejor := {}
	var coste := INF
	for m in rejilla.menas:
		if m.cantidad <= 0:
			continue
		var ocupada := 0
		for o in robots:
			if o != r and o.auto and o.auto_obj.get("id", "") == m.id:
				ocupada += 1
		var c := Vector2(m.celda).distance_to(r.pos) + ocupada * 12.0
		if c < coste:
			coste = c
			mejor = m
	return mejor


func _fundidora_para(r: Robot) -> Maquina:
	var mejor: Maquina = null
	var coste := INF
	for m: Maquina in maquinas.values():
		if m.tipo != "fundidora" or not m.lista():
			continue
		var c := m.centro().distance_to(r.pos) - m.espacio_para("cobre") * 4.0
		if c < coste:
			coste = c
			mejor = m
	return mejor


func _planificar(r: Robot, meta: Vector2i) -> bool:
	if meta.x < 0:
		return false
	if r.celda() == meta:
		r.camino = PackedVector2Array([Vector2(meta) + Vector2(0.5, 0.5)])
		r.paso = 0
		r.meta = meta
		return true
	var ruta := rejilla.ruta(r.celda(), meta)
	if ruta.is_empty():
		return false
	r.camino = PackedVector2Array()
	for p in ruta:
		r.camino.append(p + Vector2(0.5, 0.5))
	r.paso = 1 if r.camino.size() > 1 else 0
	r.meta = meta
	return true


## Avanza por el camino. Devuelve true al llegar.
func _mover(r: Robot, dt: float) -> bool:
	if r.paso >= r.camino.size():
		return true
	var obj := r.camino[r.paso]
	var c := Vector2i(floor(obj.x), floor(obj.y))
	if rejilla.astar.is_point_solid(c):
		# Algo se construyó en el camino: recalcula.
		if not _planificar(r, r.meta):
			r.camino = PackedVector2Array()
			return true
		return false
	var d := obj - r.pos
	var dist := d.length()
	var deseado := atan2(d.x, d.y)
	var giro := wrapf(deseado - r.rumbo, -PI, PI)
	r.rumbo += clamp(giro, -7.0 * dt, 7.0 * dt)
	var v := r.vel() * dt * (0.35 if abs(giro) > 1.2 else 1.0)
	# Dos robots que buscan el mismo punto se empujan sin llegar nunca: basta con acercarse,
	# y si uno no avanza durante un segundo da el punto por alcanzado.
	var tolerancia := 0.3 if r.paso < r.camino.size() - 1 else 0.12
	if dist <= max(v, tolerancia) or r.atasco > 1.0:
		if dist <= v:
			r.pos = obj
		r.distancia += min(dist, v)
		r.paso += 1
		r.atasco = 0.0
		return r.paso >= r.camino.size()
	var antes := r.pos
	r.pos += d / dist * v
	r.distancia += v
	r.atasco = r.atasco + dt if r.prev.distance_to(antes) < v * 0.3 and abs(giro) < 1.2 else 0.0
	return false


func _mirar(r: Robot, foco: Vector2, dt: float) -> void:
	var d := foco - r.pos
	if d.length_squared() < 0.0001:
		return
	r.rumbo += wrapf(atan2(d.x, d.y) - r.rumbo, -PI, PI) * min(1.0, dt * 8.0)


func _separar() -> void:
	for i in robots.size():
		for j in range(i + 1, robots.size()):
			var a := robots[i]
			var b := robots[j]
			var d := b.pos - a.pos
			var l := d.length()
			if l < 0.55 and l > 0.0001:
				var empuje := d / l * (0.55 - l) * 0.5
				_empujar(a, -empuje)
				_empujar(b, empuje)


func _empujar(r: Robot, v: Vector2) -> void:
	var n := r.pos + v
	if not rejilla.astar.is_point_solid(Vector2i(floor(n.x), floor(n.y))):
		r.pos = n


func _desatascar_robots(celdas: Array) -> void:
	for r in robots:
		if r.celda() in celdas:
			r.pos = Vector2(rejilla.casilla_libre_cerca(r.celda())) + Vector2(0.5, 0.5)
			r.prev = r.pos
			r.camino = PackedVector2Array()
			if r.pc < r.ordenes.size():
				r.ordenes[r.pc].fase = ""


func _derramar(cerca: Vector2, mat: String, cant: int, origen: String) -> void:
	if cant <= 0:
		return
	var base := Vector2i(floor(cerca.x), floor(cerca.y))
	var c := base
	for r in range(0, 5):
		var hallado := false
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := base + Vector2i(dx, dz)
				if not rejilla.libre(q) or cintas.celdas.has(q):
					continue
				var pila: Dictionary = suelo.get(q, {})
				if pila.is_empty() or pila.mat == mat:
					c = q
					hallado = true
					break
			if hallado:
				break
		if hallado:
			break
	if suelo.has(c):
		suelo[c].cant += cant
	else:
		suelo[c] = {"mat": mat, "cant": cant}
	log_evento(origen, "derrame", mat, cant, "%d,%d" % [c.x, c.y])


# ---------------------------------------------------------------- camiones

func _paso_pedidos(dt: float) -> void:
	for p in pedidos.duplicate():
		p.espera -= dt
		if p.espera <= 0.0:
			pedidos.erase(p)
			var c := _nuevo_camion("proveedor", Cfg.RUTA_PROVEEDOR)
			c.carga = {p.material: p.unidades}
			log_evento(c.id, "sale", p.material, p.unidades, "proveedor")


func _nuevo_camion(tipo: String, ruta: Array) -> Dictionary:
	var largo := 0.0
	for k in ruta.size() - 1:
		largo += (ruta[k] as Vector2).distance_to(ruta[k + 1])
	var c := {"id": "CAM-%d" % sig_camion, "tipo": tipo, "ruta": ruta, "largo": largo, "s": 0.0, "ps": 0.0,
		"estado": "ida", "carga": {}, "timer": 0.0, "esperando": false}
	sig_camion += 1
	camiones.append(c)
	return c


static func punto_ruta(ruta: Array, s: float) -> Array:
	## Devuelve [posición, dirección] a la distancia s de la polilínea.
	var resto := s
	for k in ruta.size() - 1:
		var a: Vector2 = ruta[k]
		var b: Vector2 = ruta[k + 1]
		var l := a.distance_to(b)
		if resto <= l or k == ruta.size() - 2:
			return [a.lerp(b, clamp(resto / l, 0.0, 1.0)), (b - a).normalized()]
		resto -= l
	return [ruta[0], Vector2.RIGHT]


func s_bloqueo() -> float:
	# El piquete se planta a la entrada de la ciudad, 12 m antes del mercado.
	return _largo(Cfg.RUTA_VENTA) - 12.0


func _largo(ruta: Array) -> float:
	var l := 0.0
	for k in ruta.size() - 1:
		l += (ruta[k] as Vector2).distance_to(ruta[k + 1])
	return l


func _paso_camion(c: Dictionary, dt: float) -> void:
	c.ps = c.s
	var v := Cfg.VEL_CAMION * dt
	c.esperando = false
	if c.tipo == "venta":
		_acum.trafico += dt
	match c.estado:
		"ida":
			var limite: float = c.largo
			if c.tipo == "venta" and ciudad.bloqueada() and c.s < s_bloqueo():
				limite = s_bloqueo() - 3.0
			c.s = min(c.s + v, limite)
			c.esperando = c.s >= limite and limite < c.largo
			if c.s >= c.largo:
				c.estado = "descarga"
				c.timer = 0.0
		"descarga":
			c.timer += dt
			if c.timer >= 3.0:
				if c.tipo == "proveedor":
					_descargar_proveedor(c)
				else:
					_vender(c)
				c.estado = "vuelta"
		"vuelta":
			var limite := 0.0
			if c.tipo == "venta" and ciudad.bloqueada() and c.s > s_bloqueo():
				limite = s_bloqueo() + 3.0
			c.s = max(c.s - v, limite)
			c.esperando = c.s <= limite and limite > 0.0
			if c.s <= 0.0:
				camiones.erase(c)


func _descargar_proveedor(c: Dictionary) -> void:
	var rec: Maquina = _primera("recepcion")
	for mat in c.carga:
		var n: int = c.carga[mat]
		var cabe: int = clamp(rec.cap_salida() - int(rec.salida.get(mat, 0)), 0, n)
		rec.salida[mat] = int(rec.salida.get(mat, 0)) + cabe
		log_evento(rec.id, "recibe", mat, cabe, c.id)
		if n - cabe > 0:
			_derramar(Vector2(16, 63), mat, n - cabe, c.id)
	aviso("Llegó el camión del proveedor a %s." % rec.id, "info", "proveedor")
	c.carga = {}


func _vender(c: Dictionary) -> void:
	var total := 0.0
	for mat in c.carga:
		var precio: float = ciudad.precio if mat == "circuito" else Cfg.PRECIO_LINGOTE
		var monto: float = round(precio * c.carga[mat])
		total += monto
		log_evento(c.id, "venta", mat, c.carga[mat], "mercado", monto)
	dinero += total
	hitos.venta = true
	aviso("%s vendió en la ciudad por ₵ %d." % [c.id, int(total)], "dinero")
	c.carga = {}


func _primera(tipo: String) -> Maquina:
	for m: Maquina in maquinas.values():
		if m.tipo == tipo and m.lista():
			return m
	return null


# ---------------------------------------------------------------- ciudad

func _paso_ciudad() -> void:
	var noche := Cfg.es_noche(t - 0.5 * Cfg.SEG_POR_HORA)
	var res := ciudad.hora(_acum.humo / Cfg.SEG_POR_HORA, _acum.ruido / Cfg.SEG_POR_HORA,
		_acum.trafico / Cfg.SEG_POR_HORA, noche)
	_acum = {"humo": 0.0, "ruido": 0.0, "trafico": 0.0}
	for q in res.quejas:
		q.t = t
		q.dia = dia()
		q.hora = int(hora())
		quejas.append(q)
	for e in res.eventos:
		match e.tipo:
			"bloqueo":
				log_evento("CIUDAD", "bloqueo", "", 0, "Vecinos del Centro cortan la carretera")
				aviso("Protesta: vecinos del Centro bloquean la carretera 2 horas. Los camiones esperan.", "alerta")
			"sabotaje":
				var candidatas: Array = []
				for m: Maquina in maquinas.values():
					if m.lista() and not m.averiada and m.tipo in ["fundidora", "ensambladora", "fabrica_robots"]:
						candidatas.append(m)
				if not candidatas.is_empty():
					var m: Maquina = candidatas[ciudad.rng.randi() % candidatas.size()]
					m.averiada = true
					log_evento(m.id, "sabotaje", "", 0, "Norte")
					aviso("Sabotaje en %s. Clic derecho con un robot para repararla." % m.id, "alerta")
			"ordenanza":
				log_evento("CIUDAD", "ordenanza", "", 0, "Silencio nocturno 22-06")
				aviso("Ordenanza municipal: silencio nocturno de 22:00 a 06:00. El ayuntamiento auditará tu tabla `eventos` cada noche y multará con ₵ 40 por cada máquina ruidosa que produzca.", "alerta")
	# Auditoría: la ciudad consulta TU registro. Si borras eventos, también lo verá (filas faltantes).
	if ciudad.ordenanza and int(hora()) == 6:
		auditorias.append({"dia": dia(), "sql": SQL_AUDITORIA % [dia() - 1, dia()]})


const SQL_AUDITORIA := """SELECT origen, COUNT(*) AS producciones
FROM eventos
WHERE tipo = 'salida'
  AND origen IN (SELECT id FROM maquinas WHERE ruido >= 2)
  AND ((dia = %d AND hora >= 22) OR (dia = %d AND hora < 6))
GROUP BY origen;"""


func resultado_auditoria(filas: Array) -> void:
	aplicar({"tipo": "resultado_auditoria", "filas": filas})


func _resultado_auditoria(filas: Array) -> void:
	if filas.is_empty():
		log_evento("CIUDAD", "auditoria", "", 0, "sin infracciones")
		aviso("Auditoría nocturna: sin infracciones.", "info")
		return
	var multa := 40.0 * filas.size()
	dinero -= multa
	var ids: PackedStringArray = []
	for f in filas:
		ids.append(str(f.origen))
	log_evento("CIUDAD", "multa", "", filas.size(), ", ".join(ids), -multa)
	aviso("Multa de ₵ %d: %s produjeron de noche. Pon su turno en «diurno»." % [int(multa), ", ".join(ids)], "alerta")


# ---------------------------------------------------------------- registro

func log_evento(origen: String, tipo: String, material: String = "", cantidad: int = 0, detalle: String = "", monto: Variant = null) -> void:
	# Sin dato = NULL (no cadena vacía): así `WHERE material IS NULL` significa algo.
	registro.append({"t": snappedf(t, 0.01), "dia": dia(), "hora": int(hora()), "origen": origen, "tipo": tipo,
		"material": material if material != "" else null, "cantidad": cantidad,
		"detalle": detalle if detalle != "" else null, "monto": monto})


## `clave` agrupa avisos repetidos: el mismo problema solo se anuncia una vez cada 30 s simulados.
## El registro sí guarda cada caso: para el detalle está la base de datos.
func aviso(texto: String, tipo: String = "info", clave: String = "") -> void:
	if clave != "":
		if t - float(_ultimo_aviso.get(clave, -INF)) < 30.0:
			return
		_ultimo_aviso[clave] = t
	avisos.append({"texto": texto, "tipo": tipo, "t": t})
