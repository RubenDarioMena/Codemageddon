class_name DevEscenarios
extends RefCounted
## Escenarios declarativos. Se preparan en una simulación aparte: un error nunca toca la partida.

const VERSION := 1
const MAX_PASOS := 24000
const EVENTOS_PAUSA := ["", "derrame", "multa", "bloqueo", "ordenanza", "sabotaje", "viaje_vacio", "salida"]
const COMANDOS := ["dev_dinero", "dev_sistemas", "dev_reloj", "dev_semilla", "dev_robot", "dev_robot_estado",
	"dev_maquina", "dev_maquina_estado", "dev_obras", "dev_reparar", "dev_ciudad", "dev_material", "dev_mena",
	"dev_ajuste", "dev_pedido", "dev_camion", "dev_cinta", "dev_limpiar", "dev_ordenes"]


static func plantilla() -> Dictionary:
	return {"version": VERSION, "nombre": "Laboratorio", "base": "inicial",
		"inicio": {"dia": 1, "hora": 7.0, "dinero": 1200, "semilla_ciudad": 3},
		"sistemas": {"ciudad": true, "produccion": true, "robots": true, "logistica": true},
		"ajustes": {}, "comandos": [], "eventos": [],
		"pausa": {"evento": "", "pasos": 0}, "programas": {}}


static func nombres() -> Array[String]:
	return ["Laboratorio", "Entrada llena", "Primera noche", "Cuello de botella"]


static func preset(nombre: String) -> Dictionary:
	var d := plantilla()
	d.nombre = nombre
	match nombre:
		"Laboratorio":
			d.inicio.dinero = 20000
			d.sistemas.ciudad = false
			# Robots del catálogo vigente; no presupone que las mulas permanezcan.
			var niveles := Cfg.ROBOTS.keys()
			d.comandos = [{"tipo": "dev_limpiar", "robots": true},
				{"tipo": "dev_robot", "nivel": niveles[min(1, niveles.size() - 1)], "celda": [23, 66], "cantidad": 2}]
		"Entrada llena":
			d.sistemas.ciudad = false
			d.comandos = [{"tipo": "dev_maquina_estado", "id": "FUN-01", "entrada": {"cobre": 8}, "pausada": true}]
			d.pausa.evento = "derrame"
		"Primera noche":
			d.inicio.hora = 21.5
			d.comandos = [{"tipo": "dev_maquina_estado", "id": "FUN-01", "entrada": {"cobre": 8}},
				{"tipo": "dev_ciudad", "quejas_nocturnas": 10}]
			d.pausa.evento = "ordenanza"
		"Cuello de botella":
			d.sistemas.ciudad = false
			d.comandos = [{"tipo": "dev_maquina_estado", "id": "FUN-01", "salida": {"lingote": 8}},
				{"tipo": "dev_maquina_estado", "id": "ENS-01", "entrada": {"lingote": 2, "silicio": 0}}]
		_:
			return {}
	return d


## Conversión recursiva de coordenadas JSON. No trunca coordenadas fraccionarias.
static func normalizar(cmd: Dictionary) -> Dictionary:
	var res := cmd.duplicate(true)
	for clave in res:
		if res[clave] is Dictionary:
			res[clave] = normalizar(res[clave])
		elif res[clave] is Array and clave != "celda":
			for i in res[clave].size():
				if res[clave][i] is Dictionary:
					res[clave][i] = normalizar(res[clave][i])
		elif clave == "celda" and res[clave] is Array and res[clave].size() == 2:
			var c: Array = res[clave]
			if numero(c[0]) and numero(c[1]) and c[0] == int(c[0]) and c[1] == int(c[1]):
				res[clave] = Vector2i(int(c[0]), int(c[1]))
	return res


static func numero(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and abs(float(v)) < 1e9


static func error(texto: String) -> Dictionary:
	return {"ok": false, "error": texto}


static func crear(datos: Dictionary) -> Dictionary:
	if datos.get("version") != VERSION:
		return error("Versión de escenario no compatible (se requiere 1).")
	for k in datos:
		if not plantilla().has(k):
			return error("Opción de escenario desconocida: %s" % k)
	if datos.get("base", "inicial") not in ["inicial", "vacio"]:
		return error("Base debe ser inicial o vacio.")
	for k in ["inicio", "sistemas", "ajustes", "pausa", "programas"]:
		if not datos.get(k, {}) is Dictionary:
			return error("%s debe ser un objeto." % k)
	for k in ["comandos", "eventos"]:
		if not datos.get(k, []) is Array or datos.get(k, []).size() > 1000:
			return error("%s debe ser una lista de hasta 1000 elementos." % k)
	var inicio: Dictionary = plantilla().inicio
	inicio.merge(datos.get("inicio", {}), true)
	for k in inicio:
		if not plantilla().inicio.has(k) or not numero(inicio[k]):
			return error("Campo inicial inválido: %s" % k)
	var s := Simulacion.new(true)
	var comandos: Array = [
		{"tipo": "dev_reloj", "dia": inicio.dia, "hora": inicio.hora},
		{"tipo": "dev_semilla", "valor": inicio.semilla_ciudad},
		{"tipo": "dev_dinero", "valor": inicio.dinero}]
	if datos.get("base", "inicial") == "vacio":
		comandos.append({"tipo": "dev_limpiar", "robots": true, "maquinas": true, "cintas": true, "suelo": true, "pedidos": true, "camiones": true})
	for k in datos.get("sistemas", {}):
		comandos.append({"tipo": "dev_sistemas", "sistema": k, "activo": datos.sistemas[k]})
	for k in datos.get("ajustes", {}):
		comandos.append({"tipo": "dev_ajuste", "clave": k, "valor": datos.ajustes[k]})
	comandos.append_array(datos.get("comandos", []))
	for i in comandos.size():
		if not comandos[i] is Dictionary or not str(comandos[i].get("tipo", "")).begins_with("dev_"):
			return error("Comando %d: se requiere un comando dev_* válido." % i)
		var e := s.aplicar(normalizar(comandos[i]))
		if e != "":
			return error("Comando %d: %s" % [i, e])
	var eventos: Array = []
	for ev in datos.get("eventos", []):
		if not ev is Dictionary or not numero(ev.get("paso")) or ev.paso != int(ev.paso) or ev.paso < 0 or ev.paso > MAX_PASOS:
			return error("Cada evento requiere un paso entero entre 0 y %d." % MAX_PASOS)
		if not ev.get("cmd") is Dictionary or ev.cmd.get("tipo") not in COMANDOS:
			return error("Cada evento requiere cmd de tipo dev_*.")
		if ev.cmd.tipo in ["dev_reloj", "dev_semilla", "dev_limpiar"]:
			return error("Reloj, semilla y limpieza solo se preparan al inicio.")
		eventos.append({"paso": int(ev.paso), "cmd": normalizar(ev.cmd)})
	# sort_custom no garantiza estabilidad: desempatar por orden de autoría.
	for i in eventos.size():
		eventos[i]["indice"] = i
	eventos.sort_custom(func(a, b): return a.paso < b.paso or (a.paso == b.paso and a.indice < b.indice))
	var pa: Dictionary = {"evento": "", "pasos": 0}
	pa.merge(datos.get("pausa", {}), true)
	for k in pa:
		if k not in ["evento", "pasos"]:
			return error("Opción de pausa desconocida: %s" % k)
	if pa.evento not in EVENTOS_PAUSA or not numero(pa.pasos) or pa.pasos != int(pa.pasos) or pa.pasos < 0 or pa.pasos > MAX_PASOS:
		return error("Pausa: evento desconocido o límite de pasos inválido.")
	var programas: Dictionary = datos.get("programas", {}).duplicate(true)
	for id in programas:
		if not str(id).is_valid_int() or not programas[id] is String or s.robot(int(id)) == null:
			return error("Programa: robot inexistente o código inválido (%s)." % id)
		if s.robot(int(id)).nivel < 1:
			return error("El robot %s no admite programas." % id)
		s.robot(int(id)).codigo = programas[id]
	return {"ok": true, "error": "", "sim": s, "eventos": eventos, "pausa": pa,
		"programas": programas, "nombre": str(datos.get("nombre", "Escenario"))}
