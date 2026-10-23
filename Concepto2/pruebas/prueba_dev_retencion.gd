extends SceneTree
## Una respuesta antigua de COUNT no puede borrar registros de un escenario nuevo.

class BaseDiferida extends BaseDatos:
	var pendientes: Array[Dictionary] = []
	func consultar_luego(sql: String, listo: Callable) -> void:
		pendientes.append({"sql": sql, "listo": listo})


func _init() -> void:
	var db := BaseDiferida.new()
	var avisos: Array = []
	db.retener_luego(10, func(n): avisos.append(n))
	var vieja: Callable = db.pendientes[0].listo
	db.reiniciar_dev(func(_r): pass)
	vieja.call({"ok": true, "filas": [{"n": 500}]})
	var fallos := 0
	if db.pendientes.size() != 2 or not avisos.is_empty() or db.filas_eventos != 0:
		push_error("Una respuesta de retención antigua afectó el escenario nuevo")
		fallos += 1
	db.retener_luego(10, func(n): avisos.append(n))
	var fresca: Callable = db.pendientes[2].listo
	fresca.call({"ok": true, "filas": [{"n": 25}]})
	if db.pendientes.size() != 4 or avisos != [15] or db.filas_eventos != 10:
		push_error("La retención de la generación actual dejó de funcionar")
		fallos += 1
	elif not str(db.pendientes[3].sql).contains("LIMIT 15"):
		push_error("La retención calculó un límite incorrecto")
		fallos += 1
	print("Dev retención: respuesta antigua aislada y respuesta actual aplicada; fallos=%d" % fallos)
	db.pendientes.clear()
	quit(1 if fallos > 0 else 0)
