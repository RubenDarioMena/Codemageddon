extends SceneTree
## Contrato puro del laboratorio: comandos atómicos, aislamiento y replay determinista.

var fallos := 0
var comprobaciones := 0


func _init() -> void:
	var normal := Simulacion.new()
	_rechaza(normal, {"tipo": "dev_dinero", "valor": 99999}, "gate de desarrollo")
	var a := Simulacion.new(true)
	var b := Simulacion.new(true)
	var preparacion := [
		{"tipo": "dev_reloj", "dia": 2, "hora": 22.0},
		{"tipo": "dev_semilla", "valor": 27},
		{"tipo": "dev_dinero", "valor": 54321},
		{"tipo": "dev_robot", "nivel": 2, "celda": Vector2i(40, 70), "cantidad": 3},
		{"tipo": "dev_robot_estado", "id": 4, "carga": "cobre", "cantidad": 3, "auto": false},
		{"tipo": "dev_maquina", "maquina": "fabrica_robots", "celda": Vector2i(45, 70), "rot": 1},
		{"tipo": "dev_maquina_estado", "id": "FAB-01", "receta": "explorador", "entrada": {"circuito": 6, "lingote": 4}},
		{"tipo": "dev_maquina_estado", "id": "FUN-01", "entrada": {"cobre": 8}, "salida": {"lingote": 3}, "progreso": 0.4},
		{"tipo": "dev_ciudad", "distrito": "Norte", "opinion": 0.1, "quejas_nocturnas": 11, "ordenanza": true, "bloqueo_horas": 2.0},
		{"tipo": "dev_material", "celda": Vector2i(37, 70), "material": "silicio", "cantidad": 23},
		{"tipo": "dev_mena", "id": "MENA-01", "cantidad": 100},
		{"tipo": "dev_pedido", "material": "cobre", "unidades": 11, "espera": 0.5},
		{"tipo": "dev_camion", "clase": "venta", "carga": {"circuito": 3}, "avance": 0.4},
		{"tipo": "dev_cinta", "celda": Vector2i(45, 68), "dir": 0, "material": "lingote", "cantidad": 2},
		{"tipo": "dev_ajuste", "clave": "robots.2.vel", "valor": 4.5},
		{"tipo": "dev_ajuste", "clave": "robots.2.cap", "valor": 6},
		{"tipo": "dev_ajuste", "clave": "maquinas.tiempo", "valor": 0.5},
		{"tipo": "dev_ajuste", "clave": "cintas.vel", "valor": 3.2},
		{"tipo": "dev_ajuste", "clave": "ciudad.ruido_nocturno", "valor": 3.0},
		{"tipo": "dev_ajuste", "clave": "ciudad.umbral_ordenanza", "valor": 30},
		{"tipo": "dev_ajuste", "clave": "ciudad.multa", "valor": 75},
		{"tipo": "dev_sistemas", "sistema": "robots", "activo": false}]
	for cmd in preparacion:
		_acepta(a, cmd)
		_acepta(b, cmd)
	_comprobar(a.huella() == b.huella(), "preparación repetible")
	_comprobar(a.ciudad.distritos.Sur.opinion == 0.6, "edición por distrito respeta los otros")
	_comprobar(normal.cintas.velocidad == Cfg.CINTA_VEL and normal.robot(1).vel() == Cfg.ROBOTS[0].vel, "overrides aislados de otra partida")
	_comprobar(a.robot(4).cap() == 6 and Cfg.ROBOTS[2].cap == 3, "capacidad local sin mutar Cfg")
	_acepta(a, {"tipo": "dev_robot", "nivel": 2, "celda": Vector2i(52, 70)})
	_acepta(b, {"tipo": "dev_robot", "nivel": 2, "celda": Vector2i(52, 70)})
	_comprobar(a.robot(7).vel() == 4.5 and a.robot(7).cap() == 6, "nuevos robots heredan ajustes de tipo")
	var pos := a.robot(4).pos
	var rng := a.ciudad.rng.state
	_acepta(a, {"tipo": "dev_sistemas", "sistema": "ciudad", "activo": false})
	_acepta(b, {"tipo": "dev_sistemas", "sistema": "ciudad", "activo": false})
	for k in 400:
		a.paso()
		b.paso()
	_comprobar(a.robot(4).pos == pos, "congelación de robots")
	_comprobar(a.ciudad.rng.state == rng, "congelación de ciudad no consume RNG")
	_acepta(a, {"tipo": "dev_sistemas", "sistema": "ciudad", "activo": true})
	_acepta(b, {"tipo": "dev_sistemas", "sistema": "ciudad", "activo": true})
	for k in 1000:
		a.paso()
		b.paso()
	_comprobar(a.huella() == b.huella(), "mismo escenario y mismas órdenes dan mismo estado")
	_acepta(a, {"tipo": "dev_dinero", "valor": 4321})
	_acepta(b, {"tipo": "dev_dinero", "valor": 4321})
	var diario: Array = str_to_var(var_to_str(a.diario))
	var replay := Simulacion.reproducir(diario, a.n_paso, true)
	_comprobar(a.huella() == replay.huella(), "replay dev serializado incluye comandos en último paso")
	_rechaza(a, {"tipo": "dev_reloj", "dia": 1, "hora": 4.0}, "no reescribe historia con reloj")
	_rechaza(a, {"tipo": "dev_semilla", "valor": 5}, "no cambia seed después de arrancar")
	_rechaza(a, {"tipo": "dev_limpiar", "robots": true}, "limpieza estructural solo al inicio")
	_rechaza(a, {"tipo": "dev_robot", "nivel": 99, "celda": Vector2i(40, 70)}, "nivel desconocido")
	_rechaza(a, {"tipo": "dev_robot_estado", "id": 4, "carga": "cobre", "cantidad": 7, "celda": Vector2i(40, 75)}, "robot atómico si carga excede capacidad")
	_rechaza(a, {"tipo": "dev_maquina_estado", "id": "FUN-01", "entrada": {"cobre": 9}, "pausada": true}, "máquina atómica si buffer excede capacidad")
	_rechaza(a, {"tipo": "dev_maquina_estado", "id": "FUN-01", "entrada": {"silicio": 1}}, "entrada incompatible")
	_rechaza(a, {"tipo": "dev_maquina_estado", "id": "FUN-01", "progreso": 0.5, "salida": {"lingote": 8}}, "salida reserva el producto en curso")
	_rechaza(a, {"tipo": "dev_ciudad", "opinion": 0.8, "bloqueo_horas": -1}, "ciudad valida todo antes de mutar")
	_rechaza(a, {"tipo": "dev_dinero", "valor": NAN}, "rechaza NaN")
	_rechaza(a, {"tipo": "dev_dinero", "valor": INF}, "rechaza infinito")
	_rechaza(a, {"tipo": "dev_ajuste", "clave": "robots.2.cap", "valor": 2}, "no reduce capacidad bajo carga actual")
	_rechaza(a, {"tipo": "dev_ajuste", "clave": "robots.2.cap", "valor": 3.5}, "capacidades enteras")
	_rechaza(a, {"tipo": "dev_ajuste", "clave": "cintas.vel", "valor": 0}, "límites de ajustes")
	_acepta(a, {"tipo": "iniciar_programa", "robot": 4})
	_rechaza(a, {"tipo": "dev_robot_estado", "id": 4, "celda": Vector2i(45, 75)}, "no teletransporta programa activo")
	_preparacion_vacia()
	_instancias()
	_ordenes()
	print("Dev comandos: %d comprobaciones; fallos=%d" % [comprobaciones, fallos])
	quit(1 if fallos > 0 else 0)


func _preparacion_vacia() -> void:
	var s := Simulacion.new(true)
	_acepta(s, {"tipo": "dev_limpiar", "robots": true, "maquinas": true, "cintas": true, "suelo": true, "pedidos": true, "camiones": true})
	_comprobar(s.maquinas.is_empty() and s.robots.is_empty() and s.rejilla.ocupante.is_empty(), "base vacía sin huellas residuales")
	_acepta(s, {"tipo": "dev_maquina", "maquina": "recepcion", "celda": Vector2i(17, 60)})
	_acepta(s, {"tipo": "dev_maquina", "maquina": "fundidora", "celda": Vector2i(26, 60)})
	_acepta(s, {"tipo": "dev_maquina_estado", "id": "FUN-01", "obra": 5.0, "averiada": true})
	_acepta(s, {"tipo": "dev_obras"})
	_acepta(s, {"tipo": "dev_reparar"})
	_comprobar(s.maquinas["FUN-01"].lista() and not s.maquinas["FUN-01"].averiada, "terminar obras y reparar")
	_rechaza(s, {"tipo": "dev_maquina", "maquina": "fundidora", "celda": Vector2i(26, 60)}, "huella ocupada")
	_rechaza(s, {"tipo": "dev_robot", "nivel": 1, "celda": Vector2i(-1, -1)}, "robot fuera del mapa")
	_rechaza(s, {"tipo": "dev_camion", "clase": "proveedor", "carga": {"cobre": 3}, "estado": "descarga", "avance": 0.1}, "camión descargando en destino")
	_acepta(s, {"tipo": "dev_material", "celda": Vector2i(37, 70), "material": "cobre", "cantidad": 5})
	_acepta(s, {"tipo": "dev_material", "celda": Vector2i(37, 70), "cantidad": 0})
	_comprobar(not s.suelo.has(Vector2i(37, 70)), "vaciar material en suelo")
	_acepta(s, {"tipo": "dev_sistemas", "sistema": "produccion", "activo": false})
	_acepta(s, {"tipo": "dev_maquina_estado", "id": "FUN-01", "entrada": {"cobre": 8}})
	_acepta(s, {"tipo": "dev_sistemas", "sistema": "logistica", "activo": false})
	_acepta(s, {"tipo": "dev_pedido", "material": "cobre", "unidades": 10, "espera": 0.5})
	for k in 100:
		s.paso()
	_comprobar(s.maquinas["FUN-01"].entrada.cobre == 8 and s.maquinas["FUN-01"].producidos == 0, "producción congelada")
	_comprobar(s.pedidos[0].espera == 0.5 and s.camiones.is_empty(), "logística congelada")


func _acepta(s: Simulacion, cmd: Dictionary) -> void:
	var error := s.aplicar(cmd)
	_comprobar(error == "", "%s: %s" % [str(cmd), error])


func _instancias() -> void:
	var s := Simulacion.new(true)
	_acepta(s, {"tipo": "dev_robot_estado", "id": 1, "vel": 5.0, "cap": 7})
	_comprobar(s.robot(1).cap() == 7 and s.robot(2).cap() == 2 and s.robot(2).vel() == 2.4, "balance por instancia respeta otros robots del tipo")
	_acepta(s, {"tipo": "dev_robot_estado", "id": 1, "carga": "cobre", "cantidad": 6})
	_rechaza(s, {"tipo": "dev_robot_estado", "id": 1, "vel": 3.0, "cap": 5}, "capacidad individual no pierde carga y valida velocidad atómicamente")
	_acepta(s, {"tipo": "dev_maquina_estado", "id": "FUN-01", "tiempo": 0.5, "entrada": {"cobre": 8}})
	_acepta(s, {"tipo": "dev_maquina", "maquina": "fundidora", "celda": Vector2i(45, 70)})
	_acepta(s, {"tipo": "dev_maquina_estado", "id": "FUN-02", "tiempo": 2.0, "entrada": {"cobre": 8}})
	_rechaza(s, {"tipo": "dev_maquina_estado", "id": "FUN-02", "tiempo": 0.0, "pausada": true}, "tiempo individual atómico")
	_acepta(s, {"tipo": "dev_sistemas", "sistema": "robots", "activo": false})
	_acepta(s, {"tipo": "dev_sistemas", "sistema": "logistica", "activo": false})
	for k in 26:
		s.paso()
	_comprobar(s.maquinas["FUN-01"].producidos == 1 and s.maquinas["FUN-02"].producidos == 0, "duración por instancia modifica producción")
	_acepta(s, {"tipo": "dev_maquina_estado", "id": "FUN-01", "pausada": true})
	_comprobar(Simulacion.reproducir(s.diario, s.n_paso, true).huella() == s.huella(), "replay conserva ajustes por instancia")


func _ordenes() -> void:
	var s := Simulacion.new(true)
	_acepta(s, {"tipo": "dev_ordenes", "id": 3, "repetir": true, "ordenes": [
		{"tipo": "recoger", "objetivo": "REC-01", "material": "cobre"},
		{"tipo": "entregar", "objetivo": "FUN-01"}, {"tipo": "esperar", "seg": 0.5}]})
	_rechaza(s, {"tipo": "dev_ordenes", "id": 3, "ordenes": [{"tipo": "esperar", "seg": 2.0}, {"tipo": "mover", "celda": Vector2i(-1, -1)}]}, "la lista de órdenes valida todo antes de sustituir")
	_rechaza(s, {"tipo": "dev_ordenes", "id": 1, "repetir": true, "ordenes": []}, "repetición requiere chip")
	_rechaza(s, {"tipo": "dev_ordenes", "id": 3, "ordenes": [{"tipo": "minar", "objetivo": "MENA-01"}]}, "minar requiere pala")
	_rechaza(s, {"tipo": "dev_ordenes", "id": 3, "ordenes": [{"tipo": "recoger", "objetivo": "suelo"}]}, "recoger suelo requiere coordenadas")
	for k in 500:
		s.paso()
	_comprobar(s.maquinas["FUN-01"].producidos > 0, "escenario ejecuta órdenes automáticamente")
	_comprobar(s.robot(3).repetir and s.robot(3).ordenes.size() == 3, "se conserva secuencia repetible")
	_comprobar(Simulacion.reproducir(s.diario, s.n_paso, true).huella() == s.huella(), "replay de listas de órdenes")
	_acepta(s, {"tipo": "iniciar_programa", "robot": 3})
	_rechaza(s, {"tipo": "dev_ordenes", "id": 3, "ordenes": []}, "no cambia órdenes mientras existe worker activo")


func _rechaza(s: Simulacion, cmd: Dictionary, motivo: String) -> void:
	var antes := s.huella()
	var n := s.diario.size()
	var error := s.aplicar(cmd)
	_comprobar(error != "" and s.huella() == antes and s.diario.size() == n + 1, "rechazo atómico y registrado: %s" % motivo)


func _comprobar(condicion: bool, mensaje: String) -> void:
	comprobaciones += 1
	if not condicion:
		fallos += 1
		push_error(mensaje)
