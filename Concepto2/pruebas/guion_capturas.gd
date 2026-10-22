extends Node
## Guion de prueba: da órdenes como lo haría un jugador y guarda capturas en pruebas/capturas/.

var p: Node
var t := 0.0
var paso := 0
var salida := ""


func _ready() -> void:
	salida = ProjectSettings.globalize_path("res://pruebas/capturas/")
	DirAccess.make_dir_recursive_absolute(salida)
	p.hud.ayuda.visible = false


func _captura(nombre: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(salida + nombre + ".png")
	print("CAPTURA ", nombre)


func _process(delta: float) -> void:
	t += delta
	var sim: Simulacion = p.sim
	match paso:
		0:
			if t > 1.5:
				_captura("01_inicio")
				var r1 := sim.robots[0]
				var r2 := sim.robots[1]
				sim.ordenar([r1], {"tipo": "recoger", "objetivo": "REC-01", "material": "cobre"}, false)
				sim.ordenar([r1], {"tipo": "entregar", "objetivo": "FUN-01"}, true)
				sim.ordenar([r2], {"tipo": "recoger", "objetivo": "REC-01", "material": "silicio"}, false)
				sim.ordenar([r2], {"tipo": "entregar", "objetivo": "ENS-01"}, true)
				p.control._seleccionar_robots([r1.id], false)
				sim.comprar("cobre")
				sim.construir("fabrica_robots", Vector2i(44, 64), 0)
				sim.construir("servidor", Vector2i(40, 70), 0)
				sim.construir_cintas(p.control._tramo(Vector2i(37, 61), Vector2i(65, 61)))
				p.velocidad = 4.0
				paso += 1
		1:
			if t > 6.0:
				_captura("02_robot_seleccionado")
				p.control._seleccionar_robots([], false)
				p.control.sel_maquina = "FUN-01"
				p.control.seleccion_cambiada.emit()
				paso += 1
		2:
			if t > 7.5:
				_captura("03_maquina")
				p.hud.consola.abrir_con(ConsolaSQL.EJEMPLOS[1][1])
				paso += 1
		3:
			if t > 9.0:
				_captura("04_consola")
				p.hud.consola.visible = false
				p.hud.fijar_panel(ConsolaSQL.EJEMPLOS[2][1], "¿Quién está parado?")
				p.control.empezar_construccion("ensambladora")
				Input.warp_mouse(Vector2(900, 380))
				paso += 1
		4:
			if t > 10.5:
				_captura("05_construccion")
				p.control.cancelar_modo()
				p.cam.centrar(Vector3(110, 0, 62))
				p.cam.nivel = 1
				p.velocidad = 8.0
				paso += 1
		5:
			if t > 13.0:
				_captura("06_mapa")
				# Explorador T2 con su rutina, junto a las menas del este de la fábrica.
				var e := sim._nuevo_robot(2, Vector2(78.5, 52.5))
				p.control._seleccionar_robots([e.id], false)
				p.cam.centrar(Vector3(80, 0, 51))
				p.cam.nivel = 5
				p.velocidad = 2.0
				paso += 1
		6:
			if t > 17.0:
				_captura("07_explorador")
				# Saltar a la noche (22:30).
				sim.t += (22.5 - sim.hora()) * Cfg.SEG_POR_HORA
				p.cam.centrar(Vector3(150, 0, 62))
				p.cam.nivel = 3
				p.cam.yaw_obj = PI / 4.0
				p.velocidad = 1.0
				paso += 1
		7:
			if t > 19.5:
				_captura("08_noche")
				get_tree().quit()
