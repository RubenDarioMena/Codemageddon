extends SceneTree
func _init():
	var sim := Simulacion.new()
	var r1 := sim.robots[0]
	var r2 := sim.robots[1]
	sim.ordenar([r1], {"tipo": "recoger", "objetivo": "REC-01", "material": "cobre"}, false)
	sim.ordenar([r1], {"tipo": "entregar", "objetivo": "FUN-01"}, true)
	sim.ordenar([r2], {"tipo": "recoger", "objetivo": "REC-01", "material": "silicio"}, false)
	sim.ordenar([r2], {"tipo": "entregar", "objetivo": "ENS-01"}, true)
	for i in 400:
		sim.paso()
		if i % 25 == 0:
			for r in [r1, r2]:
				print(i, " R", r.id, " pos ", r.pos, " ", r.estado, " pc ", r.pc, " paso ", r.paso, "/", r.camino.size(), " meta ", r.meta)
	quit()
