class_name DevComandos
extends RefCounted
## Operaciones del laboratorio: datos puros, validados antes de mutar el mundo.
## aplicar() conserva tanto los intentos válidos como los rechazados en el diario.


static func ajustes() -> Dictionary:
	var res := {
		"cintas.vel": _ajuste(Cfg.CINTA_VEL, 0.1, 10.0, 0.1, "m/s", "Velocidad de las cintas"),
		"maquinas.tiempo": _ajuste(1.0, 0.1, 10.0, 0.1, "× duración", "Duración de todas las recetas"),
		"ciudad.ruido_nocturno": _ajuste(2.5, 0.0, 10.0, 0.1, "× ruido", "Sensibilidad nocturna al ruido"),
		"ciudad.umbral_ordenanza": _ajuste(12.0, 1.0, 1000.0, 1.0, "quejas", "Quejas para imponer silencio nocturno"),
		"ciudad.multa": _ajuste(40.0, 0.0, 10000.0, 1.0, "₵/máquina", "Multa por máquina en la auditoría")}
	for nivel in Cfg.ROBOTS:
		res["robots.%d.vel" % nivel] = _ajuste(Cfg.ROBOTS[nivel].vel, 0.1, 15.0, 0.1, "m/s", "Velocidad de %s" % Cfg.ROBOTS[nivel].nombre)
		res["robots.%d.cap" % nivel] = _ajuste(float(Cfg.ROBOTS[nivel].cap), 1.0, 100.0, 1.0, "unidades", "Capacidad de %s" % Cfg.ROBOTS[nivel].nombre)
	return res


static func _ajuste(inicial: float, minimo: float, maximo: float, paso: float, unidad: String, descripcion: String) -> Dictionary:
	return {"valor": inicial, "min": minimo, "max": maximo, "paso": paso, "unidad": unidad, "descripcion": descripcion}


static func valor(s: Simulacion, clave: String) -> float:
	return float(s.dev_ajustes.get(clave, ajustes().get(clave, {"valor": 0.0}).valor))


static func ejecutar(s: Simulacion, cmd: Dictionary) -> String:
	if not s.desarrollo:
		return "Devtools deshabilitadas en esta simulación"
	match str(cmd.get("tipo", "")):
		"dev_dinero":
			if not _numero(cmd.get("valor"), 0.0, 1000000000.0):
				return "Presupuesto inválido (0..1000000000)"
			s.dinero = float(cmd.valor)
		"dev_sistemas":
			if not s.dev_sistemas.has(cmd.get("sistema")) or not cmd.get("activo") is bool:
				return "Sistema o estado inválido"
			s.dev_sistemas[cmd.sistema] = cmd.activo
			if cmd.sistema == "ciudad":
				s._acum = {"humo": 0.0, "ruido": 0.0, "trafico": 0.0}
		"dev_reloj":
			if s.n_paso != 0:
				return "El reloj inicial solo se prepara antes del primer paso"
			if not _entero(cmd.get("dia"), 1, 10000) or not _numero(cmd.get("hora"), 0.0, 23.999999):
				return "Día u hora inválidos"
			s.t = ((int(cmd.dia) - 1) * 24.0 + float(cmd.hora) - Cfg.HORA_INICIO) * Cfg.SEG_POR_HORA
			s._hora_previa = -1
			s._acum = {"humo": 0.0, "ruido": 0.0, "trafico": 0.0}
		"dev_semilla":
			if s.n_paso != 0:
				return "La semilla de ciudad solo se prepara antes del primer paso"
			if not _entero(cmd.get("valor"), 0, 2147483647):
				return "Semilla inválida"
			s.ciudad.rng.seed = int(cmd.valor)
		"dev_robot":
			return _robot(s, cmd)
		"dev_robot_estado":
			return _robot_estado(s, cmd)
		"dev_ordenes":
			return _ordenes(s, cmd)
		"dev_maquina":
			return _maquina(s, cmd)
		"dev_maquina_estado":
			return _maquina_estado(s, cmd)
		"dev_obras":
			for m: Maquina in s.maquinas.values():
				m.obra = 0.0
				if m.estado == "construyendo":
					m.estado = "inactiva"
			for b in s.cintas.celdas.values():
				b.obra = 0.0
		"dev_reparar":
			for m: Maquina in s.maquinas.values():
				m.averiada = false
				if m.estado == "averiada":
					m.estado = "inactiva"
		"dev_ciudad":
			return _ciudad(s, cmd)
		"dev_material":
			return _material(s, cmd)
		"dev_mena":
			var mena := s.mena(str(cmd.get("id", "")))
			if mena.is_empty() or not _entero(cmd.get("cantidad"), 0, 1000000):
				return "Mena o cantidad inválida"
			mena.cantidad = int(cmd.cantidad)
			mena.max = maxi(int(mena.max), int(cmd.cantidad))
		"dev_ajuste":
			return _aplicar_ajuste(s, cmd)
		"dev_pedido":
			return _pedido(s, cmd)
		"dev_camion":
			return _camion(s, cmd)
		"dev_cinta":
			return _cinta(s, cmd)
		"dev_limpiar":
			return _limpiar(s, cmd)
		_:
			return "Comando de desarrollo desconocido"
	return ""


static func _numero(v: Variant, minimo: float, maximo: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= minimo and float(v) <= maximo


static func _entero(v: Variant, minimo: int, maximo: int) -> bool:
	return _numero(v, float(minimo), float(maximo)) and float(v) == floor(float(v))


static func _libre(s: Simulacion, celda: Variant, excluir_robot: int = -1) -> bool:
	if not celda is Vector2i or not s.rejilla.libre(celda):
		return false
	for r in s.robots:
		if r.id != excluir_robot and r.celda() == celda:
			return false
	return true


static func _robot(s: Simulacion, cmd: Dictionary) -> String:
	if not _entero(cmd.get("nivel"), 0, 100) or not Cfg.ROBOTS.has(int(cmd.nivel)) or not _entero(cmd.get("cantidad", 1), 1, 64):
		return "Nivel o cantidad de robots inválidos (1..64)"
	if not cmd.get("celda") is Vector2i or not s.rejilla.dentro(cmd.celda):
		return "Posición de robot fuera del mapa"
	var celdas: Array[Vector2i] = []
	for radio in range(0, 9):
		for dz in range(-radio, radio + 1):
			for dx in range(-radio, radio + 1):
				if maxi(absi(dx), absi(dz)) != radio:
					continue
				var c: Vector2i = cmd.celda + Vector2i(dx, dz)
				if _libre(s, c):
					celdas.append(c)
					if celdas.size() == int(cmd.get("cantidad", 1)):
						for celda in celdas:
							s._nuevo_robot(int(cmd.nivel), Vector2(celda) + Vector2(0.5, 0.5))
						return ""
	return "No hay suficientes casillas libres cerca del punto de aparición"


static func _robot_estado(s: Simulacion, cmd: Dictionary) -> String:
	if not _entero(cmd.get("id"), 1, 2147483647):
		return "ID de robot inválido"
	var r := s.robot(int(cmd.id))
	if r == null:
		return "Robot inexistente"
	if r.ejecutando:
		return "Detén el programa del robot antes de editar su estado"
	if cmd.has("celda") and not _libre(s, cmd.celda, r.id):
		return "Destino del robot ocupado o fuera del mapa"
	var capacidad: Variant = cmd.get("cap", r.cap())
	var velocidad: Variant = cmd.get("vel", r.vel())
	if not _entero(capacidad, 1, 100) or not _numero(velocidad, 0.1, 15.0):
		return "Capacidad (1..100) o velocidad (0.1..15 m/s) inválidas"
	var material: Variant = cmd.get("carga", r.carga)
	var cantidad: Variant = cmd.get("cantidad", r.cant)
	if not material is String or not _entero(cantidad, 0, int(capacidad)):
		return "Carga o cantidad inválida"
	if (int(cantidad) > 0 and not Cfg.MATERIALES.has(material)) or (int(cantidad) == 0 and material != ""):
		return "Una carga vacía requiere cantidad cero; una carga positiva requiere material"
	if cmd.has("auto") and (not cmd.auto is bool or (cmd.auto and not r.def.auto)):
		return "Este robot no admite esa rutina automática"
	if cmd.has("celda"):
		r.pos = Vector2(cmd.celda) + Vector2(0.5, 0.5)
		r.prev = r.pos
		r.camino = PackedVector2Array()
		r.paso = 0
		r.timer = 0.0
		r.atasco = 0.0
		if r.pc < r.ordenes.size():
			r.ordenes[r.pc].fase = ""
		r.auto_fase = "buscar"
		r.auto_obj = {}
	r.carga = material
	r.cant = int(cantidad)
	r.def.cap = int(capacidad)
	r.def.vel = float(velocidad)
	if cmd.has("auto"):
		s._set_auto(r, cmd.auto)
	return ""


static func _maquina(s: Simulacion, cmd: Dictionary) -> String:
	if not Cfg.MAQUINAS.has(cmd.get("maquina")) or not cmd.get("celda") is Vector2i or not _entero(cmd.get("rot", 0), 0, 3):
		return "Tipo, posición o giro de máquina inválido"
	var tam := Cfg.tam_rotado(Cfg.MAQUINAS[cmd.maquina].tam, int(cmd.get("rot", 0)))
	for z in tam.y:
		for x in tam.x:
			var c: Vector2i = cmd.celda + Vector2i(x, z)
			if not s.rejilla.en_parcela(c) or not _libre(s, c) or s.cintas.celdas.has(c) or s.suelo.has(c):
				return "Huella de máquina ocupada o fuera de la parcela"
	s._crear_maquina(cmd.maquina, cmd.celda, int(cmd.get("rot", 0)), true)
	return ""


static func _ordenes(s: Simulacion, cmd: Dictionary) -> String:
	if not _entero(cmd.get("id"), 1, 2147483647):
		return "ID de robot inválido"
	var r := s.robot(int(cmd.id))
	if r == null or r.ejecutando:
		return "El robot debe existir y tener su programa detenido"
	if not cmd.get("ordenes") is Array or cmd.ordenes.size() > 256:
		return "Órdenes debe ser una lista de hasta 256 acciones"
	if not cmd.get("repetir", false) is bool or (cmd.get("repetir", false) and not r.def.bucle):
		return "Este robot no admite ese estado de repetición"
	var ordenes: Array[Dictionary] = []
	for i in cmd.ordenes.size():
		var dato: Variant = cmd.ordenes[i]
		if not dato is Dictionary:
			return "Orden %d: se requiere un objeto" % i
		var o := {"tipo": str(dato.get("tipo", ""))}
		match o.tipo:
			"mover":
				if not dato.get("celda") is Vector2i or not s.rejilla.libre(dato.celda):
					return "Orden %d: destino ocupado o fuera del mapa" % i
				o.celda = dato.celda
			"esperar":
				if not _numero(dato.get("seg", 1.0), 0.0, 3600.0):
					return "Orden %d: espera fuera de 0..3600 segundos" % i
				o.seg = float(dato.get("seg", 1.0))
			"recoger", "entregar", "reparar", "minar":
				var objetivo: Variant = dato.get("objetivo")
				if not objetivo is String:
					return "Orden %d: se requiere un objetivo" % i
				if o.tipo == "minar":
					if not r.def.minar or s.mena(objetivo).is_empty():
						return "Orden %d: se requiere una mena y un robot con pala" % i
				elif o.tipo == "recoger" and objetivo == "suelo":
					if not dato.get("celda") is Vector2i or not s.rejilla.dentro(dato.celda):
						return "Orden %d: casilla del suelo inválida" % i
					o.celda = dato.celda
				elif not s.maquinas.has(objetivo):
					return "Orden %d: máquina inexistente" % i
				o.objetivo = objetivo
				if o.tipo == "recoger" and dato.has("material"):
					if not Cfg.MATERIALES.has(dato.material):
						return "Orden %d: material desconocido" % i
					o.material = dato.material
			_:
				return "Orden %d: acción desconocida" % i
		ordenes.append(o)
	# Solo después de validar la lista completa se sustituyen las órdenes anteriores.
	s._limpiar_ordenes(r)
	r.auto = false
	r.auto_obj = {}
	r.auto_fase = "buscar"
	r.timer = 0.0
	r.atasco = 0.0
	r.repetir = cmd.get("repetir", false)
	for o in ordenes:
		s._ordenar([r], o, true)
	return ""


static func _buffer(v: Variant, capacidad: int, permitidos: Array) -> bool:
	if not v is Dictionary:
		return false
	for mat in v:
		if not mat is String or not Cfg.MATERIALES.has(mat) or mat not in permitidos or not _entero(v[mat], 0, capacidad):
			return false
	return true


static func _unidades(buffer: Dictionary) -> Dictionary:
	# JSON representa todos sus números como float; el estado físico cuenta enteros.
	var res := {}
	for material in buffer:
		res[material] = int(buffer[material])
	return res


static func _maquina_estado(s: Simulacion, cmd: Dictionary) -> String:
	var m: Maquina = s.maquinas.get(cmd.get("id", ""))
	if m == null:
		return "Máquina inexistente"
	var receta: Variant = cmd.get("receta", m.receta)
	if not receta is String or (receta != "" and (not m.def.has("recetas") or not m.def.recetas.has(receta))) or (m.def.has("recetas") and receta == ""):
		return "Receta incompatible con la máquina"
	if receta != m.receta and m.trabajando:
		return "La receta en proceso debe terminar antes de cambiarla"
	var rec: Dictionary = m.def.recetas[receta] if receta != "" else {}
	var permitidos: Array = m.def.get("acepta", rec.get("entra", {}).keys())
	var salidas: Array = Cfg.MATERIALES.keys() if m.tipo == "recepcion" else rec.get("sale", {}).keys()
	var entrada: Variant = cmd.get("entrada", m.entrada)
	var salida: Variant = cmd.get("salida", m.salida)
	if not _buffer(entrada, m.cap_entrada(), permitidos) or not _buffer(salida, m.cap_salida(), salidas):
		return "Buffer incompatible o por encima de su capacidad por material"
	var progreso: Variant = cmd.get("progreso", m.progreso)
	var obra: Variant = cmd.get("obra", m.obra)
	if cmd.has("tiempo") and not _numero(cmd.tiempo, 0.1, 10.0):
		return "Duración individual fuera de 0.1..10 ×"
	if (cmd.has("progreso") and not _numero(progreso, 0.0, 0.999999)) or not _numero(obra, 0.0, 3600.0):
		return "Progreso (0..<1) u obra pendiente (0..3600 s) inválidos"
	var trabajando: bool = float(progreso) > 0.0 if cmd.has("progreso") else m.trabajando
	if trabajando:
		if rec.is_empty() or float(obra) > 0.0:
			return "Solo una máquina terminada con receta puede estar produciendo"
		for mat in rec.get("sale", {}):
			if int(salida.get(mat, 0)) + int(rec.sale[mat]) > m.cap_salida():
				return "La salida necesita espacio para la producción en curso"
	for campo in ["averiada", "pausada", "turno_diurno", "envio_auto"]:
		if cmd.has(campo) and not cmd[campo] is bool:
			return "Estado booleano inválido: %s" % campo
	if cmd.has("salida_cinta") and (m.tipo != "recepcion" or not Cfg.MATERIALES.has(cmd.salida_cinta)):
		return "Material de salida de recepción inválido"
	m.receta = receta
	m.entrada = _unidades(entrada)
	m.salida = _unidades(salida)
	m.progreso = float(progreso)
	m.trabajando = trabajando
	m.obra = float(obra)
	if cmd.has("tiempo"):
		m.dev_tiempo = float(cmd.tiempo)
	for campo in ["averiada", "pausada", "turno_diurno", "envio_auto", "salida_cinta"]:
		if cmd.has(campo):
			m.set(campo, cmd[campo])
	m.estado = "construyendo" if m.obra > 0.0 else ("averiada" if m.averiada else ("pausada" if m.pausada else ("trabajando" if m.trabajando else "inactiva")))
	return ""


static func _ciudad(s: Simulacion, cmd: Dictionary) -> String:
	var distrito: Variant = cmd.get("distrito", "")
	if not distrito is String or (distrito != "" and not s.ciudad.distritos.has(distrito)):
		return "Distrito inexistente"
	if cmd.has("opinion") and not _numero(cmd.opinion, 0.0, 1.0):
		return "Opinión fuera de 0..1"
	if cmd.has("quejas_nocturnas") and not _entero(cmd.quejas_nocturnas, 0, 1000000):
		return "Cantidad de quejas inválida"
	if cmd.has("ordenanza") and not cmd.ordenanza is bool:
		return "Ordenanza inválida"
	if cmd.has("bloqueo_horas") and not _numero(cmd.bloqueo_horas, 0.0, 240.0):
		return "Bloqueo fuera de 0..240 horas"
	if cmd.has("opinion"):
		for nombre in s.ciudad.distritos:
			if distrito == "" or distrito == nombre:
				s.ciudad.distritos[nombre].opinion = float(cmd.opinion)
	for campo in ["quejas_nocturnas", "ordenanza", "bloqueo_horas"]:
		if cmd.has(campo):
			s.ciudad.set(campo, cmd[campo])
	return ""


static func _material(s: Simulacion, cmd: Dictionary) -> String:
	if not cmd.get("celda") is Vector2i or not s.rejilla.libre(cmd.celda) or s.cintas.celdas.has(cmd.celda):
		return "Casilla de material ocupada o fuera del mapa"
	if not _entero(cmd.get("cantidad"), 0, 1000000) or (int(cmd.cantidad) > 0 and not Cfg.MATERIALES.has(cmd.get("material"))):
		return "Material o cantidad inválidos"
	if int(cmd.cantidad) == 0:
		s.suelo.erase(cmd.celda)
	else:
		s.suelo[cmd.celda] = {"mat": cmd.material, "cant": int(cmd.cantidad)}
	return ""


static func _aplicar_ajuste(s: Simulacion, cmd: Dictionary) -> String:
	var clave: String = str(cmd.get("clave", ""))
	var registro := ajustes()
	if not registro.has(clave):
		return "Ajuste desconocido"
	var a: Dictionary = registro[clave]
	if not _numero(cmd.get("valor"), a.min, a.max):
		return "Valor fuera de rango para %s" % clave
	var v := float(cmd.valor)
	if clave.ends_with(".cap") or clave == "ciudad.umbral_ordenanza":
		if v != floor(v):
			return "Este ajuste requiere unidades enteras"
	if clave.begins_with("robots."):
		var partes := clave.split(".")
		var nivel := int(partes[1])
		if partes[2] == "cap":
			for r in s.robots:
				if r.nivel == nivel and r.cant > int(v):
					return "Un robot lleva más material que la capacidad propuesta"
		for r in s.robots:
			if r.nivel == nivel:
				r.def[partes[2]] = int(v) if partes[2] == "cap" else v
	elif clave == "cintas.vel":
		s.cintas.velocidad = v
	elif clave == "ciudad.ruido_nocturno":
		s.ciudad.ruido_nocturno = v
	elif clave == "ciudad.umbral_ordenanza":
		s.ciudad.umbral_ordenanza = int(v)
	s.dev_ajustes[clave] = v
	return ""


static func _pedido(s: Simulacion, cmd: Dictionary) -> String:
	if not Cfg.PEDIDOS.has(cmd.get("material")) or not _entero(cmd.get("unidades"), 1, 1000000) or not _numero(cmd.get("espera"), 0.0, 3600.0):
		return "Material, unidades o espera del pedido inválidos"
	s.pedidos.append({"material": cmd.material, "unidades": int(cmd.unidades), "espera": float(cmd.espera)})
	return ""


static func _camion(s: Simulacion, cmd: Dictionary) -> String:
	var clase: Variant = cmd.get("clase", "proveedor")
	var estado: Variant = cmd.get("estado", "ida")
	if clase not in ["proveedor", "venta"] or estado not in ["ida", "descarga", "vuelta"] or not _numero(cmd.get("avance", 0.0), 0.0, 1.0):
		return "Clase, estado o avance del camión inválidos"
	var mats: Array = Cfg.PEDIDOS.keys() if clase == "proveedor" else ["lingote", "circuito"]
	if not _buffer(cmd.get("carga", {}), 1000000, mats):
		return "Carga incompatible con ese camión"
	if clase == "proveedor" and s._primera("recepcion") == null:
		return "El proveedor necesita una recepción terminada"
	if clase == "venta" and not s.camion_venta_libre():
		return "Ya existe un camión de venta"
	if estado == "descarga" and float(cmd.get("avance", 0.0)) != 1.0:
		return "Un camión descargando debe estar al final de su ruta"
	var c := s._nuevo_camion(clase, Cfg.RUTA_PROVEEDOR if clase == "proveedor" else Cfg.RUTA_VENTA)
	c.carga = _unidades(cmd.get("carga", {}))
	c.estado = estado
	c.s = c.largo * float(cmd.get("avance", 0.0))
	c.ps = c.s
	return ""


static func _cinta(s: Simulacion, cmd: Dictionary) -> String:
	if not cmd.get("celda") is Vector2i or not s.rejilla.en_parcela(cmd.celda) or not s.rejilla.libre(cmd.celda) or s.suelo.has(cmd.celda):
		return "Casilla de cinta ocupada o fuera de la parcela"
	if not _entero(cmd.get("dir", 0), 0, 3) or not _entero(cmd.get("cantidad", 0), 0, 2):
		return "Dirección o cantidad en cinta inválida (0..2)"
	if int(cmd.get("cantidad", 0)) > 0 and not Cfg.MATERIALES.has(cmd.get("material")):
		return "Material de cinta inválido"
	if s.cintas.celdas.has(cmd.celda) and not s.cintas.celdas[cmd.celda].items.is_empty():
		return "Vacía esa cinta antes de sustituir su contenido"
	s.cintas.poner(cmd.celda, int(cmd.get("dir", 0)), 0.0)
	for k in int(cmd.get("cantidad", 0)):
		s.cintas.meter(cmd.celda, cmd.material, 0.8 - k * Cfg.CINTA_HUECO)
	return ""


static func _limpiar(s: Simulacion, cmd: Dictionary) -> String:
	if s.n_paso != 0:
		return "La limpieza estructural solo se permite al preparar el escenario"
	var campos := ["robots", "maquinas", "cintas", "suelo", "pedidos", "camiones"]
	for campo in campos:
		if cmd.has(campo) and not cmd[campo] is bool:
			return "La opción de limpieza debe ser booleana"
	if cmd.get("robots", false):
		for r in s.robots:
			if r.ejecutando:
				return "Detén los programas antes de limpiar robots"
	if cmd.get("maquinas", false) and not cmd.get("camiones", false):
		for c in s.camiones:
			if c.tipo == "proveedor":
				return "Limpia también los camiones de proveedor antes de quitar recepción"
	if cmd.get("maquinas", false) and not cmd.get("pedidos", false) and not s.pedidos.is_empty():
		return "Limpia también los pedidos antes de quitar recepción"
	if cmd.get("robots", false):
		s.robots.clear()
		s.sig_robot = 1
	if cmd.get("maquinas", false):
		for m: Maquina in s.maquinas.values():
			s.rejilla.liberar(m.celdas())
		s.maquinas.clear()
		s.contadores.clear()
		s.historial.clear()
	if cmd.get("cintas", false):
		s.cintas.celdas.clear()
	if cmd.get("suelo", false):
		s.suelo.clear()
	if cmd.get("pedidos", false):
		s.pedidos.clear()
	if cmd.get("camiones", false):
		s.camiones.clear()
		s.sig_camion = 1
	return ""
