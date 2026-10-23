class_name Hud
extends CanvasLayer
## Interfaz: barra superior (recursos y reloj), panel inferior estilo AoE2 (minimapa · selección ·
## comandos), avisos, paneles SQL fijados y la consola.

const COLOR_AVISO := {"info": Color("9fd7e6"), "error": Color("ff8a8a"), "aviso": Color("ffb547"),
	"alerta": Color("ff6b6b"), "dinero": Color("3fe08a")}

var p: Node
var sim: Simulacion
var capa_mundo: Control
var raiz: Control
var lbl_dinero: Label
var lbl_reloj: Label
var lbl_vel: Label
var lbl_precio: Label
var lbl_registro: Label
var lbl_ciudad: Label
var info: RichTextLabel
var comandos: GridContainer
var titulo_cmd: Label
var avisos: VBoxContainer
var fijados: VBoxContainer
var lbl_pista: Label
var lbl_flotante: Label
var minimapa: TextureRect
var mini_capa: Control
var ayuda: PanelContainer
var consola: ConsolaSQL
var editor: EditorPrograma
var menu_abierto := false
var _log_maquina := {}
var objetivos: RichTextLabel
var _t_objetivos := 0.0
var _objetivos_hechos := 0
var hitos_ui := {}               # consultas y paneles: hitos que ocurren en la interfaz
var _consulta_maquina_en_curso := false
var _t_info := 0.0
var _t_fijados := 0.0
var _pista_t := 0.0


func iniciar(principal: Node) -> void:
	p = principal
	sim = p.sim
	raiz = Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.theme = Estilo.tema()
	add_child(raiz)
	capa_mundo = Control.new()
	capa_mundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	capa_mundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(capa_mundo)
	_barra_superior()
	_panel_inferior()
	_laterales()
	_ayuda()
	consola = ConsolaSQL.new()
	consola.anchor_left = 0.5
	consola.anchor_right = 0.5
	consola.anchor_top = 0.0
	consola.anchor_bottom = 1.0
	consola.offset_left = -560
	consola.offset_right = 560
	consola.offset_top = 52
	consola.offset_bottom = -214
	raiz.add_child(consola)
	consola.iniciar(p.db)
	consola.fijar.connect(fijar_panel)
	consola.ejecutada.connect(func(): hitos_ui.sql = true)
	consola.visible = false
	editor = EditorPrograma.new()
	editor.anchor_left = 1.0
	editor.anchor_right = 1.0
	editor.anchor_bottom = 1.0
	editor.offset_left = -780
	editor.offset_right = -10
	editor.offset_top = 52
	editor.offset_bottom = -214
	raiz.add_child(editor)
	editor.iniciar()
	editor.ejecutar.connect(p.ejecutar_programa)
	editor.detener.connect(func(r): p.detener_programa(r))
	editor.resaltar.connect(func(id): p.control.resaltado = id)


# ================================================================ construcción de la interfaz

func _barra_superior() -> void:
	var barra := PanelContainer.new()
	barra.set_anchors_preset(Control.PRESET_TOP_WIDE)
	barra.offset_bottom = 40
	barra.add_theme_stylebox_override("panel", Estilo.caja(Estilo.FONDO, Estilo.BORDE, 0, 6))
	raiz.add_child(barra)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	barra.add_child(h)
	lbl_dinero = _etiqueta(h, 18, Estilo.VERDE)
	lbl_reloj = _etiqueta(h, 16, Estilo.TEXTO)
	lbl_vel = _etiqueta(h, 14, Estilo.ACENTO)
	lbl_precio = _etiqueta(h, 14, Estilo.TEXTO)
	lbl_registro = _etiqueta(h, 14, Estilo.TEXTO)
	lbl_ciudad = _etiqueta(h, 14, Estilo.TEXTO)
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(esp)
	for mat in Cfg.PEDIDOS:
		var pd: Dictionary = Cfg.PEDIDOS[mat]
		var b := Estilo.boton("Comprar %d %s · ₵%d" % [pd.unidades, mat, pd.precio], "",
			"Pedido al proveedor. Llega en camión a la recepción (REC-01).")
		b.custom_minimum_size.x = 190
		b.pressed.connect(func():
			var err := sim.comprar(mat)
			aviso(err if err != "" else "Pedido de %s enviado al proveedor." % mat, "error" if err != "" else "info"))
		h.add_child(b)
	var bc := Estilo.boton("Consola SQL", "F2")
	bc.custom_minimum_size.x = 130
	bc.pressed.connect(alternar_consola)
	h.add_child(bc)
	var ba := Estilo.boton("Ayuda", "F1")
	ba.custom_minimum_size.x = 90
	ba.pressed.connect(func(): ayuda.visible = not ayuda.visible)
	h.add_child(ba)


func _etiqueta(padre: Control, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	padre.add_child(l)
	return l


func _panel_inferior() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -206
	raiz.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	# Minimapa
	var mm := Control.new()
	mm.custom_minimum_size = Vector2(288, 192)
	h.add_child(mm)
	minimapa = TextureRect.new()
	minimapa.texture = ImageTexture.create_from_image(_imagen_minimapa())
	minimapa.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimapa.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimapa.stretch_mode = TextureRect.STRETCH_SCALE
	minimapa.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimapa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm.add_child(minimapa)
	mini_capa = Control.new()
	mini_capa.set_anchors_preset(Control.PRESET_FULL_RECT)
	mini_capa.draw.connect(_dibujar_minimapa)
	mini_capa.gui_input.connect(_clic_minimapa)
	mm.add_child(mini_capa)
	# Información de la selección
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.scroll_active = true
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(info)
	# Comandos
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	h.add_child(v)
	titulo_cmd = Label.new()
	titulo_cmd.add_theme_color_override("font_color", Estilo.TENUE)
	v.add_child(titulo_cmd)
	comandos = GridContainer.new()
	comandos.columns = 3
	comandos.add_theme_constant_override("h_separation", 6)
	comandos.add_theme_constant_override("v_separation", 6)
	v.add_child(comandos)


func _laterales() -> void:
	fijados = VBoxContainer.new()
	fijados.position = Vector2(10, 50)
	fijados.custom_minimum_size = Vector2(380, 0)
	fijados.add_theme_constant_override("separation", 8)
	fijados.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(fijados)
	avisos = VBoxContainer.new()
	avisos.anchor_top = 1.0
	avisos.anchor_bottom = 1.0
	avisos.offset_left = 300
	avisos.offset_right = 1000
	avisos.offset_top = -380
	avisos.offset_bottom = -214
	avisos.alignment = BoxContainer.ALIGNMENT_END
	avisos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(avisos)
	lbl_pista = Label.new()
	lbl_pista.anchor_left = 0.5
	lbl_pista.anchor_right = 0.5
	lbl_pista.anchor_top = 1.0
	lbl_pista.anchor_bottom = 1.0
	lbl_pista.offset_left = -400
	lbl_pista.offset_right = 400
	lbl_pista.offset_top = -240
	lbl_pista.offset_bottom = -214
	lbl_pista.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_pista.add_theme_color_override("font_color", Estilo.AMBAR)
	lbl_pista.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_pista.add_theme_constant_override("outline_size", 6)
	raiz.add_child(lbl_pista)
	# Objetivos guiados: arriba a la derecha, debajo de la barra.
	var po := PanelContainer.new()
	po.anchor_left = 1.0
	po.anchor_right = 1.0
	po.offset_left = -330
	po.offset_right = -10
	po.offset_top = 50
	po.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(po)
	objetivos = RichTextLabel.new()
	objetivos.bbcode_enabled = true
	objetivos.fit_content = true
	objetivos.custom_minimum_size = Vector2(300, 0)
	objetivos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	po.add_child(objetivos)
	lbl_flotante = Label.new()
	lbl_flotante.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_flotante.add_theme_constant_override("outline_size", 6)
	lbl_flotante.add_theme_font_size_override("font_size", 13)
	lbl_flotante.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(lbl_flotante)


func _ayuda() -> void:
	ayuda = PanelContainer.new()
	ayuda.anchor_left = 0.5
	ayuda.anchor_right = 0.5
	ayuda.anchor_top = 0.5
	ayuda.anchor_bottom = 0.5
	ayuda.offset_left = -430
	ayuda.offset_right = 430
	ayuda.offset_top = -300
	ayuda.offset_bottom = 230
	ayuda.add_theme_stylebox_override("panel", Estilo.caja(Color(0.03, 0.05, 0.08, 0.97), Estilo.ACENTO, 6, 16))
	raiz.add_child(ayuda)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.text = """[font_size=20][color=#59f0ff]CODEMAGEDDON · Concepto 2[/color][/font_size]
Eres la IA de una empresa nueva: un terreno, ₵ 1200, dos mulas sin chip y una minilínea. El cobre y el silicio se [b]compran[/b] (barra superior) y llegan en camión. Los circuitos se venden en la ciudad, al otro lado del río.

[color=#ffb547]Ratón (como Age of Empires II)[/color]
  [b]Clic izq.[/b] seleccionar · [b]arrastrar[/b] caja · [b]doble clic[/b] todos los del mismo nivel · [b]Shift[/b] añadir
  [b]Clic der.[/b] ordenar según el objetivo: suelo = ir · máquina = recoger o entregar · mena = minar · averiada = reparar
  [b]Shift + clic der.[/b] encolar órdenes: tu lista de clics [i]es[/i] el programa del robot (míralo en el panel)
  [b]Arrastrar con el clic der.[/b] desplazar la cámara (no da orden) · también bordes/flechas/WASD
  [b]Rueda[/b] zoom · [b]rueda pulsada[/b] orbitar (se ajusta a 45° al soltar)
  Flechas sobre las máquinas: [color=#3fe08a]verde[/color] = entrada · [color=#ff5a5a]roja[/color] = salida (parpadean hasta que una cinta las conecta)

[color=#ffb547]Teclado[/color]
  [b]B[/b] construir → [b]Q[/b] cinta · [b]W[/b] fundidora · [b]E[/b] ensambladora · [b]A[/b] fábrica de robots · [b]S[/b] despacho · [b]D[/b] servidor
  [b]R[/b] girar · [b]Shift[/b] colocar varias · [b]Supr[/b] demoler · [b]Ctrl+Z[/b] deshacer obra
  [b]Ctrl+1…9[/b] crear grupo · [b]1…9[/b] seleccionarlo · [b].[/b] robot ocioso · [b]H[/b] fábrica · [b]Espacio[/b] centrar
  [b]P[/b] pausa · [b]+ / −[/b] velocidad · [b]Q/E[/b] girar cámara · [b]F2[/b] consola SQL

[color=#ffb547]Robots[/color]  T0 Mula: ejecuta tu lista una vez · T1 Operario: [b]L[/b] la repite en bucle · T2 Explorador: [b]U[/b] rutina propia (busca menas y comprueba espacio antes de entregar)

[color=#ffb547]Programas (JavaScript)[/color]  Selecciona un T1 o T2 y pulsa [b]J[/b]: escribe su programa con [code]await yo.recoger(...)[/code], [code]maquinas["FUN-01"][/code] o [code]await db.query("SELECT ...")[/code]. Las órdenes duran tiempo de juego y la línea en curso se ilumina.

[color=#ffb547]Datos (PostgreSQL)[/color]  Cada máquina tiene un ID y registra entradas, salidas y estados en la tabla [b]eventos[/b]. Consulta con SQL (F2) y [b]fija[/b] lo que quieras vigilar. La ciudad también lee tu registro… En la web, PostgreSQL corre dentro de tu navegador.

[color=#7f95a3]F1 cierra esta ayuda.[/color]"""
	ayuda.add_child(t)


# ================================================================ actualización

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_F2 or (e.keycode == KEY_QUOTELEFT and not _escribiendo()):
			alternar_consola()
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_F1:
			ayuda.visible = not ayuda.visible
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_ESCAPE and (consola.visible or ayuda.visible or editor.visible):
			consola.visible = false
			ayuda.visible = false
			editor.visible = false
			p.control.resaltado = ""
			get_viewport().gui_release_focus()
			get_viewport().set_input_as_handled()


func _escribiendo() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func alternar_editor() -> void:
	var rs: Array[Robot] = p.control.robots_sel()
	if editor.visible:
		editor.visible = false
		p.control.resaltado = ""
		get_viewport().gui_release_focus()
		return
	if rs.size() != 1:
		aviso("Selecciona un solo robot para ver su programa.", "info")
		return
	consola.visible = false
	editor.visible = true
	editor.mostrar(rs[0])
	editor.editor.grab_focus()


func alternar_consola() -> void:
	consola.visible = not consola.visible
	if consola.visible:
		consola.editor.grab_focus()
	else:
		get_viewport().gui_release_focus()


func actualizar(delta: float) -> void:
	lbl_dinero.text = "₵ %d" % int(sim.dinero)
	var h := sim.hora()
	lbl_reloj.text = "Día %d · %02d:%02d %s" % [sim.dia(), int(h), int(fmod(h, 1.0) * 60.0), "☾" if Cfg.es_noche(sim.t) else "☀"]
	lbl_vel.text = "PAUSA" if p.velocidad == 0.0 else "×%d" % int(p.velocidad)
	lbl_precio.text = "Circuito en la ciudad: ₵ %.1f" % sim.ciudad.precio
	var cap := sim.capacidad_registro()
	var motor: String = "PostgreSQL" if p.db.es_postgres else ("PostgreSQL arrancando…" if p.db.pendiente else p.db.motor.get_slice(" ", 0))
	lbl_registro.text = "%s · registro %d / %d filas" % [motor, p.db.filas_eventos, cap]
	lbl_registro.add_theme_color_override("font_color", Estilo.AMBAR if p.db.filas_eventos > cap * 0.85 else Estilo.TEXTO)
	var op := 0.0
	for d in sim.ciudad.distritos.values():
		op += d.opinion
	op /= sim.ciudad.distritos.size()
	lbl_ciudad.text = "Opinión ciudad: %d%%%s%s" % [int(op * 100), " · BLOQUEO" if sim.ciudad.bloqueada() else "",
		" · ordenanza nocturna" if sim.ciudad.ordenanza else ""]
	lbl_ciudad.add_theme_color_override("font_color", Estilo.ROJO if op < 0.4 or sim.ciudad.bloqueada() else Estilo.TEXTO)
	_t_info += delta
	if _t_info > 0.2:
		_t_info = 0.0
		_render_info()
	_t_fijados += delta
	if _t_fijados > 2.0:
		_t_fijados = 0.0
		_refrescar_fijados()
	for a in avisos.get_children():
		a.set_meta("t", a.get_meta("t") + delta)
		if a.get_meta("t") > 9.0:
			a.queue_free()
		elif a.get_meta("t") > 7.0:
			a.modulate.a = (9.0 - a.get_meta("t")) / 2.0
	_pista_t -= delta
	if _pista_t <= 0.0:
		lbl_pista.text = ""
	mini_capa.queue_redraw()
	_flotante()
	editor.offset_left = -min(780.0, get_viewport().get_visible_rect().size.x * 0.56)
	_objetivos(delta)


## Pasos de la demo: cada uno enseña una idea (órdenes, programa, SQL, automatización, mercado).
const OBJETIVOS := [
	["entrega", "Lleva cobre a FUN-01 con una mula: clic en la mula, clic derecho en la pila de cobre de REC-01, Shift + clic derecho en FUN-01."],
	["programa", "Programa al Operario R3: selecciónalo, pulsa J y ejecuta la plantilla."],
	["sql", "Abre la consola SQL (F2) y ejecuta una consulta."],
	["panel", "Fija una consulta como panel para monitorear la fábrica."],
	["cinta_despacho", "Traza una cinta de ENS-01 a DES-01 (B, Q, arrastrar)."],
	["venta", "Vende circuitos en la ciudad (DES-01 → camión)."],
	["robot", "Construye una Fábrica de robots (B, A) y fabrica un robot."],
]


func _objetivos(delta: float) -> void:
	_t_objetivos += delta
	if _t_objetivos < 0.5:
		return
	_t_objetivos = 0.0
	var t := "[color=#59f0ff][b]OBJETIVOS[/b][/color]\n"
	var hechos := 0
	var siguiente_marcado := false
	for o in OBJETIVOS:
		var hecho: bool = sim.hitos.get(o[0], false) or hitos_ui.get(o[0], false)
		if hecho:
			hechos += 1
			t += "[color=#3fe08a]✔[/color] [color=#7f95a3]%s[/color]\n" % o[1]
		elif not siguiente_marcado:
			siguiente_marcado = true
			t += "[color=#ffb547]▶[/color] %s\n" % o[1]
		else:
			t += "[color=#4e6270]○ %s[/color]\n" % o[1]
	if hechos == OBJETIVOS.size():
		t = "[color=#3fe08a][b]OBJETIVOS COMPLETADOS[/b][/color]\nYa sabes dar órdenes, programar en JS, monitorear con SQL y automatizar. Ahora escala sin enfadar a la ciudad."
	objetivos.text = t
	if hechos > _objetivos_hechos and _objetivos_hechos > 0 or hechos > _objetivos_hechos and hechos == 1:
		aviso("Objetivo cumplido (%d/%d)." % [hechos, OBJETIVOS.size()], "dinero")
	_objetivos_hechos = hechos


func aviso(texto: String, tipo: String = "info") -> void:
	var l := Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", COLOR_AVISO.get(tipo, Estilo.TEXTO))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.set_meta("t", 0.0)
	avisos.add_child(l)
	while avisos.get_child_count() > 6:
		var viejo := avisos.get_child(0)
		avisos.remove_child(viejo)
		viejo.queue_free()


func pista(texto: String) -> void:
	lbl_pista.text = texto
	_pista_t = 0.15


func _flotante() -> void:
	var raton := get_viewport().get_mouse_position()
	lbl_flotante.visible = false
	if get_viewport().gui_get_hovered_control() != null or p.control.modo != "normal":
		return
	var texto := ""
	var r: Robot = p.control._robot_bajo(raton)
	if r != null:
		texto = "%s · %s%s" % [r.etiqueta(), r.estado, (" · %d %s" % [r.cant, r.carga]) if r.cant > 0 else ""]
	else:
		var c: Vector2i = p.control._celda_bajo(raton)
		var m := sim.maquina_en(c)
		var mena: Dictionary = p.control._mena_bajo(raton)
		if m != null:
			texto = "%s · %s" % [m.id, m.estado]
		elif not mena.is_empty():
			texto = "%s · %d/%d cobre" % [mena.id, mena.cantidad, mena.max]
		elif sim.suelo.has(c):
			texto = "Suelo: %d %s (clic derecho para recoger)" % [sim.suelo[c].cant, sim.suelo[c].mat]
	if texto != "":
		lbl_flotante.text = texto
		lbl_flotante.position = raton + Vector2(16, 14)
		lbl_flotante.visible = true


# ================================================================ panel de selección

func al_cambiar_seleccion() -> void:
	_reconstruir_comandos()
	_render_info()
	if editor.visible:
		var rs: Array[Robot] = p.control.robots_sel()
		editor.mostrar(rs[0] if rs.size() == 1 else null)


func mostrar_menu_construccion(v: bool) -> void:
	menu_abierto = v
	_reconstruir_comandos()


func _render_info() -> void:
	var c: ControlRTS = p.control
	var rs := c.robots_sel()
	var t := ""
	if rs.size() == 1:
		t = _info_robot(rs[0])
	elif rs.size() > 1:
		t = "[color=#59f0ff][b]%d robots seleccionados[/b][/color]\n" % rs.size()
		for r in rs:
			t += "%s · %s%s\n" % [r.etiqueta(), r.estado, (" · %d %s" % [r.cant, r.carga]) if r.cant > 0 else ""]
		t += "\n[color=#7f95a3]Clic derecho: la misma orden para todos. Ctrl+número: guardar como grupo.[/color]"
	elif c.sel_maquina != "" and sim.maquinas.has(c.sel_maquina):
		t = _info_maquina(sim.maquinas[c.sel_maquina])
	elif c.sel_otro.get("tipo", "") == "mena":
		var m := sim.mena(c.sel_otro.id)
		t = "[color=#ee9550][b]%s[/b][/color] · mena de cobre natural\n%d / %d unidades\n\n[color=#7f95a3]Solo un Explorador T2 tiene pala para minar. Extraer es más barato que comprar, pero hay que llegar hasta aquí.[/color]" % [m.id, m.cantidad, m.max]
	elif c.sel_otro.get("tipo", "") == "camion":
		for cam in sim.camiones:
			if cam.id == c.sel_otro.id:
				t = "[b]%s[/b] · %s · %s\nCarga: %s%s" % [cam.id, "proveedor" if cam.tipo == "proveedor" else "venta",
					cam.estado, str(cam.carga), "\n[color=#ff6b6b]Esperando: carretera bloqueada[/color]" if cam.esperando else ""]
	else:
		t = _info_general()
	info.text = t


func _info_general() -> String:
	var ociosos := 0
	for r in sim.robots:
		if r.ocioso():
			ociosos += 1
	var t := "[color=#59f0ff][b]Codemageddon S.A.[/b][/color]   %d robots (%d ociosos, tecla «.») · %d máquinas\n" % [sim.robots.size(), ociosos, sim.maquinas.size()]
	t += "[color=#7f95a3]Nada seleccionado. Selecciona un robot (clic) o varios (caja). B abre la construcción.\n"
	t += "Primer objetivo: lleva cobre de REC-01 a FUN-01 y silicio a ENS-01, y los circuitos a DES-01 para venderlos.[/color]"
	return t


func _info_robot(r: Robot) -> String:
	var t := "[color=#59f0ff][b]%s[/b][/color]  ·  %s\n" % [r.etiqueta(), r.estado]
	t += "[color=#7f95a3]%s[/color]\n" % r.def.desc
	t += "Carga: %s   ·   Recorrido: %d m\n" % ["%d %s" % [r.cant, r.carga] if r.cant > 0 else "vacío", int(r.distancia)]
	var prog: Array = r.programa()
	t += "[code]"
	for i in prog[0].size():
		var linea: String = Estilo.escapar(prog[0][i])
		if i == prog[1]:
			t += "[bgcolor=#1b4a5c][color=#ffffff]▶ %s[/color][/bgcolor]\n" % linea
		elif linea.begins_with("//"):
			t += "[color=#6a8394]  %s[/color]\n" % linea
		else:
			t += "[color=#c8e6ff]  %s[/color]\n" % linea
	t += "[/code]"
	return t


func _info_maquina(m: Maquina) -> String:
	var t := "[color=#59f0ff][b]%s[/b][/color] · %s · [color=#%s]%s[/color]\n" % [m.id, m.def.nombre,
		VistaFabrica.COLOR_ESTADO.get(m.estado, Color.WHITE).to_html(false), m.estado]
	if not m.lista():
		return t + "En construcción: %.1f s" % m.obra
	if not m.entrada.is_empty() or m.def.has("cap_entrada"):
		t += "Entrada: %s   " % _stock(m.entrada, m.cap_entrada())
	if not m.salida.is_empty() or m.def.has("cap_salida"):
		t += "Salida: %s" % _stock(m.salida, m.cap_salida())
	t += "\n"
	if m.def.has("recetas"):
		var rec := m.receta_actual()
		var ent: PackedStringArray = []
		for k in rec.entra:
			ent.append("%d %s" % [rec.entra[k], k])
		var sal: String = ("robot " + Cfg.ROBOTS[rec.robot].nombre) if rec.has("robot") else ", ".join(rec.sale.keys())
		t += "Receta: %s → %s (%.1f s) · progreso %d%% · producidos %d · turno %s\n" % [", ".join(ent), sal, rec.t,
			int(m.progreso * 100) if m.trabajando else 0, m.producidos, "diurno" if m.turno_diurno else "24h"]
	if m.tipo == "servidor":
		t += "Aporta %d filas de capacidad al registro.\n" % Cfg.MAQUINAS.servidor.filas
	# Registro de la máquina, con la consulta a la vista: así se aprende de dónde sale el dato.
	var sql := "SELECT hora, tipo, material, cantidad, detalle FROM eventos WHERE origen = '%s' ORDER BY id DESC LIMIT 5;" % m.id
	# Consulta asíncrona: se pinta con el último resultado recibido y se pide otro.
	if not _consulta_maquina_en_curso:
		_consulta_maquina_en_curso = true
		p.db.consultar_luego(sql, func(res):
			_consulta_maquina_en_curso = false
			_log_maquina = {"id": m.id, "filas": res.filas if res.ok else []})
	var r: Dictionary = _log_maquina if _log_maquina.get("id", "") == m.id else {"filas": []}
	t += "[color=#6a8394][code]%s[/code][/color]\n" % Estilo.escapar(sql)
	for f in r.filas:
		t += "[code][color=#9fb4d8]%02d h  %-12s %-9s %3s  %s[/color][/code]\n" % [int(f.hora), str(f.tipo), "" if f.material == null else str(f.material),
			"" if f.cantidad == null else str(f.cantidad), "" if f.detalle == null else str(f.detalle)]
	return t


func _stock(d: Dictionary, cap: int) -> String:
	if d.is_empty():
		return "vacía"
	var partes: PackedStringArray = []
	for k in d:
		partes.append("%d %s" % [d[k], k])
	return ", ".join(partes) + (" (máx %d c/u)" % cap if cap > 0 else "")


func _reconstruir_comandos() -> void:
	for b in comandos.get_children():
		b.queue_free()
	var c: ControlRTS = p.control
	var rs := c.robots_sel()
	if menu_abierto or (rs.is_empty() and c.sel_maquina == "" and c.sel_otro.is_empty()):
		titulo_cmd.text = "CONSTRUIR (B)" + ("  · elige con la tecla" if menu_abierto else "")
		for tipo in Cfg.ORDEN_CONSTRUCCION:
			var nombre: String = "Cinta" if tipo == "cinta" else Cfg.MAQUINAS[tipo].nombre
			var costo: int = Cfg.CINTA_COSTO if tipo == "cinta" else Cfg.MAQUINAS[tipo].costo
			var tecla: int = Cfg.TECLA_CINTA if tipo == "cinta" else Cfg.MAQUINAS[tipo].tecla
			var b := Estilo.boton("%s ₵%d" % [nombre, costo], OS.get_keycode_string(tecla), _tooltip_construccion(tipo))
			b.pressed.connect(c.empezar_construccion.bind(tipo))
			comandos.add_child(b)
		return
	if not rs.is_empty():
		titulo_cmd.text = "ÓRDENES"
		var r := rs[0]
		var bb := Estilo.boton("Bucle: %s" % ("sí" if r.repetir else "no"), "L",
			"Repetir la lista de órdenes (while). Requiere chip: Operario T1 o superior.")
		bb.disabled = not r.def.bucle
		bb.pressed.connect(_simular_tecla.bind(KEY_L))
		comandos.add_child(bb)
		var bx := Estilo.boton("Borrar órdenes", "X")
		bx.pressed.connect(_simular_tecla.bind(KEY_X))
		comandos.add_child(bx)
		var bu := Estilo.boton("Rutina auto: %s" % ("sí" if r.auto else "no"), "U", "Solo T2: busca menas, mina y entrega solo.")
		bu.disabled = not r.def.auto
		bu.pressed.connect(_simular_tecla.bind(KEY_U))
		comandos.add_child(bu)
		var bc := Estilo.boton("Centrar", "Espacio")
		bc.pressed.connect(c.centrar_seleccion)
		comandos.add_child(bc)
		var bo := Estilo.boton("Robot ocioso", ".")
		bo.pressed.connect(_simular_tecla.bind(KEY_PERIOD))
		comandos.add_child(bo)
		var bj := Estilo.boton("Programar", "J", "Escribe su programa en JavaScript.")
		bj.disabled = r.nivel == 0
		if r.nivel == 0:
			bj.tooltip_text = "La mula T0 no tiene chip: fabrica un Operario (T1)."
		bj.pressed.connect(_simular_tecla.bind(KEY_J))
		comandos.add_child(bj)
		if r.ejecutando:
			var bd := Estilo.boton("Detener programa")
			bd.pressed.connect(func(): p.detener_programa(r))
			comandos.add_child(bd)
		return
	if c.sel_maquina != "" and sim.maquinas.has(c.sel_maquina):
		var m: Maquina = sim.maquinas[c.sel_maquina]
		titulo_cmd.text = "MÁQUINA %s" % m.id
		var bp := Estilo.boton("Reanudar" if m.pausada else "Pausar", "Z")
		bp.pressed.connect(_simular_tecla.bind(KEY_Z))
		comandos.add_child(bp)
		var bt := Estilo.boton("Turno: %s" % ("diurno" if m.turno_diurno else "24h"), "T",
			"Diurno = se detiene de 22:00 a 06:00 (ruido nocturno).")
		bt.pressed.connect(_simular_tecla.bind(KEY_T))
		comandos.add_child(bt)
		var bl := Estilo.boton("Su registro", "", "Abre la consola con los eventos de esta máquina.")
		bl.pressed.connect(func(): consola.abrir_con("SELECT t, dia, hora, tipo, material, cantidad, detalle, monto\nFROM eventos\nWHERE origen = '%s'\nORDER BY id DESC\nLIMIT 50;" % m.id))
		comandos.add_child(bl)
		if m.tipo == "fabrica_robots":
			for clave in m.def.recetas:
				var rec: Dictionary = m.def.recetas[clave]
				var b := Estilo.boton(("● " if m.receta == clave else "") + Cfg.ROBOTS[rec.robot].nombre, "",
					"%d circuitos + %d lingotes · %.0f s" % [rec.entra.circuito, rec.entra.lingote, rec.t])
				b.pressed.connect(func():
					sim.aplicar({"tipo": "set_maquina", "id": m.id, "campo": "receta", "valor": clave})
					_reconstruir_comandos())
				comandos.add_child(b)
		if m.tipo == "recepcion":
			for mat in ["cobre", "silicio"]:
				var b := Estilo.boton(("● " if m.salida_cinta == mat else "") + "A cinta: " + mat, "",
					"Qué material empuja la recepción a una cinta conectada a su salida.")
				b.pressed.connect(func():
					sim.aplicar({"tipo": "set_maquina", "id": m.id, "campo": "salida_cinta", "valor": mat})
					_reconstruir_comandos())
				comandos.add_child(b)
		if m.tipo == "despacho":
			var bv := Estilo.boton("Enviar camión", "V", "Vende circuitos y lingotes en el mercado de la ciudad.")
			bv.pressed.connect(_simular_tecla.bind(KEY_V))
			comandos.add_child(bv)
			var ba := Estilo.boton("Envío auto: %s" % ("sí" if m.envio_auto else "no"), "", "Sale solo con 10 o más unidades.")
			ba.pressed.connect(func():
				sim.aplicar({"tipo": "set_maquina", "id": m.id, "campo": "envio_auto", "valor": not m.envio_auto})
				_reconstruir_comandos())
			comandos.add_child(ba)
		if m.tipo != "recepcion":
			var bd := Estilo.boton("Demoler", "Supr", "Devuelve el 50 % (100 % si sigue en obra).")
			bd.pressed.connect(c.demoler_seleccion)
			comandos.add_child(bd)
		return
	titulo_cmd.text = ""


func _tooltip_construccion(tipo: String) -> String:
	match tipo:
		"cinta":
			return "Arrastra para trazar. Entrega en la casilla de ENTRADA (cian) de una máquina; las máquinas empujan su salida (ámbar) a la cinta que tengan delante."
		"fundidora":
			return "1 cobre → 1 lingote. Ruido alto y humo."
		"ensambladora":
			return "2 lingotes + 1 silicio → 1 circuito."
		"fabrica_robots":
			return "Fabrica Mulas (T0), Operarios con chip (T1) y Exploradores (T2)."
		"despacho":
			return "Recibe circuitos y lingotes; el camión los vende en la ciudad."
		"servidor":
			return "+%d filas de capacidad en el registro de eventos." % Cfg.MAQUINAS.servidor.filas
	return ""


func _simular_tecla(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	p.control._tecla(e)


# ================================================================ paneles fijados

func fijar_panel(sql: String, titulo: String) -> void:
	if fijados.get_child_count() >= 4:
		aviso("Máximo 4 paneles fijados: cierra uno.", "error")
		return
	var panel := PanelContainer.new()
	panel.set_meta("sql", sql)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var cab := HBoxContainer.new()
	v.add_child(cab)
	var l := Label.new()
	l.text = "▪ " + titulo
	l.add_theme_color_override("font_color", Estilo.ACENTO)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	cab.add_child(l)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(panel.queue_free)
	cab.add_child(x)
	var t := Tree.new()
	t.hide_root = true
	t.column_titles_visible = true
	t.custom_minimum_size = Vector2(370, 150)
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(t)
	fijados.add_child(panel)
	_refrescar_uno(panel)
	hitos_ui.panel = true
	aviso("Panel fijado: se actualiza cada 2 s.", "info")


func _refrescar_fijados() -> void:
	for panel in fijados.get_children():
		_refrescar_uno(panel)


func _refrescar_uno(panel: Node) -> void:
	if panel.is_queued_for_deletion():
		return
	var t: Tree = panel.get_child(0).get_child(1)
	p.db.consultar_luego(panel.get_meta("sql"), func(r):
		if is_instance_valid(t):
			ConsolaSQL.llenar_tabla(t, r, 12))


# ================================================================ minimapa

func _imagen_minimapa() -> Image:
	var rj := sim.rejilla
	var img := Image.create_empty(rj.ancho, rj.alto, false, Image.FORMAT_RGBA8)
	for z in rj.alto:
		for x in rj.ancho:
			var i := z * rj.ancho + x
			var col := Color("4a8c45").darkened(rj.humedad[i] * 0.4)
			match rj.tipo[i]:
				Rejilla.AGUA:
					col = Color("34679f")
				Rejilla.ARENA:
					col = Color("d9c38a")
				Rejilla.LOSA:
					col = Color("78808a")
				Rejilla.CARRETERA, Rejilla.PUENTE:
					col = Color("2a2d33")
				Rejilla.CIUDAD:
					col = Color("b8b0a4")
			img.set_pixel(x, z, col)
	for f in rj.flora:
		if f.bloquea:
			img.set_pixel(int(f.pos.x), int(f.pos.y), Color("1f4a2c"))
	return img


func _a_mini(p_mundo: Vector2) -> Vector2:
	var tam := mini_capa.size
	return Vector2(p_mundo.x / Cfg.MAPA.x * tam.x, p_mundo.y / Cfg.MAPA.y * tam.y)


func _dibujar_minimapa() -> void:
	var esc := mini_capa.size.x / Cfg.MAPA.x
	for m in sim.rejilla.menas:
		if m.cantidad > 0:
			mini_capa.draw_rect(Rect2(_a_mini(Vector2(m.celda)), Vector2(esc * 1.5, esc * 1.5)), Color("ee9550"))
	for m: Maquina in sim.maquinas.values():
		var r := m.rect()
		mini_capa.draw_rect(Rect2(_a_mini(Vector2(r.position)), Vector2(r.size) * esc), VistaFabrica.COLOR_ESTADO.get(m.estado, Color.WHITE))
	for c in sim.cintas.celdas:
		mini_capa.draw_rect(Rect2(_a_mini(Vector2(c)), Vector2(esc, esc)), Color("1d2129"))
	for cam in sim.camiones:
		var pr := Simulacion.punto_ruta(cam.ruta, cam.s)
		mini_capa.draw_circle(_a_mini(pr[0]), 3.0, Color("ffd27a"))
	for r in sim.robots:
		mini_capa.draw_circle(_a_mini(r.pos), 2.5 if not r.id in p.control.sel_robots else 3.5,
			VistaRobots.NIVEL_COLOR[r.nivel] if not r.id in p.control.sel_robots else Color.WHITE)
	if sim.ciudad.bloqueada():
		var pr := Simulacion.punto_ruta(Cfg.RUTA_VENTA, sim.s_bloqueo())
		mini_capa.draw_circle(_a_mini(pr[0]), 5.0, Color("ff3b3b"))
	# Lo que ve la cámara: las cuatro esquinas de la pantalla proyectadas al suelo.
	var vp := get_viewport().get_visible_rect().size
	var pts := PackedVector2Array()
	for e in [Vector2(0, 40), Vector2(vp.x, 40), Vector2(vp.x, vp.y - 206), Vector2(0, vp.y - 206)]:
		var h: Vector3 = p.cam.rayo_suelo(e)
		if h != Vector3.INF:
			pts.append(_a_mini(Vector2(h.x, h.z)))
	if pts.size() == 4:
		pts.append(pts[0])
		mini_capa.draw_polyline(pts, Color(1, 1, 1, 0.85), 1.0)
	mini_capa.draw_rect(Rect2(Vector2.ZERO, mini_capa.size), Estilo.BORDE, false, 1.0)


func _clic_minimapa(e: InputEvent) -> void:
	var mover := false
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		mover = true
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		mover = true
	if mover:
		var tam := mini_capa.size
		p.cam.centrar(Vector3(e.position.x / tam.x * Cfg.MAPA.x, 0, e.position.y / tam.y * Cfg.MAPA.y))
