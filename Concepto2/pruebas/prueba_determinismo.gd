extends SceneTree

func _init() -> void:
	var a := Simulacion.new()
	var b := Simulacion.new()
	var guion := [
		{"paso": 0, "cmd": {"tipo": "ordenar", "robots": [1],
			"orden": {"tipo": "esperar", "seg": 10.0}, "encolar": false}},
		{"paso": 300, "cmd": {"tipo": "comprar", "material": "cobre"}},
		{"paso": 900, "cmd": {"tipo": "construir", "maquina": "servidor", "celda": Vector2i(40, 70), "rot": 0}},
		{"paso": 950, "cmd": {"tipo": "deshacer"}},
		{"paso": 1200, "cmd": {"tipo": "construir", "maquina": "servidor", "celda": Vector2i(40, 70), "rot": 0}},
		{"paso": 1400, "cmd": {"tipo": "demoler", "id": "SRV-02"}},
		{"paso": 1500, "cmd": {"tipo": "set_repetir", "robot": 3, "valor": true}},
		{"paso": 2300, "cmd": {"tipo": "iniciar_programa", "robot": 3}},
		{"paso": 2500, "cmd": {"tipo": "orden_programa", "robot": 3,
			"datos": {"tipo": "esperar", "seg": 2.0}, "ticket": 77}},
		{"paso": 2700, "cmd": {"tipo": "fin_programa", "robot": 3}},
		{"paso": 3000, "cmd": {"tipo": "set_maquina", "id": "REC-01", "campo": "pausada", "valor": true}},
		{"paso": 4000, "cmd": {"tipo": "resultado_auditoria", "filas": [{"origen": "FUN-01"}]}},
		{"paso": 4500, "cmd": {"tipo": "construir", "maquina": "servidor", "celda": Vector2i(-1, -1), "rot": 0}}
	]
	var puntos := [0, 299, 300, 899, 900, 949, 950, 1199, 1200, 1399, 1400,
		1499, 1500, 2299, 2300, 2499, 2500, 2699, 2700, 2999, 3000, 3999, 4000, 4499, 4500, 5999]
	var fallos := 0
	var indice := 0
	var hashes := 0
	var ultimo_resultado := ""
	for k in 6000:
		while indice < guion.size() and int(guion[indice].paso) == k:
			var cmd: Dictionary = guion[indice].cmd
			ultimo_resultado = a.aplicar(cmd)
			var resultado_b := b.aplicar(cmd)
			if ultimo_resultado != resultado_b:
				fallos = _fallar("resultado distinto al aplicar en paso %d" % k, fallos)
			indice += 1
		a.paso()
		b.paso()
		if k in puntos:
			if a.huella() != b.huella():
				fallos = _fallar("corridas divergen en paso %d" % k, fallos)
			hashes += 1
	if ultimo_resultado == "":
		fallos = _fallar("el comando inválido debía fallar", fallos)
	var replay := Simulacion.reproducir(a.diario, a.n_paso)
	if replay.huella() != a.huella():
		fallos = _fallar("replay no coincide", fallos)
	var diario_copia: Array = str_to_var(var_to_str(a.diario))
	if Simulacion.reproducir(diario_copia, a.n_paso).huella() != a.huella():
		fallos = _fallar("diario serializado no coincide", fallos)
	var alterado := diario_copia.duplicate(true)
	alterado[1].cmd.material = "silicio"
	if Simulacion.reproducir(alterado, a.n_paso).huella() == a.huella():
		fallos = _fallar("huella no detecta comando alterado", fallos)
	var hash_original := a.huella()
	a.rejilla.menas[0].cantidad -= 1
	if a.huella() == hash_original:
		fallos = _fallar("huella no incluye cantidad de menas", fallos)
	a.rejilla.menas[0].cantidad += 1
	hash_original = a.huella()
	a.robots[0].consola.append("cambio de presentación")
	if a.huella() != hash_original:
		fallos = _fallar("huella incluye consola de presentación", fallos)
	print("Determinismo: %d puntos; diario %d comandos; fallos=%d" % [hashes, a.diario.size(), fallos])
	quit(1 if fallos > 0 else 0)


func _fallar(mensaje: String, fallos: int) -> int:
	push_error(mensaje)
	return fallos + 1
