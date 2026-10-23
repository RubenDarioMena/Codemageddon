class_name DevtoolsPanel
extends CanvasLayer
## Laboratorio de juego. Los controles solo mandan comandos; nunca escriben en la simulación.
## El JSON conserva toda la granularidad del formato de escenarios sin crear otro editor de lógica.

var d: Node
var abierto: bool:
	get:
		return visible
var fondo: ColorRect
var panel: PanelContainer
var tabs: TabContainer
var estado: Label
var reloj: Label
var boton_pausa: Button
var escenario: CodeEdit
var lista_escenarios: OptionButton
var nombre_guardado: LineEdit
var inicio_dia: SpinBox
var inicio_hora: SpinBox
var inicio_dinero: SpinBox
var inicio_seed: SpinBox
var inspector: CodeEdit
var notas: LineEdit
var filtro_ajustes: LineEdit
var filas_ajustes: Array[Control] = []
var _bloqueados: Array[Dictionary] = []
var _tiempo := 0.0


func iniciar(controlador: Node) -> void:
	d = controlador
	layer = 30
	fondo = ColorRect.new()
	fondo.color = Color(0.01, 0.02, 0.04, 0.65)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fondo)
	panel = PanelContainer.new()
	panel.theme = Estilo.tema()
	panel.add_theme_stylebox_override("panel", Estilo.caja(Color("09131e"), Estilo.ACENTO, 6, 12))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var cab := _fila(v)
	_etiqueta(cab, "DEVTOOLS · Laboratorio", true)
	var espacio := Control.new()
	espacio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(espacio)
	_boton(cab, "Cerrar · F12", cerrar)
	reloj = _etiqueta(v, "")
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	_controles(_pagina("Controles"))
	_escenarios(_pagina("Escenario"))
	_entidades(_pagina("Entidades"))
	_ajustes(_pagina("Ajustes"))
	_inspector(_pagina("Inspector"))
	estado = _etiqueta(v, "Abre un escenario, ajusta una variable y repite la prueba.")
	estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	estado.custom_minimum_size.y = 35
	get_viewport().size_changed.connect(_dimensionar)
	_dimensionar()
	_actualizar_lista()
	visible = false
	set_process(false)


func abrir() -> void:
	if visible:
		return
	visible = true
	if d.p.velocidad > 0:
		d.pausa()
	refrescar_mundo()
	set_process(true)
	_actualizar_lista()
	_refrescar()


func refrescar_mundo() -> void:
	if not visible:
		return
	# Un drag empezado antes de F12 no debe convertirse en una orden al cerrar.
	d.p.control._fin_derecho()
	d.p.cam.orbitando = false
	d.p.cam.desplazando = false
	# Cargar escenario reemplaza ControlRTS; preservamos flags de los nodos aún vivos.
	for nodo in [d.p.control, d.p.cam]:
		var guardado := false
		for flags in _bloqueados:
			if is_instance_valid(flags.nodo) and flags.nodo == nodo:
				guardado = true
		if not guardado:
			_bloqueados.append({"nodo": nodo, "process": nodo.is_processing(),
				"input": nodo.is_processing_input(), "unhandled": nodo.is_processing_unhandled_input()})
		nodo.set_process(false)
		nodo.set_process_input(false)
		nodo.set_process_unhandled_input(false)


func cerrar() -> void:
	visible = false
	set_process(false)
	for flags in _bloqueados:
		if is_instance_valid(flags.nodo):
			flags.nodo.set_process(flags.process)
			flags.nodo.set_process_input(flags.input)
			flags.nodo.set_process_unhandled_input(flags.unhandled)
	_bloqueados.clear()
	var foco := get_viewport().gui_get_focus_owner()
	if foco != null and panel.is_ancestor_of(foco):
		foco.release_focus()


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_F12:
			if visible:
				cerrar()
			else:
				abrir()
			get_viewport().set_input_as_handled()
		elif visible and e.keycode == KEY_ESCAPE:
			cerrar()
			get_viewport().set_input_as_handled()


func _unhandled_input(_e: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tiempo += delta
	if _tiempo >= 0.5:
		_tiempo = 0
		_refrescar()


func _dimensionar() -> void:
	var tam := get_viewport().get_visible_rect().size
	panel.size = Vector2(minf(930, maxf(300, tam.x - 24)), minf(740, maxf(250, tam.y - 24)))
	panel.position = (tam - panel.size) / 2


func _pagina(nombre: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = nombre
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	return v


func _controles(v: VBoxContainer) -> void:
	_etiqueta(v, "Tiempo y estado de la sesión", true)
	_ayuda(v, "Al abrir se pausa. Puedes reanudar manteniendo el panel abierto. Los pasos avanzan tiempo de simulación.")
	var tiempo := _fila(v)
	boton_pausa = _boton(tiempo, "Reanudar", func(): d.pausa(); _refrescar())
	for mult in [1, 2, 4, 8, 16]:
		_boton(tiempo, "×%d" % mult, func(): d.velocidad(float(mult)); _refrescar())
	var pasos := _fila(v)
	for n in [1, 20, 250]:
		_boton(pasos, "+%d pasos" % n, func(): _mensaje(d.avanzar(n)); _refrescar())
	_boton(v, "Reiniciar escenario activo", func(): _mensaje(d.reiniciar()); _refrescar())
	_etiqueta(v, "Intervenciones inmediatas", true)
	var caja := _fila(v)
	_etiqueta(caja, "Saldo absoluto · ₵")
	var dinero := _numero(caja, 0, 100000000, 1, Cfg.PRESUPUESTO)
	_boton(caja, "Fijar saldo", func(): _cmd({"tipo": "dev_dinero", "valor": dinero.value}))
	var obras := _fila(v)
	_boton(obras, "Terminar todas las obras", func(): _cmd({"tipo": "dev_obras"}))
	_boton(obras, "Reparar todas las máquinas", func(): _cmd({"tipo": "dev_reparar"}))
	_boton(v, "Detener programas JS", func(): _cmd({"tipo": "dev_detener_programas"}))
	_etiqueta(v, "Sistemas independientes", true)
	_ayuda(v, "Congelar conserva el estado; el resto del mundo sigue avanzando. No borra quejas ni pedidos.")
	for sistema in ["ciudad", "produccion", "robots", "logistica"]:
		var f := _fila(v)
		_etiqueta(f, sistema.capitalize()).custom_minimum_size.x = 150
		_boton(f, "Congelar", func(): _cmd({"tipo": "dev_sistemas", "sistema": sistema, "activo": false}))
		_boton(f, "Activar", func(): _cmd({"tipo": "dev_sistemas", "sistema": sistema, "activo": true}))


func _escenarios(v: VBoxContainer) -> void:
	_ayuda(v, "Carga un preset o una variante guardada. Reiniciar repite su semilla, ajustes, órdenes y eventos programados.")
	var guardados := _fila(v)
	lista_escenarios = OptionButton.new()
	lista_escenarios.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guardados.add_child(lista_escenarios)
	_boton(guardados, "Cargar", func():
		if lista_escenarios.selected >= 0:
			_mensaje(d.cargar(lista_escenarios.get_item_text(lista_escenarios.selected)))
			escenario.text = JSON.stringify(d.escenario, "\t")
			_refrescar())
	var guardar := _fila(v)
	nombre_guardado = _texto(guardar, "Nombre de la variante")
	_boton(guardar, "Guardar punto de prueba", func():
		_mensaje(d.guardar(nombre_guardado.text.strip_edges()))
		_actualizar_lista())
	_etiqueta(v, "Estado inicial", true)
	var inicio := _fila(v)
	_etiqueta(inicio, "Día")
	inicio_dia = _numero(inicio, 1, 10000, 1, 1)
	_etiqueta(inicio, "Hora")
	inicio_hora = _numero(inicio, 0, 23.99, 0.25, 7)
	_etiqueta(inicio, "₵")
	inicio_dinero = _numero(inicio, 0, 100000000, 1, 1200)
	_etiqueta(inicio, "Seed ciudad")
	inicio_seed = _numero(inicio, 0, 2147483647, 1, 3)
	var botonera := _fila(v)
	_boton(botonera, "Usar estos valores en JSON", _inicio_a_json)
	_boton(botonera, "Nueva plantilla", _plantilla)
	_etiqueta(v, "Escenario completo · JSON", true)
	_ayuda(v, "Edita comandos, inventarios por material, menas, cintas, pedidos, programas, eventos y pausa automática. Aplicar valida todo antes de reemplazar la partida. Empezar a una hora no simula las horas previas.")
	escenario = _editor(v, 310)
	var ejecutar := _fila(v)
	_boton(ejecutar, "Aplicar y reiniciar", func():
		var datos = _leer_json(escenario)
		if datos is Dictionary:
			_mensaje(d.cargar_escenario(datos))
			_refrescar())
	_boton(ejecutar, "Formatear JSON", func():
		var datos = _leer_json(escenario)
		if datos is Dictionary:
			escenario.text = JSON.stringify(datos, "\t"))
	_plantilla()


func _inicio_a_json() -> void:
	var datos = _leer_json(escenario)
	if not datos is Dictionary:
		return
	datos["inicio"] = {"dia": int(inicio_dia.value), "hora": inicio_hora.value,
		"dinero": inicio_dinero.value, "semilla_ciudad": int(inicio_seed.value)}
	escenario.text = JSON.stringify(datos, "\t")
	_mensaje("Valores escritos en el JSON. Pulsa Aplicar y reiniciar para probarlos.")


func _plantilla() -> void:
	escenario.text = JSON.stringify(d.plantilla(), "\t")


func _actualizar_lista() -> void:
	var previo := lista_escenarios.get_item_text(lista_escenarios.selected) if lista_escenarios.selected >= 0 else ""
	lista_escenarios.clear()
	for nombre in d.escenarios():
		lista_escenarios.add_item(str(nombre))
		if str(nombre) == previo:
			lista_escenarios.select(lista_escenarios.item_count - 1)


func _entidades(v: VBoxContainer) -> void:
	_etiqueta(v, "Crear robots del catálogo actual", true)
	var robot := _fila(v)
	var nivel := OptionButton.new()
	for k in Cfg.ROBOTS:
		nivel.add_item("%s · %s" % [Cfg.ROBOTS[k].nivel, Cfg.ROBOTS[k].nombre], int(k))
	robot.add_child(nivel)
	_etiqueta(robot, "Cantidad")
	var cantidad := _numero(robot, 1, 64, 1, 1)
	var celda_robot := _celda(robot, 25, 65)
	_boton(robot, "Crear", func(): _cmd({"tipo": "dev_robot", "nivel": nivel.get_selected_id(),
		"cantidad": int(cantidad.value), "celda": _xy(celda_robot)}))
	_etiqueta(v, "Crear máquina terminada", true)
	var maquina := _fila(v)
	var tipo := _opciones(maquina, Cfg.MAQUINAS.keys())
	var celda_maquina := _celda(maquina, 50, 70)
	_etiqueta(maquina, "Rotación")
	var rot := _numero(maquina, 0, 3, 1, 0)
	_boton(maquina, "Crear", func(): _cmd({"tipo": "dev_maquina", "maquina": tipo.get_item_text(tipo.selected),
		"celda": _xy(celda_maquina), "rot": int(rot.value)}))
	_etiqueta(v, "Estado de máquinas · individual / grupo / todas", true)
	_ayuda(v, "IDs separados por coma (FUN-01, ENS-01), * para todas, o usa la selección del mundo. Solo se envían los campos activados; los inventarios se fijan como valores absolutos.")
	var destino := _fila(v)
	var ids := _texto(destino, "IDs de máquinas o *", "FUN-01")
	_boton(destino, "Usar selección", func(): ids.text = d.p.control.sel_maquina)
	_boton(destino, "Todas", func(): ids.text = "*")
	var f := _fila(v)
	var usa_progreso := _check(f, "Progreso (0–1)")
	var progreso := _numero(f, 0, 0.99, 0.01, 0)
	var usa_obra := _check(f, "Obra pendiente (s)")
	var obra := _numero(f, 0, 10000, 0.1, 0)
	var duracion_fila := _fila(v)
	var usa_tiempo := _check(duracion_fila, "Duración de esta máquina ×")
	var tiempo := _numero(duracion_fila, 0.1, 10, 0.1, 1)
	var flags := _fila(v)
	var averiada := _triestado(flags, "Averiada")
	var pausada := _triestado(flags, "Pausada")
	var diurna := _triestado(flags, "Turno diurno")
	var receta_fila := _fila(v)
	var usa_receta := _check(receta_fila, "Receta")
	var receta := _texto(receta_fila, "Nombre de receta (lingote, circuito, operario…)")
	var inventarios := _fila(v)
	var usa_entrada := _check(inventarios, "Entrada JSON")
	var entrada := _texto(inventarios, "{\"cobre\": 8}", "{}")
	var salidas := _fila(v)
	var usa_salida := _check(salidas, "Salida JSON")
	var salida := _texto(salidas, "{\"lingote\": 4}", "{}")
	_boton(v, "Aplicar a máquinas indicadas", func():
		var cambios := {"tipo": "dev_maquina_estado"}
		if usa_progreso.button_pressed:
			cambios["progreso"] = progreso.value
		if usa_obra.button_pressed:
			cambios["obra"] = obra.value
		if usa_tiempo.button_pressed:
			cambios["tiempo"] = tiempo.value
		for par in [["averiada", averiada], ["pausada", pausada], ["turno_diurno", diurna]]:
			if par[1].selected > 0:
				cambios[par[0]] = par[1].selected == 2
		if usa_receta.button_pressed:
			cambios["receta"] = receta.text.strip_edges()
		if usa_entrada.button_pressed:
			var datos = _parsear(entrada.text)
			if not datos is Dictionary:
				_mensaje("Entrada debe ser un objeto JSON de material a cantidad.")
				return
			cambios["entrada"] = datos
		if usa_salida.button_pressed:
			var datos = _parsear(salida.text)
			if not datos is Dictionary:
				_mensaje("Salida debe ser un objeto JSON de material a cantidad.")
				return
			cambios["salida"] = datos
		_aplicar_maquinas(ids.text, cambios))
	_etiqueta(v, "Intervenciones avanzadas · comando JSON", true)
	_ayuda(v, "Elige un ejemplo, ajusta sus campos y ejecútalo. Para repetirlo al reiniciar, añádelo a comandos en la pestaña Escenario.")
	var ejemplos := _opciones(v, ["Estado robot", "Ciudad / distrito", "Material en suelo", "Mena", "Cinta", "Pedido", "Camión"])
	var comando := _editor(v, 150)
	var plantillas := [
		{"tipo": "dev_robot_estado", "id": 3, "carga": "cobre", "cantidad": 2, "auto": false, "cap": 3, "vel": 2.6},
		{"tipo": "dev_ciudad", "distrito": "Norte", "opinion": 0.5, "quejas_nocturnas": 20, "ordenanza": true, "bloqueo_horas": 2},
		{"tipo": "dev_material", "celda": [25, 65], "material": "cobre", "cantidad": 10},
		{"tipo": "dev_mena", "id": d.p.sim.rejilla.menas[0].id if not d.p.sim.rejilla.menas.is_empty() else "", "cantidad": 100},
		{"tipo": "dev_cinta", "celda": [45, 65], "dir": 0},
		{"tipo": "dev_pedido", "material": "cobre", "unidades": 20, "espera": 6},
		{"tipo": "dev_camion", "clase": "proveedor", "carga": {"cobre": 10}, "estado": "ida", "avance": 0.5},
	]
	ejemplos.item_selected.connect(func(i): comando.text = JSON.stringify(plantillas[i], "\t"))
	comando.text = JSON.stringify(plantillas[0], "\t")
	_boton(v, "Ejecutar comando", func():
		var datos = _leer_json(comando)
		if datos is Dictionary:
			_cmd(datos))


func _aplicar_maquinas(texto_ids: String, cambios: Dictionary) -> void:
	var objetivos: Array = []
	if texto_ids.strip_edges() == "*":
		objetivos = d.p.sim.maquinas.keys()
	else:
		for id in texto_ids.split(",", false):
			var limpio := id.strip_edges()
			if limpio != "" and not objetivos.has(limpio):
				objetivos.append(limpio)
	if objetivos.is_empty():
		_mensaje("Indica al menos una máquina.")
		return
	var errores: Array[String] = []
	var exitos := 0
	for id in objetivos:
		var cmd := cambios.duplicate(true)
		cmd["id"] = str(id)
		var resultado: String = d.ejecutar(cmd)
		if resultado == "":
			exitos += 1
		else:
			errores.append("%s: %s" % [id, resultado])
	_mensaje("%d máquinas actualizadas.%s" % [exitos, " Parcial: " + "; ".join(errores) if not errores.is_empty() else ""])
	_refrescar()


func _ajustes(v: VBoxContainer) -> void:
	_ayuda(v, "Los ajustes afectan a esta sesión. Cada botón aplica un único valor. Guarda el escenario activo para repetir el experimento. El saldo y los inventarios se modifican en sus pestañas.")
	filtro_ajustes = _texto(v, "Buscar ajuste por clave, unidad o descripción")
	filtro_ajustes.text_changed.connect(func(texto):
		for fila in filas_ajustes:
			fila.visible = texto.to_lower() in str(fila.get_meta("busqueda")).to_lower())
	var catalogo := DevComandos.ajustes()
	for clave in catalogo:
		var ajuste: Dictionary = catalogo[clave]
		var caja := VBoxContainer.new()
		caja.set_meta("busqueda", "%s %s %s" % [clave, ajuste.get("unidad", ""), ajuste.get("descripcion", "")])
		v.add_child(caja)
		filas_ajustes.append(caja)
		_etiqueta(caja, clave, true)
		var f := _fila(caja)
		var valor := _numero(f, float(ajuste.get("min", 0)), float(ajuste.get("max", 100000)),
			float(ajuste.get("paso", 0.1)), float(ajuste.get("valor", 0)))
		valor.custom_minimum_size.x = 135
		_etiqueta(f, str(ajuste.get("unidad", "")))
		_boton(f, "Leer actual", func(): valor.value = float(DevComandos.valor(d.p.sim, clave)))
		_boton(f, "Aplicar", func(): _cmd({"tipo": "dev_ajuste", "clave": clave, "valor": valor.value}))
		_boton(f, "Original", func(): valor.value = float(ajuste.get("valor", 0)))
		_ayuda(caja, str(ajuste.get("descripcion", "")))


func _inspector(v: VBoxContainer) -> void:
	_ayuda(v, "Estado y causas de espera, métricas, eventos y notas de esta corrida. Se actualiza cada medio segundo; no modifica el mundo.")
	inspector = _editor(v, 410)
	inspector.editable = false
	var f := _fila(v)
	notas = _texto(f, "Confusión, espera, frustración, satisfacción…")
	_boton(f, "Anotar momento", func():
		_mensaje(d.anotar(notas.text.strip_edges()))
		notas.clear()
		_refrescar())
	notas.text_submitted.connect(func(_s):
		_mensaje(d.anotar(notas.text.strip_edges()))
		notas.clear()
		_refrescar())


func _refrescar() -> void:
	var sim = d.p.sim
	reloj.text = "Día %d · %05.2f h · paso %d · ₵ %.0f · %s" % [
		Cfg.dia_de(sim.t), Cfg.hora_de(sim.t), sim.n_paso, sim.dinero,
		"PAUSA" if d.p.velocidad == 0 else "×%g" % d.p.velocidad]
	boton_pausa.text = "Reanudar" if d.p.velocidad == 0 else "Pausar"
	if tabs.current_tab == 4:
		var linea := inspector.get_v_scroll()
		inspector.text = JSON.stringify(d.inspeccionar(), "\t")
		inspector.set_v_scroll(linea)


func _cmd(cmd: Dictionary) -> void:
	_mensaje(d.ejecutar(cmd))
	_refrescar()


func _mensaje(texto: String) -> void:
	if estado == null:
		return
	estado.text = texto if texto != "" else "Aplicado."
	estado.add_theme_color_override("font_color", Estilo.TEXTO)


func _leer_json(editor: CodeEdit) -> Variant:
	var json := JSON.new()
	var error := json.parse(editor.text)
	if error != OK:
		_mensaje("JSON · línea %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		_mensaje("El JSON debe contener un objeto {…}.")
		return null
	return json.data


func _parsear(texto: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(texto) == OK else null


func _fila(padre: Node) -> HBoxContainer:
	var f := HBoxContainer.new()
	f.add_theme_constant_override("separation", 7)
	padre.add_child(f)
	return f


func _etiqueta(padre: Node, texto: String, destacado: bool = false) -> Label:
	var l := Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if destacado:
		l.add_theme_color_override("font_color", Estilo.ACENTO)
	padre.add_child(l)
	return l


func _ayuda(padre: Node, texto: String) -> void:
	var l := _etiqueta(padre, texto)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", Estilo.TENUE)
	l.add_theme_font_size_override("font_size", 12)


func _boton(padre: Node, texto: String, accion: Callable) -> Button:
	var b := Estilo.boton(texto)
	b.clip_text = false
	b.custom_minimum_size.x = 0
	b.pressed.connect(accion)
	padre.add_child(b)
	return b


func _numero(padre: Node, minimo: float, maximo: float, paso: float, valor: float) -> SpinBox:
	var n := SpinBox.new()
	n.min_value = minimo
	n.max_value = maximo
	n.step = paso
	n.value = valor
	n.custom_minimum_size.x = 80
	padre.add_child(n)
	return n


func _texto(padre: Node, placeholder: String, valor: String = "") -> LineEdit:
	var l := LineEdit.new()
	l.placeholder_text = placeholder
	l.text = valor
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 100
	padre.add_child(l)
	return l


func _opciones(padre: Node, opciones: Array) -> OptionButton:
	var o := OptionButton.new()
	for opcion in opciones:
		o.add_item(str(opcion))
	padre.add_child(o)
	return o


func _check(padre: Node, texto: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = texto
	padre.add_child(c)
	return c


func _triestado(padre: Node, texto: String) -> OptionButton:
	return _opciones(padre, [texto + ": conservar", texto + ": no", texto + ": sí"])


func _celda(padre: Node, x: int, z: int) -> Array[SpinBox]:
	_etiqueta(padre, "X")
	var nx := _numero(padre, 0, Cfg.MAPA.x - 1, 1, x)
	_etiqueta(padre, "Z")
	var nz := _numero(padre, 0, Cfg.MAPA.y - 1, 1, z)
	return [nx, nz]


func _xy(celda: Array[SpinBox]) -> Vector2i:
	return Vector2i(int(celda[0].value), int(celda[1].value))


func _editor(padre: Node, alto: float) -> CodeEdit:
	var e := CodeEdit.new()
	e.custom_minimum_size = Vector2(0, alto)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.gutters_draw_line_numbers = true
	e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	e.add_theme_font_size_override("font_size", 12)
	padre.add_child(e)
	return e
