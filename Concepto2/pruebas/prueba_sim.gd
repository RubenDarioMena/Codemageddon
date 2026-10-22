extends SceneTree
## Prueba sin ventana: corre la simulación con órdenes y consulta la base.
func _init():
	var t0 := Time.get_ticks_msec()
	var sim := Simulacion.new()
	print("generación ms: ", Time.get_ticks_msec() - t0, " flora: ", sim.rejilla.flora.size(), " menas: ", sim.rejilla.menas.size(), " puente: ", sim.rejilla.puente_x)
	var db := BaseDatos.new()
	db.abrir()
	var r1 := sim.robots[0]
	var r2 := sim.robots[1]
	sim.ordenar([r1], {"tipo": "recoger", "objetivo": "REC-01", "material": "cobre"}, false)
	sim.ordenar([r1], {"tipo": "entregar", "objetivo": "FUN-01"}, true)
	sim.ordenar([r2], {"tipo": "recoger", "objetivo": "REC-01", "material": "silicio"}, false)
	sim.ordenar([r2], {"tipo": "entregar", "objetivo": "ENS-01"}, true)
	print(sim.set_repetir(r1, true))
	print(sim.comprar("cobre"))
	print(sim.construir("servidor", Vector2i(40, 70), 0))
	print(sim.construir("fundidora", Vector2i(5, 5), 0))
	for i in 20 * 120:
		sim.paso()
		if i % 20 == 0:
			db.volcar(sim)
	db.volcar(sim)
	db.proyectar(sim)
	print("t=", sim.t, " dinero=", sim.dinero, " hora=", sim.hora())
	for m in sim.maquinas.values():
		print(m.id, " ", m.estado, " in=", m.entrada, " out=", m.salida, " prod=", m.producidos)
	print("r1 ", r1.estado, " ", r1.pos, " carga ", r1.carga, r1.cant, " pc ", r1.pc)
	print("r2 ", r2.estado, " ", r2.pos, " pc ", r2.pc)
	print("camiones ", sim.camiones.size(), " cinta items: ", sim.cintas.celdas[Vector2i(31,61)].items)
	for q in ["SELECT origen, tipo, COUNT(*) AS n FROM eventos GROUP BY origen, tipo ORDER BY n DESC LIMIT 12;",
			"SELECT * FROM maquinas;", "SELECT * FROM eventos WHERE monto IS NOT NULL;", "SELECT COUNT(*) AS n FROM quejas;", "SELEC mal"]:
		var res := db.consultar(q)
		print(">> ", q, "\n   ok=", res.ok, " err=", res.error, " cols=", res.columnas, " ms=", res.ms)
		for f in res.filas.slice(0, 12): print("   ", f)
	print(r1.programa())
	for a in sim.avisos: print("AVISO ", a.texto)
	quit()
