extends SceneTree
## Prueba larga sin ventana: varios días con una fábrica automatizada para ejercitar
## ventas, ciudad (quejas, bloqueo, sabotaje, ordenanza) y la auditoría SQL.
func _init():
	var sim := Simulacion.new()
	var db := BaseDatos.new()
	db.abrir()
	sim.dinero = 20000
	for k in 3:
		print("FUN extra: ", sim.construir("fundidora", Vector2i(26, 44 + k * 4), 0))
	print("cinta ENS->DES: ", sim.construir_cintas(_tramo(Vector2i(37, 61), Vector2i(65, 61))))
	print("cinta REC->FUN: ", "ya existe cinta FUN->ENS")
	# Operarios T1 en bucle: cobre a cada fundidora y silicio a la ensambladora.
	var objetivos := ["FUN-01", "FUN-02", "FUN-03", "FUN-04"]
	for k in objetivos.size():
		var r := sim._nuevo_robot(1, Vector2(22.5 + k, 66.5))
		sim.ordenar([r], {"tipo": "recoger", "objetivo": "REC-01", "material": "cobre"}, false)
		sim.ordenar([r], {"tipo": "entregar", "objetivo": objetivos[k]}, true)
		sim.set_repetir(r, true)
	var rs := sim._nuevo_robot(1, Vector2(22.5, 68.5))
	sim.ordenar([rs], {"tipo": "recoger", "objetivo": "REC-01", "material": "silicio"}, false)
	sim.ordenar([rs], {"tipo": "entregar", "objetivo": "ENS-01"}, true)
	sim.set_repetir(rs, true)
	var exp := sim._nuevo_robot(2, Vector2(70.5, 50.5))
	var dias := 3
	var pasos := int(dias * 24 * Cfg.SEG_POR_HORA * Cfg.HZ)
	for i in pasos:
		sim.paso()
		if i % 100 == 0:
			var rec: Maquina = sim.maquinas["REC-01"]
			if int(rec.salida.get("cobre", 0)) < 20 and sim.pedidos.size() < 2:
				sim.comprar("cobre")
			if int(rec.salida.get("silicio", 0)) < 10 and sim.pedidos.size() < 3:
				sim.comprar("silicio")
		if i % 10 == 0:
			db.volcar(sim)
		if i % 40 == 0:
			db.proyectar(sim)
		for au in sim.auditorias:
			db.volcar(sim)
			var r := db.consultar(au.sql)
			print("AUDITORIA día ", au.dia, " ok=", r.ok, " ", r.error, " filas=", r.filas)
			sim.resultado_auditoria(r.filas if r.ok else [])
		sim.auditorias.clear()
	db.volcar(sim)
	print("dinero final: ", sim.dinero, " día ", sim.dia(), " hora ", sim.hora())
	print("explorador: ", exp.estado, " carga ", exp.cant, " fase ", exp.auto_fase)
	for m in sim.maquinas.values():
		print(m.id, " ", m.estado, " prod=", m.producidos, " in=", m.entrada, " out=", m.salida)
	for nombre in sim.ciudad.distritos:
		var d = sim.ciudad.distritos[nombre]
		print(nombre, " opinión=", snappedf(d.opinion, 0.01), " p=", d.p)
	for q in ["SELECT tipo, COUNT(*) AS n, SUM(monto) AS monto FROM eventos WHERE origen LIKE 'CAM%' OR origen IN ('CIUDAD','PROVEEDOR') GROUP BY tipo;",
			"SELECT distrito, motivo, COUNT(*) AS n FROM quejas GROUP BY distrito, motivo ORDER BY n DESC;",
			"SELECT origen, tipo, detalle FROM eventos WHERE origen = 'CIUDAD' OR tipo IN ('sabotaje','reparada');",
			"SELECT origen, COUNT(*) AS n FROM eventos WHERE tipo='mina' GROUP BY origen;",
			"SELECT tipo, COUNT(*) AS n FROM eventos GROUP BY tipo ORDER BY n DESC;"]:
		var r := db.consultar(q)
		print(">> ", q)
		for f in r.filas.slice(0, 14): print("   ", f)
	var avisos := {}
	for a in sim.avisos:
		avisos[a.texto.left(60)] = avisos.get(a.texto.left(60), 0) + 1
	for k in avisos: print("AVISO x", avisos[k], " ", k)
	quit()

func _tramo(desde: Vector2i, hasta: Vector2i) -> Array:
	var res := []
	var c := desde
	while true:
		res.append([c, 0])
		if c == hasta: break
		c.x += 1
	return res
